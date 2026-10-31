import 'package:flutter/material.dart';

import '../features/printing/data/system_print_service.dart';
import '../features/printing/presentation/print_bridge.dart';
import '../features/printing/presentation/print_measurement_host.dart';
import '../features/terminal/presentation/terminal_home_page.dart';

class PosApp extends StatelessWidget {
  PosApp({super.key, PrintService? printService, this._printBridge})
    : _printService = printService ?? SystemPrintService();

  final PrintService _printService;
  final PrintBridge? _printBridge;
  late final PrintBridge _ownedPrintBridge = PrintBridge(_printService);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Point of Sale',
      locale: const Locale('ar'),
      builder: (context, child) {
        return Directionality(
          textDirection: TextDirection.rtl,
          child: child ?? const SizedBox.shrink(),
        );
      },
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
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(6),
            ),
          ),
        ),
      ),
      home: PrintMeasurementHost(
        child: TerminalHomePage(
          printBridge: _printBridge ?? _ownedPrintBridge,
          printService: _printService,
        ),
      ),
    );
  }
}
