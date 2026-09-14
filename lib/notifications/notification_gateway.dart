import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

/// The narrow slice of the notification plugin the scheduler actually uses.
///
/// It exists so the scheduler can be tested. Without it every scheduling
/// decision runs straight into a platform channel, and the one piece of logic
/// that can silently cancel every reminder on a real device — deciding which
/// pending ids are still wanted — has no way of being checked in CI.
abstract interface class NotificationGateway {
  AndroidScheduleMode get scheduleMode;

  void setExactAlarmsPreference(bool enabled);

  Future<List<PendingNotificationRequest>> pending();

  Future<void> cancel(int id);

  Future<void> cancelAll();

  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required String title,
    required String body,
    required String payload,
    required AndroidScheduleMode androidScheduleMode,
    required NotificationDetails notificationDetails,
  });
}
