import 'package:flutter_test/flutter_test.dart';
import 'package:my_home/core/local_date.dart';
import 'package:my_home/core/waste_catalogue.dart';
import 'package:my_home/domain/entities/collection_event.dart';
import 'package:my_home/domain/statistics.dart';

CollectionEvent event(WasteType type, String date) => CollectionEvent(
  id: CollectionEvent.scheduledId(type, LocalDate.parse(date)),
  type: type,
  date: LocalDate.parse(date),
  isExtra: false,
  recordedByUid: 'davide',
  recordedByName: 'Davide',
  source: CollectionSource.app,
);

void main() {
  group('availableYears', () {
    test('covers five years ending with the current one', () {
      expect(availableYears(2026), [2026, 2025, 2024, 2023, 2022]);
      expect(availableYears(2026), hasLength(historyYears));
    });
  });

  group('monthlyBreakdown', () {
    test('always has twelve months, even with no data', () {
      final b = monthlyBreakdown(events: const [], year: 2026);
      expect(b.byMonth, hasLength(12));
      expect(b.total, 0);
      expect(b.isEmpty, isTrue);
    });

    test('places events in the right month', () {
      final b = monthlyBreakdown(
        events: [
          event(WasteType.carta, '2026-01-15'),
          event(WasteType.carta, '2026-01-29'),
          event(WasteType.plastica, '2026-03-04'),
          event(WasteType.vetro, '2026-12-31'),
        ],
        year: 2026,
      );

      expect(b.totalForMonth(0), 2);
      expect(b.totalForMonth(1), 0);
      expect(b.totalForMonth(2), 1);
      expect(b.totalForMonth(11), 1);
      expect(b.total, 4);
    });

    test('ignores events from other years', () {
      final b = monthlyBreakdown(
        events: [
          event(WasteType.carta, '2025-01-15'),
          event(WasteType.carta, '2026-01-15'),
          event(WasteType.carta, '2027-01-15'),
        ],
        year: 2026,
      );
      expect(b.total, 1);
    });

    test('splits a month by waste type', () {
      final b = monthlyBreakdown(
        events: [
          event(WasteType.carta, '2026-05-04'),
          event(WasteType.carta, '2026-05-18'),
          event(WasteType.umido, '2026-05-06'),
        ],
        year: 2026,
      );
      expect(b.byMonth[4], {WasteType.carta: 2, WasteType.umido: 1});
      expect(b.totalForType(WasteType.carta), 2);
      expect(b.totalForType(WasteType.vetro), 0);
    });

    test('peakMonthTotal finds the busiest month and never returns zero', () {
      final busy = monthlyBreakdown(
        events: [
          event(WasteType.carta, '2026-02-04'),
          event(WasteType.carta, '2026-02-11'),
          event(WasteType.carta, '2026-02-18'),
          event(WasteType.vetro, '2026-07-01'),
        ],
        year: 2026,
      );
      expect(busy.peakMonthTotal, 3);

      // Guards the division used to scale the bars.
      final empty = monthlyBreakdown(events: const [], year: 2026);
      expect(empty.peakMonthTotal, 1);
    });

    test('typesPresent reflects the year, in catalogue order', () {
      final b = monthlyBreakdown(
        events: [
          event(WasteType.vetro, '2026-05-04'),
          event(WasteType.carta, '2026-06-04'),
        ],
        year: 2026,
      );
      // Catalogue order puts carta before vetro regardless of when recorded.
      expect(b.typesPresent, [WasteType.carta, WasteType.vetro]);
    });

    test('typesPresent omits types with no collections that year', () {
      final b = monthlyBreakdown(
        events: [event(WasteType.carta, '2026-05-04')],
        year: 2026,
      );
      expect(b.typesPresent, [WasteType.carta]);
    });
  });

  group('peakYearTotal', () {
    test('returns the largest yearly total', () {
      final years = [
        const YearTotal(year: 2025, byType: {WasteType.carta: 8}, isLoaded: true),
        const YearTotal(
          year: 2026,
          byType: {WasteType.carta: 12, WasteType.vetro: 5},
          isLoaded: true,
        ),
      ];
      expect(peakYearTotal(years), 17);
    });

    test('never returns zero, so bar scaling cannot divide by it', () {
      expect(peakYearTotal(const []), 1);
      expect(
        peakYearTotal([
          const YearTotal(year: 2026, byType: {}, isLoaded: true),
        ]),
        1,
      );
    });

    test('a year still loading counts as zero rather than crashing', () {
      const loading = YearTotal(year: 2026, byType: {}, isLoaded: false);
      expect(loading.total, 0);
      expect(loading.isLoaded, isFalse);
    });
  });
}
