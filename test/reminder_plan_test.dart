import 'package:flutter_test/flutter_test.dart';
import 'package:rubbish_manager/core/fnv_hash.dart';
import 'package:rubbish_manager/core/local_date.dart';
import 'package:rubbish_manager/core/waste_catalogue.dart';
import 'package:rubbish_manager/domain/entities/collection_event.dart';
import 'package:rubbish_manager/domain/entities/waste_config.dart';
import 'package:rubbish_manager/notifications/notification_payload.dart';
import 'package:rubbish_manager/notifications/reminder_plan.dart';

WasteConfig config(
  WasteType type, {
  required Set<int> weekdays,
  int intervalWeeks = 1,
  String anchor = '2026-08-10',
  QuotaPolicy policy = const QuotaPolicy.limited(12),
  bool enabled = true,
}) => WasteConfig(
  type: type,
  enabled: enabled,
  policy: policy,
  rules: [
    ScheduleRule(
      weekdays: weekdays,
      intervalWeeks: intervalWeeks,
      anchorDate: LocalDate.parse(anchor),
    ),
  ],
);

CollectionEvent event(WasteType type, String date, {bool isExtra = false}) =>
    CollectionEvent(
      id: isExtra
          ? CollectionEvent.extraId(type, LocalDate.parse(date), 'u')
          : CollectionEvent.scheduledId(type, LocalDate.parse(date)),
      type: type,
      date: LocalDate.parse(date),
      isExtra: isExtra,
      recordedByUid: 'papa',
      recordedByName: 'Papà',
      source: CollectionSource.app,
    );

List<ReminderPlan> plans({
  required List<HouseReminderInput> houses,
  String today = '2026-08-15',
  String now = '2026-08-15 09:00',
  int hour = 20,
  int windowDays = 14,
  int maxPending = 48,
}) => buildReminderPlans(
  houses: houses,
  today: LocalDate.parse(today),
  now: DateTime.parse(now),
  notificationHour: hour,
  notificationMinute: 0,
  windowDays: windowDays,
  maxPending: maxPending,
);

void main() {
  const mon = DateTime.monday;
  const wed = DateTime.wednesday;
  const thu = DateTime.thursday;

  group('scheduling', () {
    test('fires the evening before at the configured hour', () {
      final result = plans(
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa di via Roma',
            configs: [config(WasteType.carta, weekdays: {wed})],
            events: const [],
          ),
        ],
      );

      // Next Wednesday is 2026-08-19, so the reminder is on the 18th at 20:00.
      expect(result.first.pickupDate.toKey(), '2026-08-19');
      expect(result.first.fireAt, DateTime(2026, 8, 18, 20));
    });

    test('honours a custom reminder hour', () {
      final result = plans(
        hour: 19,
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa',
            configs: [config(WasteType.carta, weekdays: {wed})],
            events: const [],
          ),
        ],
      );
      expect(result.first.fireAt, DateTime(2026, 8, 18, 19));
    });

    test('skips a reminder whose fire time has already passed', () {
      // 22:00 on the 18th: that evening's 20:00 reminder is history, so the
      // next plan must be the following pickup.
      final result = plans(
        today: '2026-08-18',
        now: '2026-08-18 22:00',
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa',
            configs: [config(WasteType.carta, weekdays: {wed})],
            events: const [],
          ),
        ],
      );
      expect(result.first.pickupDate.toKey(), '2026-08-26');
    });

    test('orders reminders by fire time and caps the pending count', () {
      final result = plans(
        maxPending: 3,
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa',
            configs: [
              config(WasteType.carta, weekdays: {mon, thu}),
              config(WasteType.vetro, weekdays: {wed}),
            ],
            events: const [],
          ),
        ],
      );

      expect(result, hasLength(3));
      for (var i = 1; i < result.length; i++) {
        expect(result[i].fireAt.isAfter(result[i - 1].fireAt), isTrue);
      }
    });

    test('respects the window length', () {
      final wide = plans(
        windowDays: 30,
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa',
            configs: [config(WasteType.carta, weekdays: {wed})],
            events: const [],
          ),
        ],
      );
      final narrow = plans(
        windowDays: 7,
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa',
            configs: [config(WasteType.carta, weekdays: {wed})],
            events: const [],
          ),
        ],
      );
      expect(wide.length, greaterThan(narrow.length));
      expect(narrow, hasLength(1));
    });
  });

  group('what gets a reminder', () {
    test('nothing when the house has notifications off', () {
      final result = plans(
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa',
            configs: [config(WasteType.carta, weekdays: {wed})],
            events: const [],
            notificationsEnabled: false,
          ),
        ],
      );
      expect(result, isEmpty);
    });

    test('nothing for a disabled waste type', () {
      final result = plans(
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa',
            configs: [
              config(WasteType.carta, weekdays: {wed}, enabled: false),
            ],
            events: const [],
          ),
        ],
      );
      expect(result, isEmpty);
    });

    test('no reminder for a pickup already recorded', () {
      final result = plans(
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa',
            configs: [config(WasteType.carta, weekdays: {wed})],
            events: [event(WasteType.carta, '2026-08-19')],
          ),
        ],
      );
      // Weekly rule, so the reminder moves on to the following Wednesday.
      expect(result.first.pickupDate.toKey(), '2026-08-26');
    });

    test('an extra on the pickup day does not suppress the reminder', () {
      // An extra bag is a separate event; the scheduled pickup still needs
      // confirming.
      final result = plans(
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa',
            configs: [config(WasteType.carta, weekdays: {wed})],
            events: [event(WasteType.carta, '2026-08-19', isExtra: true)],
          ),
        ],
      );
      expect(result.first.pickupDate.toKey(), '2026-08-19');
    });

    test('covers every house the user belongs to', () {
      final result = plans(
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa mia',
            configs: [config(WasteType.carta, weekdays: {wed})],
            events: const [],
          ),
          HouseReminderInput(
            houseId: 'h2',
            houseName: 'Casa dei miei',
            configs: [config(WasteType.vetro, weekdays: {mon})],
            events: const [],
          ),
        ],
      );
      expect(result.map((p) => p.houseId).toSet(), {'h1', 'h2'});
    });
  });

  group('grouping', () {
    test('one reminder covers every type collected the same morning', () {
      final result = plans(
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa',
            configs: [
              config(WasteType.carta, weekdays: {wed}),
              config(
                WasteType.plastica,
                weekdays: {wed},
                policy: const QuotaPolicy.unlimited(),
              ),
            ],
            events: const [],
          ),
        ],
      );

      final first = result.first;
      expect(first.pickupDate.toKey(), '2026-08-19');
      expect(first.payload.types, ['carta', 'plastica']);
      expect(first.body, contains('Carta e Plastica'));
      // Confirming this one reminder records both types.
      expect(first.payload.wasteTypes, [
        WasteType.carta,
        WasteType.plastica,
      ]);
    });

    test('a grouped reminder drops the types already recorded', () {
      final result = plans(
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa',
            configs: [
              config(WasteType.carta, weekdays: {wed}),
              config(WasteType.plastica, weekdays: {wed}),
            ],
            events: [event(WasteType.carta, '2026-08-19')],
          ),
        ],
      );
      expect(result.first.payload.types, ['plastica']);
    });

    test('reminder ids are stable and unique per house and day', () {
      final result = plans(
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa',
            configs: [config(WasteType.carta, weekdays: {mon, thu})],
            events: const [],
          ),
        ],
      );

      expect(result.map((p) => p.id).toSet(), hasLength(result.length));
      // Stable ids are what let a re-schedule replace a pending notification
      // in place, which is how stale counts get refreshed.
      expect(result.first.id, stableNotificationId('h1|2026-08-17'));
      expect(result.first.id, greaterThanOrEqualTo(0));
    });
  });

  group('wording', () {
    HouseReminderInput house({
      required QuotaPolicy policy,
      List<CollectionEvent> events = const [],
    }) => HouseReminderInput(
      houseId: 'h1',
      houseName: 'Casa di via Roma',
      configs: [config(WasteType.carta, weekdays: {wed}, policy: policy)],
      events: events,
    );

    test('names the house in the title', () {
      final result = plans(houses: [house(policy: const QuotaPolicy.limited(12))]);
      expect(result.first.title, 'Ritiro di domani — Casa di via Roma');
    });

    test('states the remaining free collections', () {
      final result = plans(
        houses: [
          house(
            policy: const QuotaPolicy.limited(12),
            events: [
              event(WasteType.carta, '2026-01-07'),
              event(WasteType.carta, '2026-02-04'),
            ],
          ),
        ],
      );
      expect(result.first.body, contains('Domani ritiro di Carta.'));
      expect(result.first.body, contains('Ritiri gratuiti rimanenti: 10 su 12.'));
    });

    test('warns on the last free collection', () {
      final result = plans(
        houses: [
          house(
            policy: const QuotaPolicy.limited(2),
            events: [event(WasteType.carta, '2026-01-07')],
          ),
        ],
      );
      expect(result.first.body, contains('ultimo ritiro gratuito'));
    });

    test('says the pickup is billed once the quota is gone', () {
      final result = plans(
        houses: [
          house(
            policy: const QuotaPolicy.limited(1),
            events: [event(WasteType.carta, '2026-01-07')],
          ),
        ],
      );
      expect(result.first.body, contains('esauriti'));
    });

    test('says nothing about counts when collections are unlimited', () {
      final result = plans(houses: [house(policy: const QuotaPolicy.unlimited())]);
      expect(result.first.body, contains('illimitati'));
      expect(result.first.body, isNot(contains('rimanenti')));
    });

    test('counts against the year of the pickup, not of the reminder', () {
      // Fired on 31 December for a 1 January pickup: the new year's allowance
      // is untouched, so it must read 12 of 12 despite a busy December.
      final result = buildReminderPlans(
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa',
            configs: [
              config(
                WasteType.carta,
                weekdays: {DateTime.friday},
                anchor: '2027-01-01',
              ),
            ],
            events: [
              for (final day in ['2026-12-04', '2026-12-11', '2026-12-18'])
                event(WasteType.carta, day),
            ],
          ),
        ],
        today: LocalDate.parse('2026-12-31'),
        now: DateTime(2026, 12, 31, 9),
        notificationHour: 20,
        notificationMinute: 0,
      );

      final firstOfJanuary = result.firstWhere(
        (p) => p.pickupDate.toKey() == '2027-01-01',
      );
      expect(firstOfJanuary.fireAt, DateTime(2026, 12, 31, 20));
      expect(
        firstOfJanuary.body,
        contains('Ritiri gratuiti rimanenti: 12 su 12.'),
      );
    });

    test('flags counts that may be stale for a distant pickup', () {
      // Local notification text is fixed when scheduled, so a count for a
      // pickup a week out can be overtaken by another member's recording.
      final result = plans(
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa',
            configs: [config(WasteType.carta, weekdays: {wed})],
            events: const [],
          ),
        ],
      );
      expect(result.first.body, contains('dati al 15/8'));
    });

    test('does not flag staleness for an imminent pickup', () {
      final result = plans(
        today: '2026-08-18',
        now: '2026-08-18 09:00',
        houses: [
          HouseReminderInput(
            houseId: 'h1',
            houseName: 'Casa',
            configs: [config(WasteType.carta, weekdays: {wed})],
            events: const [],
          ),
        ],
      );
      expect(result.first.body, isNot(contains('dati al')));
    });
  });

  group('payload round-trip', () {
    test('survives encoding and decoding', () {
      const payload = NotificationPayload(
        houseId: 'h1',
        dateKey: '2026-08-19',
        types: ['carta', 'plastica'],
      );
      final decoded = NotificationPayload.decode(payload.encode())!;
      expect(decoded.houseId, 'h1');
      expect(decoded.dateKey, '2026-08-19');
      expect(decoded.wasteTypes, [WasteType.carta, WasteType.plastica]);
    });

    test('rejects malformed payloads instead of throwing', () {
      expect(NotificationPayload.decode(null), isNull);
      expect(NotificationPayload.decode(''), isNull);
      expect(NotificationPayload.decode('not json'), isNull);
      expect(NotificationPayload.decode('{"houseId":"h1"}'), isNull);
      expect(
        NotificationPayload.decode('{"houseId":"h1","dateKey":"nope"}'),
        isNull,
      );
    });

    test('drops waste types it does not recognise', () {
      final decoded = NotificationPayload.decode(
        '{"houseId":"h1","dateKey":"2026-08-19","types":["carta","martian"]}',
      )!;
      expect(decoded.wasteTypes, [WasteType.carta]);
    });
  });

  group('stableNotificationId', () {
    test('is deterministic and fits in a positive 31-bit int', () {
      final id = stableNotificationId('h1|2026-08-19');
      expect(id, stableNotificationId('h1|2026-08-19'));
      expect(id, greaterThanOrEqualTo(0));
      expect(id, lessThan(1 << 31));
    });

    test('separates different houses and days', () {
      expect(
        stableNotificationId('h1|2026-08-19'),
        isNot(stableNotificationId('h2|2026-08-19')),
      );
      expect(
        stableNotificationId('h1|2026-08-19'),
        isNot(stableNotificationId('h1|2026-08-20')),
      );
    });
  });
}
