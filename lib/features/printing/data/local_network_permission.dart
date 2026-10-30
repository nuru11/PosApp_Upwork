import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

enum LocalNetworkStatus { granted, denied, unknown }

/// Requests and checks the iOS Local Network permission through the native
/// `LocalNetworkPermissionPlugin` in AppDelegate.swift.
///
/// The first call shows the system prompt; later calls only report the stored
/// decision. Non-iOS platforms do not have this permission.
class LocalNetworkPermission {
  const LocalNetworkPermission._();

  static const _channel = MethodChannel('pos/local_network_permission');

  static Future<LocalNetworkStatus> request() async {
    if (defaultTargetPlatform != TargetPlatform.iOS) {
      return LocalNetworkStatus.granted;
    }
    try {
      final status = await _channel
          .invokeMethod<String>('request')
          .timeout(const Duration(seconds: 35));
      debugPrint('[print][permission] local network: $status');
      return switch (status) {
        'granted' => LocalNetworkStatus.granted,
        'denied' => LocalNetworkStatus.denied,
        _ => LocalNetworkStatus.unknown,
      };
    } catch (error) {
      debugPrint('[print][permission] local network check failed: $error');
      return LocalNetworkStatus.unknown;
    }
  }
}
