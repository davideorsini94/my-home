import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'background_handler.dart';
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
