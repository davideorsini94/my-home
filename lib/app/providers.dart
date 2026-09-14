import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/auth_repository.dart';
import '../data/collection_repository.dart';
import '../data/firestore_refs.dart';
import '../data/house_repository.dart';
import '../data/invite_repository.dart';
import '../data/maintenance_repository.dart';
import '../data/waste_config_repository.dart';
import '../domain/entities/app_user.dart';
import '../domain/entities/collection_event.dart';
import '../domain/entities/house.dart';
import '../domain/entities/maintenance.dart';
import '../domain/entities/maintenance_log_entry.dart';
import '../domain/entities/waste_config.dart';
import '../domain/maintenance_schedule.dart';
import '../core/local_date.dart';
import '../features/settings/settings_service.dart';
import '../notifications/notification_scheduler.dart';
import '../notifications/notification_service.dart';
import '../notifications/reminder_plan.dart';

// ---------------------------------------------------------------- foundations

final firestoreProvider = Provider<FirebaseFirestore>(
  (ref) => FirebaseFirestore.instance,
);

final firestoreRefsProvider = Provider<FirestoreRefs>(
  (ref) => FirestoreRefs(ref.watch(firestoreProvider)),
);

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(
    auth: ref.watch(firebaseAuthProvider),
    refs: ref.watch(firestoreRefsProvider),
  ),
);

final houseRepositoryProvider = Provider<HouseRepository>(
  (ref) => HouseRepository(ref.watch(firestoreRefsProvider)),
);

final wasteConfigRepositoryProvider = Provider<WasteConfigRepository>(
  (ref) => WasteConfigRepository(ref.watch(firestoreRefsProvider)),
);

final collectionRepositoryProvider = Provider<CollectionRepository>(
  (ref) => CollectionRepository(ref.watch(firestoreRefsProvider)),
);

final inviteRepositoryProvider = Provider<InviteRepository>(
  (ref) => InviteRepository(ref.watch(firestoreRefsProvider)),
);

final maintenanceRepositoryProvider = Provider<MaintenanceRepository>(
  (ref) => MaintenanceRepository(ref.watch(firestoreRefsProvider)),
);

/// Overridden in `main` with the instance that was already initialised there,
/// so the plugin is set up exactly once.
final notificationServiceProvider = Provider<NotificationService>(
  (ref) =>
      throw UnimplementedError('notificationServiceProvider non inizializzato'),
);

final notificationSchedulerProvider = Provider<NotificationScheduler>(
  (ref) => NotificationScheduler(ref.watch(notificationServiceProvider)),
);

// ----------------------------------------------------------------------- auth

final authStateProvider = StreamProvider<AppUser?>(
  (ref) => ref.watch(authRepositoryProvider).authStateChanges(),
);

/// The signed-in user, or null while signed out or still loading.
final currentUserProvider = Provider<AppUser?>(
  (ref) => ref.watch(authStateProvider).value,
);

// ------------------------------------------------------------------- settings

/// Seeded in `main` from disk so that the theme and the reminder hour are known
/// before the first frame, with no loading flicker.
final initialSettingsProvider = Provider<AppSettings>(
  (ref) =>
      throw UnimplementedError('initialSettingsProvider non inizializzato'),
);

final settingsServiceProvider = Provider<SettingsService>(
  (ref) => const SettingsService(),
);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.read(initialSettingsProvider);

  Future<void> update(AppSettings settings) async {
    state = settings;
    await ref.read(settingsServiceProvider).save(settings);
    ref.read(notificationSyncProvider).requestSync();
  }
}

final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(
  SettingsNotifier.new,
);

// --------------------------------------------------------------------- houses

final myHousesProvider = StreamProvider<List<House>>((ref) {
  final user = ref.watch(currentUserProvider);
  if (user == null) return Stream.value(const []);
  return ref.watch(houseRepositoryProvider).watchMyHouses(user.uid);
});

final houseProvider = StreamProvider.family<House?, String>(
  (ref, houseId) => ref.watch(houseRepositoryProvider).watchHouse(houseId),
);

final wasteConfigsProvider = StreamProvider.family<List<WasteConfig>, String>(
  (ref, houseId) =>
      ref.watch(wasteConfigRepositoryProvider).watchConfigs(houseId),
);

/// Identifies one house-year ledger.
typedef LedgerKey = ({String houseId, int year});

final collectionsProvider =
    StreamProvider.family<List<CollectionEvent>, LedgerKey>(
      (ref, key) => ref
          .watch(collectionRepositoryProvider)
          .watchYear(key.houseId, key.year),
    );

/// The current year's ledger for a house — the source every counter derives
/// from.
final currentYearCollectionsProvider =
    StreamProvider.family<List<CollectionEvent>, String>(
      (ref, houseId) => ref
          .watch(collectionRepositoryProvider)
          .watchYear(houseId, DateTime.now().year),
    );

// --------------------------------------------------------------- maintenance

final maintenancesProvider = StreamProvider.family<List<Maintenance>, String>(
  (ref, houseId) =>
      ref.watch(maintenanceRepositoryProvider).watchMaintenances(houseId),
);

/// The ledger for a house, bounded below by how far back its maintenances can
/// reach.
///
/// The bound depends on the maintenances themselves — a five-year cadence needs
/// more history than a monthly one — so it is derived from them rather than
/// fixed. A lower bound only: skipping a future occurrence writes a
/// future-dated entry, and an upper bound would hide it.
final maintenanceLogProvider =
    StreamProvider.family<List<MaintenanceLogEntry>, String>((ref, houseId) {
      final maintenances =
          ref.watch(maintenancesProvider(houseId)).value ?? const [];
      final from = logLowerBound(maintenances, LocalDate.today());
      return ref.watch(maintenanceRepositoryProvider).watchLog(houseId, from);
    });

/// Keeps the maintenance listeners of every house alive for the whole session.
///
/// Without this they would only live while a maintenance screen is on screen,
/// so a member's execution on another device would stay invisible — and a
/// reminder for an already-done maintenance would fire — until the app was next
/// resumed. The waste side avoids the same trap by resyncing on every snapshot.
final maintenanceWatchProvider = Provider<void>((ref) {
  final houses = ref.watch(myHousesProvider).value ?? const <House>[];
  for (final house in houses) {
    ref.listen(maintenancesProvider(house.id), (_, _) {
      ref.read(notificationSyncProvider).requestSync();
    });
    ref.listen(maintenanceLogProvider(house.id), (_, _) {
      ref.read(notificationSyncProvider).requestSync();
    });
  }
});

// -------------------------------------------------------- notification syncing

/// The single entry point for rescheduling local notifications.
///
/// Every trigger — app start, resume, a change in the ledger or the schedules,
/// a settings edit — funnels through here, which is also what would let a push
/// wake-up drive it unchanged if FCM is ever added.
class NotificationSync {
  NotificationSync(this._ref);

  final Ref _ref;
  bool _running = false;
  bool _queued = false;

  void requestSync() {
    unawaited(_run());
  }

  Future<void> _run() async {
    // Collapses bursts — several snapshot updates arriving together must not
    // start several overlapping reschedules.
    if (_running) {
      _queued = true;
      return;
    }
    _running = true;
    try {
      await _sync();
    } on Exception catch (e) {
      debugPrint('Sincronizzazione notifiche non riuscita: $e');
    } finally {
      _running = false;
      if (_queued) {
        _queued = false;
        unawaited(_run());
      }
    }
  }

  Future<void> _sync() async {
    final user = _ref.read(currentUserProvider);
    final scheduler = _ref.read(notificationSchedulerProvider);

    if (user == null) {
      await scheduler.cancelAllForSignOut();
      return;
    }

    final settings = _ref.read(settingsProvider);
    final houses = _ref.read(myHousesProvider).value ?? const <House>[];
    final configRepo = _ref.read(wasteConfigRepositoryProvider);
    final collectionRepo = _ref.read(collectionRepositoryProvider);
    final year = DateTime.now().year;

    final inputs = <HouseReminderInput>[];
    for (final house in houses) {
      // One-shot reads rather than listeners: reminders span every house the
      // user belongs to, not just the one on screen, and a listener per house
      // would stay alive for the whole session for no benefit.
      final configs = await configRepo.getConfigs(house.id);
      if (!configs.any((c) => c.enabled)) continue;
      final events = await collectionRepo.getYear(house.id, year);
      inputs.add(
        HouseReminderInput(
          houseId: house.id,
          houseName: house.name,
          configs: configs,
          events: events,
        ),
      );
    }

    await scheduler.sync(
      houses: inputs,
      notificationHour: settings.notificationHour,
      notificationMinute: settings.notificationMinute,
      masterEnabled: settings.notificationsEnabled,
    );
  }
}

final notificationSyncProvider = Provider<NotificationSync>(
  (ref) => NotificationSync(ref),
);
