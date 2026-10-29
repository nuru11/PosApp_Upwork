import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

/// Persists the last generated receipt PDF so that the raw file, with its
/// intrinsic page size preserved, can be inspected by the operator to verify
/// the layout produced by the print pipeline.
class ReceiptArchive {
  ReceiptArchive({
    bool? isAndroid,
    Future<Directory?> Function()? externalStorageDirectoryProvider,
    Future<Directory> Function()? applicationDocumentsDirectoryProvider,
  }) : _isAndroid = isAndroid ?? Platform.isAndroid,
       _externalStorageDirectoryProvider =
           externalStorageDirectoryProvider ?? getExternalStorageDirectory,
       _applicationDocumentsDirectoryProvider =
           applicationDocumentsDirectoryProvider ??
           getApplicationDocumentsDirectory;

  static const _folderName = 'Receipts';

  final bool _isAndroid;
  final Future<Directory?> Function() _externalStorageDirectoryProvider;
  final Future<Directory> Function() _applicationDocumentsDirectoryProvider;

  Future<File> save({
    required String fileName,
    required Uint8List bytes,
  }) async {
    final base = _isAndroid
        ? await _externalStorageDirectoryProvider() ??
              await _applicationDocumentsDirectoryProvider()
        : await _applicationDocumentsDirectoryProvider();
    final folder = Directory(
      '${base.path}${Platform.pathSeparator}$_folderName',
    );
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
