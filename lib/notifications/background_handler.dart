import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../core/local_date.dart';
import '../data/collection_repository.dart';
import '../domain/entities/collection_event.dart';
import '../data/firestore_refs.dart';
import '../firebase_options.dart';
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
  if (response.actionId != NotificationService.markDoneActionId) return;

  final payload = NotificationPayload.decode(response.payload);
  if (payload == null) return;

  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    await recordFromPayload(payload);
  } on Exception catch (e) {
    debugPrint('Registrazione da notifica non riuscita, accodata: $e');
    await const PendingActionsStore().add(payload.encode());
  }
}

/// Writes the collections described by a notification payload.
///
/// Shared by the background isolate and by the replay of any queued action on
/// the next app launch. Scheduled collections use deterministic document ids,
/// so running this twice records the same single collection.
Future<void> recordFromPayload(NotificationPayload payload) async {
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
