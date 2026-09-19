import 'package:flutter_test/flutter_test.dart';
import 'package:my_home/core/date_format_it.dart';
import 'package:my_home/core/local_date.dart';

void main() {
  group('formatShortInContext', () {
    final today = LocalDate(2026, 9, 19);

    test('drops the year inside the reference year', () {
      expect(formatShortInContext(LocalDate(2026, 9, 15), today), 'mar 15 set');
    });

    test('keeps the year outside it, in both directions', () {
      // A maintenance "ogni 2 anni" falls here: without the year, "ven 15 set"
      // reads as a date four days ago.
      expect(
        formatShortInContext(LocalDate(2028, 9, 15), today),
        'ven 15 set 2028',
      );
      expect(
        formatShortInContext(LocalDate(2024, 9, 15), today),
        'dom 15 set 2024',
      );
    });

    test('shows the year across a new year, however few days away', () {
      final newYearsEve = LocalDate(2026, 12, 31);
      expect(
        formatShortInContext(LocalDate(2027, 1, 7), newYearsEve),
        'gio 7 gen 2027',
      );
    });
  });

  group('formatRelative', () {
    final today = LocalDate(2026, 9, 19);

    test('prefers the relative wording when it is clearer', () {
      expect(formatRelative(today, today), 'oggi');
      expect(formatRelative(LocalDate(2026, 9, 20), today), 'domani');
      expect(formatRelative(LocalDate(2026, 9, 18), today), 'ieri');
      expect(formatRelative(LocalDate(2026, 9, 23), today), 'mercoledì');
    });

    test('falls back to a date that carries its year when it needs one', () {
      expect(formatRelative(LocalDate(2026, 10, 5), today), 'lun 5 ott');
      expect(formatRelative(LocalDate(2027, 9, 15), today), 'mer 15 set 2027');
    });
  });
}
