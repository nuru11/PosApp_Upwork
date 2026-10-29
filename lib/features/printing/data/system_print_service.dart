import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:printing/printing.dart';
import 'package:srag_printer/srag_printer.dart' hide PrintResult;

import 'html_pdf_renderer.dart';
import 'receipt_archive.dart';
import '../domain/print_request.dart';

abstract interface class PrintService {
  Future<PrintResult> print(PrintRequest request);
}

/// Clean, user-facing print failure. Avoids leaking Dart's "Bad state" text
/// from [StateError] into the POS web UI.
class PrintException implements Exception {
  const PrintException(this.message);

  final String message;

  @override
  String toString() => message;
}

class SystemPrintService implements PrintService {
  SystemPrintService({HtmlPdfRenderer? renderer, ReceiptArchive? archive})
    : _renderer = renderer ?? HtmlPdfRenderer(),
      _archive = archive ?? ReceiptArchive();

  final HtmlPdfRenderer _renderer;
  final ReceiptArchive _archive;

  @override
  Future<PrintResult> print(PrintRequest request) async {
    try {
      _trace('starting print job', request);
      final receipt = await _wrapStage(
        'render receipt',
        request,
        () => _renderer.render(
          html: request.html,
          paperWidthMm: request.paperWidthMm,
        ),
      );

      String? archivedPath;
      String? archiveWarning;
      if (_persistsForVerification) {
        try {
          final file = await _wrapStage(
            'archive receipt PDF',
            request,
            () => _archive.save(
              fileName: request.jobId ?? request.title,
              bytes: receipt.bytes,
            ),
          );
          archivedPath = file.path;
          _trace('archived receipt PDF at $archivedPath', request);
        } on PrintException catch (error) {
          archiveWarning = error.message;
          _trace('receipt archive unavailable: $archiveWarning', request);
        }
      }

      if (request.printerIp != null) {
        final protocol = request.printerProtocol ?? 'raw';
        if (protocol != 'raw' && protocol != 'escpos') {
          throw UnsupportedError(
            'Unsupported network printer protocol "$protocol". '
            'Use raw or escpos for port 9100.',
          );
        }

        await _wrapStage(
          'send network print job',
          request,
          () =>
              _printNetworkWithRetry(request: request, pdfBytes: receipt.bytes),
        );
        return PrintResult.success(
          jobId: request.jobId,
          printer: request.printerIp,
          archivedPath: archivedPath,
          warning: archiveWarning,
        );
      }

      final info = await Printing.info();
      if (!info.canPrint) {
        throw const PrintException('Printing is unavailable on this device.');
      }

      if (info.directPrint && info.canListPrinters) {
        final printer = await _wrapStage(
          'resolve target printer',
          request,
          () => _resolvePrinter(request.printerName),
        );
        final printed = await _wrapStage(
          'send direct print job',
          request,
          () => Printing.directPrintPdf(
            printer: printer,
            name: request.title,
            format: receipt.format,
            dynamicLayout: false,
            onLayout: (_) async => receipt.bytes,
          ),
        );
        if (!printed) {
          throw const PrintException('The print was not completed.');
        }

        return PrintResult.success(
          jobId: request.jobId,
          printer: printer.name,
          archivedPath: archivedPath,
          warning: archiveWarning,
        );
      }

      final printed = await _wrapStage(
        'open system print dialog',
        request,
        () => Printing.layoutPdf(
          name: request.title,
          format: receipt.format,
          dynamicLayout: false,
          onLayout: (_) async => receipt.bytes,
        ),
      );
      if (!printed) throw const PrintException('The print was not completed.');

      return PrintResult.success(
        jobId: request.jobId,
        printer: null,
        archivedPath: archivedPath,
        warning: archiveWarning,
      );
    } catch (error) {
      _trace('print failed: $error', request);
      return PrintResult.failure(jobId: request.jobId, error: '$error');
    }
  }

  Future<void> _printNetwork({
    required PrintRequest request,
    required Uint8List pdfBytes,
  }) async {
    final printer = SragPrinter(
      transport: NetworkPrinterTransport(
        host: request.printerIp!,
        port: request.printerPort ?? 9100,
      ),
      config: SragPrinterConfig(
        paper: _paperFor(request.paperWidthMm),
        chunkSize: 8 * 1024,
        chunkDelay: Duration.zero,
      ),
    );
    await printer.printPdf(pdfBytes);
  }

  Future<void> _printNetworkWithRetry({
    required PrintRequest request,
    required Uint8List pdfBytes,
  }) async {
    const maxAttempts = 5;
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _printNetwork(request: request, pdfBytes: pdfBytes);
        return;
      } on PrinterConnectionException catch (error) {
        // Only connection (printer busy) is safe to retry; a mid-stream write
        // failure could reprint a partial receipt, so it is never retried.
        lastError = error;
        if (attempt == maxAttempts) break;
        _trace(
          'network printer busy; retrying ($attempt/$maxAttempts)',
          request,
        );
        await Future<void>.delayed(Duration(milliseconds: 150 * attempt));
      }
    }
    throw PrintException('Network printer is busy: $lastError');
  }

  SragPaper _paperFor(double? widthMm) {
    if (widthMm != null && widthMm <= 60) {
      return SragPaper.mm58(headDots: 384);
    }
    return SragPaper.mm80Wide();
  }

  Future<T> _wrapStage<T>(
    String stage,
    PrintRequest request,
    FutureOr<T> Function() action,
  ) async {
    try {
      _trace(stage, request);
      return await action();
    } on PrintException {
      rethrow;
    } catch (error) {
      throw PrintException('Failed to $stage: $error');
    }
  }

  void _trace(String message, PrintRequest request) {
    debugPrint(
      '[print][job:${request.jobId ?? '-'}][printer:${request.printerName ?? '-'}] '
      '[host:${request.printerIp ?? '-'}] '
      '$message',
    );
  }

  bool get _persistsForVerification =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<Printer> _resolvePrinter(String? printerName) async {
    if (printerName == null) {
      throw const PrintException(
        'The print plan does not specify target.deviceNameEn.',
      );
    }

    final printers = await Printing.listPrinters();
    final normalizedTargetName = _normalize(printerName);
    for (final printer in printers.where((value) => value.isAvailable)) {
      if (_normalize(printer.name) == normalizedTargetName) {
        return printer;
      }
    }

    throw PrintException(
      'Printer "$printerName" was not found. Available printers: '
      '${printers.map((printer) => printer.name).join(', ')}',
    );
  }

  String _normalize(String value) => value.trim().toLowerCase();
}
