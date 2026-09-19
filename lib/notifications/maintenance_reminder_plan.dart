import '../core/date_format_it.dart';
import '../core/fnv_hash.dart';
import '../core/local_date.dart';
import '../domain/entities/maintenance.dart';
import '../domain/entities/maintenance_log_entry.dart';
import '../domain/maintenance_schedule.dart';
import 'maintenance_payload.dart';

/// Days after the due date at which the single follow-up nudge fires.
const int maintenanceFollowUpDays = 7;

/// Everything the scheduler needs about one house's maintenances.
class MaintenanceReminderInput {
  const MaintenanceReminderInput({
    required this.houseId,
    required this.houseName,
    required this.maintenances,
    required this.log,
  });

  final String houseId;
  final String houseName;
  final List<Maintenance> maintenances;
  final List<MaintenanceLogEntry> log;
}

/// One scheduled maintenance reminder, rendered and ready for the plugin.
class MaintenanceReminderPlan {
  const MaintenanceReminderPlan({
    required this.id,
    required this.houseId,
    required this.maintenanceId,
    required this.dueDate,
    required this.slot,
    required this.fireAt,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final String houseId;
  final String maintenanceId;
  final LocalDate dueDate;
  final MaintenanceReminderSlot slot;
  final DateTime fireAt;
  final String title;
  final String body;
  final MaintenancePayload payload;
}

/// Builds the maintenance reminders for the given houses.
///
/// Pure: no plugin, no clock of its own, no I/O — so the wording, the slot
/// arithmetic and the budget behaviour are all unit-testable.
///
/// Both slots are scheduled up front rather than the follow-up being added
/// later, because a sync only happens when the app is opened: the user who
/// needs a second nudge is precisely the one who will not open it in time.
List<MaintenanceReminderPlan> buildMaintenanceReminderPlans({
  required List<MaintenanceReminderInput> houses,
  required LocalDate today,
  required DateTime now,
  required int notificationHour,
  required int notificationMinute,
  int maxPending = 16,
}) {
  final plans = <MaintenanceReminderPlan>[];

  for (final house in houses) {
    for (final maintenance in house.maintenances) {
      final status = deriveStatus(maintenance, house.log, today);
      // Never executed, unreadable recurrence and wedged all yield no due date
      // and therefore no reminder — there is nothing truthful to say.
      final due = status.nextDue;
      if (due == null) continue;

      for (final slot in MaintenanceReminderSlot.values) {
        final fireDate = slot == MaintenanceReminderSlot.due
            ? due
            : due.addDays(maintenanceFollowUpDays);
        final fireAt = DateTime(
          fireDate.year,
          fireDate.month,
          fireDate.day,
          notificationHour,
          notificationMinute,
        );
        if (!fireAt.isAfter(now)) continue;

        plans.add(
          MaintenanceReminderPlan(
            id: stableNotificationId(
              'm|${house.houseId}|${maintenance.id}|${slot == MaintenanceReminderSlot.due ? 'due' : 'fu'}',
            ),
            houseId: house.houseId,
            maintenanceId: maintenance.id,
            dueDate: due,
            slot: slot,
            fireAt: fireAt,
            title: _title(slot, house.houseName),
            body: _body(slot, maintenance, status, due, fireDate),
            payload: MaintenancePayload(
              houseId: house.houseId,
              maintenanceId: maintenance.id,
              dueDateKey: due.toKey(),
              slot: slot,
            ),
          ),
        );
      }
    }
  }

  // Kind first, then time. Sorting by time alone would let one maintenance's
  // follow-up — due date plus a week — outrank another maintenance's primary
  // reminder and evict it when the budget runs out, so a second-chance nudge
  // could silence a first notice.
  plans.sort((a, b) {
    final bySlot = a.slot.index.compareTo(b.slot.index);
    if (bySlot != 0) return bySlot;
    return a.fireAt.compareTo(b.fireAt);
  });

  return plans.length > maxPending ? plans.sublist(0, maxPending) : plans;
}

String _title(MaintenanceReminderSlot slot, String houseName) =>
    slot == MaintenanceReminderSlot.due
    ? 'Manutenzione in scadenza — $houseName'
    : 'Manutenzione in ritardo — $houseName';

String _body(
  MaintenanceReminderSlot slot,
  Maintenance maintenance,
  MaintenanceStatus status,
  LocalDate due,
  // The reader sees this text on the day it fires, so that is the year the
  // dates are read against: a maintenance every three years would otherwise
  // say "ultima esecuzione: mar 15 set" and look a week old.
  LocalDate readOn,
) {
  if (slot == MaintenanceReminderSlot.followUp) {
    // "o dalla notifica" matters: this nudge exists precisely for the case
    // where someone settled it from the shade with the app closed, which no
    // sync has had a chance to notice yet.
    return '«${maintenance.name}» era prevista il ${formatShortInContext(due, readOn)}. '
        'Se l\'hai già eseguita o saltata dall\'app o dalla notifica, '
        'ignora questo avviso.';
  }

  final buffer = StringBuffer(
    'Oggi è prevista la manutenzione «${maintenance.name}»',
  );
  final recurrence = maintenance.recurrence;
  if (recurrence != null) buffer.write(' (${recurrence.label})');
  buffer.write('.');

  final lastDone = status.lastDone;
  if (lastDone != null) {
    buffer.write(
      ' Ultima esecuzione: ${formatShortInContext(lastDone, readOn)}.',
    );
  }

  final contact = maintenance.contact;
  if (contact != null && contact.hasName) {
    buffer.write(' Contatto: ${contact.label}.');
  }

  return buffer.toString();
}

/// Maps a notification action id onto the ledger entry it should write.
///
/// Null for anything else — a tap on the body, or an id from a future version
/// — so an unrecognised action can never silently write the wrong outcome.
MaintenanceEntryStatus? maintenanceStatusForAction(String? actionId) =>
    switch (actionId) {
      'mark_done' => MaintenanceEntryStatus.done,
      'skip' => MaintenanceEntryStatus.skipped,
      _ => null,
    };
