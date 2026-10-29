import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class LocalAlertService {
  LocalAlertService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _channelId = 'cashier_order_alerts';
  static const _channelName = 'تنبيهات الطلبات';

  final FlutterLocalNotificationsPlugin _plugin;
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    const settings = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      macOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      ),
      windows: WindowsInitializationSettings(
        appName: 'Point of Sale',
        appUserModelId: 'PointOfSale.Terminal.App.1',
        guid: '8f3c1a2e-6b47-4d1a-9c55-2e7b0a4f91d3',
      ),
    );
    await _plugin.initialize(settings: settings);
    _initialized = true;
  }

  Future<bool> requestPermission() async {
    await initialize();
    final iosGranted = await _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >()
        ?.requestPermissions(alert: true, badge: false, sound: true);
    final androidGranted = await _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.requestNotificationsPermission();

    if (iosGranted != null) return iosGranted;
    if (androidGranted != null) return androidGranted;
    return true;
  }

  Future<void> showTestOrderAlert() async {
    await initialize();
    const darwinDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentSound: true,
    );
    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        _channelId,
        _channelName,
        channelDescription: 'تنبيهات وصول طلب جديد إلى صندوق الكاشير',
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
      ),
      iOS: darwinDetails,
      macOS: darwinDetails,
    );
    await _plugin.show(
      id: 1,
      title: 'طلب جديد',
      body: 'تنبيه تجريبي من نقطة البيع',
      notificationDetails: details,
    );
  }
}
