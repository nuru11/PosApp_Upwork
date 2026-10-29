import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../../core/config/app_config.dart';

/// Hosts a permanently mounted, invisible [InAppWebView] used to measure the
/// intrinsic content height of backend print templates.
///
/// Android's headless WebView never receives a real layout pass, which makes
/// `scrollHeight` unreliable for templates that rely on layout (e.g. `height:
/// 100%`). Mounting a real WebView inside the widget tree (hidden via
/// [Visibility]) guarantees the platform performs an actual layout pass.
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

  @override
  State<PrintMeasurementHost> createState() => PrintMeasurementHostState();
}

class PrintMeasurementHostState extends State<PrintMeasurementHost> {
  // CSS pixel is defined as 1/96 inch, and 1 inch = 25.4 mm.
  static const double _cssPxPerMm = 96 / 25.4;

  // Wide/tall enough to fit any supported thermal paper without wrapping;
  // the template's own CSS controls the actual printed width in mm.
  static const double _hostWidthPx = 400;
  static const double _hostHeightPx = 4000;

  InAppWebViewController? _controller;
  Completer<void>? _loadCompleter;
  Future<double?> _queue = Future.value(null);

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
    final result = _queue.then(
      (_) => _runMeasurement(html, paperWidthMm),
      onError: (_) => _runMeasurement(html, paperWidthMm),
    );
    _queue = result.then<double?>((value) => value, onError: (_) => null);
    return result;
  }

  Future<double?> _runMeasurement(String html, double paperWidthMm) async {
    final controller = _controller;
    if (controller == null) return null;

    final completer = Completer<void>();
    _loadCompleter = completer;
    await controller.loadData(
      data: html,
      mimeType: 'text/html',
      encoding: 'utf-8',
      baseUrl: WebUri(AppConfig.webUrl),
      historyUrl: WebUri(AppConfig.webUrl),
    );

    try {
      await completer.future.timeout(const Duration(seconds: 20));
    } on TimeoutException {
      return null;
    } finally {
      // Detach so a late onLoadStop from this load cannot complete the next
      // measurement's completer during continuous printing.
      if (identical(_loadCompleter, completer)) _loadCompleter = null;
    }

    for (var attempt = 0; attempt < 20; attempt++) {
      final result = await controller.callAsyncJavaScript(
        functionBody: _probeJs(paperWidthMm),
      );
      final heightPx = result?.value is num ? (result!.value as num).toDouble() : 0.0;
      if (heightPx > 0) {
        return heightPx / _cssPxPerMm;
      }
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        Positioned(
          left: 0,
          top: 0,
          child: IgnorePointer(
            // `Opacity` still performs a real paint pass (unlike `Visibility`),
            // which is required for the platform WebView to actually composite
            // and run a real layout pass on Android.
            child: Opacity(
              opacity: 0.0,
              child: SizedBox(
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
              ),
            ),
          ),
        ),
      ],
    );
  }

  // Forces the template to the requested paper width so measurement is
  // consistent even if the template relies on the viewport width itself.
  // Runs as an async function body via callAsyncJavaScript: evaluateJavascript
  // never awaits a returned Promise on Android, so it always yields 0.
  String _probeJs(double paperWidthMm) => '''
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
