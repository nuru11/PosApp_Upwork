import 'dart:async';

import 'package:flutter/material.dart';

import 'app/pos_app.dart';
import 'features/printing/data/local_network_primer.dart';
import 'features/web_shell/presentation/push_notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await PushNotificationService.initialize();
  runApp(PosApp());
  // Surface the iOS local-network permission prompt at startup (not during the
  // first print), so network print jobs are never blocked waiting for the user
  // to tap "Allow". Fire-and-forget so it never delays the first frame.
  unawaited(const LocalNetworkPrimer().warmUp());
}
