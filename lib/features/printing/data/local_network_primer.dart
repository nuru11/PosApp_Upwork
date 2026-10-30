import 'dart:io';

import 'package:flutter/foundation.dart';

/// Triggers the iOS local-network permission prompt early, at app startup,
/// instead of on the first print.
///
/// iOS 14+ blocks the first access to the local network (a LAN printer socket)
/// until the user taps "Allow". If that prompt only appears on the first print,
/// the first jobs are blocked and pile up as "printing..." until the user taps
/// Allow — exactly the "stuck for a few tries, then suddenly prints" behaviour.
///
/// A plain outbound TCP connection attempt to a LAN address surfaces the prompt
/// without needing the multicast entitlement (which `joinMulticast` would
/// require on iOS 14+, and which Apple must approve). The connection is expected
/// to fail — only the attempt matters — and `NSLocalNetworkUsageDescription`
/// must be present in Info.plist for the prompt to appear.
class LocalNetworkPrimer {
  const LocalNetworkPrimer();

  // A common thermal-printer port; nothing needs to be listening for the prompt
  // to appear — the outbound attempt to a LAN address is what counts.
  static const _probePort = 9100;
  static const _probeTimeout = Duration(milliseconds: 400);

  Future<void> warmUp() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) return;
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
  Future<List<String>> _localTargets() async {
    final targets = <String>{};
    final interfaces = await NetworkInterface.list(
      type: InternetAddressType.IPv4,
      includeLoopback: false,
    );
    for (final interface in interfaces) {
      for (final address in interface.addresses) {
        final ip = address.address;
        targets.add(ip);
        final lastDot = ip.lastIndexOf('.');
        if (lastDot > 0) {
          targets.add('${ip.substring(0, lastDot)}.1');
        }
      }
    }
    return targets.toList();
  }
}
