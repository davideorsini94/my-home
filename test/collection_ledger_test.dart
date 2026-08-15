import 'package:flutter_test/flutter_test.dart';
import 'package:rubbish_manager/core/local_date.dart';
import 'package:rubbish_manager/core/waste_catalogue.dart';
import 'package:rubbish_manager/domain/collection_ledger.dart';
import 'package:rubbish_manager/domain/entities/collection_event.dart';
import 'package:rubbish_manager/domain/entities/waste_config.dart';
import 'package:rubbish_manager/domain/quota_calculator.dart';

/// A stand-in for the Firestore subcollection: documents keyed by id, where
/// writing an existing id overwrites rather than appends.
///
/// That single property is exactly what the app relies on for multi-user
/// counting, so modelling it here tests the design invariant directly.
/// (`fake_cloud_firestore` cannot be used: its `MockWriteBatch.update`
/// signature is incompatible with `cloud_firestore` 6.x.)
class FakeLedger {
  final Map<String, CollectionEvent> _docs = {};

  List<CollectionEvent> get events => _docs.values.toList()
    ..sort((a, b) => b.date.compareTo(a.date));

  String recordScheduled(
    WasteType type,
    String date, {
    String by = 'davide',
    CollectionSource source = CollectionSource.app,
  }) => _set(
    type: type,
    date: LocalDate.parse(date),
    isExtra: false,
    uniqueSuffix: '',
    by: by,
    source: source,
  );

  String recordExtra(
    WasteType type,
    String date, {
    required String unique,
    String by = 'davide',
  }) => _set(
    type: type,
    date: LocalDate.parse(date),
    isExtra: true,
    uniqueSuffix: unique,
    by: by,
    source: CollectionSource.app,
  );

  String _set({
    required WasteType type,
    required LocalDate date,
    required bool isExtra,
    required String uniqueSuffix,
    required String by,
    required CollectionSource source,
  }) {
    final id = idForEvent(
      type: type,
      date: date,
      isExtra: isExtra,
      uniqueSuffix: uniqueSuffix,
    );
    _docs[id] = CollectionEvent(
      id: id,
      type: type,
      date: date,
      isExtra: isExtra,
      recordedByUid: by,
      recordedByName: by,
      source: source,
    );
    return id;
  }

  void delete(String id) => _docs.remove(id);

  /// Mirrors `CollectionRepository.updateEvent`: moving an event deletes the
  /// old document and writes the new one.
  String move(CollectionEvent original, WasteType type, String date) {
    final newId = idForEvent(
      type: type,
      date: LocalDate.parse(date),
      isExtra: original.isExtra,
      uniqueSuffix: extraSuffixOf(original.id),
    );
    _docs.remove(original.id);
    _docs[newId] = original.copyWith(
      id: newId,
      type: type,
      date: LocalDate.parse(date),
    );
    return newId;
  }

  CollectionEvent byDate(String date) =>
      events.firstWhere((e) => e.date.toKey() == date);
}

void main() {
  late FakeLedger ledger;

  setUp(() => ledger = FakeLedger());

  int countOf(WasteType type, [int year = 2026]) =>
      countByType(ledger.events, year)[type] ?? 0;

  group('deterministic ids', () {
    test('a scheduled pickup always maps to the same id', () {
      expect(
        ledger.recordScheduled(WasteType.carta, '2026-08-19'),
        'carta_2026-08-19',
      );
      expect(
        idForEvent(
          type: WasteType.carta,
          date: LocalDate.parse('2026-08-19'),
          isExtra: false,
          uniqueSuffix: 'ignored',
        ),
        'carta_2026-08-19',
      );
    });

    test('an extra id carries its unique suffix', () {
      final id = idForEvent(
        type: WasteType.umido,
        date: LocalDate.parse('2026-08-19'),
        isExtra: true,
        uniqueSuffix: 'abc',
      );
      expect(id, 'umido_2026-08-19_x_abc');
      expect(extraSuffixOf(id), 'abc');
    });

    test('extraSuffixOf tolerates an id with no marker', () {
      expect(extraSuffixOf('carta_2026-08-19'), 'carta_2026-08-19');
    });
  });

  group('two members recording the same pickup', () {
    test('counts as one collection', () {
      // The scenario the id scheme exists for: Davide taps the button in the
      // app, his father confirms the notification. The free-collection count
      // must move by exactly one.
      ledger.recordScheduled(WasteType.carta, '2026-08-19', by: 'davide');
      ledger.recordScheduled(
        WasteType.carta,
        '2026-08-19',
        by: 'papa',
        source: CollectionSource.notification,
      );

      expect(ledger.events, hasLength(1));
      expect(countOf(WasteType.carta), 1);
    });

    test('is order-independent, so an offline replay is harmless', () {
      ledger.recordScheduled(WasteType.carta, '2026-08-19', by: 'papa');
      ledger.recordScheduled(WasteType.carta, '2026-08-19', by: 'davide');
      ledger.recordScheduled(WasteType.carta, '2026-08-19', by: 'papa');
      expect(countOf(WasteType.carta), 1);
    });

    test('different days and types stay separate', () {
      ledger.recordScheduled(WasteType.carta, '2026-08-19');
      ledger.recordScheduled(WasteType.carta, '2026-08-26');
      ledger.recordScheduled(WasteType.plastica, '2026-08-19');
      expect(countOf(WasteType.carta), 2);
      expect(countOf(WasteType.plastica), 1);
    });
  });

  group('extras', () {
    test('two extras on the same day are two collections', () {
      ledger.recordExtra(WasteType.umido, '2026-08-19', unique: 'a');
      ledger.recordExtra(WasteType.umido, '2026-08-19', unique: 'b');
      expect(countOf(WasteType.umido), 2);
    });

    test('an extra never collides with the scheduled pickup', () {
      ledger.recordScheduled(WasteType.umido, '2026-08-19');
      ledger.recordExtra(WasteType.umido, '2026-08-19', unique: 'a');
      expect(ledger.events, hasLength(2));
      expect(countOf(WasteType.umido), 2);
    });
  });

  group('correcting the history', () {
    test('deleting gives the free collection back', () {
      ledger.recordScheduled(WasteType.carta, '2026-08-19');
      expect(countOf(WasteType.carta), 1);
      ledger.delete('carta_2026-08-19');
      expect(countOf(WasteType.carta), 0);
    });

    test('changing the date moves the document, leaving no duplicate', () {
      ledger.recordScheduled(WasteType.carta, '2026-08-19');
      ledger.move(ledger.byDate('2026-08-19'), WasteType.carta, '2026-08-20');

      expect(ledger.events, hasLength(1));
      expect(ledger.events.single.date.toKey(), '2026-08-20');
      expect(ledger.events.single.id, 'carta_2026-08-20');
    });

    test('changing the type fixes both counters at once', () {
      ledger.recordScheduled(WasteType.carta, '2026-08-19');
      ledger.move(
        ledger.byDate('2026-08-19'),
        WasteType.plastica,
        '2026-08-19',
      );
      expect(countOf(WasteType.carta), 0);
      expect(countOf(WasteType.plastica), 1);
    });

    test('moving onto an occupied day merges the two records', () {
      ledger.recordScheduled(WasteType.carta, '2026-08-19');
      ledger.recordScheduled(WasteType.carta, '2026-08-26');
      expect(countOf(WasteType.carta), 2);

      ledger.move(ledger.byDate('2026-08-26'), WasteType.carta, '2026-08-19');
      // One scheduled pickup of one type on one day is one collection, so the
      // count dropping to 1 is correct rather than lossy.
      expect(countOf(WasteType.carta), 1);
    });

    test('an edited extra keeps its own identity', () {
      ledger.recordExtra(WasteType.umido, '2026-08-19', unique: 'abc');
      ledger.recordScheduled(WasteType.umido, '2026-08-20');

      final extra = ledger.events.firstWhere((e) => e.isExtra);
      final newId = ledger.move(extra, WasteType.umido, '2026-08-20');

      expect(newId, 'umido_2026-08-20_x_abc');
      expect(countOf(WasteType.umido), 2);
    });

    test('a correction moved out of the year leaves that year\'s count', () {
      ledger.recordScheduled(WasteType.vetro, '2026-01-02');
      expect(countOf(WasteType.vetro, 2026), 1);
      ledger.move(ledger.byDate('2026-01-02'), WasteType.vetro, '2025-12-31');
      expect(countOf(WasteType.vetro, 2026), 0);
      expect(countOf(WasteType.vetro, 2025), 1);
    });
  });

  group('wouldMergeOnMove', () {
    test('is true only when a scheduled record already occupies the target', () {
      ledger.recordScheduled(WasteType.carta, '2026-08-19');
      ledger.recordScheduled(WasteType.carta, '2026-08-26');
      final toMove = ledger.byDate('2026-08-26');

      expect(
        wouldMergeOnMove(
          original: toMove,
          type: WasteType.carta,
          date: LocalDate.parse('2026-08-19'),
          existing: ledger.events,
        ),
        isTrue,
      );
      expect(
        wouldMergeOnMove(
          original: toMove,
          type: WasteType.carta,
          date: LocalDate.parse('2026-09-02'),
          existing: ledger.events,
        ),
        isFalse,
      );
      expect(
        wouldMergeOnMove(
          original: toMove,
          type: WasteType.plastica,
          date: LocalDate.parse('2026-08-19'),
          existing: ledger.events,
        ),
        isFalse,
      );
    });

    test('is false when the record is not moving at all', () {
      ledger.recordScheduled(WasteType.carta, '2026-08-19');
      final event = ledger.byDate('2026-08-19');
      expect(
        wouldMergeOnMove(
          original: event,
          type: WasteType.carta,
          date: LocalDate.parse('2026-08-19'),
          existing: ledger.events,
        ),
        isFalse,
      );
    });

    test('is false for extras, which never merge', () {
      ledger.recordExtra(WasteType.umido, '2026-08-19', unique: 'abc');
      ledger.recordScheduled(WasteType.umido, '2026-08-20');
      expect(
        wouldMergeOnMove(
          original: ledger.events.firstWhere((e) => e.isExtra),
          type: WasteType.umido,
          date: LocalDate.parse('2026-08-20'),
          existing: ledger.events,
        ),
        isFalse,
      );
    });
  });

  group('the quota follows the ledger', () {
    QuotaStatus status(int quota) => quotaStatusFor(
      config: WasteConfig(
        type: WasteType.carta,
        enabled: true,
        policy: QuotaPolicy.limited(quota),
        rules: const [],
      ),
      events: ledger.events,
      year: 2026,
    );

    test('every correction is reflected without any counter to repair', () {
      ledger.recordScheduled(WasteType.carta, '2026-01-07');
      ledger.recordScheduled(WasteType.carta, '2026-02-04');
      expect(status(3).remaining, 1);

      // A mistaken record is deleted; the allowance comes back on its own.
      ledger.delete('carta_2026-02-04');
      expect(status(3).remaining, 2);

      // Both members confirm the same pickup: still only one is consumed.
      ledger.recordScheduled(WasteType.carta, '2026-03-04', by: 'davide');
      ledger.recordScheduled(WasteType.carta, '2026-03-04', by: 'papa');
      expect(status(3).remaining, 1);

      // Past the allowance, the surplus is billed rather than going negative.
      ledger.recordScheduled(WasteType.carta, '2026-04-01');
      ledger.recordScheduled(WasteType.carta, '2026-05-06');
      expect(status(3).remaining, 0);
      expect(status(3).billed, 1);
    });
  });
}
