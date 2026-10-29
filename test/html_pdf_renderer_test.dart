import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_native_html_to_pdf/flutter_native_html_to_pdf.dart';
import 'package:pointofsalesapp/features/printing/data/html_content_sizer.dart';
import 'package:pointofsalesapp/features/printing/data/html_pdf_renderer.dart';

void main() {
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  test('keeps thermal kitchen receipts in portrait when content is short', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final converter = _FakeHtmlToPdfConverter();
    final renderer = HtmlPdfRenderer(
      nativeConverter: converter,
      sizer: _FakeHtmlContentSizer(heightMm: 63.5),
    );

    final receipt = await renderer.render(
      html: '<html><body>Kitchen order</body></html>',
      paperWidthMm: 80,
    );

    expect(converter.lastPageSize, isNotNull);
    expect(converter.lastPageSize!.width, lessThan(converter.lastPageSize!.height));
    expect(receipt.format.width, lessThan(receipt.format.height));
    expect(converter.lastHtml, contains('@page { margin: 0; }'));
    expect(converter.lastHtml, contains('width: 100% !important;'));
    expect(converter.lastHtml, contains('margin: 0 !important;'));
  });
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