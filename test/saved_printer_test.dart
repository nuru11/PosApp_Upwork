import 'package:flutter_test/flutter_test.dart';
import 'package:pointofsalesapp/features/printing/domain/print_request.dart';
import 'package:pointofsalesapp/features/terminal/domain/saved_printer.dart';

void main() {
  const saved = SavedPrinter(
    name: 'طابعة الكاشير',
    ip: '192.168.1.50',
    port: 9100,
    paperWidthMm: 58,
  );

  PrintRequest request({
    String? printerIp,
    double? paperWidthMm,
    String? printerName,
  }) {
    return PrintRequest(
      html: '<html><body>Receipt</body></html>',
      title: 'Receipt',
      paperWidthMm: paperWidthMm,
      jobId: 'job-1',
      printerName: printerName,
      printerIp: printerIp,
    );
  }

  test('fills a missing website printer address from the saved printer', () {
    final resolved = applySavedPrinter(
      request(printerName: 'SunmiPrinter'),
      saved,
    );

    expect(resolved.printerIp, '192.168.1.50');
    expect(resolved.printerPort, 9100);
    expect(resolved.printerProtocol, 'raw');
    expect(resolved.printerName, 'SunmiPrinter');
    expect(resolved.paperWidthMm, 58);
  });

  test('keeps a printer address the website already sent', () {
    final resolved = applySavedPrinter(
      request(printerIp: '10.0.0.8', paperWidthMm: 80, printerName: 'Kitchen'),
      saved,
    );

    expect(resolved.printerIp, '10.0.0.8');
    expect(resolved.printerPort, isNull);
    expect(resolved.printerProtocol, isNull);
    expect(resolved.printerName, 'Kitchen');
    expect(resolved.paperWidthMm, 80);
  });

  test('leaves the job unchanged when no printer is saved', () {
    final original = request(printerName: 'SunmiPrinter', paperWidthMm: 80);

    final resolved = applySavedPrinter(original, null);
    final withoutAddress = applySavedPrinter(
      original,
      const SavedPrinter(name: 'طابعة الكاشير', paperWidthMm: 58),
    );

    expect(resolved.printerIp, isNull);
    expect(withoutAddress.printerIp, isNull);
    expect(withoutAddress.paperWidthMm, 80);
    expect(withoutAddress.printerName, 'SunmiPrinter');
  });
}
