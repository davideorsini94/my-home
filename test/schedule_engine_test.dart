import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:my_home/core/local_date.dart';
import 'package:my_home/core/waste_catalogue.dart';
import 'package:my_home/domain/entities/waste_config.dart';
import 'package:my_home/domain/schedule_engine.dart';

ScheduleRule rule({
  required Set<int> weekdays,
  required int intervalWeeks,
  required String anchor,
}) => ScheduleRule(
  weekdays: weekdays,
  intervalWeeks: intervalWeeks,
  anchorDate: LocalDate.parse(anchor),
);

List<String> next(ScheduleRule r, String from, [int count = 3]) =>
    occurrences(rule: r, from: LocalDate.parse(from))
        .take(count)
        .map((d) => d.toKey())
        .toList();

void main() {
  const mon = DateTime.monday;
  const tue = DateTime.tuesday;
  const wed = DateTime.wednesday;
  const thu = DateTime.thursday;
  const fri = DateTime.friday;
  const sat = DateTime.saturday;
  const sun = DateTime.sunday;

  group('occurrences — reference cases', () {
    test('case 1: Wednesday every 2 weeks ("ogni 15 giorni")', () {
      final r = rule(
        weekdays: {wed},
        intervalWeeks: 2,
        anchor: '2026-08-05',
      );
      expect(next(r, '2026-08-15'), [
        '2026-08-19',
        '2026-09-02',
        '2026-09-16',
      ]);
    });

    test('case 2: Monday and Thursday every week', () {
      final r = rule(
        weekdays: {mon, thu},
        intervalWeeks: 1,
        anchor: '2026-01-01',
      );
      expect(next(r, '2026-08-15'), [
        '2026-08-17',
        '2026-08-20',
        '2026-08-24',
      ]);
    });

    test('case 3: anchor in the future yields a negative week index', () {
      final r = rule(
        weekdays: {tue},
        intervalWeeks: 2,
        anchor: '2026-09-07',
      );
      expect(next(r, '2026-08-15'), [
        '2026-08-25',
        '2026-09-08',
        '2026-09-22',
      ]);
    });

    test('case 4: anchor weekday need not be one of the pickup weekdays', () {
      // Anchor is a Thursday; the Monday of the anchor week precedes the anchor
      // and must still count as an occurrence.
      final r = rule(
        weekdays: {mon},
        intervalWeeks: 2,
        anchor: '2026-08-06',
      );
      expect(next(r, '2026-08-01'), [
        '2026-08-03',
        '2026-08-17',
        '2026-08-31',
      ]);
    });

    test('case 5: interval applies per week block, not per weekday', () {
      final r = rule(
        weekdays: {mon, thu},
        intervalWeeks: 2,
        anchor: '2026-08-03',
      );
      expect(next(r, '2026-08-04'), [
        '2026-08-06',
        '2026-08-17',
        '2026-08-20',
      ]);
    });

    test('case 6: spring DST week is unaffected', () {
      final r = rule(weekdays: {mon}, intervalWeeks: 1, anchor: '2026-01-05');
      expect(next(r, '2026-03-28'), [
        '2026-03-30',
        '2026-04-06',
        '2026-04-13',
      ]);
    });

    test('case 7: Sunday every 2 weeks across the autumn DST change', () {
      // The anchor 2026-10-19 is a Monday, so its week is week zero and the
      // first Sunday occurrence is 2026-10-25 — the DST-change day itself.
      final r = rule(
        weekdays: {sun},
        intervalWeeks: 2,
        anchor: '2026-10-19',
      );
      expect(next(r, '2026-10-20'), [
        '2026-10-25',
        '2026-11-08',
        '2026-11-22',
      ]);
    });

    test('case 8: fortnightly rhythm carries across the year boundary', () {
      // ISO week alignment continues; it does not restart on 1 January.
      final r = rule(
        weekdays: {fri},
        intervalWeeks: 2,
        anchor: '2025-12-22',
      );
      expect(next(r, '2025-12-27'), [
        '2026-01-09',
        '2026-01-23',
        '2026-02-06',
      ]);
    });

    test('case 9: every 4 weeks behaves monthly-ish', () {
      final r = rule(
        weekdays: {wed},
        intervalWeeks: 4,
        anchor: '2026-08-05',
      );
      expect(next(r, '2026-08-06'), [
        '2026-09-02',
        '2026-09-30',
        '2026-10-28',
      ]);
    });

    test('case 10: "from" is inclusive', () {
      final r = rule(weekdays: {sat}, intervalWeeks: 1, anchor: '2026-08-15');
      expect(next(r, '2026-08-15'), [
        '2026-08-15',
        '2026-08-22',
        '2026-08-29',
      ]);
    });
  });

  group('occurrences — degenerate rules', () {
    test('no weekdays yields nothing', () {
      final r = rule(weekdays: {}, intervalWeeks: 1, anchor: '2026-08-15');
      expect(next(r, '2026-08-15'), isEmpty);
    });

    test('all seven weekdays every week yields every day', () {
      final r = rule(
        weekdays: {mon, tue, wed, thu, fri, sat, sun},
        intervalWeeks: 1,
        anchor: '2026-08-15',
      );
      expect(next(r, '2026-08-15', 4), [
        '2026-08-15',
        '2026-08-16',
        '2026-08-17',
        '2026-08-18',
      ]);
    });

    test('weekdays are emitted in chronological order within a week', () {
      final r = rule(
        weekdays: {sat, mon, thu},
        intervalWeeks: 1,
        anchor: '2026-08-10',
      );
      expect(next(r, '2026-08-10', 3), [
        '2026-08-10',
        '2026-08-13',
        '2026-08-15',
      ]);
    });
  });

  group('occurrences — invariants', () {
    test('every yielded date matches both predicates and increases', () {
      final random = Random(20260815);
      for (var i = 0; i < 200; i++) {
        final weekdayCount = 1 + random.nextInt(7);
        final weekdays = <int>{};
        while (weekdays.length < weekdayCount) {
          weekdays.add(1 + random.nextInt(7));
        }
        final r = ScheduleRule(
          weekdays: weekdays,
          intervalWeeks: 1 + random.nextInt(6),
          anchorDate: LocalDate(2026, 1, 1).addDays(random.nextInt(730) - 365),
        );
        final from = LocalDate(2026, 1, 1).addDays(random.nextInt(730) - 365);
        final dates = occurrences(rule: r, from: from).take(25).toList();

        expect(dates, hasLength(25), reason: 'rule must be productive');
        final anchorMonday = r.anchorDate.mondayOfWeek;
        LocalDate? previous;
        for (final date in dates) {
          expect(date >= from, isTrue, reason: '$date before $from');
          expect(r.weekdays.contains(date.weekday), isTrue);
          final weekIndex = anchorMonday.daysUntil(date.mondayOfWeek) ~/ 7;
          expect(weekIndex.floorMod(r.intervalWeeks), 0);
          if (previous != null) {
            expect(date > previous, isTrue, reason: 'not strictly increasing');
          }
          previous = date;
        }
      }
    });

    test('shifting the anchor by a whole interval changes nothing', () {
      final a = rule(weekdays: {tue, fri}, intervalWeeks: 3, anchor: '2026-05-04');
      final b = ScheduleRule(
        weekdays: a.weekdays,
        intervalWeeks: a.intervalWeeks,
        anchorDate: a.anchorDate.addDays(21),
      );
      expect(next(a, '2026-08-15', 8), next(b, '2026-08-15', 8));
    });
  });

  group('pickupsInRange', () {
    WasteConfig config(List<ScheduleRule> rules, {bool enabled = true}) =>
        WasteConfig(
          type: WasteType.carta,
          enabled: enabled,
          policy: const QuotaPolicy.limited(12),
          rules: rules,
        );

    test('is inclusive on both ends', () {
      final c = config([
        rule(weekdays: {sat}, intervalWeeks: 1, anchor: '2026-08-15'),
      ]);
      final dates = pickupsInRange(
        c,
        LocalDate.parse('2026-08-15'),
        LocalDate.parse('2026-08-29'),
      ).map((d) => d.toKey()).toList();
      expect(dates, ['2026-08-15', '2026-08-22', '2026-08-29']);
    });

    test('merges and de-duplicates overlapping rules', () {
      final c = config([
        rule(weekdays: {mon}, intervalWeeks: 1, anchor: '2026-08-10'),
        rule(weekdays: {mon, thu}, intervalWeeks: 2, anchor: '2026-08-10'),
      ]);
      final dates = pickupsInRange(
        c,
        LocalDate.parse('2026-08-10'),
        LocalDate.parse('2026-08-24'),
      ).map((d) => d.toKey()).toList();
      expect(dates, [
        '2026-08-10',
        '2026-08-13',
        '2026-08-17',
        '2026-08-24',
      ]);
    });

    test('a disabled config has no pickups', () {
      final c = config([
        rule(weekdays: {sat}, intervalWeeks: 1, anchor: '2026-08-15'),
      ], enabled: false);
      expect(
        pickupsInRange(
          c,
          LocalDate.parse('2026-08-15'),
          LocalDate.parse('2026-12-31'),
        ),
        isEmpty,
      );
    });

    test('an inverted range is empty rather than infinite', () {
      final c = config([
        rule(weekdays: {sat}, intervalWeeks: 1, anchor: '2026-08-15'),
      ]);
      expect(
        pickupsInRange(
          c,
          LocalDate.parse('2026-08-29'),
          LocalDate.parse('2026-08-15'),
        ),
        isEmpty,
      );
    });
  });

  group('nextPickups', () {
    test('caps the merged result at the requested count', () {
      final c = WasteConfig(
        type: WasteType.vetro,
        enabled: true,
        policy: const QuotaPolicy.unlimited(),
        rules: [
          rule(weekdays: {mon}, intervalWeeks: 1, anchor: '2026-08-10'),
          rule(weekdays: {fri}, intervalWeeks: 1, anchor: '2026-08-10'),
        ],
      );
      final dates = nextPickups(c, LocalDate.parse('2026-08-15'), count: 4)
          .map((d) => d.toKey())
          .toList();
      expect(dates, [
        '2026-08-17',
        '2026-08-21',
        '2026-08-24',
        '2026-08-28',
      ]);
    });
  });

  group('isPickupDay', () {
    final c = WasteConfig(
      type: WasteType.umido,
      enabled: true,
      policy: const QuotaPolicy.paid(),
      rules: [rule(weekdays: {wed}, intervalWeeks: 2, anchor: '2026-08-05')],
    );

    test('is true on an on-week Wednesday', () {
      expect(isPickupDay(c, LocalDate.parse('2026-08-19')), isTrue);
    });

    test('is false on an off-week Wednesday', () {
      expect(isPickupDay(c, LocalDate.parse('2026-08-26')), isFalse);
    });

    test('is false on another weekday of an on-week', () {
      expect(isPickupDay(c, LocalDate.parse('2026-08-20')), isFalse);
    });
  });
}
