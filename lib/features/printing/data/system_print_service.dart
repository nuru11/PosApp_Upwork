import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:printing/printing.dart';
import 'package:srag_printer/srag_printer.dart' hide PrintResult;

import 'html_pdf_renderer.dart';
import 'local_network_permission.dart';
import 'print_breadcrumbs.dart';
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
      PrintBreadcrumbs.begin();
      // Start the iOS local-network permission check right away, in parallel
      // with rendering, so the prompt appears immediately on the first print.
      final permission = request.printerIp != null
          ? LocalNetworkPermission.request()
          : null;
      final receipt = await _wrapStage(
        'render receipt',
        request,
        () => _renderer.render(
          html: request.html,
          paperWidthMm: request.paperWidthMm,
        ),
        timeout: const Duration(seconds: 60),
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
            timeout: const Duration(seconds: 15),
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

        if (permission != null) {
          PrintBreadcrumbs.mark('check local network permission');
          if (await permission == LocalNetworkStatus.denied) {
            throw const PrintException(
              'iOS يمنع التطبيق من الوصول إلى الطابعة على الشبكة المحلية. '
              'فعّل "Point of Sale" من: الإعدادات > الخصوصية والأمان > '
              'الشبكة المحلية، ثم أعد الطباعة.',
            );
          }
        }

        await _wrapStage(
          'send network print job',
          request,
          () =>
              _printNetworkWithRetry(request: request, pdfBytes: receipt.bytes),
          timeout: const Duration(seconds: 45),
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
    } finally {
      PrintBreadcrumbs.clear();
    }
  }

  SragPrinterConfig _configFor(PrintRequest request) => SragPrinterConfig(
    paper: _paperFor(request.paperWidthMm),
    chunkSize: 8 * 1024,
    chunkDelay: Duration.zero,
    feedLines: 2,
    cutAfterPrint: true,
  );

  Future<void> _printNetwork({
    required PrintRequest request,
    required List<Uint8List> frames,
  }) async {
    final transport = NetworkPrinterTransport(
      host: request.printerIp!,
      port: request.printerPort ?? 9100,
      timeout: const Duration(seconds: 8),
    );
    final printer = SragPrinter(
      transport: transport,
      config: _configFor(request),
    );
    try {
      PrintBreadcrumbs.mark('send receipt to printer');
      // Hard deadline on the whole send. On timeout we close the socket so a
      // half-sent job cannot keep printing in the background (which would make
      // an operator reprint produce a duplicate receipt).
      await printer.printImages(frames).timeout(const Duration(seconds: 20));
    } on TimeoutException {
      await transport.close();
      throw PrintException(
        'Timed out sending the receipt to '
        '${request.printerIp}:${request.printerPort ?? 9100}.',
      );
    } catch (_) {
      // Ensure the socket is always released; a lingering connection can block
      // the next job on printers that accept only one connection at a time.
      await transport.close();
      rethrow;
    }
  }

  Future<void> _printNetworkWithRetry({
    required PrintRequest request,
    required Uint8List pdfBytes,
  }) async {
    // Rasterize once, before connecting, so retries never redo this work.
    PrintBreadcrumbs.mark('convert PDF to printer image');
    final frames = await _rasterize(request, pdfBytes);

    // A few connect retries give the first print after install time to survive
    // the iOS local-network permission prompt (iOS blocks the first connection
    // to a LAN printer until the user taps Allow). The total stays well under
    // the 45s stage timeout so a blocked job never freezes the print queue.
    const maxAttempts = 4;
    Object? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        await _printNetwork(request: request, frames: frames);
        return;
      } on PrinterConnectionException catch (error) {
        // Only connection failures are safe to retry; nothing was sent yet, so
        // the printer cannot reprint a partial receipt. A mid-stream write
        // failure throws a different exception and is never retried here.
        lastError = error;
        if (attempt == maxAttempts) break;
        _trace(
          'cannot reach printer; retrying ($attempt/$maxAttempts)',
          request,
        );
        final delayMs = (attempt * 1000).clamp(1000, 3000);
        await Future<void>.delayed(Duration(milliseconds: delayMs));
      }
    }
    throw PrintException(
      'Cannot reach the network printer at '
      '${request.printerIp}:${request.printerPort ?? 9100}. '
      'On iPhone/iPad, allow Local Network access for this app '
      '(Settings > Privacy & Security > Local Network), and make sure the '
      'device and printer are on the same Wi-Fi network. ($lastError)',
    );
  }

  SragPaper _paperFor(double? widthMm) {
    if (widthMm != null && widthMm <= 60) {
      return SragPaper.mm58(headDots: 384);
    }
    return SragPaper.mm80Wide();
  }

  // Converts the receipt PDF into ESC/POS-ready image frames sized exactly to
  // the printer head width.
  //
  // Android keeps srag's pdfx-based rasterizer, which is proven to work there.
  // iOS must not use pdfx: on iOS it miscomputes the bitmap size and crashes in
  // Foundation's Data allocation (EXC_BREAKPOINT on queue io.scer.pdf_renderer).
  // Instead iOS rasterizes with the printing package (pdfium) and resizes to the
  // head width in Dart, so the image dimensions can never overflow.
  Future<List<Uint8List>> _rasterize(
    PrintRequest request,
    Uint8List pdfBytes,
  ) async {
    final headDots = _paperFor(request.paperWidthMm).headDots;
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return PdfRasterRenderer(config: _configFor(request)).render(pdfBytes);
    }

    final frames = <Uint8List>[];
    // 150 dpi keeps a bounded receipt (page height is capped during rendering)
    // well within a safe bitmap size; the result is then scaled to head width.
    await for (final page in Printing.raster(pdfBytes, dpi: 150)) {
      final png = await page.toPng();
      final decoded = img.decodeImage(png);
      if (decoded == null) continue;
      final frame = decoded.width == headDots
          ? decoded
          : img.copyResize(
              decoded,
              width: headDots,
              interpolation: img.Interpolation.average,
            );
      frames.add(img.encodePng(frame));
    }
    if (frames.isEmpty) {
      throw const PrintException(
        'Could not rasterize the receipt for printing.',
      );
    }
    return frames;
  }

  Future<T> _wrapStage<T>(
    String stage,
    PrintRequest request,
    FutureOr<T> Function() action, {
    Duration? timeout,
  }) async {
    try {
      _trace(stage, request);
      PrintBreadcrumbs.mark(stage);
      final result = Future<T>.value(action());
      if (timeout == null) return await result;
      return await result.timeout(
        timeout,
        onTimeout: () => throw PrintException(
          'Stage "$stage" did not finish within ${timeout.inSeconds}s. '
          'The device may be stuck rendering, or the printer is not responding.',
        ),
      );
    } on PrintException {
      rethrow;
    } catch (error) {
      throw PrintException('Failed to $stage: $error');
    }
  }

  void _trace(String message, PrintRequest request) {
    debugPrint(
      '[print][job:${request.jobId ?? '-'}][printer:${request.printerName ?? '-'}] '
      '[endpoint:${request.printerIp ?? '-'}:${request.printerPort ?? 9100}] '
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
