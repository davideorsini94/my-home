import '../core/waste_catalogue.dart';
import 'entities/collection_event.dart';
import 'entities/waste_config.dart';

/// The free-collection standing for one waste type in one year.
class QuotaStatus {
  const QuotaStatus({
    required this.type,
    required this.policy,
    required this.year,
    required this.used,
  });

  final WasteType type;
  final QuotaPolicy policy;
  final int year;

  /// Collections recorded for this type in this year, extras included — an
  /// extra bag still consumes an allowance.
  final int used;

  int? get quota =>
      policy.kind == QuotaKind.limited ? policy.yearlyQuota : null;

  /// Free collections still available. `null` means unlimited.
  int? get remaining => switch (policy.kind) {
    QuotaKind.unlimited => null,
    QuotaKind.paid => 0,
    QuotaKind.limited => (quota ?? 0) - used < 0 ? 0 : (quota ?? 0) - used,
  };

  /// Collections beyond the free allowance, i.e. the billed ones.
  int get billed => switch (policy.kind) {
    QuotaKind.unlimited => 0,
    QuotaKind.paid => used,
    QuotaKind.limited => used - (quota ?? 0) < 0 ? 0 : used - (quota ?? 0),
  };

  bool get isUnlimited => policy.kind == QuotaKind.unlimited;
  bool get isAlwaysPaid => policy.kind == QuotaKind.paid;
  bool get isExhausted => policy.kind == QuotaKind.limited && remaining == 0;
  bool get isLastFree => policy.kind == QuotaKind.limited && remaining == 1;

  /// Short badge text for the dashboard, e.g. "3/12 gratuiti".
  String get shortLabel => switch (policy.kind) {
    QuotaKind.unlimited => 'Illimitati',
    QuotaKind.paid => 'A pagamento',
    QuotaKind.limited => '${remaining ?? 0}/${quota ?? 0} gratuiti',
  };

  /// The sentence used inside the evening notification.
  String get notificationLine => switch (policy.kind) {
    QuotaKind.unlimited => 'Ritiri gratuiti illimitati.',
    QuotaKind.paid => 'Questo ritiro è a pagamento.',
    QuotaKind.limited when isExhausted =>
      'Ritiri gratuiti esauriti: questo ritiro è a pagamento.',
    QuotaKind.limited when isLastFree =>
      'Attenzione: è l\'ultimo ritiro gratuito dell\'anno.',
    QuotaKind.limited =>
      'Ritiri gratuiti rimanenti: ${remaining ?? 0} su ${quota ?? 0}.',
  };
}

/// Counts recorded collections per waste type, restricted to [year].
///
/// Counters are always derived from the ledger rather than stored as an
/// aggregate: an aggregate would need a compensating write on every edit or
/// delete, and any missed pairing would drift permanently with no source of
/// truth to repair it from. Deriving also works straight from the offline
/// cache, whereas Firestore transactions and `count()` aggregations do not.
Map<WasteType, int> countByType(Iterable<CollectionEvent> events, int year) {
  final counts = <WasteType, int>{};
  for (final event in events) {
    if (event.date.year != year) continue;
    // A skipped pickup is on record so the reminder stops asking, but nothing
    // was put out, so it consumes no allowance.
    if (!event.countsTowardsQuota) continue;
    counts.update(event.type, (v) => v + 1, ifAbsent: () => 1);
  }
  return counts;
}

/// The quota standing for one type, for the year the pickup falls in.
///
/// The year comes from the pickup date, not from "today": a notification fired
/// on 31 December for a 1 January pickup must report next year's fresh quota.
QuotaStatus quotaStatusFor({
  required WasteConfig config,
  required Iterable<CollectionEvent> events,
  required int year,
}) {
  var used = 0;
  for (final event in events) {
    if (event.type != config.type) continue;
    if (event.date.year != year) continue;
    if (!event.countsTowardsQuota) continue;
    used++;
  }
  return QuotaStatus(
    type: config.type,
    policy: config.policy,
    year: year,
    used: used,
  );
}

/// Quota standings for every enabled type of a house.
List<QuotaStatus> quotaStatusesFor({
  required Iterable<WasteConfig> configs,
  required Iterable<CollectionEvent> events,
  required int year,
}) {
  final counts = countByType(events, year);
  return [
    for (final config in configs)
      if (config.enabled)
        QuotaStatus(
          type: config.type,
          policy: config.policy,
          year: year,
          used: counts[config.type] ?? 0,
        ),
  ];
}
