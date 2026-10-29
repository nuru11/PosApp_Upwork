import 'package:flutter_test/flutter_test.dart';
import 'package:pointofsalesapp/features/printing/domain/print_request.dart';

void main() {
  test('parses the Angular print agent payload', () {
    final request = PrintRequest.fromBridgeMessage({
      'type': 'print-html',
      'title': 'SalesReceipt-24',
      'html': '<html><body>Receipt</body></html>',
      'context': {
        'paperSize': '58mm',
        'jobId': 'job-1',
        'sequence': 0,
        'documentType': 1,
        'target': {
          'deviceCode': '2239',
          'deviceNameAr': 'طابعة الكاشير',
          'deviceNameEn': 'SunmiPrinter',
        },
      },
    });

    expect(request.title, 'SalesReceipt-24');
    expect(request.paperWidthMm, 58);
    expect(request.jobId, 'job-1');
    expect(request.printerName, 'SunmiPrinter');
  });

  test('reads network printer routing from the target', () {
    final request = PrintRequest.fromBridgeMessage({
      'type': 'print-html',
      'html': '<html><body>Network receipt</body></html>',
      'context': {
        'target': {
          'deviceNameEn': 'Kitchen Printer',
          'ipAddress': '192.168.100.99',
          'port': '9100',
          'protocol': 'RAW',
        },
      },
    });

    expect(request.printerIp, '192.168.100.99');
    expect(request.printerPort, 9100);
    expect(request.printerProtocol, 'raw');
  });

  test('does not use the Arabic name or device code for printer routing', () {
    final request = PrintRequest.fromBridgeMessage({
      'type': 'print-html',
      'html': '<html><body>Kitchen order</body></html>',
      'context': {
        'paperSize': '80mm',
        'target': {
          'deviceCode': 'KITCHEN-01',
          'deviceNameAr': 'طابعة المطبخ',
          'deviceNameEn': '  Kitchen Printer  ',
        },
      },
    });

    expect(request.printerName, 'Kitchen Printer');
    expect(request.paperWidthMm, 80);
  });

  test('rejects unsupported messages before they reach a printer', () {
    expect(
      () => PrintRequest.fromBridgeMessage({'type': 'unknown', 'html': 'x'}),
      throwsFormatException,
    );
  });

  test('reads any paper width supplied by the print plan', () {
    final request = PrintRequest.fromBridgeMessage({
      'type': 'print-html',
      'html': '<html><body>Report</body></html>',
      'context': {
        'paperSize': '110 mm',
        'target': {'deviceNameEn': 'A5 Printer'},
      },
    });

    expect(request.paperWidthMm, 110);
  });

  test('keeps paper width unset when the plan omits it', () {
    final request = PrintRequest.fromBridgeMessage({
      'type': 'print-html',
      'html': '<html><body>Report</body></html>',
      'context': {
        'target': {'deviceNameEn': 'A5 Printer'},
      },
    });

    expect(request.paperWidthMm, isNull);
  });

  test('includes non-blocking warnings in successful print results', () {
    final result = PrintResult.success(
      jobId: 'job-1',
      printer: '192.168.1.50',
      warning: 'Receipt archive unavailable.',
    );

    expect(result.toJson()['warning'], 'Receipt archive unavailable.');
  });
}
