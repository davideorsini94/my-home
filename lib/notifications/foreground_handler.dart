import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/local_date.dart';
import 'background_handler.dart';
import 'maintenance_payload.dart';
import 'maintenance_reminder_plan.dart';
import 'notification_payload.dart';
import 'pending_actions_store.dart';

/// The house a notification tap asked to open, consumed once by the app.
///
/// A plain notifier rather than routing directly, because the tap can arrive
/// before the router exists — including from a cold start via
/// `getNotificationAppLaunchDetails`.
final ValueNotifier<String?> pendingNavigationHouseId = ValueNotifier(null);

/// Handles a notification interaction while the app is running.
///
/// The background isolate handler does not fire when the app is in the
/// foreground, so without this the action button would silently do nothing for
/// anyone who taps it with the app open.
Future<void> onForegroundNotificationResponse(
  NotificationResponse response,
) async {
  if (MaintenancePayload.kindOf(response.payload) == ReminderKind.maintenance) {
    await _handleMaintenanceForeground(response);
    return;
  }

  final payload = NotificationPayload.decode(response.payload);
  if (payload == null) return;

  final status = statusForAction(response.actionId);
  if (status != null) {
    try {
      await recordFromPayload(payload, status);
    } on Exception catch (e) {
      debugPrint('Registrazione da notifica in primo piano non riuscita: $e');
      await const PendingActionsStore().add(payload.encode(status: status));
    }
    return;
  }

  // Tapping the body opens the house it refers to.
  pendingNavigationHouseId.value = payload.houseId;
}

Future<void> _handleMaintenanceForeground(NotificationResponse response) async {
  final payload = MaintenancePayload.decode(response.payload);
  if (payload == null) return;

  final status = maintenanceStatusForAction(response.actionId);
  if (status == null) {
    // Tapping the body opens the house the maintenance belongs to.
    pendingNavigationHouseId.value = payload.houseId;
    return;
  }

  final tapDay = LocalDate.today();
  try {
    await recordMaintenanceFromPayload(payload, status, tapDay);
  } on Exception catch (e) {
    debugPrint('Manutenzione da notifica in primo piano non riuscita: $e');
    await const PendingActionsStore().add(
      payload.encode(status: status, doneDateKey: tapDay.toKey()),
    );
  }
}
