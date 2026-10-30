import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Persists the current print step to disk before it runs, so that if the app
/// is killed mid-print (a native crash) the next launch can report exactly
/// which step it died in, without needing Xcode or device logs.
class PrintBreadcrumbs {
  const PrintBreadcrumbs._();

  static File? _file;

  // Steps are only recorded while a print job is active, so work that outlives
  // a timed-out job cannot leave a false "closed during printing" record.
  static bool _active = false;

  /// Step recorded by a print job that never finished in the previous run.
  static String? previousUnfinishedStep;

  static Future<void> init() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}print_step.txt');
      if (await file.exists()) {
        previousUnfinishedStep = (await file.readAsString()).trim();
        await file.delete();
      }
      _file = file;
    } catch (error) {
      debugPrint('[print][breadcrumb] unavailable: $error');
    }
  }

  static void begin() {
    _active = true;
  }

  static void mark(String step) {
    debugPrint('[print][step] $step');
    if (!_active) return;
    try {
      _file?.writeAsStringSync(step, flush: true);
    } catch (_) {}
  }

  static void clear() {
    _active = false;
    try {
      final file = _file;
      if (file != null && file.existsSync()) file.deleteSync();
    } catch (_) {}
  }
}
