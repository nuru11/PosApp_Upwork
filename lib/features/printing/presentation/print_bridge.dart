import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../data/system_print_service.dart';
import '../domain/print_request.dart';

class PrintBridge {
  PrintBridge(this._printService);

  static const handlerName = 'printAgent';

  final PrintService _printService;
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
    diagnostic.value = const PrintDiagnostic(
      message: 'وصل طلب الطباعة إلى التطبيق، جارٍ تنفيذه.',
    );
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
      final request = PrintRequest.fromBridgeMessage(
        arguments.isEmpty ? null : arguments.first,
      );
      final result = await _printService.print(request);
      if (completer.isCompleted) return;
      if (!result.success) {
        _reportFailure(result.error ?? 'تعذر تحديد سبب فشل الطباعة.');
        completer.completeError(PrintBridgeException(result.error));
        return;
      }
      diagnostic.value = PrintDiagnostic(
        message: [
          'أُرسلت مهمة الطباعة بنجاح إلى ${result.printer ?? 'طابعة النظام'}.',
          if (result.warning != null) 'تحذير: ${result.warning}',
        ].join('\n'),
      );
      completer.complete(result.toJson());
    } catch (error) {
      _reportFailure('$error');
      if (!completer.isCompleted) {
        completer.completeError(PrintBridgeException('$error'));
      }
    }
  }

  void _reportFailure(String message) {
    debugPrint('[print][bridge] failed: $message');
    diagnostic.value = PrintDiagnostic(
      message: 'فشلت الطباعة:\n$message',
      isError: true,
    );
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
