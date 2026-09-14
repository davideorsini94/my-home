import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import 'background_handler.dart';
import 'notification_gateway.dart';

/// Owns the notification plugin: channel setup, permissions and timezone.
class NotificationService implements NotificationGateway {
  NotificationService({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const channelId = 'pickup_reminders';
  static const channelName = 'Promemoria ritiri';
  static const channelDescription =
      'Avviso la sera prima di ogni ritiro dei rifiuti';

  static const maintenanceChannelId = 'maintenance_reminders';
  static const maintenanceChannelName = 'Promemoria manutenzioni';
  static const maintenanceChannelDescription =
      'Avviso il giorno in cui una manutenzione della casa è in scadenza';

  /// Ids of the notification action buttons.
  static const markDoneActionId = 'mark_done';
  static const skipActionId = 'skip';

  bool _initialized = false;
  bool _useExactAlarms = false;

  FlutterLocalNotificationsPlugin get plugin => _plugin;

  /// True when the device grants exact alarms, so reminders land on the minute
  /// instead of within the system's batching window.
  bool get useExactAlarms => _useExactAlarms;

  @override
  AndroidScheduleMode get scheduleMode => _useExactAlarms
      ? AndroidScheduleMode.exactAllowWhileIdle
      : AndroidScheduleMode.inexactAllowWhileIdle;

  Future<void> initialize({
    DidReceiveNotificationResponseCallback? onForegroundResponse,
  }) async {
    if (_initialized) return;

    await _initializeTimezone();

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    // Not const: DarwinNotificationAction.plain is a factory.
    final darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: [
        DarwinNotificationCategory(
          'maintenance',
          actions: [
            DarwinNotificationAction.plain(
              markDoneActionId,
              'Eseguita',
              options: const {DarwinNotificationActionOption.foreground},
            ),
            DarwinNotificationAction.plain(
              skipActionId,
              'Salta',
              options: const {DarwinNotificationActionOption.foreground},
            ),
          ],
        ),
        DarwinNotificationCategory(
          'pickup',
          actions: [
            DarwinNotificationAction.plain(
              markDoneActionId,
              'Raccolta fatta',
              options: const {DarwinNotificationActionOption.foreground},
            ),
            DarwinNotificationAction.plain(
              skipActionId,
              'Salta',
              options: const {DarwinNotificationActionOption.foreground},
            ),
          ],
        ),
      ],
    );

    await _plugin.initialize(
      settings: InitializationSettings(android: android, iOS: darwin),
      onDidReceiveNotificationResponse: onForegroundResponse,
      onDidReceiveBackgroundNotificationResponse:
          onBackgroundNotificationResponse,
    );

    await _createAndroidChannel();
    await _refreshExactAlarmCapability();

    _initialized = true;
  }

  Future<void> _initializeTimezone() async {
    tzdata.initializeTimeZones();
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(info.identifier));
    } on Exception catch (e) {
      // An unknown IANA name must not stop the app from scheduling anything.
      debugPrint('Timezone non riconosciuto, uso Europe/Rome: $e');
      tz.setLocalLocation(tz.getLocation('Europe/Rome'));
    }
  }

  Future<void> _createAndroidChannel() async {
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    if (android == null) return;
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        channelId,
        channelName,
        description: channelDescription,
        importance: Importance.high,
      ),
    );
    // A separate channel so the user can silence maintenance reminders without
    // losing the waste ones, from the system settings.
    await android.createNotificationChannel(
      const AndroidNotificationChannel(
        maintenanceChannelId,
        maintenanceChannelName,
        description: maintenanceChannelDescription,
        importance: Importance.high,
      ),
    );
  }

  Future<void> _refreshExactAlarmCapability() async {
    if (!Platform.isAndroid) return;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    _useExactAlarms = await android?.canScheduleExactNotifications() ?? false;
  }

  /// Whether the OS currently lets the app post notifications.
  Future<bool> areNotificationsEnabled() async {
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.areNotificationsEnabled() ?? false;
    }
    return true;
  }

  /// Asks for the POST_NOTIFICATIONS runtime permission (Android 13+) or the
  /// iOS equivalent.
  Future<bool> requestPermission() async {
    if (Platform.isAndroid) {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      return await android?.requestNotificationsPermission() ?? false;
    }
    final darwin = _plugin
        .resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin
        >();
    return await darwin?.requestPermissions(
          alert: true,
          badge: true,
          sound: true,
        ) ??
        false;
  }

  Future<bool> canScheduleExactAlarms() async {
    if (!Platform.isAndroid) return true;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    return await android?.canScheduleExactNotifications() ?? false;
  }

  /// Opens the system screen for the "alarms & reminders" special access.
  ///
  /// Exact alarms are opt-in rather than the default: an evening reminder
  /// tolerates the system's batching window, and requesting the special access
  /// up front is friction the app does not need.
  Future<bool> requestExactAlarmsPermission() async {
    if (!Platform.isAndroid) return true;
    final android = _plugin
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    final granted = await android?.requestExactAlarmsPermission() ?? false;
    _useExactAlarms = granted;
    return granted;
  }

  @override
  void setExactAlarmsPreference(bool enabled) {
    _useExactAlarms = enabled;
  }

  @override
  Future<List<PendingNotificationRequest>> pending() =>
      _plugin.pendingNotificationRequests();

  @override
  Future<void> cancel(int id) => _plugin.cancel(id: id);

  @override
  Future<void> cancelAll() => _plugin.cancelAll();

  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required String title,
    required String body,
    required String payload,
    required AndroidScheduleMode androidScheduleMode,
    required NotificationDetails notificationDetails,
  }) => _plugin.zonedSchedule(
    id: id,
    scheduledDate: scheduledDate,
    title: title,
    body: body,
    payload: payload,
    androidScheduleMode: androidScheduleMode,
    notificationDetails: notificationDetails,
  );

  Future<NotificationAppLaunchDetails?> launchDetails() =>
      _plugin.getNotificationAppLaunchDetails();
}
