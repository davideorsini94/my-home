/// A calendar date without a time or a timezone.
///
/// Backed by a UTC [DateTime] so that day arithmetic is never disturbed by DST
/// transitions: adding 1 day always adds exactly 24 hours in UTC, whereas the
/// same operation on a local `DateTime` silently shifts by an hour twice a year.
class LocalDate implements Comparable<LocalDate> {
  LocalDate(int year, int month, int day)
    : _utc = DateTime.utc(year, month, day);

  LocalDate._fromUtc(this._utc);

  /// Today in the device's local timezone.
  factory LocalDate.today({DateTime? now}) {
    final n = now ?? DateTime.now();
    return LocalDate(n.year, n.month, n.day);
  }

  /// Parses a `YYYY-MM-DD` key. Throws [FormatException] on anything else.
  factory LocalDate.parse(String key) {
    if (key.length != 10 || key[4] != '-' || key[7] != '-') {
      throw FormatException('Invalid date key', key);
    }
    final year = int.parse(key.substring(0, 4));
    final month = int.parse(key.substring(5, 7));
    final day = int.parse(key.substring(8, 10));
    if (month < 1 || month > 12 || day < 1 || day > 31) {
      throw FormatException('Invalid date key', key);
    }
    final date = LocalDate(year, month, day);
    // Rejects overflow such as 2026-02-30, which DateTime.utc would roll over.
    if (date.month != month || date.day != day) {
      throw FormatException('Invalid date key', key);
    }
    return date;
  }

  static LocalDate? tryParse(String? key) {
    if (key == null) return null;
    try {
      return LocalDate.parse(key);
    } on FormatException {
      return null;
    }
  }

  final DateTime _utc;

  int get year => _utc.year;
  int get month => _utc.month;
  int get day => _utc.day;

  /// ISO weekday: [DateTime.monday] (1) through [DateTime.sunday] (7).
  int get weekday => _utc.weekday;

  /// `YYYY-MM-DD`, which sorts lexicographically in chronological order — the
  /// property that lets Firestore range queries work on plain strings.
  String toKey() {
    final m = month.toString().padLeft(2, '0');
    final d = day.toString().padLeft(2, '0');
    return '$year-$m-$d';
  }

  LocalDate addDays(int days) =>
      LocalDate._fromUtc(_utc.add(Duration(days: days)));

  /// Whole days from this date to [other]; negative when [other] is earlier.
  int daysUntil(LocalDate other) => other._utc.difference(_utc).inDays;

  /// The Monday of the ISO week containing this date.
  LocalDate get mondayOfWeek => addDays(-(weekday - DateTime.monday));

  /// Converts to a local-time [DateTime] at midnight, for date pickers only.
  DateTime toLocalDateTime() => DateTime(year, month, day);

  static LocalDate fromDateTime(DateTime dt) =>
      LocalDate(dt.year, dt.month, dt.day);

  bool operator <(LocalDate other) => compareTo(other) < 0;
  bool operator <=(LocalDate other) => compareTo(other) <= 0;
  bool operator >(LocalDate other) => compareTo(other) > 0;
  bool operator >=(LocalDate other) => compareTo(other) >= 0;

  @override
  int compareTo(LocalDate other) => _utc.compareTo(other._utc);

  @override
  bool operator ==(Object other) =>
      other is LocalDate && other._utc.isAtSameMomentAs(_utc);

  @override
  int get hashCode => _utc.hashCode;

  @override
  String toString() => toKey();
}

extension IntFloorMod on int {
  /// Modulo with a non-negative result, unlike Dart's `%` on negative operands
  /// combined with `~/` truncation toward zero.
  int floorMod(int modulus) => ((this % modulus) + modulus) % modulus;
}
