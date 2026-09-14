import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/local_date.dart';
import 'maintenance_reminder_plan.dart';
import 'notification_gateway.dart';
import 'notification_service.dart';
import 'reminder_plan.dart';

/// How many pending notifications each feature may hold.
///
/// iOS caps pending notifications at 64. Waste gives up four of its former 48
/// so maintenance has room; both numbers are passed explicitly rather than left
/// to a default, and both are asserted by the scheduler tests.
const int wasteNotificationBudget = 44;
const int maintenanceNotificationBudget = 16;

/// Keeps the OS's pending notifications in step with the current schedules,
/// counters and maintenance due dates.
///
/// Local notifications are static strings fixed at scheduling time, so the only
/// way to keep them honest when another family member records something on
/// their own device is to rewrite them. Ids are deterministic, so re-scheduling
/// the same id replaces the pending notification in place.
///
/// This runs on app start, on resume, and whenever the underlying data changes.
/// It is deliberately trigger-agnostic, so an FCM wake-up could drive it
/// unchanged if push is ever added.
class NotificationScheduler {
  NotificationScheduler(this._gateway);

  final NotificationGateway _gateway;

  Future<void> sync({
    required List<HouseReminderInput> wasteHouses,
    required List<MaintenanceReminderInput> maintenanceHouses,
    required int notificationHour,
    required int notificationMinute,
    bool wasteEnabled = true,
    bool maintenanceEnabled = true,
    DateTime? nowOverride,
  }) async {
    final now = nowOverride ?? DateTime.now();
    final today = LocalDate.fromDateTime(now);

    final wastePlans = wasteEnabled
        ? buildReminderPlans(
            houses: wasteHouses,
            today: today,
            now: now,
            notificationHour: notificationHour,
            notificationMinute: notificationMinute,
            maxPending: wasteNotificationBudget,
          )
        : const <ReminderPlan>[];

    final maintenancePlans = maintenanceEnabled
        ? buildMaintenanceReminderPlans(
            houses: maintenanceHouses,
            today: today,
            now: now,
            notificationHour: notificationHour,
            notificationMinute: notificationMinute,
            maxPending: maintenanceNotificationBudget,
          )
        : const <MaintenanceReminderPlan>[];

    // The union of BOTH kinds. Getting this wrong cancels every reminder of the
    // kind left out, silently and only on a real device — which is why it is
    // computed in one place and covered by tests.
    final wanted = <int>{
      ...wastePlans.map((p) => p.id),
      ...maintenancePlans.map((p) => p.id),
    };

    await _cancelObsolete(wanted);

    for (final plan in wastePlans) {
      await _schedule(
        id: plan.id,
        fireAt: plan.fireAt,
        title: plan.title,
        body: plan.body,
        payload: plan.payload.encode(),
        details: _wasteDetails(),
      );
    }

    for (final plan in maintenancePlans) {
      await _schedule(
        id: plan.id,
        fireAt: plan.fireAt,
        title: plan.title,
        body: plan.body,
        payload: plan.payload.encode(),
        details: _maintenanceDetails(),
      );
    }
  }

  /// Cancels only the reminders that are no longer wanted.
  ///
  /// Never `cancelAll()`: that would also dismiss a reminder currently showing
  /// in the notification shade, which the user may be about to act on.
  Future<void> _cancelObsolete(Set<int> wanted) async {
    final List<PendingNotificationRequest> pending;
    try {
      pending = await _gateway.pending();
    } on Exception catch (e) {
      debugPrint('Lettura notifiche pendenti non riuscita: $e');
      return;
    }
    // Iterate a snapshot of the ids: cancelling may mutate the collection the
    // plugin handed back, and the loop must not depend on it not doing so.
    final obsolete = [
      for (final request in pending)
        if (!wanted.contains(request.id)) request.id,
    ];
    for (final id in obsolete) {
      await _gateway.cancel(id);
    }
  }

  Future<void> _schedule({
    required int id,
    required DateTime fireAt,
    required String title,
    required String body,
    required String payload,
    required NotificationDetails details,
  }) async {
    final scheduledDate = tz.TZDateTime(
      tz.local,
      fireAt.year,
      fireAt.month,
      fireAt.day,
      fireAt.hour,
      fireAt.minute,
    );

    try {
      await _gateway.zonedSchedule(
        id: id,
        scheduledDate: scheduledDate,
        title: title,
        body: body,
        payload: payload,
        androidScheduleMode: _gateway.scheduleMode,
        notificationDetails: details,
      );
    } on PlatformException catch (e) {
      // The exact-alarm grant can be revoked at any moment; fall back rather
      // than losing the reminder.
      if (e.code == 'exact_alarms_not_permitted') {
        _gateway.setExactAlarmsPreference(false);
        await _gateway.zonedSchedule(
          id: id,
          scheduledDate: scheduledDate,
          title: title,
          body: body,
          payload: payload,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          notificationDetails: details,
        );
      } else {
        rethrow;
      }
    }
  }

  NotificationDetails _wasteDetails() => const NotificationDetails(
    android: AndroidNotificationDetails(
      NotificationService.channelId,
      NotificationService.channelName,
      channelDescription: NotificationService.channelDescription,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
      actions: [
        AndroidNotificationAction(
          NotificationService.markDoneActionId,
          'Raccolta fatta',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          NotificationService.skipActionId,
          'Salta',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    ),
    iOS: DarwinNotificationDetails(categoryIdentifier: 'pickup'),
  );

  NotificationDetails _maintenanceDetails() => const NotificationDetails(
    android: AndroidNotificationDetails(
      NotificationService.maintenanceChannelId,
      NotificationService.maintenanceChannelName,
      channelDescription: NotificationService.maintenanceChannelDescription,
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(''),
      actions: [
        AndroidNotificationAction(
          NotificationService.markDoneActionId,
          'Eseguita',
          showsUserInterface: false,
          cancelNotification: true,
        ),
        AndroidNotificationAction(
          NotificationService.skipActionId,
          'Salta',
          showsUserInterface: false,
          cancelNotification: true,
        ),
      ],
    ),
    iOS: DarwinNotificationDetails(categoryIdentifier: 'maintenance'),
  );

  Future<void> cancelAllForSignOut() => _gateway.cancelAll();
}
