import 'dart:convert';

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

  test(
    're-renders tall enough to collapse a multi-page PDF into one page',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      // Emulates UIPrintPageRenderer: content needs ~120mm, so any page shorter
      // than that paginates. The first render at 46mm yields 3 pages.
      final converter = _PaginatingConverter(contentHeightMm: 120);
      final renderer = HtmlPdfRenderer(
        nativeConverter: converter,
        sizer: _FakeHtmlContentSizer(heightMm: 40),
      );

      final receipt = await renderer.render(
        html: '<html><body>Multi page receipt</body></html>',
        paperWidthMm: 80,
      );

      const pointsPerMm = 72 / 25.4;
      // The final PDF must be a single page tall enough to hold all content.
      expect(converter.lastPageCount, 1);
      expect(converter.lastPageSize!.height, greaterThan(120 * pointsPerMm));
      expect(receipt.format.height, greaterThan(120 * PdfPageFormat.mm));
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

/// Emulates a native converter that paginates content taller than the page,
/// emitting one `/Type /Page` object per page so page counting can detect it.
class _PaginatingConverter extends HtmlToPdfConverter {
  _PaginatingConverter({required this.contentHeightMm});

  final double contentHeightMm;
  PdfPageSize? lastPageSize;
  int lastPageCount = 0;

  @override
  Future<Uint8List> convertHtmlToPdfBytes({
    required String html,
    PdfPageSize? pageSize,
  }) async {
    lastPageSize = pageSize;
    const pointsPerMm = 72 / 25.4;
    final pageHeightMm = (pageSize?.height ?? 1) / pointsPerMm;
    lastPageCount = (contentHeightMm / pageHeightMm).ceil().clamp(1, 1000);
    final body = List.filled(lastPageCount, '/Type /Page\n').join();
    return Uint8List.fromList(latin1.encode('%PDF-1.7\n$body'));
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
