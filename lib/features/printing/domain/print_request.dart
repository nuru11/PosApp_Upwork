class PrintRequest {
  const PrintRequest({
    required this.html,
    required this.title,
    required this.paperWidthMm,
    required this.jobId,
    required this.printerName,
    this.printerIp,
    this.printerPort,
    this.printerProtocol,
  });

  factory PrintRequest.fromBridgeMessage(Object? message) {
    if (message is! Map) {
      throw const FormatException('Print payload must be a JSON object.');
    }

    final payload = Map<String, Object?>.from(message);
    if (payload['type'] != 'print-html') {
      throw const FormatException('Unsupported print message type.');
    }

    final html = payload['html']?.toString() ?? '';
    if (html.trim().isEmpty) {
      throw const FormatException('Print HTML is empty.');
    }

    final context = _asMap(payload['context']);
    final target = _asMap(context['target']);

    return PrintRequest(
      html: html,
      title: _nonEmpty(payload['title']) ?? 'Receipt',
      paperWidthMm: _parsePaperWidthMm(context['paperSize']),
      jobId: _nonEmpty(context['jobId']),
      printerName: _nonEmpty(target['deviceNameEn']),
      printerIp: _nonEmpty(target['ipAddress'] ?? target['ip']),
      printerPort: _parsePort(target['port']),
      printerProtocol: _nonEmpty(target['protocol'])?.toLowerCase(),
    );
  }

  final String html;
  final String title;
  final double? paperWidthMm;
  final String? jobId;
  final String? printerName;
  final String? printerIp;
  final int? printerPort;
  final String? printerProtocol;

  PrintRequest copyWith({
    String? printerName,
    String? printerIp,
    int? printerPort,
    String? printerProtocol,
    double? paperWidthMm,
  }) {
    return PrintRequest(
      html: html,
      title: title,
      paperWidthMm: paperWidthMm ?? this.paperWidthMm,
      jobId: jobId,
      printerName: printerName ?? this.printerName,
      printerIp: printerIp ?? this.printerIp,
      printerPort: printerPort ?? this.printerPort,
      printerProtocol: printerProtocol ?? this.printerProtocol,
    );
  }

  static Map<String, Object?> _asMap(Object? value) =>
      value is Map ? Map<String, Object?>.from(value) : const {};

  static String? _nonEmpty(Object? value) {
    final text = value?.toString().trim();
    return text == null || text.isEmpty ? null : text;
  }

  static double? _parsePaperWidthMm(Object? value) {
    if (value is num) return value.toDouble();
    final text = value?.toString().trim();
    if (text == null || text.isEmpty) {
      return null;
    }
    final match = RegExp(r'\d+(?:\.\d+)?').firstMatch(text);
    if (match == null) {
      throw FormatException('Invalid paperSize "$text".');
    }
    return double.parse(match.group(0)!);
  }

  static int? _parsePort(Object? value) {
    if (value is int) return value;
    final parsed = int.tryParse(value?.toString().trim() ?? '');
    if (parsed == null) return null;
    if (parsed < 1 || parsed > 65535) {
      throw FormatException('Invalid printer port "$value".');
    }
    return parsed;
  }
}

class PrintResult {
  const PrintResult.success({
    required this.jobId,
    required this.printer,
    this.archivedPath,
  }) : success = true,
       error = null;

  const PrintResult.failure({required this.jobId, required this.error})
    : success = false,
      printer = null,
      archivedPath = null;

  final bool success;
  final String? jobId;
  final String? printer;
  final String? archivedPath;
  final String? error;

  Map<String, Object?> toJson() => {
    'success': success,
    'jobId': jobId,
    'printer': printer,
    'archivedPath': archivedPath,
    'error': error,
  };
}
