import '../core/local_date.dart';
import 'entities/waste_config.dart';

/// Generates the dates on which a [ScheduleRule] fires, starting at [from].
///
/// A date D matches when both hold:
///   1. `D.weekday` is one of the rule's weekdays, and
///   2. the ISO week containing D is an "on" week, i.e.
///      `weekIndex(D) % intervalWeeks == 0` where `weekIndex` counts whole weeks
///      between the Monday of the anchor's week and the Monday of D's week.
///
/// The interval therefore applies per *week block*, not per weekday: with
/// `{Mon, Thu}` every 2 weeks, both days fire in an "on" week and neither fires
/// in the "off" week. This is how Italian municipal calendars express
/// "settimana A / settimana B", and it makes "mercoledì ogni 15 giorni" simply
/// `{Wed}` with `intervalWeeks: 2`.
///
/// The anchor only pins which week is week zero — its own weekday need not be
/// in [ScheduleRule.weekdays]. Week indices before the anchor are negative and
/// are handled with a floored modulo, so occurrences that precede the anchor
/// are still generated; editing the anchor never hides past pickups.
///
/// The returned iterable is infinite — always bound it with `take`.
Iterable<LocalDate> occurrences({
  required ScheduleRule rule,
  required LocalDate from,
}) sync* {
  if (rule.weekdays.isEmpty || rule.intervalWeeks < 1) return;

  final anchorMonday = rule.anchorDate.mondayOfWeek;
  final sortedWeekdays = rule.weekdays.toList()..sort();
  var monday = from.mondayOfWeek;

  while (true) {
    // Always an exact multiple of 7, so truncating division is safe here; the
    // modulo below is the part that must be floored for negative indices.
    final weekIndex = anchorMonday.daysUntil(monday) ~/ 7;
    if (weekIndex.floorMod(rule.intervalWeeks) == 0) {
      for (final weekday in sortedWeekdays) {
        final date = monday.addDays(weekday - DateTime.monday);
        if (date >= from) yield date;
      }
    }
    monday = monday.addDays(7);
  }
}

/// The next [count] pickup dates for a configuration, merging all its rules.
List<LocalDate> nextPickups(
  WasteConfig config,
  LocalDate from, {
  int count = 10,
}) {
  if (!config.enabled || config.rules.isEmpty) return const [];
  final merged = <LocalDate>{};
  for (final rule in config.rules) {
    merged.addAll(occurrences(rule: rule, from: from).take(count));
  }
  final sorted = merged.toList()..sort();
  return sorted.length > count ? sorted.sublist(0, count) : sorted;
}

/// Every pickup date for a configuration within `[from, until]`, inclusive.
///
/// Bounded by date rather than by count, which is what the notification
/// scheduler needs for its rolling window.
List<LocalDate> pickupsInRange(
  WasteConfig config,
  LocalDate from,
  LocalDate until,
) {
  if (!config.enabled || config.rules.isEmpty || until < from) return const [];
  final merged = <LocalDate>{};
  for (final rule in config.rules) {
    for (final date in occurrences(rule: rule, from: from)) {
      if (date > until) break;
      merged.add(date);
    }
  }
  return merged.toList()..sort();
}

/// Whether a pickup is scheduled exactly on [date].
bool isPickupDay(WasteConfig config, LocalDate date) =>
    pickupsInRange(config, date, date).isNotEmpty;
