import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await PushNotificationService.handleBackgroundMessage(message);
}

class PushNotificationService {
  PushNotificationService._();

  static final ValueNotifier<String?> tokenListenable = ValueNotifier<String?>(
    null,
  );

  static bool _initialized = false;
  static bool _available = false;
  static StreamSubscription<String>? _tokenRefreshSubscription;
  static StreamSubscription<RemoteMessage>? _foregroundMessageSubscription;

  static String? get currentToken => tokenListenable.value;

  static bool get isAvailable => _available;

  static Future<void> initialize() async {
    if (_initialized) {
      return;
    }
    _initialized = true;

    final options = _firebaseOptions;
    if (options == null) {
      debugPrint(
        '[push] Firebase configuration missing. Set FIREBASE_* dart-defines to enable push notifications.',
      );
      return;
    }

    try {
      await _ensureFirebaseInitialized(options);
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
      await _requestPermission();
      await _refreshToken();

      _tokenRefreshSubscription = FirebaseMessaging.instance.onTokenRefresh.listen(
        (token) {
          tokenListenable.value = token.trim().isEmpty ? null : token.trim();
          debugPrint('[push] Token refreshed.');
        },
      );

      _foregroundMessageSubscription = FirebaseMessaging.onMessage.listen((message) {
        debugPrint(
          '[push] Foreground message received: '
          'id=${message.messageId ?? '-'} type=${message.data['type'] ?? '-'}',
        );
        unawaited(_playNotificationSound());
      });

      _available = true;
      debugPrint('[push] Firebase messaging initialized.');
    } catch (error, stackTrace) {
      debugPrint('[push] Firebase messaging initialization failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static Future<void> handleBackgroundMessage(RemoteMessage message) async {
    final options = _firebaseOptions;
    if (options == null) {
      return;
    }

    await _ensureFirebaseInitialized(options);
    debugPrint(
      '[push] Background message received: '
      'id=${message.messageId ?? '-'} type=${message.data['type'] ?? '-'}',
    );
    await _playNotificationSound();
  }

  static Future<void> dispose() async {
    await _tokenRefreshSubscription?.cancel();
    await _foregroundMessageSubscription?.cancel();
    _tokenRefreshSubscription = null;
    _foregroundMessageSubscription = null;
  }

  static Future<void> _ensureFirebaseInitialized(FirebaseOptions options) async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: options);
    }
  }

  static Future<void> _requestPermission() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
    );
  }

  static Future<void> _refreshToken() async {
    final token = await FirebaseMessaging.instance.getToken();
    tokenListenable.value = token?.trim().isEmpty ?? true ? null : token!.trim();
    if (tokenListenable.value != null) {
      debugPrint('[push] Token acquired.');
    }
  }

  static Future<void> _playNotificationSound() async {
    try {
      await FlutterRingtonePlayer().playNotification();
    } catch (error, stackTrace) {
      debugPrint('[push] Notification sound playback failed: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  static FirebaseOptions? get _firebaseOptions {
    const apiKey = String.fromEnvironment('FIREBASE_API_KEY');
    const appId = String.fromEnvironment('FIREBASE_APP_ID');
    const messagingSenderId = String.fromEnvironment(
      'FIREBASE_MESSAGING_SENDER_ID',
    );
    const projectId = String.fromEnvironment('FIREBASE_PROJECT_ID');
    const storageBucket = String.fromEnvironment('FIREBASE_STORAGE_BUCKET');

    if (
        apiKey.isEmpty ||
        appId.isEmpty ||
        messagingSenderId.isEmpty ||
        projectId.isEmpty) {
      return null;
    }

    return FirebaseOptions(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: messagingSenderId,
      projectId: projectId,
      storageBucket: storageBucket.isEmpty ? null : storageBucket,
    );
  }
}