import '../../core/local_date.dart';
import '../../core/waste_catalogue.dart';

/// How many collections of a given type are free in a year.
enum QuotaKind {
  /// A fixed number of free collections per calendar year.
  limited,

  /// No limit — every collection is free.
  unlimited,

  /// No free collections — every one is billed.
  paid;

  static QuotaKind fromId(String? id) => switch (id) {
    'unlimited' => QuotaKind.unlimited,
    'paid' => QuotaKind.paid,
    _ => QuotaKind.limited,
  };
}

class QuotaPolicy {
  const QuotaPolicy({required this.kind, this.yearlyQuota});

  const QuotaPolicy.limited(int quota)
    : kind = QuotaKind.limited,
      yearlyQuota = quota;

  const QuotaPolicy.unlimited() : kind = QuotaKind.unlimited, yearlyQuota = null;

  const QuotaPolicy.paid() : kind = QuotaKind.paid, yearlyQuota = null;

  final QuotaKind kind;

  /// Only meaningful — and only ever non-null — when [kind] is
  /// [QuotaKind.limited].
  final int? yearlyQuota;

  Map<String, Object?> toMap() => {
    'kind': kind.name,
    if (kind == QuotaKind.limited) 'yearlyQuota': yearlyQuota ?? 0,
  };

  factory QuotaPolicy.fromMap(Map<String, Object?>? map) {
    final kind = QuotaKind.fromId(map?['kind'] as String?);
    if (kind != QuotaKind.limited) return QuotaPolicy(kind: kind);
    final quota = (map?['yearlyQuota'] as num?)?.toInt() ?? 0;
    return QuotaPolicy(kind: kind, yearlyQuota: quota);
  }

  QuotaPolicy copyWith({QuotaKind? kind, int? yearlyQuota}) => QuotaPolicy(
    kind: kind ?? this.kind,
    yearlyQuota: yearlyQuota ?? this.yearlyQuota,
  );

  @override
  bool operator ==(Object other) =>
      other is QuotaPolicy &&
      other.kind == kind &&
      other.yearlyQuota == yearlyQuota;

  @override
  int get hashCode => Object.hash(kind, yearlyQuota);
}

/// A recurring pickup pattern: some weekdays, repeating every N weeks.
class ScheduleRule {
  const ScheduleRule({
    required this.weekdays,
    required this.intervalWeeks,
    required this.anchorDate,
  });

  /// ISO weekdays, [DateTime.monday] (1) .. [DateTime.sunday] (7).
  final Set<int> weekdays;

  /// 1 = every week, 2 = every other week ("ogni 15 giorni"), and so on.
  final int intervalWeeks;

  /// Any date inside a week in which the pickup happens. Pins which week is
  /// "week zero" for intervals greater than 1; irrelevant when [intervalWeeks]
  /// is 1.
  final LocalDate anchorDate;

  Map<String, Object?> toMap() => {
    'weekdays': (weekdays.toList()..sort()),
    'intervalWeeks': intervalWeeks,
    'anchorDate': anchorDate.toKey(),
  };

  factory ScheduleRule.fromMap(Map<String, Object?> map) {
    final rawDays = (map['weekdays'] as List?) ?? const [];
    final days = rawDays
        .map((d) => (d as num).toInt())
        .where((d) => d >= DateTime.monday && d <= DateTime.sunday)
        .toSet();
    final interval = (map['intervalWeeks'] as num?)?.toInt() ?? 1;
    return ScheduleRule(
      weekdays: days,
      intervalWeeks: interval < 1 ? 1 : interval,
      anchorDate:
          LocalDate.tryParse(map['anchorDate'] as String?) ??
          LocalDate.today(),
    );
  }

  ScheduleRule copyWith({
    Set<int>? weekdays,
    int? intervalWeeks,
    LocalDate? anchorDate,
  }) => ScheduleRule(
    weekdays: weekdays ?? this.weekdays,
    intervalWeeks: intervalWeeks ?? this.intervalWeeks,
    anchorDate: anchorDate ?? this.anchorDate,
  );
}

/// The per-house settings for one waste type.
class WasteConfig {
  const WasteConfig({
    required this.type,
    required this.enabled,
    required this.policy,
    required this.rules,
  });

  final WasteType type;
  final bool enabled;
  final QuotaPolicy policy;

  /// Stored as a list so that a future "Mon weekly + Thu fortnightly" pattern
  /// is a UI change only. The current editor writes exactly one rule.
  final List<ScheduleRule> rules;

  ScheduleRule? get primaryRule => rules.isEmpty ? null : rules.first;

  Map<String, Object?> toMap() => {
    'enabled': enabled,
    'policy': policy.toMap(),
    'rules': rules.map((r) => r.toMap()).toList(),
  };

  factory WasteConfig.fromMap(WasteType type, Map<String, Object?> map) =>
      WasteConfig(
        type: type,
        enabled: map['enabled'] as bool? ?? false,
        policy: QuotaPolicy.fromMap(
          (map['policy'] as Map?)?.cast<String, Object?>(),
        ),
        rules: ((map['rules'] as List?) ?? const [])
            .map((r) => ScheduleRule.fromMap((r as Map).cast<String, Object?>()))
            .toList(),
      );

  WasteConfig copyWith({
    bool? enabled,
    QuotaPolicy? policy,
    List<ScheduleRule>? rules,
  }) => WasteConfig(
    type: type,
    enabled: enabled ?? this.enabled,
    policy: policy ?? this.policy,
    rules: rules ?? this.rules,
  );
}
