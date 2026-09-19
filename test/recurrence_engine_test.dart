import 'package:flutter_test/flutter_test.dart';
import 'package:my_home/core/local_date.dart';
import 'package:my_home/domain/entities/maintenance.dart';
import 'package:my_home/domain/recurrence_engine.dart';

String jump(String from, int every, RecurrenceUnit unit, {int times = 1}) =>
    advance(
      LocalDate.parse(from),
      Recurrence(every: every, unit: unit),
      times: times,
    ).toKey();

void main() {
  group('daysInMonth', () {
    test('knows February in both kinds of year', () {
      expect(daysInMonth(2026, 2), 28);
      expect(daysInMonth(2028, 2), 29);
      expect(daysInMonth(2026, 12), 31);
      expect(daysInMonth(2026, 4), 30);
    });
  });

  group('month clamping', () {
    test('clamps onto a shorter target month', () {
      expect(jump('2026-08-31', 6, RecurrenceUnit.months), '2027-02-28');
      expect(jump('2026-08-31', 1, RecurrenceUnit.months), '2026-09-30');
      expect(jump('2026-01-31', 1, RecurrenceUnit.months), '2026-02-28');
    });

    test('is anchor-based, so a clamp never drifts', () {
      // Two periods from the anchor returns to the 31st. Chaining one period
      // twice would have stuck on the clamped 28th for ever after.
      expect(jump('2026-08-31', 6, RecurrenceUnit.months, times: 2), '2027-08-31');
      expect(jump('2026-01-31', 1, RecurrenceUnit.months, times: 2), '2026-03-31');
    });

    test('clamps onto a leap day and off one', () {
      expect(jump('2027-11-30', 3, RecurrenceUnit.months), '2028-02-29');
      expect(jump('2028-02-29', 1, RecurrenceUnit.months), '2028-03-29');
      expect(jump('2028-02-29', 1, RecurrenceUnit.years), '2029-02-28');
      expect(jump('2028-02-29', 1, RecurrenceUnit.years, times: 4), '2032-02-29');
    });

    test('years and the equivalent months agree', () {
      expect(
        jump('2028-02-29', 12, RecurrenceUnit.months),
        jump('2028-02-29', 1, RecurrenceUnit.years),
      );
      expect(jump('2026-11-30', 3, RecurrenceUnit.months), '2027-02-28');
      expect(jump('2026-12-15', 1, RecurrenceUnit.months), '2027-01-15');
    });
  });

  group('day and week arithmetic', () {
    test('is unaffected by daylight saving', () {
      // 29 Mar 2026 is the spring change, 25 Oct 2026 the autumn one. LocalDate
      // is UTC-backed, so neither shortens or lengthens a step.
      expect(jump('2026-03-28', 3, RecurrenceUnit.days), '2026-03-31');
      expect(jump('2026-10-24', 2, RecurrenceUnit.weeks), '2026-11-07');
    });

    test('counts weeks as seven days', () {
      expect(
        jump('2026-09-14', 3, RecurrenceUnit.weeks),
        jump('2026-09-14', 21, RecurrenceUnit.days),
      );
    });
  });

  group('caps', () {
    test('the largest allowed recurrence of each unit stays in range', () {
      expect(jump('2026-09-14', 50, RecurrenceUnit.years), '2076-09-14');
      expect(jump('2026-09-14', 600, RecurrenceUnit.months), '2076-09-14');
      // 3653 days reaches 2036-09-14, so 3660 lands a week later.
      expect(jump('2026-09-14', 3660, RecurrenceUnit.days), '2036-09-21');
      // 520 weeks is 3640 days, 13 short of the 3653 that reach 2036-09-14.
      expect(jump('2026-09-14', 520, RecurrenceUnit.weeks), '2036-09-01');
    });
  });

  group('Recurrence construction', () {
    test('asserts on out-of-range values in debug', () {
      expect(
        () => Recurrence(every: 0, unit: RecurrenceUnit.months),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => Recurrence(every: 51, unit: RecurrenceUnit.years),
        throwsA(isA<AssertionError>()),
      );
    });

    test('clamped is the release-safe path and never throws', () {
      expect(Recurrence.clamped(0, RecurrenceUnit.months).every, 1);
      expect(Recurrence.clamped(-5, RecurrenceUnit.days).every, 1);
      expect(Recurrence.clamped(51, RecurrenceUnit.years).every, 50);
      expect(Recurrence.clamped(99999, RecurrenceUnit.days).every, 3660);
      expect(Recurrence.clamped(6, RecurrenceUnit.months).every, 6);
    });

    test('fromMap clamps and rejects an unknown unit', () {
      expect(
        Recurrence.fromMap({'every': 0, 'unit': 'months'})!.every,
        1,
      );
      expect(
        Recurrence.fromMap({'every': 1000, 'unit': 'years'})!.every,
        50,
      );
      // An unknown unit must not become months: an older client would compute
      // wrong due dates and write skips keyed to them.
      expect(Recurrence.fromMap({'every': 6, 'unit': 'fortnights'}), isNull);
      expect(Recurrence.fromMap({'every': 6}), isNull);
      expect(Recurrence.fromMap(null), isNull);
    });

    test('round-trips through a map', () {
      final r = Recurrence(every: 6, unit: RecurrenceUnit.months);
      expect(Recurrence.fromMap(r.toMap()), r);
    });

    test('labels itself in Italian', () {
      expect(Recurrence(every: 1, unit: RecurrenceUnit.years).label, 'ogni anno');
      expect(
        Recurrence(every: 6, unit: RecurrenceUnit.months).label,
        'ogni 6 mesi',
      );
      expect(
        Recurrence(every: 1, unit: RecurrenceUnit.weeks).label,
        'ogni settimana',
      );
      expect(
        Recurrence(every: 15, unit: RecurrenceUnit.days).label,
        'ogni 15 giorni',
      );
    });
  });
}
