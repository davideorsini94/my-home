import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rubbish_manager/core/local_date.dart';
import 'package:rubbish_manager/core/waste_catalogue.dart';
import 'package:rubbish_manager/domain/entities/maintenance.dart';
import 'package:rubbish_manager/domain/entities/maintenance_log_entry.dart';
import 'package:rubbish_manager/domain/entities/waste_config.dart';
import 'package:rubbish_manager/notifications/maintenance_reminder_plan.dart';
import 'package:rubbish_manager/notifications/notification_gateway.dart';
import 'package:rubbish_manager/notifications/notification_scheduler.dart';
import 'package:rubbish_manager/notifications/notification_service.dart';
import 'package:rubbish_manager/notifications/reminder_plan.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Records what the scheduler asked the plugin to do.
class FakeNotificationGateway implements NotificationGateway {
  final List<PendingNotificationRequest> pendingRequests = [];
  final List<int> cancelled = [];
  final List<({int id, String channel, DateTime fireAt})> scheduled = [];
  bool cancelAllCalled = false;
  bool exactAlarmsPreference = true;

  @override
  AndroidScheduleMode get scheduleMode =>
      AndroidScheduleMode.inexactAllowWhileIdle;

  @override
  void setExactAlarmsPreference(bool enabled) =>
      exactAlarmsPreference = enabled;

  @override
  Future<List<PendingNotificationRequest>> pending() async => pendingRequests;

  @override
  Future<void> cancel(int id) async {
    cancelled.add(id);
    pendingRequests.removeWhere((r) => r.id == id);
  }

  @override
  Future<void> cancelAll() async {
    cancelAllCalled = true;
    pendingRequests.clear();
  }

  @override
  Future<void> zonedSchedule({
    required int id,
    required tz.TZDateTime scheduledDate,
    required String title,
    required String body,
    required String payload,
    required AndroidScheduleMode androidScheduleMode,
    required NotificationDetails notificationDetails,
  }) async {
    scheduled.add((
      id: id,
      channel: notificationDetails.android?.channelId ?? '',
      fireAt: scheduledDate,
    ));
  }

  void seedPending(List<int> ids) {
    pendingRequests
      ..clear()
      ..addAll(
        ids.map((id) => PendingNotificationRequest(id, null, null, null)),
      );
  }

  Set<int> get scheduledIds => scheduled.map((s) => s.id).toSet();
}

WasteConfig wasteConfig({
  WasteType type = WasteType.carta,
  Set<int> weekdays = const {DateTime.wednesday},
}) => WasteConfig(
  type: type,
  enabled: true,
  policy: const QuotaPolicy.limited(12),
  rules: [
    ScheduleRule(
      weekdays: weekdays,
      intervalWeeks: 1,
      anchorDate: LocalDate.parse('2026-08-10'),
    ),
  ],
);

HouseReminderInput wasteHouse({
  String id = 'h1',
  List<WasteConfig>? configs,
}) => HouseReminderInput(
  houseId: id,
  houseName: 'Casa',
  configs: configs ?? [wasteConfig()],
  events: const [],
);

Maintenance maintenance({String id = 'm1', int every = 1}) => Maintenance(
  id: id,
  name: 'Caldaia',
  iconKey: 'boiler',
  recurrence: Recurrence(every: every, unit: RecurrenceUnit.years),
);

MaintenanceLogEntry executed(String date, {String id = 'm1'}) =>
    MaintenanceLogEntry(
      id: MaintenanceLogEntry.doneId(id, LocalDate.parse(date)),
      maintenanceId: id,
      date: LocalDate.parse(date),
      status: MaintenanceEntryStatus.done,
      recordedByUid: 'davide',
      recordedByName: 'Davide',
    );

MaintenanceReminderInput maintenanceHouse({
  String id = 'h1',
  List<Maintenance>? maintenances,
  List<MaintenanceLogEntry>? log,
}) => MaintenanceReminderInput(
  houseId: id,
  houseName: 'Casa',
  maintenances: maintenances ?? [maintenance()],
  log: log ?? [executed('2025-10-01')],
);

void main() {
  setUpAll(() {
    tzdata.initializeTimeZones();
    tz.setLocalLocation(tz.getLocation('Europe/Rome'));
  });

  late FakeNotificationGateway gateway;
  late NotificationScheduler scheduler;

  setUp(() {
    gateway = FakeNotificationGateway();
    scheduler = NotificationScheduler(gateway);
  });

  Future<void> sync({
    List<HouseReminderInput>? waste,
    List<MaintenanceReminderInput>? maintenance,
    bool wasteEnabled = true,
    bool maintenanceEnabled = true,
  }) => scheduler.sync(
    wasteHouses: waste ?? [wasteHouse()],
    maintenanceHouses: maintenance ?? [maintenanceHouse()],
    notificationHour: 20,
    notificationMinute: 0,
    wasteEnabled: wasteEnabled,
    maintenanceEnabled: maintenanceEnabled,
    nowOverride: DateTime.parse('2026-09-14 09:00'),
  );

  group('the wanted set covers both kinds', () {
    test('waste and maintenance reminders are both scheduled', () async {
      await sync();
      final channels = gateway.scheduled.map((s) => s.channel).toSet();
      expect(channels, contains(NotificationService.channelId));
      expect(channels, contains(NotificationService.maintenanceChannelId));
    });

    test('a second sync cancels neither kind', () async {
      // This is the regression the whole fake exists for: if the union left one
      // kind out, every reminder of that kind would be cancelled on every sync,
      // silently and only on a real device.
      await sync();
      final firstRound = gateway.scheduledIds;
      expect(firstRound, isNotEmpty);

      gateway
        ..seedPending(firstRound.toList())
        ..cancelled.clear()
        ..scheduled.clear();

      await sync();
      expect(gateway.cancelled, isEmpty, reason: 'nothing was obsolete');
      expect(gateway.scheduledIds, firstRound);
    });

    test('a pending id belonging to neither kind is cancelled', () async {
      // Stale reminders from a deleted house must still be cleaned up.
      gateway.seedPending([999999]);
      await sync();
      expect(gateway.cancelled, contains(999999));
    });

    test('cancelAll is never used, so a shown reminder is not dismissed', () async {
      gateway.seedPending([999999]);
      await sync();
      expect(gateway.cancelAllCalled, isFalse);
    });
  });

  group('budgets', () {
    test('waste is capped at its own budget, not the old default', () async {
      // Waste reminders are grouped per house and day, so one house can only
      // ever produce 14 in the window: exceeding the budget takes several.
      final configs = [
        wasteConfig(type: WasteType.carta, weekdays: {1, 2, 3, 4, 5, 6, 7}),
      ];
      await sync(
        waste: [
          for (var i = 0; i < 5; i++)
            wasteHouse(id: 'h$i', configs: configs),
        ],
        maintenance: const [],
      );
      final wasteCount = gateway.scheduled
          .where((s) => s.channel == NotificationService.channelId)
          .length;
      expect(wasteCount, wasteNotificationBudget);
    });

    test('maintenance is capped at its own budget', () async {
      final maintenances = <Maintenance>[];
      final log = <MaintenanceLogEntry>[];
      for (var i = 0; i < 20; i++) {
        maintenances.add(maintenance(id: 'm$i'));
        log.add(executed(LocalDate(2025, 9, 20).addDays(i).toKey(), id: 'm$i'));
      }
      await sync(
        waste: const [],
        maintenance: [maintenanceHouse(maintenances: maintenances, log: log)],
      );
      expect(gateway.scheduled, hasLength(maintenanceNotificationBudget));
    });

    test('the two budgets together stay under the iOS pending cap', () {
      expect(wasteNotificationBudget + maintenanceNotificationBudget, 60);
      expect(
        wasteNotificationBudget + maintenanceNotificationBudget,
        lessThan(64),
      );
    });
  });

  group('master switches', () {
    test('disabling maintenance leaves waste untouched', () async {
      await sync(maintenanceEnabled: false);
      final channels = gateway.scheduled.map((s) => s.channel).toSet();
      expect(channels, contains(NotificationService.channelId));
      expect(
        channels,
        isNot(contains(NotificationService.maintenanceChannelId)),
      );
    });

    test('disabling waste leaves maintenance untouched', () async {
      await sync(wasteEnabled: false);
      final channels = gateway.scheduled.map((s) => s.channel).toSet();
      expect(channels, contains(NotificationService.maintenanceChannelId));
      expect(channels, isNot(contains(NotificationService.channelId)));
    });

    test('turning one kind off cancels only that kind', () async {
      await sync();
      final maintenanceIds = gateway.scheduled
          .where((s) => s.channel == NotificationService.maintenanceChannelId)
          .map((s) => s.id)
          .toSet();
      final wasteIds = gateway.scheduled
          .where((s) => s.channel == NotificationService.channelId)
          .map((s) => s.id)
          .toSet();

      gateway
        ..seedPending([...maintenanceIds, ...wasteIds])
        ..cancelled.clear();

      await sync(maintenanceEnabled: false);
      expect(gateway.cancelled.toSet(), maintenanceIds);
      expect(
        gateway.cancelled.toSet().intersection(wasteIds),
        isEmpty,
      );
    });

    test('both disabled cancels everything pending, without cancelAll', () async {
      await sync();
      gateway
        ..seedPending(gateway.scheduledIds.toList())
        ..cancelled.clear()
        ..scheduled.clear();

      await sync(wasteEnabled: false, maintenanceEnabled: false);
      expect(gateway.scheduled, isEmpty);
      expect(gateway.cancelled, isNotEmpty);
      expect(gateway.cancelAllCalled, isFalse);
    });
  });

  group('signing out', () {
    test('clears every pending reminder', () async {
      await scheduler.cancelAllForSignOut();
      expect(gateway.cancelAllCalled, isTrue);
    });
  });

  group('ids and fire times', () {
    test('ids of the two kinds never collide', () async {
      await sync();
      expect(
        gateway.scheduledIds,
        hasLength(gateway.scheduled.length),
        reason: 'every scheduled id is distinct',
      );
    });

    test('every reminder is scheduled in the future', () async {
      await sync();
      final now = DateTime.parse('2026-09-14 09:00');
      for (final entry in gateway.scheduled) {
        expect(entry.fireAt.isAfter(now), isTrue);
      }
    });

    test('a maintenance schedules both its due and follow-up slots', () async {
      await sync(waste: const []);
      expect(gateway.scheduled, hasLength(2));
      final times = gateway.scheduled.map((s) => s.fireAt).toList()..sort();
      expect(times[1].difference(times[0]).inDays, maintenanceFollowUpDays);
    });
  });
}
