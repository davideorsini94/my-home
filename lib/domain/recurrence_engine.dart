import '../core/local_date.dart';
import 'entities/maintenance.dart';

/// The last day of [month] in [year].
///
/// Day 0 of the following month is the last day of this one — Dart normalises
/// the overflow, the same trick `LocalDate.parse` already relies on to reject
/// dates like 2026-02-30.
int daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

/// The date [times] recurrence periods after [from].
///
/// Always computed as a single jump from the anchor, never chained: chaining
/// would let a clamped month bleed into every later period, so "il 31 di ogni
/// mese" would silently become "il 28" forever after one February.
LocalDate advance(LocalDate from, Recurrence recurrence, {int times = 1}) {
  final n = recurrence.every * times;
  return switch (recurrence.unit) {
    RecurrenceUnit.days => from.addDays(n),
    RecurrenceUnit.weeks => from.addDays(7 * n),
    RecurrenceUnit.months => _addMonths(from, n),
    RecurrenceUnit.years => _addMonths(from, 12 * n),
  };
}

/// Adds whole months, keeping the day of the month where the target month has
/// one and falling back to its last day where it does not: 31 August + 6 months
/// is 28 February, but + 12 months is 31 August again.
LocalDate _addMonths(LocalDate from, int months) {
  final zeroBased = from.month - 1 + months;
  final year = from.year + zeroBased ~/ 12;
  final month = zeroBased % 12 + 1;
  final last = daysInMonth(year, month);
  return LocalDate(year, month, from.day < last ? from.day : last);
}
