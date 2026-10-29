import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pointofsalesapp/features/printing/data/receipt_archive.dart';

void main() {
  test(
    'uses the documents directory instead of external storage on iOS',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'receipt-archive-test',
      );
      addTearDown(() => root.delete(recursive: true));

      var externalStorageRequested = false;
      final archive = ReceiptArchive(
        isAndroid: false,
        externalStorageDirectoryProvider: () async {
          externalStorageRequested = true;
          throw UnsupportedError('Not supported on iOS');
        },
        applicationDocumentsDirectoryProvider: () async => root,
      );

      final bytes = Uint8List.fromList([1, 2, 3]);
      final file = await archive.save(fileName: 'job-1', bytes: bytes);

      expect(externalStorageRequested, isFalse);
      expect(file.parent.path, endsWith('Receipts'));
      expect(await file.readAsBytes(), bytes);
    },
  );

  test(
    'falls back to documents when Android external storage is unavailable',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'receipt-archive-test',
      );
      addTearDown(() => root.delete(recursive: true));

      final archive = ReceiptArchive(
        isAndroid: true,
        externalStorageDirectoryProvider: () async => null,
        applicationDocumentsDirectoryProvider: () async => root,
      );

      final file = await archive.save(
        fileName: 'job-2',
        bytes: Uint8List.fromList([4, 5, 6]),
      );

      expect(file.parent.path, endsWith('Receipts'));
      expect(await file.readAsBytes(), [4, 5, 6]);
    },
  );
}
