import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../printing/data/system_print_service.dart';
import '../../printing/domain/print_request.dart';
import '../data/printer_settings_store.dart';
import '../domain/saved_printer.dart';

class PrinterSettingsPage extends StatefulWidget {
  const PrinterSettingsPage({
    required this.printService,
    this.printerSettings,
    super.key,
  });

  final PrintService printService;
  final PrinterSettingsStore? printerSettings;

  @override
  State<PrinterSettingsPage> createState() => _PrinterSettingsPageState();
}

class _PrinterSettingsPageState extends State<PrinterSettingsPage> {
  late final PrinterSettingsStore _store =
      widget.printerSettings ?? PrinterSettingsStore();
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '9100');
  double _paperWidthMm = 80;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ipController.dispose();
    _portController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final saved = await _store.read();
    if (!mounted) return;
    if (saved != null) {
      _nameController.text = saved.name ?? '';
      _ipController.text = saved.ip ?? '';
      _portController.text = '${saved.port}';
      _paperWidthMm = saved.paperWidthMm;
    }
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الطابعة')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SafeArea(
              child: Form(
                key: _formKey,
                child: ListView(
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      'احفظ طابعة الإيصالات ثم اطبع إيصالاً تجريبياً بدون فتح نقطة البيع.',
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _nameController,
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(
                        labelText: 'اسم الطابعة',
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _ipController,
                      textInputAction: TextInputAction.next,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(
                        labelText: 'عنوان IP',
                        hintText: '192.168.1.50',
                      ),
                      validator: _validateHost,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      decoration: const InputDecoration(labelText: 'المنفذ'),
                      validator: _validatePort,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'عرض الورق',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    SegmentedButton<double>(
                      segments: const [
                        ButtonSegment(value: 58.0, label: Text('58 مم')),
                        ButtonSegment(value: 80.0, label: Text('80 مم')),
                      ],
                      selected: {_paperWidthMm},
                      onSelectionChanged: (selection) {
                        setState(() => _paperWidthMm = selection.first);
                      },
                    ),
                    const SizedBox(height: 32),
                    FilledButton.icon(
                      onPressed: _busy ? null : _save,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('حفظ'),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _busy ? null : _printTestReceipt,
                      icon: const Icon(Icons.receipt_long_outlined),
                      label: const Text('طباعة إيصال تجريبي'),
                    ),
                  ],
                ),
              ),
            ),
    );
  }

  String? _validateHost(String? value) {
    final host = value?.trim() ?? '';
    if (host.isEmpty) return null;
    if (!RegExp(r'^[A-Za-z0-9.\-]+$').hasMatch(host)) {
      return 'أدخل عنوان طابعة صالحاً';
    }
    return null;
  }

  String? _validatePort(String? value) {
    final port = int.tryParse(value?.trim() ?? '');
    if (port == null || port < 1 || port > 65535) {
      return 'أدخل منفذاً بين 1 و 65535';
    }
    return null;
  }

  SavedPrinter? _printerFromForm() {
    if (_formKey.currentState?.validate() != true) return null;
    return SavedPrinter(
      name: _nameController.text,
      ip: _ipController.text,
      port: int.parse(_portController.text.trim()),
      paperWidthMm: _paperWidthMm,
    );
  }

  Future<void> _save() async {
    final printer = _printerFromForm();
    if (printer == null) return;
    setState(() => _busy = true);
    try {
      await _store.save(printer);
      if (!mounted) return;
      _showMessage('تم حفظ الطابعة');
    } catch (_) {
      if (!mounted) return;
      _showMessage('تعذر حفظ الطابعة');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _printTestReceipt() async {
    final printer = _printerFromForm();
    if (printer == null) return;
    setState(() => _busy = true);
    try {
      await _store.save(printer);
      final result = await widget.printService.print(
        PrintRequest(
          html: _testReceiptHtml(printer.paperWidthMm),
          title: 'إيصال تجريبي',
          paperWidthMm: printer.paperWidthMm,
          jobId: 'test-receipt',
          printerName: printer.name,
          printerIp: printer.hasNetworkAddress ? printer.ip!.trim() : null,
          printerPort: printer.port,
          printerProtocol: printer.hasNetworkAddress ? 'raw' : null,
        ),
      );
      if (!mounted) return;
      _showMessage(
        result.success
            ? 'تم إرسال الإيصال التجريبي'
            : (result.error ?? 'تعذرت طباعة الإيصال التجريبي'),
      );
    } catch (_) {
      if (!mounted) return;
      _showMessage('تعذرت طباعة الإيصال التجريبي');
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

String _testReceiptHtml(double paperWidthMm) {
  final width = paperWidthMm.round();
  return '''
<!DOCTYPE html>
<html dir="rtl" lang="ar">
<head>
  <meta charset="utf-8">
  <style>
    body { font-family: sans-serif; margin: 0; padding: 8px; width: ${width}mm; }
    h1 { font-size: 16px; text-align: center; margin: 0 0 8px; }
    p { font-size: 12px; margin: 4px 0; }
  </style>
</head>
<body>
  <h1>إيصال تجريبي</h1>
  <p>نقطة البيع</p>
  <p>هذا إيصال اختبار من التطبيق.</p>
  <p>عرض الورق: $width مم</p>
</body>
</html>
''';
}
