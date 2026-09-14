import 'package:flutter_test/flutter_test.dart';
import 'package:rubbish_manager/core/local_date.dart';
import 'package:rubbish_manager/core/waste_catalogue.dart';
import 'package:rubbish_manager/domain/entities/collection_event.dart';
import 'package:rubbish_manager/domain/entities/waste_config.dart';
import 'package:rubbish_manager/domain/quota_calculator.dart';
import 'package:rubbish_manager/domain/statistics.dart';
import 'package:rubbish_manager/notifications/notification_payload.dart';
import 'package:rubbish_manager/notifications/reminder_plan.dart';

CollectionEvent event(
  WasteType type,
  String date, {
  CollectionStatus status = CollectionStatus.done,
  bool isExtra = false,
}) => CollectionEvent(
  id: isExtra
      ? CollectionEvent.extraId(type, LocalDate.parse(date), 'u')
      : CollectionEvent.scheduledId(type, LocalDate.parse(date)),
  type: type,
  date: LocalDate.parse(date),
  isExtra: isExtra,
  recordedByUid: 'davide',
  recordedByName: 'Davide',
  source: CollectionSource.app,
  status: status,
);

WasteConfig config(
  WasteType type, {
  Set<int> weekdays = const {DateTime.wednesday},
  QuotaPolicy policy = const QuotaPolicy.limited(12),
}) => WasteConfig(
  type: type,
  enabled: true,
  policy: policy,
  rules: [
    ScheduleRule(
      weekdays: weekdays,
      intervalWeeks: 1,
      anchorDate: LocalDate.parse('2026-08-10'),
    ),
  ],
);

void main() {
  group('CollectionStatus', () {
    test('defaults to done for records written before skipping existed', () {
      // Documents already in Firestore carry no status field at all, and every
      // one of them was a real collection.
      expect(CollectionStatus.fromId(null), CollectionStatus.done);
      expect(CollectionStatus.fromId(''), CollectionStatus.done);
      expect(CollectionStatus.fromId('done'), CollectionStatus.done);
      expect(CollectionStatus.fromId('skipped'), CollectionStatus.skipped);
      // An unknown value must not silently become a skip.
      expect(CollectionStatus.fromId('qualcosaltro'), CollectionStatus.done);
    });

    test('only a done record consumes an allowance', () {
      expect(event(WasteType.carta, '2026-08-19').countsTowardsQuota, isTrue);
      expect(
        event(
          WasteType.carta,
          '2026-08-19',
          status: CollectionStatus.skipped,
        ).countsTowardsQuota,
        isFalse,
      );
    });

    test('the status survives a round trip through the document map', () {
      final map = event(
        WasteType.carta,
        '2026-08-19',
        status: CollectionStatus.skipped,
      ).toMap();
      expect(map['status'], 'skipped');
      expect(CollectionStatus.fromId(map['status'] as String?),
          CollectionStatus.skipped);
    });
  });

  group('counters ignore skipped pickups', () {
    test('a skip does not increment the count', () {
      final events = [
        event(WasteType.carta, '2026-08-19'),
        event(WasteType.carta, '2026-08-26', status: CollectionStatus.skipped),
        event(WasteType.carta, '2026-09-02'),
      ];
      expect(countByType(events, 2026), {WasteType.carta: 2});
    });

    test('the free allowance is preserved by skipping', () {
      final status = quotaStatusFor(
        config: config(WasteType.carta, policy: const QuotaPolicy.limited(3)),
        events: [
          event(WasteType.carta, '2026-01-07'),
          event(
            WasteType.carta,
            '2026-01-14',
            status: CollectionStatus.skipped,
          ),
        ],
        year: 2026,
      );
      expect(status.used, 1);
      expect(status.remaining, 2);
    });

    test('a year of nothing but skips reads as untouched', () {
      final status = quotaStatusFor(
        config: config(WasteType.carta, policy: const QuotaPolicy.limited(12)),
        events: [
          for (final d in ['2026-01-07', '2026-01-14', '2026-01-21'])
            event(WasteType.carta, d, status: CollectionStatus.skipped),
        ],
        year: 2026,
      );
      expect(status.used, 0);
      expect(status.remaining, 12);
      expect(status.billed, 0);
    });

    test('flipping a record back to done restores the count', () {
      final skipped = event(
        WasteType.carta,
        '2026-08-19',
        status: CollectionStatus.skipped,
      );
      expect(countByType([skipped], 2026), isEmpty);

      final restored = skipped.copyWith(status: CollectionStatus.done);
      expect(countByType([restored], 2026), {WasteType.carta: 1});
    });
  });

  group('statistics ignore skipped pickups', () {
    test('a skipped month shows nothing collected', () {
      final b = monthlyBreakdown(
        events: [
          event(WasteType.carta, '2026-03-04'),
          event(
            WasteType.carta,
            '2026-03-11',
            status: CollectionStatus.skipped,
          ),
        ],
        year: 2026,
      );
      expect(b.totalForMonth(2), 1);
      expect(b.total, 1);
    });

    test('a type present only as skips does not appear at all', () {
      final b = monthlyBreakdown(
        events: [
          event(WasteType.vetro, '2026-03-11', status: CollectionStatus.skipped),
        ],
        year: 2026,
      );
      expect(b.typesPresent, isEmpty);
      expect(b.isEmpty, isTrue);
    });
  });

  group('reminders stop for a settled pickup', () {
    List<ReminderPlan> plansFor(List<CollectionEvent> events) =>
        buildReminderPlans(
          houses: [
            HouseReminderInput(
              houseId: 'h1',
              houseName: 'Casa',
              configs: [config(WasteType.carta)],
              events: events,
            ),
          ],
          today: LocalDate.parse('2026-08-15'),
          now: DateTime.parse('2026-08-15 09:00'),
          notificationHour: 20,
          notificationMinute: 0,
        );

    test('a skipped pickup gets no reminder, like a recorded one', () {
      // The user has decided not to put that waste out; asking again would be
      // nagging about a decision already made.
      final skipped = plansFor([
        event(WasteType.carta, '2026-08-19', status: CollectionStatus.skipped),
      ]);
      expect(skipped.first.pickupDate.toKey(), '2026-08-26');
    });

    test('undoing a skip brings the reminder back', () {
      final pending = plansFor(const []);
      expect(pending.first.pickupDate.toKey(), '2026-08-19');
    });

    test('a skip on a different day leaves the reminder alone', () {
      final plans = plansFor([
        event(WasteType.carta, '2026-08-12', status: CollectionStatus.skipped),
      ]);
      expect(plans.first.pickupDate.toKey(), '2026-08-19');
    });

    test('the reminder count is unaffected by earlier skips', () {
      final plans = plansFor([
        event(WasteType.carta, '2026-01-07'),
        event(WasteType.carta, '2026-01-14', status: CollectionStatus.skipped),
      ]);
      expect(
        plans.first.body,
        contains('Ritiri gratuiti rimanenti: 11 su 12.'),
      );
    });
  });

  group('queued notification actions keep their outcome', () {
    const payload = NotificationPayload(
      houseId: 'h1',
      dateKey: '2026-08-19',
      types: ['carta'],
    );

    test('a skip replayed later is still a skip', () {
      final encoded = payload.encode(status: CollectionStatus.skipped);
      expect(
        NotificationPayload.decodeStatus(encoded),
        CollectionStatus.skipped,
      );
      // The rest of the payload must survive alongside it.
      final decoded = NotificationPayload.decode(encoded)!;
      expect(decoded.houseId, 'h1');
      expect(decoded.wasteTypes, [WasteType.carta]);
    });

    test('a confirmation replayed later is still a confirmation', () {
      final encoded = payload.encode(status: CollectionStatus.done);
      expect(NotificationPayload.decodeStatus(encoded), CollectionStatus.done);
    });

    test('an entry with no status replays as a collection', () {
      expect(
        NotificationPayload.decodeStatus(payload.encode()),
        CollectionStatus.done,
      );
      expect(NotificationPayload.decodeStatus(null), CollectionStatus.done);
      expect(NotificationPayload.decodeStatus('non json'), CollectionStatus.done);
    });

    test('a scheduled reminder carries no status of its own', () {
      // The outcome is unknown until the user picks a button.
      expect(payload.encode(), isNot(contains('status')));
    });
  });
}
