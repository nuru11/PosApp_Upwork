import 'package:flutter/material.dart';

import '../data/local_alert_service.dart';

class AlertSettingsPage extends StatefulWidget {
  const AlertSettingsPage({this.alerts, super.key});

  final LocalAlertService? alerts;

  @override
  State<AlertSettingsPage> createState() => _AlertSettingsPageState();
}

class _AlertSettingsPageState extends State<AlertSettingsPage> {
  late final LocalAlertService _alerts = widget.alerts ?? LocalAlertService();
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('التنبيهات')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text(
              'أرسل تنبيهاً تجريبياً للتأكد من ظهور تنبيهات الطلبات وصوتها على هذا الجهاز.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _busy ? null : _sendTestAlert,
              icon: const Icon(Icons.notifications_active_outlined),
              label: const Text('إرسال تنبيه تجريبي'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _sendTestAlert() async {
    setState(() => _busy = true);
    try {
      final allowed = await _alerts.requestPermission();
      if (!mounted) return;
      if (!allowed) {
        _showMessage('لم يتم منح إذن التنبيهات');
        return;
      }
      await _alerts.showTestOrderAlert();
      if (!mounted) return;
      _showMessage('تم إرسال التنبيه التجريبي');
    } catch (_) {
      if (!mounted) return;
      _showMessage('تعذر إرسال التنبيه التجريبي');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
}
