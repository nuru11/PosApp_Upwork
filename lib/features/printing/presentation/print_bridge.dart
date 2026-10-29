import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../../terminal/data/printer_settings_store.dart';
import '../../terminal/domain/saved_printer.dart';
import '../data/system_print_service.dart';
import '../domain/print_request.dart';

class PrintBridge {
  PrintBridge(
    this._printService, {
    Future<SavedPrinter?> Function()? loadSavedPrinter,
  }) : _loadSavedPrinter = loadSavedPrinter ?? PrinterSettingsStore().read;

  static const handlerName = 'printAgent';

  final PrintService _printService;
  final Future<SavedPrinter?> Function() _loadSavedPrinter;
  Future<void> _queue = Future.value();

  void register(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: handlerName,
      callback: (arguments) => _enqueue(arguments),
    );
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

  Future<Map<String, Object?>> _enqueue(List<Object?> arguments) {
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
        completer.completeError(PrintBridgeException(result.error));
        return;
      }
      completer.complete(result.toJson());
    } catch (error) {
      if (!completer.isCompleted) {
        completer.completeError(PrintBridgeException('$error'));
      }
    }
  }
}

class PrintBridgeException implements Exception {
  const PrintBridgeException(this.message);

  final String? message;

  @override
  String toString() => message ?? 'Print agent failed.';
}
