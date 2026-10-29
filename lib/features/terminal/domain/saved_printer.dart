import '../../printing/domain/print_request.dart';

class SavedPrinter {
  const SavedPrinter({
    this.name,
    this.ip,
    this.port = 9100,
    this.paperWidthMm = 80,
  });

  final String? name;
  final String? ip;
  final int port;
  final double paperWidthMm;

  bool get hasNetworkAddress {
    final address = ip?.trim();
    return address != null && address.isNotEmpty;
  }

  String get statusLabel {
    if (!hasNetworkAddress && (name == null || name!.trim().isEmpty)) {
      return 'لم يتم حفظ طابعة';
    }
    final label = (name == null || name!.trim().isEmpty)
        ? ip!.trim()
        : name!.trim();
    return 'الطابعة: $label';
  }
}

/// Uses the printer saved on this device only when the website print job has
/// no network address. A target the website already addressed is kept.
PrintRequest applySavedPrinter(PrintRequest request, SavedPrinter? saved) {
  if (request.printerIp != null) return request;
  if (saved == null || !saved.hasNetworkAddress) return request;

  return request.copyWith(
    printerName: request.printerName ?? saved.name,
    printerIp: saved.ip!.trim(),
    printerPort: saved.port,
    printerProtocol: request.printerProtocol ?? 'raw',
    paperWidthMm: request.paperWidthMm ?? saved.paperWidthMm,
  );
}
