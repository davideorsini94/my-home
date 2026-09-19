import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../notifications/background_handler.dart';
import '../notifications/foreground_handler.dart';
import '../notifications/maintenance_payload.dart';
import '../notifications/notification_payload.dart';
import '../notifications/pending_actions_store.dart';
import 'providers.dart';
import 'router.dart';
import 'theme.dart';

class MyHomeApp extends ConsumerStatefulWidget {
  const MyHomeApp({super.key});

  @override
  ConsumerState<MyHomeApp> createState() => _MyHomeAppState();
}

class _MyHomeAppState extends ConsumerState<MyHomeApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    pendingNavigationHouseId.addListener(_openPendingHouse);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _onResumed();
      _openPendingHouse();
    });
  }

  @override
  void dispose() {
    pendingNavigationHouseId.removeListener(_openPendingHouse);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Opens the house a notification tap referred to, once the router exists.
  void _openPendingHouse() {
    final houseId = pendingNavigationHouseId.value;
    if (houseId == null || !mounted) return;
    if (ref.read(currentUserProvider) == null) return;
    pendingNavigationHouseId.value = null;
    // A waste reminder opens the waste dashboard directly: the hub is one tap
    // further from what the notification was actually about.
    ref.read(routerProvider).go('/house/$houseId/waste');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _onResumed();
  }

  /// Replays anything the background isolate could not write, then rewrites the
  /// pending reminders so their counts reflect what every member has recorded.
  Future<void> _onResumed() async {
    final queued = await const PendingActionsStore().drain();
    for (final raw in queued) {
      try {
        if (MaintenancePayload.kindOf(raw) == ReminderKind.maintenance) {
          final payload = MaintenancePayload.decode(raw);
          if (payload == null) continue;
          final status = MaintenancePayload.decodeStatus(raw);
          if (status == null) continue;
          // The queued entry carries the day the button was pressed, so a
          // replay days later still records when it actually happened.
          await recordMaintenanceFromPayload(
            payload,
            status,
            MaintenancePayload.decodeDoneDate(raw),
          );
        } else {
          final payload = NotificationPayload.decode(raw);
          if (payload == null) continue;
          // The queued entry carries the outcome the user chose, so a skip
          // replayed later stays a skip rather than becoming a collection.
          await recordFromPayload(
            payload,
            NotificationPayload.decodeStatus(raw),
          );
        }
      } on Exception catch (e) {
        debugPrint('Replay azione notifica non riuscito: $e');
        await const PendingActionsStore().add(raw);
      }
    }
    if (mounted) ref.read(notificationSyncProvider).requestSync();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final themeMode = ref.watch(settingsProvider).themeMode;

    // Any change to the set of houses changes which reminders are wanted.
    ref.listen(myHousesProvider, (_, _) {
      ref.read(notificationSyncProvider).requestSync();
    });

    // A notification tap may have arrived before the user was signed in.
    ref.listen(authStateProvider, (_, _) => _openPendingHouse());

    // Holds the maintenance listeners open for the whole session, so another
    // member's execution is reflected without waiting for a resume.
    ref.watch(maintenanceWatchProvider);

    return MaterialApp.router(
      title: 'MyHome',
      debugShowCheckedModeBanner: false,
      routerConfig: router,
      theme: buildLightTheme(),
      darkTheme: buildDarkTheme(),
      themeMode: themeMode,
      locale: const Locale('it'),
      supportedLocales: const [Locale('it')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
    );
  }
}
