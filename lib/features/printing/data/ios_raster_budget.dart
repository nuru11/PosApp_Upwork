import 'dart:convert';
import 'dart:typed_data';

/// Page box of one PDF page, in PDF points (1/72 inch).
class PdfPageBox {
  const PdfPageBox({required this.width, required this.height});

  final double width;
  final double height;

  /// Reads the first CropBox, or MediaBox when the page has no crop box.
  ///
  /// WKWebView PDFs keep these dictionaries uncompressed, so this does not
  /// allocate a bitmap. Returns null when neither box can be read.
  static PdfPageBox? fromPdf(Uint8List bytes) {
    final text = latin1.decode(bytes, allowInvalid: true);
    return _readBox(text, 'CropBox') ?? _readBox(text, 'MediaBox');
  }

  static PdfPageBox? _readBox(String text, String name) {
    final match = RegExp(
      '/$name\\s*\\[\\s*([-+]?\\d+(?:\\.\\d+)?)\\s+([-+]?\\d+(?:\\.\\d+)?)\\s+'
      '([-+]?\\d+(?:\\.\\d+)?)\\s+([-+]?\\d+(?:\\.\\d+)?)\\s*\\]',
    ).firstMatch(text);
    if (match == null) return null;
    final x1 = double.tryParse(match.group(1)!);
    final y1 = double.tryParse(match.group(2)!);
    final x2 = double.tryParse(match.group(3)!);
    final y2 = double.tryParse(match.group(4)!);
    if (x1 == null || y1 == null || x2 == null || y2 == null) return null;
    final width = (x2 - x1).abs();
    final height = (y2 - y1).abs();
    if (width <= 0 || height <= 0) return null;
    return PdfPageBox(width: width, height: height);
  }
}

/// Decides the iOS raster scale before native code allocates a bitmap.
///
/// Printing.raster sizes the buffer from the PDF crop box times dpi/72 and
/// aborts the process when that buffer is huge. These checks run in Dart so a
/// bad page fails the print job instead.
class IosRasterBudget {
  const IosRasterBudget._();

  static const double minDpi = 72;
  static const double maxDpi = 144;
  static const int maxPixels = 2000000;

  /// Dpi that makes [pageWidthPoints] about [headDots] wide, clamped so a
  /// tiny or huge page box cannot request an unbounded bitmap.
  static double dpiFor({
    required int headDots,
    required double pageWidthPoints,
  }) {
    if (pageWidthPoints <= 0 || headDots <= 0) return minDpi;
    final dpi = headDots * 72 / pageWidthPoints;
    return dpi.clamp(minDpi, maxDpi);
  }

  static bool withinPixelBudget({
    required double pageWidthPoints,
    required double pageHeightPoints,
    required double dpi,
  }) {
    if (pageWidthPoints <= 0 || pageHeightPoints <= 0 || dpi <= 0) {
      return false;
    }
    final widthPx = pageWidthPoints * dpi / 72;
    final heightPx = pageHeightPoints * dpi / 72;
    return widthPx * heightPx <= maxPixels;
  }
}
