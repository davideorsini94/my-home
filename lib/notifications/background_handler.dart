import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/local_date.dart';
import '../data/collection_repository.dart';
import '../data/maintenance_repository.dart';
import '../domain/entities/collection_event.dart';
import '../domain/entities/maintenance_log_entry.dart';
import '../data/firestore_refs.dart';
import '../firebase_options.dart';
import 'maintenance_payload.dart';
import 'maintenance_reminder_plan.dart';
import 'notification_payload.dart';
import 'notification_service.dart';
import 'pending_actions_store.dart';

/// Handles "Raccolta fatta" tapped on a notification while the app is not in
/// the foreground.
///
/// This runs in a separate background isolate, in a process that may have been
/// cold-started with no Flutter UI at all, so it bootstraps its own bindings
/// and Firebase instance. `FirebaseAuth` restores the session from disk, which
/// is what lets the write pass the security rules.
///
/// Being offline is not a failure here: Firestore persists queued mutations to
/// disk and syncs them on the next launch. The [PendingActionsStore] fallback
/// only covers a failure earlier than that.
@pragma('vm:entry-point')
Future<void> onBackgroundNotificationResponse(
  NotificationResponse response,
) async {
  // The day the button was pressed, captured before anything can fail, so an
  // action replayed days later still records when it actually happened.
  final tapDay = LocalDate.today();

  if (MaintenancePayload.kindOf(response.payload) == ReminderKind.maintenance) {
    await _handleMaintenanceAction(response, tapDay);
    return;
  }

  final status = statusForAction(response.actionId);
  if (status == null) return;

  final payload = NotificationPayload.decode(response.payload);
  if (payload == null) return;

  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await recordFromPayload(payload, status);
  } on Exception catch (e) {
    debugPrint('Registrazione da notifica non riuscita, accodata: $e');
    await const PendingActionsStore().add(payload.encode(status: status));
  }
}

Future<void> _handleMaintenanceAction(
  NotificationResponse response,
  LocalDate tapDay,
) async {
  final status = maintenanceStatusForAction(response.actionId);
  if (status == null) return;

  final payload = MaintenancePayload.decode(response.payload);
  if (payload == null) return;

  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await recordMaintenanceFromPayload(payload, status, tapDay);
  } on Exception catch (e) {
    debugPrint('Registrazione manutenzione da notifica non riuscita: $e');
    await const PendingActionsStore().add(
      payload.encode(status: status, doneDateKey: tapDay.toKey()),
    );
  }
}

/// Settles a maintenance from a notification action.
///
/// Both outcomes are blind writes on deterministic ids — nothing is read first
/// — which is what makes this safe from a background isolate where no UI, no
/// providers and no cached state exist.
Future<void> recordMaintenanceFromPayload(
  MaintenancePayload payload,
  MaintenanceEntryStatus status, [
  LocalDate? doneDate,
]) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw StateError('Nessun utente autenticato');
  }

  final repository = MaintenanceRepository(
    FirestoreRefs(FirebaseFirestore.instance),
  );
  final name = _displayName(user);

  if (status == MaintenanceEntryStatus.done) {
    await repository.recordExecution(
      houseId: payload.houseId,
      maintenanceId: payload.maintenanceId,
      // The execution happened on the day the button was pressed, which is not
      // necessarily the due date and not necessarily today at replay time.
      date: doneDate ?? LocalDate.today(),
      uid: user.uid,
      userName: name,
      source: MaintenanceEntrySource.notification,
    );
  } else {
    await repository.recordSkip(
      houseId: payload.houseId,
      maintenanceId: payload.maintenanceId,
      // A skip is keyed to the DUE date the reminder was about, never to today.
      dueDate: payload.dueDate,
      uid: user.uid,
      userName: name,
      source: MaintenanceEntrySource.notification,
    );
  }
}

/// Maps a notification action id onto the record it should write.
///
/// Returns null for anything else — a tap on the notification body, or an
/// action id from a future version — so an unrecognised id can never silently
/// write the wrong thing.
CollectionStatus? statusForAction(String? actionId) => switch (actionId) {
  NotificationService.markDoneActionId => CollectionStatus.done,
  NotificationService.skipActionId => CollectionStatus.skipped,
  _ => null,
};

/// Writes the collections described by a notification payload.
///
/// Shared by the background isolate and by the replay of any queued action on
/// the next app launch. Scheduled collections use deterministic document ids,
/// so running this twice records the same single collection.
Future<void> recordFromPayload(
  NotificationPayload payload, [
  CollectionStatus status = CollectionStatus.done,
]) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) {
    throw StateError('Nessun utente autenticato');
  }

  final repository = CollectionRepository(
    FirestoreRefs(FirebaseFirestore.instance),
  );
  final date = LocalDate.parse(payload.dateKey);
  final name = _displayName(user);

  for (final type in payload.wasteTypes) {
    await repository.recordScheduled(
      houseId: payload.houseId,
      type: type,
      date: date,
      uid: user.uid,
      userName: name,
      source: CollectionSource.notification,
      status: status,
    );
  }
}

String _displayName(User user) {
  final name = user.displayName?.trim();
  if (name != null && name.isNotEmpty) return name;
  final email = user.email ?? '';
  final at = email.indexOf('@');
  return at > 0 ? email.substring(0, at) : 'Utente';
}
