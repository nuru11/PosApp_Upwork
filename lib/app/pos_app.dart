import 'package:flutter/material.dart';

import '../core/config/app_config.dart';
import '../features/printing/data/system_print_service.dart';
import '../features/printing/presentation/print_bridge.dart';
import '../features/printing/presentation/print_measurement_host.dart';
import '../features/web_shell/presentation/pos_webview_page.dart';

class PosApp extends StatelessWidget {
  PosApp({super.key});

  final PrintBridge _printBridge = PrintBridge(SystemPrintService());

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Point of Sale',
      locale: const Locale('ar'),
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF006B5E),
          brightness: Brightness.light,
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
      home: PrintMeasurementHost(
        child: PosWebViewPage(webUrl: AppConfig.webUrl, printBridge: _printBridge),
      ),
    );
  }
}
