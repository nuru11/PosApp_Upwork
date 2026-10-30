import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/config/app_config.dart';
import '../data/print_breadcrumbs.dart';

/// Hosts a permanently mounted [InAppWebView] used to measure backend print
/// templates and, on iOS, to export them as PDF.
///
/// Android's headless WebView never receives a real layout pass, which makes
/// `scrollHeight` unreliable for templates that rely on layout (e.g. `height:
/// 100%`). On iOS the WebView must be attached to the app's window, otherwise
/// WebKit suspends it and loads/JavaScript never complete.
class PrintMeasurementHost extends StatefulWidget {
  const PrintMeasurementHost({required this.child, super.key});

  final Widget child;

  static PrintMeasurementHostState? _active;

  /// Measures [html]'s rendered height in millimeters at [paperWidthMm].
  /// Returns `null` if no host is currently mounted or measurement failed.
  static Future<double?> measureHeightMm({
    required String html,
    required double paperWidthMm,
  }) {
    final state = _active;
    if (state == null) return Future.value(null);
    return state._measureHeightMm(html: html, paperWidthMm: paperWidthMm);
  }

  /// iOS only: renders [html] in the mounted WebView and exports it with
  /// `WKWebView.createPDF` as a single page cropped to [paperWidthMm].
  /// Returns `null` when unavailable so the caller can fall back.
  static Future<HostRenderedPdf?> renderPdf({
    required String html,
    required double paperWidthMm,
  }) {
    final state = _active;
    if (state == null || defaultTargetPlatform != TargetPlatform.iOS) {
      return Future.value(null);
    }
    return state._renderPdf(html: html, paperWidthMm: paperWidthMm);
  }

  /// iOS only: exports [html] as short PDF pages so each page can be rasterized
  /// without allocating one bitmap for the whole receipt.
  /// Returns `null` when no host is mounted or a slice fails.
  static Future<List<Uint8List>?> renderPdfSlices({
    required String html,
    required double paperWidthMm,
  }) {
    final state = _active;
    if (state == null || defaultTargetPlatform != TargetPlatform.iOS) {
      return Future.value(null);
    }
    return state._renderPdfSlices(html: html, paperWidthMm: paperWidthMm);
  }

  @override
  State<PrintMeasurementHost> createState() => PrintMeasurementHostState();
}

class HostRenderedPdf {
  const HostRenderedPdf({required this.bytes, required this.heightMm});

  final Uint8List bytes;
  final double heightMm;
}

class _IosPdfLayout {
  const _IosPdfLayout({
    required this.controller,
    required this.pointsPerCss,
    required this.rectX,
    required this.rectWidth,
    required this.rectHeight,
    required this.heightMm,
  });

  final InAppWebViewController controller;
  final double pointsPerCss;
  final double rectX;
  final double rectWidth;
  final double rectHeight;
  final double heightMm;
}

class PrintMeasurementHostState extends State<PrintMeasurementHost> {
  // CSS pixel is defined as 1/96 inch, and 1 inch = 25.4 mm.
  static const double _cssPxPerMm = 96 / 25.4;

  // Wide/tall enough to fit any supported thermal paper without wrapping;
  // the template's own CSS controls the actual printed width in mm.
  static const double _hostWidthPx = 400;
  static const double _hostHeightPx = 4000;

  // Each printer image is one strip this tall. A full receipt rasterized as a
  // single page is what makes iOS kill the process.
  static const double _sliceCss = 700;

  InAppWebViewController? _controller;
  Completer<void>? _loadCompleter;
  Future<void> _queue = Future.value();

  // Serializes every use of the single shared WebView (measure or render).
  Future<T> _serialized<T>(Future<T> Function() task) {
    final result = _queue.then((_) => task(), onError: (_) => task());
    _queue = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  @override
  void initState() {
    super.initState();
    PrintMeasurementHost._active = this;
  }

  @override
  void dispose() {
    if (identical(PrintMeasurementHost._active, this)) {
      PrintMeasurementHost._active = null;
    }
    super.dispose();
  }

  Future<double?> _measureHeightMm({
    required String html,
    required double paperWidthMm,
  }) {
    return _serialized(() => _runMeasurement(html, paperWidthMm));
  }

  Future<HostRenderedPdf?> _renderPdf({
    required String html,
    required double paperWidthMm,
  }) {
    return _serialized(() async {
      try {
        // Hard cap for the whole job so a stalled WebView can never hold the
        // shared queue (and every later print) hostage.
        return await _runRenderPdf(
          html,
          paperWidthMm,
        ).timeout(const Duration(seconds: 35));
      } on TimeoutException {
        try {
          await _controller?.stopLoading();
        } catch (_) {}
        return null;
      }
    });
  }

  Future<List<Uint8List>?> _renderPdfSlices({
    required String html,
    required double paperWidthMm,
  }) {
    return _serialized(() async {
      try {
        return await _runRenderPdfSlices(
          html,
          paperWidthMm,
        ).timeout(const Duration(seconds: 40));
      } on TimeoutException {
        try {
          await _controller?.stopLoading();
        } catch (_) {}
        return null;
      }
    });
  }

  Future<bool> _load(InAppWebViewController controller, String html) async {
    final completer = Completer<void>();
    _loadCompleter = completer;
    try {
      await controller
          .loadData(
            data: html,
            mimeType: 'text/html',
            encoding: 'utf-8',
            baseUrl: WebUri(AppConfig.webUrl),
            historyUrl: WebUri(AppConfig.webUrl),
          )
          .timeout(const Duration(seconds: 5));
      await completer.future.timeout(const Duration(seconds: 10));
      return true;
    } on TimeoutException {
      return false;
    } finally {
      // Detach so a late onLoadStop from this load cannot complete the next
      // job's completer during continuous printing.
      if (identical(_loadCompleter, completer)) _loadCompleter = null;
    }
  }

  Future<HostRenderedPdf?> _runRenderPdf(
    String html,
    double paperWidthMm,
  ) async {
    final layout = await _measureIosLayout(html, paperWidthMm);
    if (layout == null) return null;
    // One archive page has to fit the host. A taller receipt is printed from
    // slices instead of this single page.
    if (layout.rectHeight > _hostHeightPx) return null;

    PrintBreadcrumbs.mark('iOS render: create PDF (WKWebView.createPDF)');
    final bytes = await _createPdfRect(
      controller: layout.controller,
      x: layout.rectX,
      y: 0,
      width: layout.rectWidth,
      height: layout.rectHeight,
    );
    if (bytes == null) return null;
    return HostRenderedPdf(bytes: bytes, heightMm: layout.heightMm);
  }

  Future<List<Uint8List>?> _runRenderPdfSlices(
    String html,
    double paperWidthMm,
  ) async {
    final layout = await _measureIosLayout(html, paperWidthMm);
    if (layout == null) return null;

    final slicePoints = _sliceCss * layout.pointsPerCss;
    if (slicePoints <= 0) return null;
    // createPDF rejects a rect that sticks out of the WebView.
    final captureHeight = math.min(layout.rectHeight, _hostHeightPx);
    final slices = <Uint8List>[];
    var y = 0.0;
    while (y < captureHeight - 0.5) {
      final height = math.min(slicePoints, captureHeight - y);
      if (height <= 0.5) break;
      if (y + height > _hostHeightPx) return null;
      PrintBreadcrumbs.mark('iOS render: create PDF slice');
      final bytes = await _createPdfRect(
        controller: layout.controller,
        x: layout.rectX,
        y: y,
        width: layout.rectWidth,
        height: height,
      );
      if (bytes == null) return null;
      slices.add(bytes);
      y += height;
    }
    return slices.isEmpty ? null : slices;
  }

  Future<_IosPdfLayout?> _measureIosLayout(
    String html,
    double paperWidthMm,
  ) async {
    final controller = _controller;
    if (controller == null) return null;

    // A unique token lets the layout script confirm it is reading this job's
    // document, not a late navigation from the previous one.
    final token = '${DateTime.now().microsecondsSinceEpoch}';
    final printHtml = _iosPrintHtml(html, token);
    PrintBreadcrumbs.mark('iOS render: load receipt HTML');
    if (!await _load(controller, printHtml)) return null;

    PrintBreadcrumbs.mark('iOS render: measure layout');
    final result = await controller
        .callAsyncJavaScript(functionBody: _layoutJs(paperWidthMm, token))
        .timeout(const Duration(seconds: 15), onTimeout: () => null);
    final value = result?.value;
    if (value is! Map || value['ok'] != true) return null;
    final heightCss = (value['height'] as num?)?.toDouble() ?? 0;
    final leftCss = (value['left'] as num?)?.toDouble() ?? 0;
    final viewportCss = (value['viewport'] as num?)?.toDouble() ?? 0;
    if (heightCss <= 0 || viewportCss <= 0) return null;

    // DOM values are CSS px; createPDF's rect is in view points. They differ
    // if WebKit scales the layout viewport, so convert explicitly.
    final pointsPerCss = _hostWidthPx / viewportCss;
    final widthCss = paperWidthMm * _cssPxPerMm;
    final guardedHeightCss = heightCss + 4 * _cssPxPerMm;
    final rectWidth = widthCss * pointsPerCss;
    final rectHeight = guardedHeightCss * pointsPerCss;
    if (rectWidth <= 0 || rectWidth > _hostWidthPx || rectHeight <= 0) {
      return null;
    }
    final rectX = (leftCss * pointsPerCss)
        .clamp(0, _hostWidthPx - rectWidth)
        .toDouble();
    return _IosPdfLayout(
      controller: controller,
      pointsPerCss: pointsPerCss,
      rectX: rectX,
      rectWidth: rectWidth,
      rectHeight: rectHeight,
      heightMm: guardedHeightCss / _cssPxPerMm,
    );
  }

  Future<Uint8List?> _createPdfRect({
    required InAppWebViewController controller,
    required double x,
    required double y,
    required double width,
    required double height,
  }) async {
    final bytes = await controller
        .createPdf(
          pdfConfiguration: PDFConfiguration(
            rect: InAppWebViewRect(x: x, y: y, width: width, height: height),
          ),
        )
        .timeout(const Duration(seconds: 12), onTimeout: () => null);
    if (bytes == null || bytes.isEmpty) return null;
    return bytes;
  }

  // WKWebView renders screen media while the Android converter renders print
  // media, so print-only rules are promoted. A fixed 1:1 viewport keeps CSS px
  // aligned with view points, and the job token tags this document.
  String _iosPrintHtml(String html, String token) {
    final withoutViewport = html.replaceAll(
      RegExp(
        r'''<meta[^>]+name\s*=\s*["']?viewport["']?[^>]*>''',
        caseSensitive: false,
      ),
      '',
    );
    final media = withoutViewport
        .replaceAll(
          RegExp(r'@media\s+print', caseSensitive: false),
          '@media all',
        )
        .replaceAll(
          RegExp(r'@media\s+screen', caseSensitive: false),
          '@media not all',
        );
    final tags =
        '<meta name="viewport" content="width=device-width, initial-scale=1, '
        'maximum-scale=1, user-scalable=no">'
        '<meta name="print-job" content="$token">';
    final head = RegExp(r'<head[^>]*>', caseSensitive: false).firstMatch(media);
    if (head != null) {
      return '${media.substring(0, head.end)}$tags${media.substring(head.end)}';
    }
    return '<head>$tags</head>$media';
  }

  Future<double?> _runMeasurement(String html, double paperWidthMm) async {
    final controller = _controller;
    if (controller == null) return null;

    if (!await _load(controller, html)) return null;

    // Bounded by an overall deadline so a stalled measurement finishes well
    // before the render stage timeout (60s) and never serializes behind the
    // next print job on the shared measurement queue.
    final deadline = DateTime.now().add(const Duration(seconds: 18));
    for (
      var attempt = 0;
      attempt < 20 && DateTime.now().isBefore(deadline);
      attempt++
    ) {
      final result = await controller
          .callAsyncJavaScript(functionBody: _probeJs(paperWidthMm))
          .timeout(const Duration(seconds: 4), onTimeout: () => null);
      final heightPx = result?.value is num
          ? (result!.value as num).toDouble()
          : 0.0;
      if (heightPx > 0) {
        return heightPx / _cssPxPerMm;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    final webView = SizedBox(
      width: _hostWidthPx,
      height: _hostHeightPx,
      child: InAppWebView(
        initialSettings: InAppWebViewSettings(
          transparentBackground: true,
          supportZoom: false,
          useWideViewPort: false,
          loadWithOverviewMode: false,
          disableHorizontalScroll: true,
        ),
        onWebViewCreated: (controller) => _controller = controller,
        onLoadStop: (controller, _) {
          final completer = _loadCompleter;
          if (completer != null && !completer.isCompleted) {
            completer.complete();
          }
        },
      ),
    );

    if (defaultTargetPlatform == TargetPlatform.iOS) {
      // Opacity(0) skips painting its child, so on iOS the platform view would
      // never be added to the window and WebKit suspends it: loads and
      // JavaScript never complete. Keep it fully composited but underneath the
      // opaque app content, where it is never visible.
      return Stack(
        children: [
          Positioned(left: 0, top: 0, child: IgnorePointer(child: webView)),
          widget.child,
        ],
      );
    }

    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          top: 0,
          child: IgnorePointer(child: Opacity(opacity: 0.0, child: webView)),
        ),
      ],
    );
  }

  // Lays the template out at the paper width, anchored at x=0, and reports its
  // height, left edge and layout-viewport width (all in CSS px). Inline
  // `!important` is required to beat the injected `width: 100% !important`.
  String _layoutJs(double paperWidthMm, String token) =>
      '''
  const tokenMeta = () => document.querySelector('meta[name="print-job"]');
  for (let i = 0; i < 50 && tokenMeta()?.content !== '$token'; i++) {
    await new Promise((resolve) => setTimeout(resolve, 100));
  }
  if (tokenMeta()?.content !== '$token') return { ok: false };

  window.scrollTo(0, 0);
  const root = document.documentElement;
  root.style.setProperty('width', '${paperWidthMm}mm', 'important');
  root.style.setProperty('margin-left', '0', 'important');
  root.style.setProperty('margin-right', 'auto', 'important');
  if (document.body) {
    document.body.style.setProperty('width', '${paperWidthMm}mm', 'important');
    document.body.style.setProperty('margin', '0', 'important');
  }
  await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  if (document.fonts && document.fonts.ready) {
    try { await Promise.race([document.fonts.ready, new Promise((r) => setTimeout(r, 5000))]); } catch (_) {}
  }
  const images = Array.from(document.images);
  await Promise.race([
    Promise.all(images.map((img) => img.complete
      ? Promise.resolve()
      : new Promise((resolve) => {
          img.addEventListener('load', resolve, { once: true });
          img.addEventListener('error', resolve, { once: true });
        }))),
    new Promise((resolve) => setTimeout(resolve, 6000)),
  ]);
  await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));

  const body = document.body;
  let maxBottom = 0;
  for (const element of Array.from(body?.querySelectorAll('*') || [])) {
    const rect = element.getBoundingClientRect();
    if (rect && Number.isFinite(rect.bottom)) maxBottom = Math.max(maxBottom, rect.bottom);
  }
  if (body?.childNodes.length) {
    const range = document.createRange();
    range.selectNodeContents(body);
    const bottom = range.getBoundingClientRect().bottom;
    if (Number.isFinite(bottom)) maxBottom = Math.max(maxBottom, bottom);
  }
  const rootRect = root.getBoundingClientRect();
  const bodyRect = body ? body.getBoundingClientRect() : rootRect;
  return {
    ok: true,
    height: Math.ceil(maxBottom),
    left: Math.max(0, Math.floor(Math.min(rootRect.left, bodyRect.left) + window.scrollX)),
    viewport: window.innerWidth,
  };
''';

  // Forces the template to the requested paper width so measurement is
  // consistent even if the template relies on the viewport width itself.
  // Runs as an async function body via callAsyncJavaScript: evaluateJavascript
  // never awaits a returned Promise on Android, so it always yields 0.
  String _probeJs(double paperWidthMm) =>
      '''
  const measureHeight = () => {
    const body = document.body;
    let maxBottom = 0;

    const all = Array.from(document.body?.querySelectorAll('*') || []);
    for (const element of all) {
      const rect = element.getBoundingClientRect();
      if (!rect) continue;
      const bottom = rect.bottom + window.scrollY;
      if (Number.isFinite(bottom)) {
        maxBottom = Math.max(maxBottom, bottom);
      }
    }

    for (const child of Array.from(body?.children || [])) {
      const rect = child.getBoundingClientRect();
      const bottom = rect.bottom + window.scrollY;
      if (Number.isFinite(bottom)) maxBottom = Math.max(maxBottom, bottom);
    }

    if (body?.childNodes.length) {
      const range = document.createRange();
      range.selectNodeContents(body);
      const bottom = range.getBoundingClientRect().bottom + window.scrollY;
      if (Number.isFinite(bottom)) maxBottom = Math.max(maxBottom, bottom);
    }

    return Math.ceil(maxBottom);
  };

  document.documentElement.style.width = '${paperWidthMm}mm';
  if (document.body) document.body.style.width = '${paperWidthMm}mm';
  await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  if (document.fonts && document.fonts.ready) {
    try { await document.fonts.ready; } catch (_) {}
  }
  const images = Array.from(document.images);
  await Promise.all(images.map((img) => img.complete
    ? Promise.resolve()
    : new Promise((resolve) => {
        img.addEventListener('load', resolve, { once: true });
        img.addEventListener('error', resolve, { once: true });
      })));
  await new Promise((resolve) => requestAnimationFrame(() => requestAnimationFrame(resolve)));
  return measureHeight();
''';
}
