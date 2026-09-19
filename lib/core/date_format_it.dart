import 'local_date.dart';

const _weekdayShort = ['lun', 'mar', 'mer', 'gio', 'ven', 'sab', 'dom'];

const _weekdayLong = [
  'lunedì',
  'martedì',
  'mercoledì',
  'giovedì',
  'venerdì',
  'sabato',
  'domenica',
];

const _monthShort = [
  'gen',
  'feb',
  'mar',
  'apr',
  'mag',
  'giu',
  'lug',
  'ago',
  'set',
  'ott',
  'nov',
  'dic',
];

const _monthLong = [
  'gennaio',
  'febbraio',
  'marzo',
  'aprile',
  'maggio',
  'giugno',
  'luglio',
  'agosto',
  'settembre',
  'ottobre',
  'novembre',
  'dicembre',
];

/// Italian date formatting, written out rather than pulled from `intl` so the
/// app carries no locale-data initialisation and the strings stay predictable
/// in tests.
String weekdayShort(int weekday) => _weekdayShort[weekday - 1];
String weekdayLong(int weekday) => _weekdayLong[weekday - 1];
String monthLong(int month) => _monthLong[month - 1];

/// "mer 19 ago"
String formatShort(LocalDate date) =>
    '${weekdayShort(date.weekday)} ${date.day} ${_monthShort[date.month - 1]}';

/// "mer 19 ago" within [reference]'s year, "mer 19 ago 2028" outside it.
///
/// A waste pickup is always a few days away, so its year would be noise; a
/// maintenance due "ogni 2 anni" is not, and a bare "ven 15 set" for a date in
/// 2028 reads as this September.
String formatShortInContext(LocalDate date, LocalDate reference) =>
    date.year == reference.year
    ? formatShort(date)
    : '${formatShort(date)} ${date.year}';

/// "mercoledì 19 agosto 2026"
String formatLong(LocalDate date) =>
    '${weekdayLong(date.weekday)} ${date.day} ${monthLong(date.month)} ${date.year}';

/// "19/08/2026"
String formatNumeric(LocalDate date) {
  final d = date.day.toString().padLeft(2, '0');
  final m = date.month.toString().padLeft(2, '0');
  return '$d/$m/${date.year}';
}

/// "agosto 2026", for grouping the history by month.
String formatMonthYear(LocalDate date) =>
    '${monthLong(date.month)} ${date.year}';

/// A relative label when the date is close enough for it to be clearer than the
/// calendar date.
String formatRelative(LocalDate date, LocalDate today) {
  final days = today.daysUntil(date);
  return switch (days) {
    0 => 'oggi',
    1 => 'domani',
    -1 => 'ieri',
    > 1 && < 7 => weekdayLong(date.weekday),
    _ => formatShortInContext(date, today),
  };
}

/// "Lun e Gio, ogni settimana" — the summary of a recurrence rule.
String formatSchedule(Set<int> weekdays, int intervalWeeks) {
  if (weekdays.isEmpty) return 'Nessun giorno impostato';
  final days = (weekdays.toList()..sort()).map((d) {
    final label = weekdayShort(d);
    return label[0].toUpperCase() + label.substring(1);
  }).toList();
  final dayPart = days.length == 1
      ? days.first
      : '${days.sublist(0, days.length - 1).join(', ')} e ${days.last}';
  final frequency = switch (intervalWeeks) {
    1 => 'ogni settimana',
    2 => 'ogni 2 settimane',
    _ => 'ogni $intervalWeeks settimane',
  };
  return '$dayPart, $frequency';
}
