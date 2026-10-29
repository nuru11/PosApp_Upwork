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
  bool _webCanGoBack = false;
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
      canPop: !_webCanGoBack,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        if (await _controller?.canGoBack() == true) {
          await _controller?.goBack();
          await _syncWebHistory();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: const Text('نقطة البيع'),
          leading: IconButton(
            tooltip: 'الإعدادات',
            onPressed: _returnToTerminal,
            icon: const Icon(Icons.settings_outlined),
          ),
        ),
        body: SafeArea(
          top: false,
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
                onLoadStop: (_, _) {
                  _publishPushTokenToWeb();
                  _syncWebHistory();
                },
                onUpdateVisitedHistory: (_, _, _) {
                  _syncWebHistory();
                },
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
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _syncWebHistory() async {
    final canGoBack = await _controller?.canGoBack() ?? false;
    if (mounted && canGoBack != _webCanGoBack) {
      setState(() => _webCanGoBack = canGoBack);
    }
  }

  void _returnToTerminal() {
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) return;
    final route = ModalRoute.of(context);
    if (route != null && route.popDisposition == RoutePopDisposition.doNotPop) {
      navigator.removeRoute(route);
      return;
    }
    navigator.pop();
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
