import 'dart:io';

import 'package:flutter/foundation.dart';

import 'local_network_permission.dart';

/// Triggers the iOS local-network permission prompt early, at app startup,
/// instead of on the first print.
///
/// iOS 14+ blocks the first access to the local network (a LAN printer socket)
/// until the user taps "Allow". The native Bonjour-based check
/// ([LocalNetworkPermission]) reliably shows the prompt; plain Dart sockets do
/// not, so a TCP probe is kept only as a fallback if the native check is
/// unavailable. `NSLocalNetworkUsageDescription` must be in Info.plist.
class LocalNetworkPrimer {
  const LocalNetworkPrimer();

  // A common thermal-printer port; nothing needs to be listening for the prompt
  // to appear — the outbound attempt to a LAN address is what counts.
  static const _probePort = 9100;
  static const _probeTimeout = Duration(milliseconds: 400);

  Future<void> warmUp() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
    if (await LocalNetworkPermission.request() != LocalNetworkStatus.unknown) {
      return;
    }
    try {
      final targets = await _localTargets();
      for (final ip in targets) {
        Socket? socket;
        try {
          socket = await Socket.connect(ip, _probePort, timeout: _probeTimeout);
        } catch (_) {
          // Expected: nothing is listening. The attempt still surfaces the iOS
          // local-network permission prompt, which is the whole point.
        } finally {
          socket?.destroy();
        }
      }
    } catch (error) {
      debugPrint('[print][permission] local network warm-up skipped: $error');
    }
  }

  // Builds a small set of LAN addresses to poke: this device's own Wi-Fi IPs and
  // the likely gateway (x.x.x.1), which reliably counts as local-network access.
  // Cellular interfaces (pdp_ip*) are skipped: they are not the local network
  // and probing them never surfaces the prompt.
  Future<List<String>> _localTargets() async {
    final targets = <String>{};
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      if (interface.name.startsWith('pdp_ip')) continue;
      for (final address in interface.addresses) {
        final ip = address.address;
        if (!_isPrivateLan(ip)) continue;
        targets.add(ip);
        final lastDot = ip.lastIndexOf('.');
        if (lastDot > 0) {
          targets.add('${ip.substring(0, lastDot)}.1');
        }
      }
    }
    return targets.toList();
  }

  bool _isPrivateLan(String ip) {
    final parts = ip.split('.').map(int.tryParse).toList();
    if (parts.length != 4 || parts.any((part) => part == null)) return false;
    final a = parts[0]!;
    final b = parts[1]!;
    return a == 10 ||
        (a == 172 && b >= 16 && b <= 31) ||
        (a == 192 && b == 168);
  }
}
