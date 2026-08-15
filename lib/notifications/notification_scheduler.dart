import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../core/local_date.dart';
import 'notification_service.dart';
import 'reminder_plan.dart';

/// Keeps the OS's pending notifications in step with the current schedules and
/// counters.
///
/// Local notifications are static strings fixed at scheduling time, so the only
/// way to keep "ritiri gratuiti rimanenti" honest when another family member
/// records a collection on their own device is to rewrite them. Reminder ids
/// are deterministic, so re-scheduling the same id replaces the pending
/// notification in place — the refresh costs nothing and needs no server.
///
/// This runs on app start, on resume, and whenever the schedules or the ledger
/// change. It is deliberately trigger-agnostic, so an FCM wake-up could call it
/// unchanged if push is ever added.
class NotificationScheduler {
  NotificationScheduler(this._service);

  final NotificationService _service;

  Future<void> sync({
    required List<HouseReminderInput> houses,
    required int notificationHour,
    required int notificationMinute,
    bool masterEnabled = true,
    DateTime? nowOverride,
  }) async {
    final now = nowOverride ?? DateTime.now();

    final plans = masterEnabled
        ? buildReminderPlans(
            houses: houses,
            today: LocalDate.fromDateTime(now),
            now: now,
            notificationHour: notificationHour,
            notificationMinute: notificationMinute,
          )
        : const <ReminderPlan>[];

    await _cancelObsolete(plans);

    for (final plan in plans) {
      await _schedule(plan);
    }
  }

  /// Cancels only the reminders that are no longer wanted.
  ///
  /// Never `cancelAll()`: that would also dismiss a reminder currently showing
  /// in the notification shade, which the user may be about to act on.
  Future<void> _cancelObsolete(List<ReminderPlan> plans) async {
    final wanted = plans.map((p) => p.id).toSet();
    final List<PendingNotificationRequest> pending;
    try {
      pending = await _service.pending();
    } on Exception catch (e) {
      debugPrint('Lettura notifiche pendenti non riuscita: $e');
      return;
    }
    for (final request in pending) {
      if (!wanted.contains(request.id)) {
        await _service.plugin.cancel(id: request.id);
      }
    }
  }

  Future<void> _schedule(ReminderPlan plan) async {
    final fireAt = tz.TZDateTime(
      tz.local,
      plan.fireAt.year,
      plan.fireAt.month,
      plan.fireAt.day,
      plan.fireAt.hour,
      plan.fireAt.minute,
    );

    try {
      await _service.plugin.zonedSchedule(
        id: plan.id,
        scheduledDate: fireAt,
        title: plan.title,
        body: plan.body,
        payload: plan.payload.encode(),
        androidScheduleMode: _service.scheduleMode,
        notificationDetails: _details(),
      );
    } on PlatformException catch (e) {
      // The exact-alarm grant can be revoked at any moment; fall back rather
      // than losing the reminder.
      if (e.code == 'exact_alarms_not_permitted') {
        _service.setExactAlarmsPreference(false);
        await _service.plugin.zonedSchedule(
          id: plan.id,
          scheduledDate: fireAt,
          title: plan.title,
          body: plan.body,
          payload: plan.payload.encode(),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          notificationDetails: _details(),
        );
      } else {
        rethrow;
      }
    }
  }

  NotificationDetails _details() => const NotificationDetails(
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
      ],
    ),
    iOS: DarwinNotificationDetails(categoryIdentifier: 'pickup'),
  );

  Future<void> cancelAllForSignOut() => _service.plugin.cancelAll();
}
