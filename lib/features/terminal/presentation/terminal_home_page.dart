import 'package:flutter/material.dart';

import '../../../core/config/app_config.dart';
import '../../printing/data/system_print_service.dart';
import '../../printing/presentation/print_bridge.dart';
import '../../web_shell/presentation/pos_webview_page.dart';
import '../data/printer_settings_store.dart';
import '../data/register_connection.dart';
import '../domain/saved_printer.dart';
import 'alert_settings_page.dart';
import 'printer_settings_page.dart';

class TerminalHomePage extends StatefulWidget {
  const TerminalHomePage({
    required this.printBridge,
    required this.printService,
    this.printerSettings,
    this.connection,
    super.key,
  });

  final PrintBridge printBridge;
  final PrintService printService;
  final PrinterSettingsStore? printerSettings;
  final RegisterConnection? connection;

  @override
  State<TerminalHomePage> createState() => _TerminalHomePageState();
}

class _TerminalHomePageState extends State<TerminalHomePage> {
  late final PrinterSettingsStore _printerSettings =
      widget.printerSettings ?? PrinterSettingsStore();
  late final RegisterConnection _connection =
      widget.connection ?? const RegisterConnection();

  String _printerStatus = 'لم يتم حفظ طابعة';
  bool? _connected;
  bool _checkingConnection = true;

  @override
  void initState() {
    super.initState();
    _loadPrinterStatus();
    _checkConnection();
  }

  Future<void> _loadPrinterStatus() async {
    final saved = await _printerSettings.read();
    if (!mounted) return;
    setState(() {
      _printerStatus = (saved ?? const SavedPrinter()).statusLabel;
    });
  }

  Future<void> _checkConnection() async {
    setState(() => _checkingConnection = true);
    final reachable = await _connection.canReach(AppConfig.webUrl);
    if (!mounted) return;
    setState(() {
      _connected = reachable;
      _checkingConnection = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('نقطة البيع')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            Text('جهاز الكاشير', style: theme.textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              'طباعة الإيصالات وتنبيهات الطلبات على هذا الجهاز.',
              style: theme.textTheme.bodyLarge,
            ),
            const SizedBox(height: 24),
            _StatusTile(
              icon: _checkingConnection
                  ? Icons.cloud_outlined
                  : _connected == true
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
              label: _checkingConnection
                  ? 'جارٍ التحقق من الاتصال'
                  : _connected == true
                  ? 'النظام متاح'
                  : 'تعذر الاتصال بالنظام',
            ),
            const SizedBox(height: 12),
            _StatusTile(icon: Icons.print_outlined, label: _printerStatus),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _openRegister,
              icon: const Icon(Icons.point_of_sale_outlined),
              label: const Text('فتح نقطة البيع'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openPrinterSettings,
              icon: const Icon(Icons.print_outlined),
              label: const Text('الطابعة'),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _openAlerts,
              icon: const Icon(Icons.notifications_outlined),
              label: const Text('التنبيهات'),
            ),
          ],
        ),
      ),
    );
  }

  void _openRegister() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PosWebViewPage(
          webUrl: AppConfig.webUrl,
          printBridge: widget.printBridge,
        ),
      ),
    );
  }

  Future<void> _openPrinterSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (context) => PrinterSettingsPage(
          printService: widget.printService,
          printerSettings: _printerSettings,
        ),
      ),
    );
    await _loadPrinterStatus();
  }

  void _openAlerts() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (context) => const AlertSettingsPage()),
    );
  }
}

class _StatusTile extends StatelessWidget {
  const _StatusTile({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(leading: Icon(icon), title: Text(label)),
    );
  }
}
