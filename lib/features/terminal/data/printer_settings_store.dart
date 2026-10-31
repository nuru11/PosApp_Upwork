import 'package:shared_preferences/shared_preferences.dart';

import '../domain/saved_printer.dart';

class PrinterSettingsStore {
  static const nameKey = 'terminal.printer.name';
  static const ipKey = 'terminal.printer.ip';
  static const portKey = 'terminal.printer.port';
  static const paperWidthKey = 'terminal.printer.paper_width_mm';

  Future<SavedPrinter?> read() async {
    final preferences = await SharedPreferences.getInstance();
    if (!preferences.containsKey(portKey) &&
        !preferences.containsKey(ipKey) &&
        !preferences.containsKey(nameKey) &&
        !preferences.containsKey(paperWidthKey)) {
      return null;
    }

    final name = _nonEmpty(preferences.getString(nameKey));
    final ip = _nonEmpty(preferences.getString(ipKey));
    final port = preferences.getInt(portKey) ?? 9100;
    final paperWidthMm = preferences.getDouble(paperWidthKey) ?? 80;

    return SavedPrinter(
      name: name,
      ip: ip,
      port: port,
      paperWidthMm: paperWidthMm <= 60 ? 58 : 80,
    );
  }

  Future<void> save(SavedPrinter printer) async {
    final preferences = await SharedPreferences.getInstance();
    final name = _nonEmpty(printer.name);
    final ip = _nonEmpty(printer.ip);
    if (name == null) {
      await preferences.remove(nameKey);
    } else {
      await preferences.setString(nameKey, name);
    }
    if (ip == null) {
      await preferences.remove(ipKey);
    } else {
      await preferences.setString(ipKey, ip);
    }
    await preferences.setInt(portKey, printer.port);
    await preferences.setDouble(
      paperWidthKey,
      printer.paperWidthMm <= 60 ? 58 : 80,
    );
  }

  static String? _nonEmpty(String? value) {
    final text = value?.trim();
    return text == null || text.isEmpty ? null : text;
  }
}
