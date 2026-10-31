import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../terminal/data/printer_settings_store.dart';
import '../../terminal/domain/saved_printer.dart';
import '../data/print_breadcrumbs.dart';
import '../data/system_print_service.dart';
import '../domain/print_request.dart';

class PrintBridge {
  PrintBridge(
    this._printService, {
    Future<SavedPrinter?> Function()? loadSavedPrinter,
  }) : _loadSavedPrinter = loadSavedPrinter ?? PrinterSettingsStore().read {
    final step = PrintBreadcrumbs.previousUnfinishedStep;
    if (step != null && step.isNotEmpty) {
      // diagnostic.value = PrintDiagnostic(
      //   message: 'أُغلق التطبيق أثناء الطباعة السابقة في المرحلة:\n$step',
      //   isError: true,
      // );
    }
  }

  static const handlerName = 'printAgent';

  final PrintService _printService;
  final Future<SavedPrinter?> Function() _loadSavedPrinter;
  final ValueNotifier<PrintDiagnostic?> diagnostic =
      ValueNotifier<PrintDiagnostic?>(null);
  Future<void> _queue = Future.value();

  void register(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: handlerName,
      callback: _enqueue,
    );
  }

  Future<Map<String, Object?>> _enqueue(List<Object?> arguments) {
    // diagnostic.value = const PrintDiagnostic(
    //   message: 'وصل طلب الطباعة إلى التطبيق، جارٍ تنفيذه.',
    // );
    final completer = Completer<Map<String, Object?>>();
    // Keep the queue tail as a never-rejecting future so one failed job can
    // never poison the jobs queued after it.
    _queue = _queue
        .then((_) => _process(arguments, completer))
        .catchError((_) {});
    return completer.future;
  }

  Future<void> _process(
    List<Object?> arguments,
    Completer<Map<String, Object?>> completer,
  ) async {
    try {
      var request = PrintRequest.fromBridgeMessage(
        arguments.isEmpty ? null : arguments.first,
      );
      request = await _withSavedPrinter(request);
      final result = await _printService.print(request);
      if (completer.isCompleted) return;
      if (!result.success) {
        _reportFailure(result.error ?? 'تعذر تحديد سبب فشل الطباعة.');
        completer.completeError(PrintBridgeException(result.error));
        return;
      }
      diagnostic.value = null;
      completer.complete(result.toJson());
    } catch (error) {
      _reportFailure('$error');
      if (!completer.isCompleted) {
        completer.completeError(PrintBridgeException('$error'));
      }
    }
  }

  Future<PrintRequest> _withSavedPrinter(PrintRequest request) async {
    if (request.printerIp != null) return request;
    try {
      return applySavedPrinter(request, await _loadSavedPrinter());
    } catch (error) {
      debugPrint('[print] saved printer unavailable: $error');
      return request;
    }
  }

  void _reportFailure(String message) {
    debugPrint('[print][bridge] failed: $message');
    // diagnostic.value = PrintDiagnostic(
    //   message: 'فشلت الطباعة:\n$message',
    //   isError: true,
    // );
  }
}

class PrintDiagnostic {
  const PrintDiagnostic({required this.message, this.isError = false});

  final String message;
  final bool isError;
}

class PrintBridgeException implements Exception {
  const PrintBridgeException(this.message);

  final String? message;

  @override
  String toString() => message ?? 'Print agent failed.';
}
