import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Persists the last generated receipt PDF so that the raw file, with its
/// intrinsic page size preserved, can be inspected by the operator to verify
/// the layout produced by the print pipeline.
class ReceiptArchive {
  const ReceiptArchive();

  static const _folderName = 'Receipts';

  Future<File> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final base =
        await getExternalStorageDirectory() ??
        await getApplicationDocumentsDirectory();
    final folder = Directory('${base.path}${Platform.pathSeparator}$_folderName');
    if (!await folder.exists()) {
      await folder.create(recursive: true);
    }
    final file = File(
      '${folder.path}${Platform.pathSeparator}${_sanitize(fileName)}.pdf',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file;
  }

  String _sanitize(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
}
