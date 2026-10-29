import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../data/system_print_service.dart';
import '../domain/print_request.dart';

class PrintBridge {
  PrintBridge(this._printService);

  static const handlerName = 'printAgent';

  final PrintService _printService;
  Future<void> _queue = Future.value();

  void register(InAppWebViewController controller) {
    controller.addJavaScriptHandler(
      handlerName: handlerName,
      callback: (arguments) => _enqueue(arguments),
    );
  }

  Future<Map<String, Object?>> _enqueue(List<Object?> arguments) {
    final completer = Completer<Map<String, Object?>>();
    // Keep the queue tail as a never-rejecting future so one failed job can
    // never poison the jobs queued after it.
    _queue = _queue.then((_) => _process(arguments, completer)).catchError(
          (_) {},
        );
    return completer.future;
  }

  Future<void> _process(
    List<Object?> arguments,
    Completer<Map<String, Object?>> completer,
  ) async {
    try {
      final request = PrintRequest.fromBridgeMessage(
        arguments.isEmpty ? null : arguments.first,
      );
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
