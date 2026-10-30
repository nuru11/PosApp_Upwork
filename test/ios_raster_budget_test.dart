import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointofsalesapp/features/printing/data/ios_raster_budget.dart';

void main() {
  const headDots = 576;
  // 80mm paper at 96 CSS px per inch, which is the slice width in PDF points
  // when the WebView viewport is 1:1.
  const sliceWidthPoints = 80 * 96 / 25.4;

  test('clamps raster dpi to the printer head width', () {
    final dpi = IosRasterBudget.dpiFor(
      headDots: headDots,
      pageWidthPoints: sliceWidthPoints,
    );

    expect(
      dpi,
      inInclusiveRange(IosRasterBudget.minDpi, IosRasterBudget.maxDpi),
    );
    expect(dpi, closeTo(headDots * 72 / sliceWidthPoints, 0.01));
    expect(
      IosRasterBudget.dpiFor(headDots: headDots, pageWidthPoints: 10),
      IosRasterBudget.maxDpi,
    );
    expect(
      IosRasterBudget.dpiFor(headDots: headDots, pageWidthPoints: 5000),
      IosRasterBudget.minDpi,
    );
  });

  test(
    'accepts a 700-point slice and rejects a page that is too tall or wide',
    () {
      final dpi = IosRasterBudget.dpiFor(
        headDots: headDots,
        pageWidthPoints: sliceWidthPoints,
      );

      expect(
        IosRasterBudget.withinPixelBudget(
          pageWidthPoints: sliceWidthPoints,
          pageHeightPoints: 700,
          dpi: dpi,
        ),
        isTrue,
      );
      expect(
        IosRasterBudget.withinPixelBudget(
          pageWidthPoints: sliceWidthPoints,
          pageHeightPoints: 4000,
          dpi: dpi,
        ),
        isFalse,
      );

      final wideDpi = IosRasterBudget.dpiFor(
        headDots: headDots,
        pageWidthPoints: 3000,
      );
      expect(
        IosRasterBudget.withinPixelBudget(
          pageWidthPoints: 3000,
          pageHeightPoints: 1000,
          dpi: wideDpi,
        ),
        isFalse,
      );
      expect(
        IosRasterBudget.withinPixelBudget(
          pageWidthPoints: 0,
          pageHeightPoints: 700,
          dpi: dpi,
        ),
        isFalse,
      );
    },
  );

  test('reads the crop box and falls back to the media box', () {
    final cropped = PdfPageBox.fromPdf(
      latin1.encode('/MediaBox [0 0 300 400] /CropBox [0 0 100.5 200]'),
    );
    expect(cropped, isNotNull);
    expect(cropped!.width, closeTo(100.5, 0.001));
    expect(cropped.height, closeTo(200, 0.001));

    final media = PdfPageBox.fromPdf(
      latin1.encode('/MediaBox [0 0 $sliceWidthPoints 700]'),
    );
    expect(media, isNotNull);
    expect(media!.width, closeTo(sliceWidthPoints, 0.001));
    expect(media.height, 700);
    expect(PdfPageBox.fromPdf(latin1.encode('%PDF')), isNull);
  });
}
