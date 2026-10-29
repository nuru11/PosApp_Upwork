import 'dart:async';
import 'dart:ui';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/config/app_config.dart';
import '../presentation/print_measurement_host.dart';

/// Renders the backend print template in a WebView at the exact paper width
/// supplied by the print plan and reports the intrinsic content height.
///
/// This keeps the printed page as tall as the receipt actually is, without
/// baking any physical dimension into Dart code.
class HtmlContentSizer {
  const HtmlContentSizer({this.timeout = const Duration(seconds: 20)});

  final Duration timeout;

  // CSS pixel is defined as 1/96 inch, and 1 inch = 25.4 mm.
  static const double _cssPxPerMm = 96 / 25.4;

  Future<double> measureHeightMm({
    required String html,
    required double paperWidthMm,
  }) async {
    // A real, attached WebView is required on Android/iOS: a headless one
    // never receives a layout pass, so scrollHeight stays 0.
    double? hosted;
    try {
      hosted = await PrintMeasurementHost.measureHeightMm(
        html: html,
        paperWidthMm: paperWidthMm,
      );
    } catch (_) {
      hosted = null;
    }
    if (hosted != null) return hosted;

    return _measureHeadless(html: html, paperWidthMm: paperWidthMm);
  }

  Future<double> _measureHeadless({
    required String html,
    required double paperWidthMm,
  }) async {
    final widthPx = paperWidthMm * _cssPxPerMm;
    final completer = Completer<InAppWebViewController>();
    late final HeadlessInAppWebView headless;
    headless = HeadlessInAppWebView(
      initialSize: Size(widthPx, 20000),
      initialSettings: InAppWebViewSettings(
        transparentBackground: true,
        supportZoom: false,
        useWideViewPort: false,
        loadWithOverviewMode: false,
        disableHorizontalScroll: true,
      ),
      initialData: InAppWebViewInitialData(
        data: html,
        baseUrl: WebUri(AppConfig.webUrl),
      ),
      onLoadStop: (controller, _) {
        if (!completer.isCompleted) completer.complete(controller);
      },
    );

    try {
      await headless.run();
      final controller = await completer.future.timeout(timeout);
      final measured = await _measureWithRetry(controller);
      if (measured <= 0) {
        throw StateError('Content height could not be measured.');
      }
      return measured / _cssPxPerMm;
    } finally {
      await headless.dispose();
    }
  }

  Future<double> _measureWithRetry(InAppWebViewController controller) async {
    for (var attempt = 0; attempt < 20; attempt++) {
      final result = await controller.callAsyncJavaScript(functionBody: _probeJs);
      final heightPx = result?.value is num ? (result!.value as num).toDouble() : 0.0;
      if (heightPx > 0) return heightPx;
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    return 0;
  }

  // Runs as an async function body via callAsyncJavaScript: evaluateJavascript
  // never awaits a returned Promise on Android, so it always yields 0.
  static const _probeJs = r'''
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
