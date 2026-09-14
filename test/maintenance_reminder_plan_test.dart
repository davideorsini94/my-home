import 'package:flutter_test/flutter_test.dart';
import 'package:rubbish_manager/core/fnv_hash.dart';
import 'package:rubbish_manager/core/local_date.dart';
import 'package:rubbish_manager/domain/entities/maintenance.dart';
import 'package:rubbish_manager/domain/entities/maintenance_log_entry.dart';
import 'package:rubbish_manager/notifications/maintenance_payload.dart';
import 'package:rubbish_manager/notifications/maintenance_reminder_plan.dart';
import 'package:rubbish_manager/notifications/notification_service.dart';

Maintenance boiler({
  String id = 'm1',
  String name = 'Caldaia',
  int every = 1,
  RecurrenceUnit unit = RecurrenceUnit.years,
  bool unknownRecurrence = false,
  MaintenanceContact? contact,
}) => Maintenance(
  id: id,
  name: name,
  iconKey: 'boiler',
  recurrence: unknownRecurrence ? null : Recurrence(every: every, unit: unit),
  contact: contact,
);

MaintenanceLogEntry done(String date, {String id = 'm1'}) =>
    MaintenanceLogEntry(
      id: MaintenanceLogEntry.doneId(id, LocalDate.parse(date)),
      maintenanceId: id,
      date: LocalDate.parse(date),
      status: MaintenanceEntryStatus.done,
      recordedByUid: 'davide',
      recordedByName: 'Davide',
    );

List<MaintenanceReminderPlan> plansFor(
  List<MaintenanceReminderInput> houses, {
  String today = '2026-09-14',
  String now = '2026-09-14 09:00',
  int maxPending = 16,
}) => buildMaintenanceReminderPlans(
  houses: houses,
  today: LocalDate.parse(today),
  now: DateTime.parse(now),
  notificationHour: 20,
  notificationMinute: 0,
  maxPending: maxPending,
);

MaintenanceReminderInput house({
  String id = 'h1',
  String name = 'Casa Orsini',
  required List<Maintenance> maintenances,
  List<MaintenanceLogEntry> log = const [],
}) => MaintenanceReminderInput(
  houseId: id,
  houseName: name,
  maintenances: maintenances,
  log: log,
);

void main() {
  group('both slots are scheduled up front', () {
    test('a due maintenance gets a due reminder and a follow-up', () {
      // Scheduling the follow-up later would depend on the app being opened in
      // that exact week — and the person who needs the nudge is the one who
      // will not open it.
      final plans = plansFor([
        house(maintenances: [boiler()], log: [done('2025-10-01')]),
      ]);
      expect(plans, hasLength(2));
      expect(plans[0].slot, MaintenanceReminderSlot.due);
      expect(plans[0].fireAt, DateTime(2026, 10, 1, 20));
      expect(plans[1].slot, MaintenanceReminderSlot.followUp);
      expect(plans[1].fireAt, DateTime(2026, 10, 8, 20));
    });

    test('a slot already in the past is skipped independently', () {
      // Due today at 20:00 has passed; the follow-up a week out has not.
      final plans = plansFor(
        [
          house(maintenances: [boiler()], log: [done('2025-09-14')]),
        ],
        now: '2026-09-14 22:00',
      );
      expect(plans, hasLength(1));
      expect(plans.single.slot, MaintenanceReminderSlot.followUp);
      expect(plans.single.fireAt, DateTime(2026, 9, 21, 20));
    });

    test('an overdue maintenance whose both slots passed gets nothing', () {
      final plans = plansFor([
        house(maintenances: [boiler()], log: [done('2020-01-01')]),
      ]);
      expect(plans, isEmpty);
    });
  });

  group('what earns no reminder', () {
    test('never executed', () {
      expect(plansFor([house(maintenances: [boiler()])]), isEmpty);
    });

    test('a recurrence this client cannot read', () {
      final plans = plansFor([
        house(
          maintenances: [boiler(unknownRecurrence: true)],
          log: [done('2025-10-01')],
        ),
      ]);
      expect(plans, isEmpty);
    });
  });

  group('a follow-up can never evict a primary reminder', () {
    test('every due slot survives the cap before any follow-up', () {
      // Sorting by time alone would let maintenance 1's follow-up, seven days
      // after its due date, outrank maintenance 9's first notice.
      final maintenances = <Maintenance>[];
      final log = <MaintenanceLogEntry>[];
      for (var i = 0; i < 10; i++) {
        final id = 'm$i';
        maintenances.add(boiler(id: id, name: 'Item $i'));
        log.add(done(LocalDate(2025, 9, 20).addDays(i).toKey(), id: id));
      }

      final plans = plansFor(
        [house(maintenances: maintenances, log: log)],
        maxPending: 12,
      );

      final dues = plans.where((p) => p.slot == MaintenanceReminderSlot.due);
      expect(dues, hasLength(10), reason: 'all primary reminders kept');
      expect(plans, hasLength(12));
      expect(
        plans.skip(10).every((p) => p.slot == MaintenanceReminderSlot.followUp),
        isTrue,
      );
    });

    test('the budget truncates the latest follow-ups first', () {
      final maintenances = <Maintenance>[];
      final log = <MaintenanceLogEntry>[];
      for (var i = 0; i < 3; i++) {
        final id = 'm$i';
        maintenances.add(boiler(id: id));
        log.add(done(LocalDate(2025, 9, 20).addDays(i * 3).toKey(), id: id));
      }
      final plans = plansFor(
        [house(maintenances: maintenances, log: log)],
        maxPending: 4,
      );
      expect(plans, hasLength(4));
      expect(plans.last.slot, MaintenanceReminderSlot.followUp);
      // The surviving follow-up is the earliest one.
      expect(plans.last.fireAt, DateTime(2026, 9, 27, 20));
    });
  });

  group('ids', () {
    test('are stable, distinct per slot, and disjoint from waste ids', () {
      final plans = plansFor([
        house(maintenances: [boiler()], log: [done('2025-10-01')]),
      ]);
      expect(plans[0].id, stableNotificationId('m|h1|m1|due'));
      expect(plans[1].id, stableNotificationId('m|h1|m1|fu'));
      expect(plans[0].id, isNot(plans[1].id));
      // Waste ids are 'houseId|dateKey'; the 'm|' prefix keeps the namespaces
      // from ever producing the same string.
      expect(plans[0].id, isNot(stableNotificationId('h1|2026-10-01')));
    });

    test('differ across houses and maintenances', () {
      final plans = plansFor([
        house(
          id: 'h1',
          maintenances: [boiler(id: 'a'), boiler(id: 'b')],
          log: [done('2025-10-01', id: 'a'), done('2025-10-02', id: 'b')],
        ),
        house(
          id: 'h2',
          maintenances: [boiler(id: 'a')],
          log: [done('2025-10-01', id: 'a')],
        ),
      ]);
      expect(plans.map((p) => p.id).toSet(), hasLength(plans.length));
    });
  });

  group('wording', () {
    test('the due reminder names the house, cadence and last execution', () {
      final plans = plansFor([
        house(maintenances: [boiler(every: 1)], log: [done('2025-10-01')]),
      ]);
      final due = plans.first;
      expect(due.title, 'Manutenzione in scadenza — Casa Orsini');
      expect(due.body, contains('«Caldaia»'));
      expect(due.body, contains('ogni anno'));
      expect(due.body, contains('Ultima esecuzione:'));
    });

    test('the due reminder names the contact when there is one', () {
      final plans = plansFor([
        house(
          maintenances: [
            boiler(
              contact: const MaintenanceContact(
                name: 'Idraulico Rossi',
                phone: '+39 333 1234567',
              ),
            ),
          ],
          log: [done('2025-10-01')],
        ),
      ]);
      expect(plans.first.body, contains('Contatto: Idraulico Rossi.'));
    });

    test('a number-only contact is not announced by number', () {
      final plans = plansFor([
        house(
          maintenances: [
            boiler(contact: const MaintenanceContact(phone: '3331234567')),
          ],
          log: [done('2025-10-01')],
        ),
      ]);
      expect(plans.first.body, isNot(contains('Contatto:')));
    });

    test('the follow-up covers being settled from the notification too', () {
      // It exists precisely for the case where someone acted from the shade
      // with the app closed, so "dall'app" alone would contradict its purpose.
      final plans = plansFor([
        house(maintenances: [boiler()], log: [done('2025-10-01')]),
      ]);
      final followUp = plans[1];
      expect(followUp.title, 'Manutenzione in ritardo — Casa Orsini');
      expect(followUp.body, contains('dall\'app o dalla notifica'));
      expect(followUp.body, contains('era prevista il'));
    });
  });

  group('payload', () {
    const payload = MaintenancePayload(
      houseId: 'h1',
      maintenanceId: 'm1',
      dueDateKey: '2026-10-01',
      slot: MaintenanceReminderSlot.due,
    );

    test('round-trips', () {
      final decoded = MaintenancePayload.decode(payload.encode())!;
      expect(decoded.houseId, 'h1');
      expect(decoded.maintenanceId, 'm1');
      expect(decoded.dueDate, LocalDate.parse('2026-10-01'));
      expect(decoded.slot, MaintenanceReminderSlot.due);
    });

    test('carries the outcome and the day it was chosen', () {
      // The tap day is captured before the write so an action replayed later
      // records when it happened, not when it synced.
      final encoded = payload.encode(
        status: MaintenanceEntryStatus.done,
        doneDateKey: '2026-10-03',
      );
      expect(
        MaintenancePayload.decodeStatus(encoded),
        MaintenanceEntryStatus.done,
      );
      expect(
        MaintenancePayload.decodeDoneDate(encoded),
        LocalDate.parse('2026-10-03'),
      );
    });

    test('a scheduled reminder carries no outcome of its own', () {
      expect(MaintenancePayload.decodeStatus(payload.encode()), isNull);
      expect(MaintenancePayload.decodeDoneDate(payload.encode()), isNull);
    });

    test('rejects malformed input instead of throwing', () {
      expect(MaintenancePayload.decode(null), isNull);
      expect(MaintenancePayload.decode(''), isNull);
      expect(MaintenancePayload.decode('non json'), isNull);
      expect(MaintenancePayload.decode('{"kind":"maintenance"}'), isNull);
      expect(
        MaintenancePayload.decode(
          '{"kind":"maintenance","houseId":"h","maintenanceId":"m","dueDateKey":"nope"}',
        ),
        isNull,
      );
    });

    test('a waste payload is never mistaken for a maintenance one', () {
      // Waste payloads predate the kind field, so its absence must read as
      // waste or every reminder already in a shade would break on upgrade.
      const wastePayload =
          '{"houseId":"h1","dateKey":"2026-08-19","types":["carta"]}';
      expect(MaintenancePayload.decode(wastePayload), isNull);
      expect(MaintenancePayload.kindOf(wastePayload), ReminderKind.waste);
      expect(
        MaintenancePayload.kindOf(payload.encode()),
        ReminderKind.maintenance,
      );
    });
  });

  group('action mapping', () {
    test('maps the two buttons and nothing else', () {
      expect(
        maintenanceStatusForAction('mark_done'),
        MaintenanceEntryStatus.done,
      );
      expect(
        maintenanceStatusForAction('skip'),
        MaintenanceEntryStatus.skipped,
      );
      expect(maintenanceStatusForAction(null), isNull);
      expect(maintenanceStatusForAction('qualcosaltro'), isNull);
    });

    test('the literals agree with the ids the notifications actually use', () {
      // The mapping hardcodes the strings so the pure file needs no plugin
      // import; this is what stops the two drifting apart silently.
      expect(NotificationService.markDoneActionId, 'mark_done');
      expect(NotificationService.skipActionId, 'skip');
    });
  });
}
