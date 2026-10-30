import 'package:flutter/foundation.dart';
import 'package:flutter_native_html_to_pdf/flutter_native_html_to_pdf.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';

import '../../../core/config/app_config.dart';
import 'html_content_sizer.dart';

class RenderedReceipt {
  const RenderedReceipt({required this.bytes, required this.format});

  final Uint8List bytes;
  final PdfPageFormat format;
}

class HtmlPdfRenderer {
  HtmlPdfRenderer({
    HtmlToPdfConverter? nativeConverter,
    HtmlContentSizer? sizer,
  }) : _nativeConverter = nativeConverter ?? HtmlToPdfConverter(),
       _sizer = sizer ?? const HtmlContentSizer();

  final HtmlToPdfConverter _nativeConverter;
  final HtmlContentSizer _sizer;

  // Extra paper height added below the measured content so a tiny overflow
  // cannot push the receipt onto a second, equally tall blank page.
  static const double _overflowGuardMm = 6.0;

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
      final bytes = await _nativeConverter.convertHtmlToPdfBytes(
        html: preparedHtml,
        pageSize: PdfPageSize.fromMillimeters(
          widthMm: resolvedPaperWidthMm,
          heightMm: resolvedHeightMm,
          name:
              'Receipt ${resolvedPaperWidthMm.round()}x${resolvedHeightMm.round()}mm',
        ),
      );
      if (bytes.isEmpty) {
        throw StateError('The operating system could not render the receipt.');
      }
      return RenderedReceipt(bytes: bytes, format: format);
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
    final guardedHeightMm = measuredHeightMm + _overflowGuardMm;
    return guardedHeightMm < _minHeightMm ? _minHeightMm : guardedHeightMm;
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
