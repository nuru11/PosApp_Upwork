import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_native_html_to_pdf/flutter_native_html_to_pdf.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../core/config/app_config.dart';
import '../presentation/print_measurement_host.dart';
import 'html_content_sizer.dart';

typedef HostPdfRenderer =
    Future<HostRenderedPdf?> Function({
      required String html,
      required double paperWidthMm,
    });

class RenderedReceipt {
  const RenderedReceipt({required this.bytes, required this.format});

  final Uint8List bytes;
  final PdfPageFormat format;
}

class HtmlPdfRenderer {
  HtmlPdfRenderer({
    HtmlToPdfConverter? nativeConverter,
    HtmlContentSizer? sizer,
    HostPdfRenderer? hostPdfRenderer,
  }) : _nativeConverter = nativeConverter ?? HtmlToPdfConverter(),
       _sizer = sizer ?? const HtmlContentSizer(),
       _hostPdfRenderer = hostPdfRenderer ?? PrintMeasurementHost.renderPdf;

  final HtmlToPdfConverter _nativeConverter;
  final HtmlContentSizer _sizer;
  final HostPdfRenderer _hostPdfRenderer;

  // Extra paper height added below the measured content so a tiny overflow
  // cannot push the receipt onto a second, equally tall blank page.
  static const double _overflowGuardMm = 6.0;

  // iOS measures content height in a separate WebView than the one the native
  // converter paginates with, so the two can disagree by a few millimetres. A
  // larger guard on iOS keeps the receipt on a single page from the first
  // render, which is what prevents the endless roll / missing cut.
  static const double _iosOverflowGuardMm = 20.0;

  // Minimal page height so a near-zero measurement cannot produce an invalid
  // page; real receipts are always taller than this floor.
  static const double _minHeightMm = 10.0;

  Future<RenderedReceipt> render({
    required String html,
    required double? paperWidthMm,
  }) async {
    final preparedHtml = _prepareHtml(html);
    final resolvedPaperWidthMm = _resolvePaperWidthMm(
      html: preparedHtml,
      paperWidthMm: paperWidthMm,
    );

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // The native converter renders in a UIWindow that is not attached to any
      // scene, so in this scene-based app WebKit suspends it and the job hangs.
      // Render with WKWebView.createPDF on the WebView mounted in the app's own
      // window instead: one page, cropped to the paper width.
      final hosted = await _hostPdfRenderer(
        html: preparedHtml,
        paperWidthMm: resolvedPaperWidthMm,
      );
      if (hosted != null) {
        debugPrint(
          '[print][pdf] iOS createPDF widthMm=$resolvedPaperWidthMm '
          'heightMm=${hosted.heightMm} pages=${_countPdfPages(hosted.bytes)}',
        );
        return RenderedReceipt(
          bytes: hosted.bytes,
          format: PdfPageFormat(
            resolvedPaperWidthMm * PdfPageFormat.mm,
            hosted.heightMm * PdfPageFormat.mm,
            marginAll: 0,
          ),
        );
      }
      debugPrint('[print][pdf] iOS createPDF unavailable; using fallback');
    }

    final heightMm = await _sizer.measureHeightMm(
      html: preparedHtml,
      paperWidthMm: resolvedPaperWidthMm,
    );
    final resolvedHeightMm = _resolvePaperHeightMm(measuredHeightMm: heightMm);
    debugPrint(
      '[print][size] requestedWidthMm=$paperWidthMm '
      'resolvedWidthMm=$resolvedPaperWidthMm '
      'measuredHeightMm=$heightMm resolvedHeightMm=$resolvedHeightMm',
    );
    final format = PdfPageFormat(
      resolvedPaperWidthMm * PdfPageFormat.mm,
      resolvedHeightMm * PdfPageFormat.mm,
      marginAll: 0,
    );

    if (defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS) {
      // iOS renders through UIPrintPageRenderer, which paginates any content
      // taller than the page we pass in. Each PDF page then becomes a separate
      // ESC/POS image frame with a single cut only after the last one, so a
      // multi-page PDF makes the thermal roll feed endlessly without cutting.
      // Force a single page by re-rendering tall enough to hold all content.
      var targetHeightMm = resolvedHeightMm;
      var bytes = await _convertNative(
        html: preparedHtml,
        widthMm: resolvedPaperWidthMm,
        heightMm: targetHeightMm,
      );
      var pageCount = _countPdfPages(bytes);
      var attempt = 0;
      while (pageCount > 1 && attempt < 3) {
        targetHeightMm = targetHeightMm * pageCount + _overflowGuardMm;
        bytes = await _convertNative(
          html: preparedHtml,
          widthMm: resolvedPaperWidthMm,
          heightMm: targetHeightMm,
        );
        pageCount = _countPdfPages(bytes);
        attempt++;
      }
      debugPrint(
        '[print][pdf] finalHeightMm=$targetHeightMm pages=$pageCount '
        'reRenders=$attempt',
      );
      if (bytes.isEmpty) {
        throw StateError('The operating system could not render the receipt.');
      }
      final finalFormat = PdfPageFormat(
        resolvedPaperWidthMm * PdfPageFormat.mm,
        targetHeightMm * PdfPageFormat.mm,
        marginAll: 0,
      );
      return RenderedReceipt(bytes: bytes, format: finalFormat);
    }

    final info = await Printing.info();
    if (!info.canConvertHtml) {
      throw UnsupportedError(
        'HTML rendering is unavailable on this operating system.',
      );
    }
    // printing currently exposes no non-deprecated equivalent for HTML input.
    // ignore: deprecated_member_use
    final bytes = await Printing.convertHtml(
      html: preparedHtml,
      format: format,
    );
    return RenderedReceipt(bytes: bytes, format: format);
  }

  String _prepareHtml(String html) {
    final baseTag = '<base href="${AppConfig.webUrl}">';
    const printStyle = '''<style data-print-agent>
@page { margin: 0; }
html, body {
  width: 100% !important;
  height: auto !important;
  min-height: 0 !important;
  margin: 0 !important;
  padding: 0 !important;
}
html, body, body * { box-sizing: border-box; }
/* Collapse trailing bottom whitespace so the measured height matches the
   rendered height; an unmeasured bottom margin is the usual cause of a second,
   blank page before the cut. */
body *:last-child { margin-bottom: 0 !important; }
body { padding-bottom: 0 !important; }
</style>''';
    final additions = StringBuffer();
    if (!html.contains(RegExp(r'<base\s', caseSensitive: false))) {
      additions.write(baseTag);
    }
    additions.write(printStyle);

    final headMatch = RegExp(
      r'<head[^>]*>',
      caseSensitive: false,
    ).firstMatch(html);
    if (headMatch != null) {
      final insertAt = headMatch.end;
      return '${html.substring(0, insertAt)}$additions${html.substring(insertAt)}';
    }

    return '<head>$additions</head>$html';
  }

  double _resolvePaperHeightMm({required double measuredHeightMm}) {
    // Keep the receipt height dynamic: it always follows the measured content
    // so a short kitchen order is not padded up to a fixed page height. A small
    // overflow guard is added so the native HTML-to-PDF converter cannot push
    // a trailing margin onto a second, equally tall blank page, and a minimal
    // floor protects against a degenerate near-zero measurement.
    final guard = defaultTargetPlatform == TargetPlatform.iOS
        ? _iosOverflowGuardMm
        : _overflowGuardMm;
    final guardedHeightMm = measuredHeightMm + guard;
    return guardedHeightMm < _minHeightMm ? _minHeightMm : guardedHeightMm;
  }

  Future<Uint8List> _convertNative({
    required String html,
    required double widthMm,
    required double heightMm,
  }) {
    return _nativeConverter.convertHtmlToPdfBytes(
      html: html,
      pageSize: PdfPageSize.fromMillimeters(
        widthMm: widthMm,
        heightMm: heightMm,
        name: 'Receipt ${widthMm.round()}x${heightMm.round()}mm',
      ),
    );
  }

  // Counts page objects in a PDF without a full parser. UIKit/Android PDF output
  // keeps page dictionaries uncompressed, so matching "/Type /Page" (but not
  // "/Type /Pages") reliably reports how many pages the converter produced. The
  // Pages-tree "/Count" entry is used as a fallback.
  int _countPdfPages(Uint8List bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    final pageObjects = RegExp(
      r'/Type\s*/Page(?![a-zA-Z])',
    ).allMatches(text).length;
    if (pageObjects > 0) return pageObjects;
    final countMatch = RegExp(r'/Count\s+(\d+)').firstMatch(text);
    if (countMatch != null) {
      return int.tryParse(countMatch.group(1)!) ?? 1;
    }
    return 1;
  }

  double _resolvePaperWidthMm({
    required String html,
    required double? paperWidthMm,
  }) {
    if (paperWidthMm != null) {
      return paperWidthMm;
    }

    final templateWidthMm = _parseTemplatePaperWidthMm(html);
    if (templateWidthMm != null) {
      return templateWidthMm;
    }

    throw const FormatException(
      'The print plan does not include paperSize and the template does not declare a paper width.',
    );
  }

  double? _parseTemplatePaperWidthMm(String html) {
    for (final pattern in _millimeterPatterns) {
      final match = RegExp(
        pattern,
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(html);
      if (match != null) {
        return double.parse(match.group(1)!);
      }
    }

    for (final pattern in _pixelPatterns) {
      final match = RegExp(
        pattern,
        caseSensitive: false,
        dotAll: true,
      ).firstMatch(html);
      if (match != null) {
        final pixels = double.parse(match.group(1)!);
        return pixels / (96 / 25.4);
      }
    }

    return null;
  }

  static const _millimeterPatterns = <String>[
    r'@page\s*\{[^}]*size\s*:\s*(\d+(?:\.\d+)?)mm',
    r'(?:width|min-width|max-width)\s*:\s*(\d+(?:\.\d+)?)mm',
    r'''data-paper-size\s*=\s*["']?(\d+(?:\.\d+)?)mm''',
    r'''(?:paper|receipt)[-_ ]width\s*[:=]\s*["']?(\d+(?:\.\d+)?)''',
  ];

  static const _pixelPatterns = <String>[
    r'(?:width|min-width|max-width)\s*:\s*(\d+(?:\.\d+)?)px',
    r'''(?:paper|receipt)[-_ ]width\s*[:=]\s*["']?(\d+(?:\.\d+)?)px''',
  ];
}
