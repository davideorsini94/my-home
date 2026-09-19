import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'app/providers.dart';
import 'features/settings/settings_service.dart';
import 'firebase_options.dart';
import 'notifications/foreground_handler.dart';
import 'notifications/notification_payload.dart';
import 'notifications/notification_service.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Offline persistence is what makes the app usable without a network and what
  // lets a collection recorded on the doorstep sync later.
  FirebaseFirestore.instance.settings = const Settings(
    persistenceEnabled: true,
    cacheSizeBytes: Settings.CACHE_SIZE_UNLIMITED,
  );

  final settingsService = const SettingsService();
  final settings = await settingsService.load();

  final notificationService = NotificationService();
  await notificationService.initialize(
    onForegroundResponse: onForegroundNotificationResponse,
  );
  notificationService.setExactAlarmsPreference(settings.exactAlarms);

  // A tap that cold-started the app is not delivered to the callback above, so
  // it has to be read out of the launch details instead.
  final launch = await notificationService.launchDetails();
  if (launch?.didNotificationLaunchApp ?? false) {
    final payload = NotificationPayload.decode(
      launch?.notificationResponse?.payload,
    );
    if (payload != null) pendingNavigationHouseId.value = payload.houseId;
  }

  runApp(
    ProviderScope(
      overrides: [
        initialSettingsProvider.overrideWithValue(settings),
        notificationServiceProvider.overrideWithValue(notificationService),
      ],
      child: const MyHomeApp(),
    ),
  );
}
