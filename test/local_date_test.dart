import 'package:flutter_test/flutter_test.dart';
import 'package:rubbish_manager/core/local_date.dart';

void main() {
  group('parsing and formatting', () {
    test('round-trips a key', () {
      expect(LocalDate.parse('2026-08-15').toKey(), '2026-08-15');
    });

    test('pads single-digit months and days', () {
      expect(LocalDate(2026, 1, 5).toKey(), '2026-01-05');
    });

    test('rejects malformed keys', () {
      expect(() => LocalDate.parse('2026-8-15'), throwsFormatException);
      expect(() => LocalDate.parse('20260815'), throwsFormatException);
      expect(() => LocalDate.parse(''), throwsFormatException);
    });

    test('rejects dates that would silently roll over', () {
      // DateTime.utc(2026, 2, 30) quietly becomes 2 March; parse must not.
      expect(() => LocalDate.parse('2026-02-30'), throwsFormatException);
      expect(() => LocalDate.parse('2026-13-01'), throwsFormatException);
    });

    test('tryParse returns null instead of throwing', () {
      expect(LocalDate.tryParse('nope'), isNull);
      expect(LocalDate.tryParse(null), isNull);
      expect(LocalDate.tryParse('2026-08-15')!.day, 15);
    });

    test('keys sort lexicographically in chronological order', () {
      final keys = ['2026-10-02', '2026-01-15', '2025-12-31', '2026-01-05']
        ..sort();
      expect(keys, [
        '2025-12-31',
        '2026-01-05',
        '2026-01-15',
        '2026-10-02',
      ]);
    });
  });

  group('weekday and week arithmetic', () {
    test('knows the reference weekdays', () {
      expect(LocalDate(2026, 8, 15).weekday, DateTime.saturday);
      expect(LocalDate(2026, 1, 1).weekday, DateTime.thursday);
      expect(LocalDate(2026, 10, 19).weekday, DateTime.monday);
      expect(LocalDate(2025, 12, 22).weekday, DateTime.monday);
    });

    test('mondayOfWeek snaps back to Monday', () {
      expect(LocalDate(2026, 8, 15).mondayOfWeek, LocalDate(2026, 8, 10));
      expect(LocalDate(2026, 8, 10).mondayOfWeek, LocalDate(2026, 8, 10));
      // Sunday belongs to the week that started the previous Monday.
      expect(LocalDate(2026, 8, 16).mondayOfWeek, LocalDate(2026, 8, 10));
    });

    test('mondayOfWeek crosses a year boundary', () {
      expect(LocalDate(2026, 1, 1).mondayOfWeek, LocalDate(2025, 12, 29));
    });
  });

  group('day arithmetic is DST-proof', () {
    test('spans the spring-forward transition', () {
      // Europe/Rome moves to CEST on 2026-03-29; a local DateTime would gain
      // only 23 hours here and could land on the wrong calendar day.
      final before = LocalDate(2026, 3, 28);
      expect(before.addDays(1), LocalDate(2026, 3, 29));
      expect(before.addDays(2), LocalDate(2026, 3, 30));
      expect(before.daysUntil(LocalDate(2026, 3, 30)), 2);
    });

    test('spans the autumn fall-back transition', () {
      final before = LocalDate(2026, 10, 24);
      expect(before.addDays(1), LocalDate(2026, 10, 25));
      expect(before.addDays(2), LocalDate(2026, 10, 26));
      expect(before.daysUntil(LocalDate(2026, 10, 26)), 2);
    });

    test('daysUntil is negative going backwards', () {
      expect(LocalDate(2026, 8, 15).daysUntil(LocalDate(2026, 8, 10)), -5);
    });

    test('crosses a leap-year February', () {
      expect(LocalDate(2028, 2, 28).addDays(1), LocalDate(2028, 2, 29));
      expect(LocalDate(2028, 2, 29).addDays(1), LocalDate(2028, 3, 1));
    });
  });

  group('comparison', () {
    test('orders dates', () {
      expect(LocalDate(2026, 1, 1) < LocalDate(2026, 1, 2), isTrue);
      expect(LocalDate(2026, 1, 2) >= LocalDate(2026, 1, 2), isTrue);
      expect(LocalDate(2026, 1, 2) > LocalDate(2026, 1, 2), isFalse);
    });

    test('equal dates share a hash code', () {
      expect(LocalDate(2026, 8, 15), LocalDate.parse('2026-08-15'));
      expect(
        LocalDate(2026, 8, 15).hashCode,
        LocalDate.parse('2026-08-15').hashCode,
      );
    });
  });

  group('floorMod', () {
    test('never returns a negative result', () {
      expect((-1).floorMod(2), 1);
      expect((-4).floorMod(2), 0);
      expect((-3).floorMod(4), 1);
      expect(5.floorMod(2), 1);
      expect(0.floorMod(3), 0);
    });
  });
}
