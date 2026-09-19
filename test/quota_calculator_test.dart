import 'package:flutter_test/flutter_test.dart';
import 'package:my_home/core/local_date.dart';
import 'package:my_home/core/waste_catalogue.dart';
import 'package:my_home/domain/entities/collection_event.dart';
import 'package:my_home/domain/entities/waste_config.dart';
import 'package:my_home/domain/quota_calculator.dart';

CollectionEvent event(
  WasteType type,
  String date, {
  bool isExtra = false,
  String by = 'davide',
}) => CollectionEvent(
  id: isExtra
      ? CollectionEvent.extraId(type, LocalDate.parse(date), 'u1')
      : CollectionEvent.scheduledId(type, LocalDate.parse(date)),
  type: type,
  date: LocalDate.parse(date),
  isExtra: isExtra,
  recordedByUid: by,
  recordedByName: by,
  source: CollectionSource.app,
);

WasteConfig config(WasteType type, QuotaPolicy policy, {bool enabled = true}) =>
    WasteConfig(
      type: type,
      enabled: enabled,
      policy: policy,
      rules: const [],
    );

void main() {
  group('countByType', () {
    test('groups by type within the requested year', () {
      final events = [
        event(WasteType.carta, '2026-01-10'),
        event(WasteType.carta, '2026-06-10'),
        event(WasteType.plastica, '2026-06-11'),
        event(WasteType.carta, '2025-12-31'),
      ];
      expect(countByType(events, 2026), {
        WasteType.carta: 2,
        WasteType.plastica: 1,
      });
    });

    test('excludes other years entirely', () {
      final events = [
        event(WasteType.vetro, '2025-01-10'),
        event(WasteType.vetro, '2027-01-10'),
      ];
      expect(countByType(events, 2026), isEmpty);
    });

    test('counts extras alongside scheduled collections', () {
      final events = [
        event(WasteType.umido, '2026-03-02'),
        event(WasteType.umido, '2026-03-02', isExtra: true),
      ];
      expect(countByType(events, 2026), {WasteType.umido: 2});
    });

    test('is empty for no events', () {
      expect(countByType(const [], 2026), isEmpty);
    });
  });

  group('QuotaStatus — limited policy', () {
    QuotaStatus status(int used, int quota) => QuotaStatus(
      type: WasteType.carta,
      policy: QuotaPolicy.limited(quota),
      year: 2026,
      used: used,
    );

    test('counts down the free allowance', () {
      expect(status(0, 12).remaining, 12);
      expect(status(5, 12).remaining, 7);
      expect(status(12, 12).remaining, 0);
    });

    test('never reports a negative remainder', () {
      expect(status(15, 12).remaining, 0);
    });

    test('bills everything past the allowance', () {
      expect(status(5, 12).billed, 0);
      expect(status(12, 12).billed, 0);
      expect(status(15, 12).billed, 3);
    });

    test('flags the exhausted and last-free states', () {
      expect(status(11, 12).isLastFree, isTrue);
      expect(status(11, 12).isExhausted, isFalse);
      expect(status(12, 12).isExhausted, isTrue);
      expect(status(13, 12).isExhausted, isTrue);
    });

    test('formats the badge and the notification line', () {
      expect(status(9, 12).shortLabel, '3/12 gratuiti');
      expect(
        status(9, 12).notificationLine,
        'Ritiri gratuiti rimanenti: 3 su 12.',
      );
      expect(
        status(11, 12).notificationLine,
        'Attenzione: è l\'ultimo ritiro gratuito dell\'anno.',
      );
      expect(
        status(12, 12).notificationLine,
        'Ritiri gratuiti esauriti: questo ritiro è a pagamento.',
      );
    });

    test('a zero quota behaves as immediately exhausted', () {
      expect(status(0, 0).remaining, 0);
      expect(status(0, 0).isExhausted, isTrue);
      expect(status(2, 0).billed, 2);
    });
  });

  group('QuotaStatus — unlimited policy', () {
    final s = QuotaStatus(
      type: WasteType.vetro,
      policy: const QuotaPolicy.unlimited(),
      year: 2026,
      used: 40,
    );

    test('has no remainder and never bills', () {
      expect(s.remaining, isNull);
      expect(s.billed, 0);
      expect(s.isUnlimited, isTrue);
      expect(s.isExhausted, isFalse);
    });

    test('labels itself as unlimited', () {
      expect(s.shortLabel, 'Illimitati');
      expect(s.notificationLine, 'Ritiri gratuiti illimitati.');
    });
  });

  group('QuotaStatus — always-paid policy', () {
    final s = QuotaStatus(
      type: WasteType.indifferenziato,
      policy: const QuotaPolicy.paid(),
      year: 2026,
      used: 3,
    );

    test('has no free collections and bills every one', () {
      expect(s.remaining, 0);
      expect(s.billed, 3);
      expect(s.isAlwaysPaid, isTrue);
      // "Exhausted" is reserved for a limited quota that ran out, so that the
      // UI can word the two situations differently.
      expect(s.isExhausted, isFalse);
    });

    test('labels itself as paid', () {
      expect(s.shortLabel, 'A pagamento');
      expect(s.notificationLine, 'Questo ritiro è a pagamento.');
    });
  });

  group('quotaStatusFor', () {
    final events = [
      event(WasteType.carta, '2026-01-10'),
      event(WasteType.carta, '2026-02-10'),
      event(WasteType.carta, '2025-11-10'),
      event(WasteType.plastica, '2026-02-11'),
    ];

    test('ignores other types and other years', () {
      final s = quotaStatusFor(
        config: config(WasteType.carta, const QuotaPolicy.limited(12)),
        events: events,
        year: 2026,
      );
      expect(s.used, 2);
      expect(s.remaining, 10);
    });

    test('uses the year of the pickup, not the year of today', () {
      // A notification fired on 31 Dec 2025 for a 1 Jan 2026 pickup must report
      // the fresh 2026 allowance, not what is left of 2025.
      final s2025 = quotaStatusFor(
        config: config(WasteType.carta, const QuotaPolicy.limited(12)),
        events: events,
        year: 2025,
      );
      final s2026 = quotaStatusFor(
        config: config(WasteType.carta, const QuotaPolicy.limited(12)),
        events: events,
        year: 2026,
      );
      expect(s2025.used, 1);
      expect(s2026.used, 2);
    });

    test('a year with no events starts at the full allowance', () {
      final s = quotaStatusFor(
        config: config(WasteType.carta, const QuotaPolicy.limited(12)),
        events: events,
        year: 2027,
      );
      expect(s.used, 0);
      expect(s.remaining, 12);
    });
  });

  group('quotaStatusesFor', () {
    test('covers enabled types only, including those with no events', () {
      final statuses = quotaStatusesFor(
        configs: [
          config(WasteType.carta, const QuotaPolicy.limited(12)),
          config(WasteType.vetro, const QuotaPolicy.unlimited()),
          config(
            WasteType.umido,
            const QuotaPolicy.limited(6),
            enabled: false,
          ),
        ],
        events: [event(WasteType.carta, '2026-01-10')],
        year: 2026,
      );

      expect(statuses.map((s) => s.type), [WasteType.carta, WasteType.vetro]);
      expect(statuses.first.used, 1);
      expect(statuses.last.used, 0);
    });

    test('is empty when nothing is monitored', () {
      expect(
        quotaStatusesFor(configs: const [], events: const [], year: 2026),
        isEmpty,
      );
    });
  });

  group('deterministic event ids', () {
    test('a scheduled pickup always maps to the same id', () {
      // This is what makes two family members confirming the same pickup
      // collapse into one document instead of double-counting.
      final a = CollectionEvent.scheduledId(
        WasteType.carta,
        LocalDate.parse('2026-08-19'),
      );
      final b = CollectionEvent.scheduledId(
        WasteType.carta,
        LocalDate(2026, 8, 19),
      );
      expect(a, b);
      expect(a, 'carta_2026-08-19');
    });

    test('extras on the same day stay distinct', () {
      final a = CollectionEvent.extraId(
        WasteType.carta,
        LocalDate.parse('2026-08-19'),
        'aaa',
      );
      final b = CollectionEvent.extraId(
        WasteType.carta,
        LocalDate.parse('2026-08-19'),
        'bbb',
      );
      expect(a, isNot(b));
    });
  });
}
