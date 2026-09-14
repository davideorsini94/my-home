import 'dart:convert';

import '../core/local_date.dart';
import '../domain/entities/maintenance_log_entry.dart';

/// Distinguishes what a notification payload refers to.
///
/// Waste payloads predate this field and carry no `kind`, so their absence must
/// mean waste — anything else would break every reminder already sitting in a
/// user's notification shade at upgrade time.
enum ReminderKind {
  waste,
  maintenance;

  static ReminderKind fromId(String? id) =>
      id == 'maintenance' ? ReminderKind.maintenance : ReminderKind.waste;
}

/// Which of a maintenance's two reminder slots a notification is.
enum MaintenanceReminderSlot {
  /// Fires on the due date.
  due,

  /// Fires a week later if nothing settled it.
  followUp;

  static MaintenanceReminderSlot fromId(String? id) =>
      id == 'followUp' ? MaintenanceReminderSlot.followUp : MaintenanceReminderSlot.due;
}

/// What a maintenance reminder carries, so its action buttons can settle the
/// maintenance without the app coming to the foreground.
class MaintenancePayload {
  const MaintenancePayload({
    required this.houseId,
    required this.maintenanceId,
    required this.dueDateKey,
    required this.slot,
  });

  final String houseId;
  final String maintenanceId;

  /// The due date this reminder is about — needed by "Salta", which must write
  /// its entry keyed to that exact date rather than to today.
  final String dueDateKey;

  final MaintenanceReminderSlot slot;

  LocalDate get dueDate => LocalDate.parse(dueDateKey);

  /// [doneDateKey] is the day the button was tapped, captured before the write
  /// so that an action replayed days later still records the day it happened
  /// rather than the day it synced.
  String encode({
    MaintenanceEntryStatus? status,
    String? doneDateKey,
  }) => jsonEncode({
    'kind': ReminderKind.maintenance.name,
    'houseId': houseId,
    'maintenanceId': maintenanceId,
    'dueDateKey': dueDateKey,
    'slot': slot.name,
    if (status != null) 'status': status.name,
    if (doneDateKey != null) 'doneDateKey': doneDateKey,
  });

  static MaintenancePayload? decode(String? raw) {
    final map = _decodeMap(raw);
    if (map == null) return null;
    if (ReminderKind.fromId(map['kind'] as String?) != ReminderKind.maintenance) {
      return null;
    }
    final houseId = map['houseId'] as String?;
    final maintenanceId = map['maintenanceId'] as String?;
    final dueDateKey = map['dueDateKey'] as String?;
    if (houseId == null || maintenanceId == null || dueDateKey == null) {
      return null;
    }
    if (LocalDate.tryParse(dueDateKey) == null) return null;
    return MaintenancePayload(
      houseId: houseId,
      maintenanceId: maintenanceId,
      dueDateKey: dueDateKey,
      slot: MaintenanceReminderSlot.fromId(map['slot'] as String?),
    );
  }

  /// The outcome recorded in a queued action awaiting replay.
  static MaintenanceEntryStatus? decodeStatus(String? raw) {
    final map = _decodeMap(raw);
    return MaintenanceEntryStatus.fromId(map?['status'] as String?);
  }

  /// The day the action was actually taken, if it was captured.
  static LocalDate? decodeDoneDate(String? raw) =>
      LocalDate.tryParse(_decodeMap(raw)?['doneDateKey'] as String?);

  /// Which feature a raw payload belongs to, without decoding it fully.
  static ReminderKind kindOf(String? raw) =>
      ReminderKind.fromId(_decodeMap(raw)?['kind'] as String?);

  static Map<String, dynamic>? _decodeMap(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      return decoded is Map<String, dynamic> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
