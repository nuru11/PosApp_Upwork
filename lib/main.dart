import 'package:flutter/material.dart';

import 'app/pos_app.dart';
import 'features/web_shell/presentation/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushNotificationService.initialize();
  runApp(PosApp());
}
