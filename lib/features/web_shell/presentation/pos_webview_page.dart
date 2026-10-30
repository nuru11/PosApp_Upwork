import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'dart:convert';

import '../../../core/config/app_config.dart';
import '../../printing/presentation/print_bridge.dart';
import 'push_notification_service.dart';

class PosWebViewPage extends StatefulWidget {
  const PosWebViewPage({
    required this.webUrl,
    required this.printBridge,
    super.key,
  });

  final String webUrl;
  final PrintBridge printBridge;

  @override
  State<PosWebViewPage> createState() => _PosWebViewPageState();
}

class _PosWebViewPageState extends State<PosWebViewPage> {
  InAppWebViewController? _controller;
  int _progress = 0;
  String? _error;
  late final VoidCallback _pushTokenListener;

  @override
  void initState() {
    super.initState();
    _pushTokenListener = _publishPushTokenToWeb;
    PushNotificationService.tokenListenable.addListener(_pushTokenListener);
  }

  @override
  void dispose() {
    PushNotificationService.tokenListenable.removeListener(_pushTokenListener);
    super.dispose();
  }

  String get _allowedHost {
    return AppConfig.allowedHost;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (!didPop && await _controller?.canGoBack() == true) {
          await _controller?.goBack();
        }
      },
      child: Scaffold(
        body: SafeArea(
          bottom: false,
          child: Stack(
            children: [
              InAppWebView(
                initialUrlRequest: URLRequest(url: WebUri(widget.webUrl)),
                initialSettings: InAppWebViewSettings(
                  javaScriptEnabled: true,
                  domStorageEnabled: true,
                  databaseEnabled: true,
                  supportZoom: false,
                  mediaPlaybackRequiresUserGesture: false,
                  allowsInlineMediaPlayback: true,
                  transparentBackground: false,
                ),
                onWebViewCreated: (controller) {
                  _controller = controller;
                  widget.printBridge.register(controller);
                  _publishPushTokenToWeb();
                },
                onLoadStop: (_, _) => _publishPushTokenToWeb(),
                shouldOverrideUrlLoading: (controller, action) async {
                  final url = action.request.url;
                  if (url == null || url.host == _allowedHost) {
                    return NavigationActionPolicy.ALLOW;
                  }
                  return NavigationActionPolicy.CANCEL;
                },
                onLoadStart: (_, _) {
                  if (mounted) setState(() => _error = null);
                },
                onProgressChanged: (_, progress) {
                  if (mounted) setState(() => _progress = progress);
                },
                onReceivedError: (_, request, error) {
                  if (request.isForMainFrame == true && mounted) {
                    setState(() => _error = error.description);
                  }
                },
              ),
              if (_progress < 100 && _error == null)
                LinearProgressIndicator(value: _progress / 100),
              if (_error != null)
                _ErrorView(
                  message: _error!,
                  onRetry: () => _controller?.reload(),
                ),
              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: ValueListenableBuilder<PrintDiagnostic?>(
                  valueListenable: widget.printBridge.diagnostic,
                  builder: (context, diagnostic, _) {
                    if (diagnostic == null) return const SizedBox.shrink();
                    return _PrintDiagnosticView(
                      diagnostic: diagnostic,
                      onDismiss: () =>
                          widget.printBridge.diagnostic.value = null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _publishPushTokenToWeb() async {
    final controller = _controller;
    final token = PushNotificationService.currentToken;
    if (controller == null || token == null || token.isEmpty) {
      return;
    }

    final encodedToken = jsonEncode(token);
    await controller.evaluateJavascript(
      source:
          '''
window.__flutterFcmToken = $encodedToken;
window.__flutterPushBridge = {
  getToken: function() { return window.__flutterFcmToken; }
};
window.dispatchEvent(new CustomEvent('flutter-fcm-token', {
  detail: { token: $encodedToken }
}));
''',
    );
  }
}

class _PrintDiagnosticView extends StatelessWidget {
  const _PrintDiagnosticView({
    required this.diagnostic,
    required this.onDismiss,
  });

  final PrintDiagnostic diagnostic;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final backgroundColor = diagnostic.isError
        ? colorScheme.errorContainer
        : colorScheme.surfaceContainerHighest;
    final foregroundColor = diagnostic.isError
        ? colorScheme.onErrorContainer
        : colorScheme.onSurface;

    return Material(
      color: backgroundColor,
      elevation: 8,
      borderRadius: BorderRadius.circular(12),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 180),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  child: SelectableText(
                    diagnostic.message,
                    style: TextStyle(color: foregroundColor),
                    textDirection: TextDirection.ltr,
                    textAlign: TextAlign.left,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'إغلاق',
                onPressed: onDismiss,
                icon: Icon(Icons.close, color: foregroundColor),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_rounded, size: 52),
              const SizedBox(height: 16),
              Text(
                'تعذر الاتصال بنظام نقطة البيع',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('إعادة المحاولة'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
