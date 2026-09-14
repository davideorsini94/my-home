import '../core/fnv_hash.dart';
import '../core/local_date.dart';
import '../core/waste_catalogue.dart';
import '../domain/entities/collection_event.dart';
import '../domain/entities/waste_config.dart';
import '../domain/quota_calculator.dart';
import '../domain/schedule_engine.dart';
import 'notification_payload.dart';

/// Everything the scheduler needs about one house to plan its reminders.
class HouseReminderInput {
  const HouseReminderInput({
    required this.houseId,
    required this.houseName,
    required this.configs,
    required this.events,
    this.notificationsEnabled = true,
  });

  final String houseId;
  final String houseName;
  final List<WasteConfig> configs;

  /// Recorded collections, used both to compute the remaining free quota and to
  /// skip a reminder for a pickup that has already been confirmed.
  final List<CollectionEvent> events;

  final bool notificationsEnabled;
}

/// One evening reminder, fully rendered and ready to be handed to the plugin.
class ReminderPlan {
  const ReminderPlan({
    required this.id,
    required this.houseId,
    required this.pickupDate,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final String houseId;
  final LocalDate pickupDate;

  /// Local wall-clock time the reminder should appear — the evening before the
  /// pickup.
  final DateTime fireAt;

  final String title;
  final String body;
  final NotificationPayload payload;
}

/// Builds the reminders for a rolling window, newest information first.
///
/// Pure on purpose: all the grouping, wording and quota arithmetic is testable
/// without a plugin, a device or a clock.
///
/// Reminders are grouped by (house, pickup day): when several types are
/// collected the same morning, one evening reminder lists them all and
/// confirming it records them all. That keeps the number of pending
/// notifications low, which matters because iOS caps them at 64.
List<ReminderPlan> buildReminderPlans({
  required List<HouseReminderInput> houses,
  required LocalDate today,
  required DateTime now,
  required int notificationHour,
  required int notificationMinute,
  int windowDays = 14,
  int maxPending = 48,
}) {
  final plans = <ReminderPlan>[];
  final until = today.addDays(windowDays);

  for (final house in houses) {
    if (!house.notificationsEnabled) continue;

    final enabled = house.configs.where((c) => c.enabled).toList();
    if (enabled.isEmpty) continue;

    // pickup day -> types collected that day
    final byDate = <String, List<WasteConfig>>{};
    for (final config in enabled) {
      for (final date in pickupsInRange(config, today, until)) {
        byDate.putIfAbsent(date.toKey(), () => []).add(config);
      }
    }

    for (final entry in byDate.entries) {
      final pickupDate = LocalDate.parse(entry.key);
      final configs = entry.value
        ..sort((a, b) => a.type.index.compareTo(b.type.index));

      // Nothing to remind about if every type for that day is already settled —
      // whether it was collected or deliberately skipped.
      final outstanding = configs
          .where((c) => !_alreadySettled(house.events, c.type, pickupDate))
          .toList();
      if (outstanding.isEmpty) continue;

      final fireAt = DateTime(
        pickupDate.year,
        pickupDate.month,
        pickupDate.day,
        notificationHour,
        notificationMinute,
      ).subtract(const Duration(days: 1));
      if (!fireAt.isAfter(now)) continue;

      plans.add(
        ReminderPlan(
          id: stableNotificationId('${house.houseId}|${entry.key}'),
          houseId: house.houseId,
          pickupDate: pickupDate,
          fireAt: fireAt,
          title: _buildTitle(house.houseName),
          body: _buildBody(
            configs: outstanding,
            events: house.events,
            pickupDate: pickupDate,
            today: today,
          ),
          payload: NotificationPayload(
            houseId: house.houseId,
            dateKey: entry.key,
            types: outstanding.map((c) => c.type.id).toList(),
          ),
        ),
      );
    }
  }

  plans.sort((a, b) => a.fireAt.compareTo(b.fireAt));
  return plans.length > maxPending ? plans.sublist(0, maxPending) : plans;
}

/// Whether this pickup has already been dealt with, either way.
///
/// A skip counts as settled: the user has said they are not putting that waste
/// out, so reminding them again would be nagging about a decision they made.
bool _alreadySettled(
  List<CollectionEvent> events,
  WasteType type,
  LocalDate date,
) => events.any((e) => !e.isExtra && e.type == type && e.date == date);

String _buildTitle(String houseName) => 'Ritiro di domani — $houseName';

String _buildBody({
  required List<WasteConfig> configs,
  required List<CollectionEvent> events,
  required LocalDate pickupDate,
  required LocalDate today,
}) {
  final names = configs.map((c) => c.type.label).toList();
  final buffer = StringBuffer('Domani ritiro di ${_joinItalian(names)}.');

  for (final config in configs) {
    // The year comes from the pickup, not from today: a reminder fired on
    // 31 December for a 1 January pickup must report next year's fresh quota.
    final status = quotaStatusFor(
      config: config,
      events: events,
      year: pickupDate.year,
    );
    buffer.write(' ');
    if (configs.length > 1) buffer.write('${config.type.label}: ');
    buffer.write(
      configs.length > 1 ? _shortQuotaLine(status) : status.notificationLine,
    );
  }

  // These texts are baked in when the reminder is scheduled, so a count for a
  // pickup several days out may be overtaken by another member's recording.
  // Say so rather than state a stale number as fact; reminders inside the next
  // two days are refreshed on every app resume and need no caveat.
  if (today.daysUntil(pickupDate) > 2) {
    buffer.write(' (dati al ${_shortDate(today)})');
  }

  return buffer.toString();
}

String _shortQuotaLine(QuotaStatus status) => switch (status.policy.kind) {
  QuotaKind.unlimited => 'illimitati.',
  QuotaKind.paid => 'a pagamento.',
  QuotaKind.limited when status.isExhausted => 'gratuiti esauriti.',
  QuotaKind.limited => '${status.remaining} gratuiti rimasti.',
};

String _joinItalian(List<String> items) {
  if (items.isEmpty) return '';
  if (items.length == 1) return items.first;
  return '${items.sublist(0, items.length - 1).join(', ')} e ${items.last}';
}

String _shortDate(LocalDate date) => '${date.day}/${date.month}';
