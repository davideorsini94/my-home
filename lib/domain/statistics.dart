import '../core/waste_catalogue.dart';
import 'entities/collection_event.dart';

/// How many years of history the app looks back over.
///
/// Nothing is ever deleted from Firestore, so this only bounds what the year
/// pickers and the statistics offer — it is not a retention policy.
const int historyYears = 5;

/// The years available for browsing, newest first.
List<int> availableYears(int currentYear) => [
  for (var i = 0; i < historyYears; i++) currentYear - i,
];

/// Collections per month for one year, index 0 = January .. 11 = December.
class MonthlyBreakdown {
  const MonthlyBreakdown({required this.year, required this.byMonth});

  final int year;

  /// Twelve entries, each mapping waste type to its count for that month.
  final List<Map<WasteType, int>> byMonth;

  int totalForMonth(int monthIndex) =>
      byMonth[monthIndex].values.fold(0, (sum, n) => sum + n);

  int totalForType(WasteType type) =>
      byMonth.fold(0, (sum, m) => sum + (m[type] ?? 0));

  int get total => byMonth.fold(0, (sum, m) {
    return sum + m.values.fold(0, (s, n) => s + n);
  });

  /// The busiest month's total, used to scale the bars. Never zero, so callers
  /// can divide by it safely.
  int get peakMonthTotal {
    var peak = 0;
    for (var i = 0; i < 12; i++) {
      final t = totalForMonth(i);
      if (t > peak) peak = t;
    }
    return peak == 0 ? 1 : peak;
  }

  /// Types that actually appear this year, in catalogue order — so a year is
  /// summarised by what really happened, not by today's configuration.
  List<WasteType> get typesPresent => [
    for (final type in WasteType.values)
      if (totalForType(type) > 0) type,
  ];

  bool get isEmpty => total == 0;
}

/// Groups a year's ledger into months.
MonthlyBreakdown monthlyBreakdown({
  required Iterable<CollectionEvent> events,
  required int year,
}) {
  final byMonth = List.generate(12, (_) => <WasteType, int>{});
  for (final event in events) {
    if (event.date.year != year) continue;
    final month = byMonth[event.date.month - 1];
    month.update(event.type, (v) => v + 1, ifAbsent: () => 1);
  }
  return MonthlyBreakdown(year: year, byMonth: byMonth);
}

/// One year's totals, for the year-over-year comparison.
class YearTotal {
  const YearTotal({
    required this.year,
    required this.byType,
    required this.isLoaded,
  });

  final int year;
  final Map<WasteType, int> byType;

  /// False while that year's ledger is still being fetched, so the UI can tell
  /// "no data yet" apart from "genuinely zero".
  final bool isLoaded;

  int get total => byType.values.fold(0, (sum, n) => sum + n);
}

/// The tallest bar across a set of years, for scaling. Never zero.
int peakYearTotal(Iterable<YearTotal> years) {
  var peak = 0;
  for (final y in years) {
    if (y.total > peak) peak = y.total;
  }
  return peak == 0 ? 1 : peak;
}
