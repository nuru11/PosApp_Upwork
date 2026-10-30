import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_native_html_to_pdf/flutter_native_html_to_pdf.dart';
import 'package:pdf/pdf.dart';
import 'package:pointofsalesapp/features/printing/data/html_content_sizer.dart';
import 'package:pointofsalesapp/features/printing/data/html_pdf_renderer.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'uses a dynamic height that follows short kitchen receipt content',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final converter = _FakeHtmlToPdfConverter();
      final renderer = HtmlPdfRenderer(
        nativeConverter: converter,
        sizer: _FakeHtmlContentSizer(heightMm: 40),
      );

      final receipt = await renderer.render(
        html: '<html><body>Kitchen order</body></html>',
        paperWidthMm: 80,
      );

      // The height follows the measured content (plus the overflow guard) and
      // is not padded up to a fixed page height, so a short order stays short.
      const pointsPerMm = 72 / 25.4;
      const expectedHeightMm = 40 + 6.0;
      expect(converter.lastPageSize, isNotNull);
      expect(
        converter.lastPageSize!.height,
        closeTo(expectedHeightMm * pointsPerMm, 0.01),
      );
      expect(
        receipt.format.height,
        closeTo(expectedHeightMm * PdfPageFormat.mm, 0.01),
      );
      expect(receipt.format.height, lessThan(receipt.format.width));
      expect(converter.lastHtml, contains('@page { margin: 0; }'));
      expect(converter.lastHtml, contains('width: 100% !important;'));
      expect(converter.lastHtml, contains('margin: 0 !important;'));
    },
  );

  test(
    'adds an overflow guard so long receipts stay on a single page',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final converter = _FakeHtmlToPdfConverter();
      final renderer = HtmlPdfRenderer(
        nativeConverter: converter,
        sizer: _FakeHtmlContentSizer(heightMm: 150),
      );

      final receipt = await renderer.render(
        html: '<html><body>Long sales receipt</body></html>',
        paperWidthMm: 80,
      );

      // The page must be taller than the measured content so a trailing margin
      // cannot spill onto a second, equally tall blank page.
      const pointsPerMm = 72 / 25.4;
      expect(converter.lastPageSize!.height, greaterThan(150 * pointsPerMm));
      expect(receipt.format.height, greaterThan(150 * PdfPageFormat.mm));
    },
  );
}

class _FakeHtmlToPdfConverter extends HtmlToPdfConverter {
  PdfPageSize? lastPageSize;
  String? lastHtml;

  @override
  Future<Uint8List> convertHtmlToPdfBytes({
    required String html,
    PdfPageSize? pageSize,
  }) async {
    lastHtml = html;
    lastPageSize = pageSize;
    return Uint8List.fromList([1, 2, 3]);
  }
}

class _FakeHtmlContentSizer extends HtmlContentSizer {
  const _FakeHtmlContentSizer({required this.heightMm});

  final double heightMm;

  @override
  Future<double> measureHeightMm({
    required String html,
    required double paperWidthMm,
  }) async => heightMm;
}
