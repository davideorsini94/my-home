import 'package:flutter_test/flutter_test.dart';
import 'package:my_home/core/local_date.dart';
import 'package:my_home/domain/entities/maintenance.dart';
import 'package:my_home/domain/entities/maintenance_log_entry.dart';
import 'package:my_home/domain/maintenance_schedule.dart';

Maintenance boiler({
  String id = 'm1',
  int every = 1,
  RecurrenceUnit unit = RecurrenceUnit.years,
  bool unknownRecurrence = false,
  String name = 'Caldaia',
}) => Maintenance(
  id: id,
  name: name,
  iconKey: 'boiler',
  recurrence: unknownRecurrence
      ? null
      : Recurrence(every: every, unit: unit),
  costCents: 12000,
);

MaintenanceLogEntry done(
  String date, {
  String id = 'm1',
  String by = 'davide',
  int? cost,
}) => MaintenanceLogEntry(
  id: MaintenanceLogEntry.doneId(id, LocalDate.parse(date)),
  maintenanceId: id,
  date: LocalDate.parse(date),
  status: MaintenanceEntryStatus.done,
  recordedByUid: by,
  recordedByName: by,
  costCents: cost,
);

MaintenanceLogEntry skip(String date, {String id = 'm1', String by = 'papa'}) =>
    MaintenanceLogEntry(
      id: MaintenanceLogEntry.skipId(id, LocalDate.parse(date)),
      maintenanceId: id,
      date: LocalDate.parse(date),
      status: MaintenanceEntryStatus.skipped,
      recordedByUid: by,
      recordedByName: by,
    );

LocalDate on(String date) => LocalDate.parse(date);

MaintenanceStatus statusOf(
  Maintenance m,
  List<MaintenanceLogEntry> log,
  String today,
) => deriveStatus(m, log, on(today));

void main() {
  group('never executed', () {
    test('has no due date and no reminder', () {
      final s = statusOf(boiler(), const [], '2026-09-14');
      expect(s.isNeverDone, isTrue);
      expect(s.nextDue, isNull);
      expect(s.isWedged, isFalse);
      expect(s.isActionable(on('2026-09-14')), isFalse);
    });

    test('the first execution seeds everything', () {
      final s = statusOf(boiler(), [done('2026-09-14')], '2026-09-14');
      expect(s.lastDone, on('2026-09-14'));
      expect(s.nextDue, on('2027-09-14'));
    });
  });

  group('unknown recurrence', () {
    test('stays visible but computes no due date', () {
      // Hiding a shared object from an older client is worse than showing it
      // read-only, so the maintenance survives with no schedule.
      final s = statusOf(
        boiler(unknownRecurrence: true),
        [done('2026-09-14')],
        '2026-09-14',
      );
      expect(s.hasUnknownRecurrence, isTrue);
      expect(s.nextDue, isNull);
      expect(s.isWedged, isFalse);
    });
  });

  group('skips move the due date without faking an execution', () {
    test('one skip advances exactly one period', () {
      final m = boiler(every: 6, unit: RecurrenceUnit.months);
      final log = [done('2025-09-10'), skip('2026-03-10')];
      final s = statusOf(m, log, '2026-01-01');
      expect(s.lastDone, on('2025-09-10'), reason: 'a skip is not an execution');
      expect(s.nextDue, on('2026-09-10'));
      expect(s.skipsAfterLastDone, 1);
    });

    test('consecutive skips accumulate', () {
      final m = boiler(every: 6, unit: RecurrenceUnit.months);
      final log = [done('2025-09-10'), skip('2026-03-10'), skip('2026-09-10')];
      final s = statusOf(m, log, '2026-01-01');
      expect(s.nextDue, on('2027-03-10'));
      expect(s.skipsAfterLastDone, 2);
    });

    test('a skip on a date that is not a due date is inert', () {
      final m = boiler(every: 6, unit: RecurrenceUnit.months);
      final log = [done('2025-09-10'), skip('2026-05-01')];
      expect(statusOf(m, log, '2026-01-01').nextDue, on('2026-03-10'));
    });
  });

  group('an execution always dominates a skip on the same date', () {
    // The reminder fires on the due date, so both actions target it. Sharing a
    // document id here would let a skip erase the execution and drag the last
    // execution date back a whole period.
    test('execute then skip, same due date', () {
      final m = boiler(every: 1, unit: RecurrenceUnit.months);
      final log = [
        done('2026-08-14'),
        done('2026-09-14', cost: 12000),
        skip('2026-09-14'),
      ];
      final s = statusOf(m, log, '2026-09-14');
      expect(s.lastDone, on('2026-09-14'));
      expect(s.lastExecution!.costCents, 12000, reason: 'cost survives');
      expect(s.nextDue, on('2026-10-14'));
    });

    test('skip then execute, same due date — order does not matter', () {
      final m = boiler(every: 1, unit: RecurrenceUnit.months);
      final log = [
        done('2026-08-14'),
        skip('2026-09-14'),
        done('2026-09-14', cost: 12000),
      ];
      final s = statusOf(m, log, '2026-09-14');
      expect(s.lastDone, on('2026-09-14'));
      expect(s.lastExecution!.costCents, 12000);
      expect(s.nextDue, on('2026-10-14'));
    });

    test('an offline skip syncing after an execution cannot shadow it', () {
      final m = boiler(every: 1, unit: RecurrenceUnit.months);
      final base = [done('2026-08-14'), done('2026-09-14')];
      final before = statusOf(m, base, '2026-09-14');
      final after = statusOf(m, [...base, skip('2026-09-14')], '2026-09-14');
      expect(after.lastDone, before.lastDone);
      expect(after.nextDue, before.nextDue);
    });

    test('the ids of a done and a skip on one date really do differ', () {
      expect(
        MaintenanceLogEntry.doneId('m1', on('2026-09-14')),
        isNot(MaintenanceLogEntry.skipId('m1', on('2026-09-14'))),
      );
    });
  });

  group('self-repair', () {
    test('an execution dated in the future is ignored and surfaced', () {
      // A device with a wrong clock writes one of these. Without the exclusion
      // every later real execution is older than it and gets ignored, locking
      // the maintenance permanently.
      final m = boiler();
      final log = [done('2027-01-01'), done('2026-09-14')];
      final s = statusOf(m, log, '2026-09-14');
      expect(s.lastDone, on('2026-09-14'));
      expect(s.nextDue, on('2027-09-14'));
      expect(s.ignoredFutureExecutions.single.date, on('2027-01-01'));
      expect(s.hasIgnoredFutureExecutions, isTrue);
    });

    test('deleting every entry returns to never-executed', () {
      final s = statusOf(boiler(), const [], '2026-09-14');
      expect(s.isNeverDone, isTrue);
      expect(s.nextDue, isNull);
    });

    test('the last execution moving backwards recomputes cleanly', () {
      final m = boiler();
      final s = statusOf(m, [done('2024-09-14')], '2026-09-14');
      expect(s.lastDone, on('2024-09-14'));
      expect(s.nextDue, on('2025-09-14'));
      expect(s.isOverdue(on('2026-09-14')), isTrue);
    });

    test('entries of another maintenance are ignored', () {
      final s = statusOf(
        boiler(id: 'm1'),
        [done('2026-09-14', id: 'm2')],
        '2026-09-14',
      );
      expect(s.isNeverDone, isTrue);
    });
  });

  group('dueAfterSkip agrees with what the list will show', () {
    test('matches the derivation after a recurrence edit to a divisor', () {
      // Two skips were recorded under a 6-month cadence. Switching to 3 months
      // makes one of them line up again, so a single tap would move two
      // periods. The preview must say so rather than promising March.
      final log = [done('2025-09-10'), skip('2026-03-10'), skip('2026-09-10')];
      final edited = boiler(every: 3, unit: RecurrenceUnit.months);

      final before = statusOf(edited, log, '2025-11-01');
      expect(before.nextDue, on('2025-12-10'));

      final preview = dueAfterSkip(edited, log, on('2025-11-01'));
      final actual = statusOf(
        edited,
        [...log, skip('2025-12-10')],
        '2025-11-01',
      ).nextDue;
      expect(preview, actual);
      expect(preview, on('2026-06-10'));
    });

    test('is null when there is nothing to skip', () {
      expect(dueAfterSkip(boiler(), const [], on('2026-09-14')), isNull);
    });
  });

  group('wedging', () {
    test('too many skips yields no due date rather than a skipped one', () {
      // Returning the last candidate would hand back a date already in the
      // skipped set: "Salta" would rewrite an existing skip and appear to do
      // nothing, for ever.
      final m = boiler(every: 1, unit: RecurrenceUnit.days);
      final start = on('2026-01-01');
      final log = <MaintenanceLogEntry>[done('2026-01-01')];
      for (var i = 1; i <= maxSkipDerivation + 5; i++) {
        log.add(skip(start.addDays(i).toKey()));
      }
      final s = statusOf(m, log, '2026-01-01');
      expect(s.isWedged, isTrue);
      expect(s.nextDue, isNull);
      expect(dueAfterSkip(m, log, on('2026-01-01')), isNull);
    });

    test('an executable maintenance is never wedged', () {
      final s = statusOf(boiler(), [done('2026-09-14')], '2026-09-14');
      expect(s.isWedged, isFalse);
    });
  });

  group('duesToSkipUntilFuture', () {
    test('is empty when nothing is overdue', () {
      final m = boiler();
      expect(
        duesToSkipUntilFuture(m, [done('2026-09-14')], on('2026-09-14')),
        isEmpty,
      );
    });

    test('lists exactly the occurrences needed to catch up', () {
      // Seeded Jan 2024 on a 6-month cadence: due 2024-07, 2025-01, 2025-07,
      // 2026-01, 2026-07 are all in the past by Sept 2026.
      final m = boiler(every: 6, unit: RecurrenceUnit.months);
      final dues = duesToSkipUntilFuture(
        m,
        [done('2024-01-10')],
        on('2026-09-14'),
      );
      expect(dues.map((d) => d.toKey()), [
        '2024-07-10',
        '2025-01-10',
        '2025-07-10',
        '2026-01-10',
        '2026-07-10',
      ]);
    });

    test('leaves the next due strictly in the future', () {
      final m = boiler(every: 6, unit: RecurrenceUnit.months);
      final log = [done('2024-01-10')];
      final dues = duesToSkipUntilFuture(m, log, on('2026-09-14'));
      final after = deriveStatus(m, [
        ...log,
        for (final d in dues) skip(d.toKey()),
      ], on('2026-09-14'));
      expect(after.nextDue!.compareTo(on('2026-09-14')) > 0, isTrue);
    });

    test('refuses rather than writing more than a tap should', () {
      // A daily item untouched for years would need hundreds of entries.
      // Declining is better than silently writing them, and better than
      // nudging the derivation towards its guard.
      final m = boiler(every: 1, unit: RecurrenceUnit.days);
      expect(
        duesToSkipUntilFuture(m, [done('2024-01-01')], on('2026-09-14')),
        isEmpty,
      );
    });

    test('never pushes the total past the safety limit', () {
      final m = boiler(every: 1, unit: RecurrenceUnit.days);
      final start = on('2026-01-01');
      final log = <MaintenanceLogEntry>[done('2026-01-01')];
      for (var i = 1; i <= maxSkipsPerMaintenance - 10; i++) {
        log.add(skip(start.addDays(i).toKey()));
      }
      final dues = duesToSkipUntilFuture(m, log, on('2026-12-31'));
      expect(dues.length <= maxSkipsPerTap, isTrue);
      final total = deriveStatus(m, log, on('2026-12-31')).skipsAfterLastDone +
          dues.length;
      expect(total <= maxSkipsPerMaintenance, isTrue);
    });
  });

  group('logLowerBound', () {
    test('is at least ten years back', () {
      final bound = logLowerBound([boiler()], on('2026-09-14'));
      expect(bound.year, 2016);
      expect(bound < on('2016-09-14'), isTrue, reason: 'plus a 30-day margin');
    });

    test('stretches for a long cadence', () {
      // A five-year item needs fifteen years of history to still read as
      // executed rather than silently reading as never done.
      final bound = logLowerBound(
        [boiler(every: 5, unit: RecurrenceUnit.years)],
        on('2026-09-14'),
      );
      expect(bound.year, 2011);
    });

    test('takes the longest cadence across the house', () {
      final bound = logLowerBound([
        boiler(id: 'a', every: 1, unit: RecurrenceUnit.months),
        boiler(id: 'b', every: 5, unit: RecurrenceUnit.years),
      ], on('2026-09-14'));
      expect(bound.year, 2011);
    });

    test('is capped so the query cannot grow without limit', () {
      final bound = logLowerBound(
        [boiler(every: 50, unit: RecurrenceUnit.years)],
        on('2026-09-14'),
      );
      expect(bound.year, 1996);
    });

    test('ignores a maintenance whose recurrence cannot be read', () {
      final bound = logLowerBound(
        [boiler(unknownRecurrence: true)],
        on('2026-09-14'),
      );
      expect(bound.year, 2016);
    });

    test('an execution at the bound is still loaded, one day older is not', () {
      final m = boiler();
      final bound = logLowerBound([m], on('2026-09-14'));
      final atBound = statusOf(m, [done(bound.toKey())], '2026-09-14');
      expect(atBound.isNeverDone, isFalse);
      expect(atBound.isOverdue(on('2026-09-14')), isTrue);

      // Older than the bound the entry is never fetched, so the maintenance
      // reads as never executed. One "Esegui" repairs it.
      final beyond = statusOf(m, const [], '2026-09-14');
      expect(beyond.isNeverDone, isTrue);
    });
  });

  group('compareForList', () {
    test('puts broken items first, then overdue, then scheduled, then unused', () {
      final today = on('2026-09-14');
      final wedgedLog = <MaintenanceLogEntry>[done('2026-01-01', id: 'w')];
      for (var i = 1; i <= maxSkipDerivation + 2; i++) {
        wedgedLog.add(skip(on('2026-01-01').addDays(i).toKey(), id: 'w'));
      }

      final items = [
        deriveStatus(boiler(id: 'n', name: 'Mai usata'), const [], today),
        deriveStatus(
          boiler(id: 'f', name: 'Futura'),
          [done('2026-09-01', id: 'f')],
          today,
        ),
        deriveStatus(
          boiler(id: 'o', name: 'Scaduta'),
          [done('2024-01-01', id: 'o')],
          today,
        ),
        deriveStatus(
          boiler(id: 'w', name: 'Bloccata', every: 1, unit: RecurrenceUnit.days),
          wedgedLog,
          today,
        ),
      ]..sort((a, b) => compareForList(a, b, today));

      expect(
        items.map((s) => s.maintenance.name),
        ['Bloccata', 'Scaduta', 'Futura', 'Mai usata'],
      );
    });

    test('orders equal ranks by due date, then by name', () {
      final today = on('2026-09-14');
      final items = [
        deriveStatus(
          boiler(id: 'b', name: 'Zeta'),
          [done('2025-10-01', id: 'b')],
          today,
        ),
        deriveStatus(
          boiler(id: 'a', name: 'Alfa'),
          [done('2025-09-01', id: 'a')],
          today,
        ),
      ]..sort((a, b) => compareForList(a, b, today));
      expect(items.first.maintenance.name, 'Alfa');
    });
  });
}
