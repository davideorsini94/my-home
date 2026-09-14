import '../../core/local_date.dart';

/// What a ledger entry records about one occurrence of a maintenance.
enum MaintenanceEntryStatus {
  /// The maintenance was actually carried out on [MaintenanceLogEntry.date].
  done,

  /// A scheduled occurrence was deliberately skipped. Nothing was carried out,
  /// so it must not move the last-execution date — it only pushes the next due
  /// date one period forward.
  skipped;

  static MaintenanceEntryStatus? fromId(String? id) => switch (id) {
    'done' => MaintenanceEntryStatus.done,
    'skipped' => MaintenanceEntryStatus.skipped,
    // Unlike the recurrence unit, an unknown status has no safe reading: it
    // would either invent an execution or hide one. The entry is dropped.
    _ => null,
  };
}

/// One entry in a house's maintenance ledger.
///
/// The ledger is the source of truth: the last-execution date and the next due
/// date are both derived from it, never stored. That is what keeps every write
/// a blind, idempotent `set` on a deterministic id — no read-modify-write
/// anywhere, so the notification action buttons are safe from a background
/// isolate and everything works offline.
///
/// Document ids, and why they differ by status:
/// ```
/// done     {maintenanceId}_{executionDate}        abc123_2026-09-14
/// skipped  {maintenanceId}_{dueDate}_skip         abc123_2026-09-14_skip
/// ```
/// Giving a skip its own id is not cosmetic. Share the id and a skip arriving
/// on the due date — the normal case, since that is when the reminder fires —
/// would overwrite an execution, erasing its cost and dragging the last
/// execution date back a whole period.
class MaintenanceLogEntry {
  const MaintenanceLogEntry({
    required this.id,
    required this.maintenanceId,
    required this.date,
    required this.status,
    required this.recordedByUid,
    required this.recordedByName,
    this.costCents,
    this.notes,
    this.createdAt,
    this.hasPendingWrites = false,
  });

  final String id;
  final String maintenanceId;

  /// For a [MaintenanceEntryStatus.done] this is the execution date; for a
  /// skip it is the due date being skipped.
  final LocalDate date;

  final MaintenanceEntryStatus status;
  final String recordedByUid;
  final String recordedByName;

  /// Snapshot of what this execution cost, independent of the maintenance's
  /// current cost — that is the whole point of keeping a log.
  final int? costCents;

  final String? notes;
  final DateTime? createdAt;
  final bool hasPendingWrites;

  bool get isDone => status == MaintenanceEntryStatus.done;
  bool get isSkipped => status == MaintenanceEntryStatus.skipped;

  static const String _skipSuffix = '_skip';

  static String doneId(String maintenanceId, LocalDate date) =>
      '${maintenanceId}_${date.toKey()}';

  static String skipId(String maintenanceId, LocalDate dueDate) =>
      '${maintenanceId}_${dueDate.toKey()}$_skipSuffix';

  static String idFor(
    String maintenanceId,
    LocalDate date,
    MaintenanceEntryStatus status,
  ) => status == MaintenanceEntryStatus.skipped
      ? skipId(maintenanceId, date)
      : doneId(maintenanceId, date);

  /// A skip that exists only inside a calculation, never written.
  ///
  /// Used to answer "where would Salta take this?" by re-running the real
  /// derivation with one extra skip, rather than by reimplementing the maths —
  /// a duplicated formula was how the skip preview came to disagree with the
  /// list after a recurrence edit.
  factory MaintenanceLogEntry.virtualSkip(
    String maintenanceId,
    LocalDate dueDate,
  ) => MaintenanceLogEntry(
    id: skipId(maintenanceId, dueDate),
    maintenanceId: maintenanceId,
    date: dueDate,
    status: MaintenanceEntryStatus.skipped,
    recordedByUid: '',
    recordedByName: '',
  );

  /// The six fields every writer must provide.
  ///
  /// Writes use `set(merge: true)`, and a merge onto a document that does not
  /// exist yet is validated by the rules as if it were the whole document — so
  /// a partial write on a new entry is rejected. Every writer sends the full
  /// shape.
  Map<String, Object?> toMap() => {
    'maintenanceId': maintenanceId,
    'dateKey': date.toKey(),
    'status': status.name,
    'recordedByUid': recordedByUid,
    'recordedByName': recordedByName,
    'costCents': costCents,
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
  };

  MaintenanceLogEntry copyWith({
    String? id,
    LocalDate? date,
    MaintenanceEntryStatus? status,
    int? costCents,
    String? notes,
    bool clearCost = false,
    bool clearNotes = false,
  }) => MaintenanceLogEntry(
    id: id ?? this.id,
    maintenanceId: maintenanceId,
    date: date ?? this.date,
    status: status ?? this.status,
    recordedByUid: recordedByUid,
    recordedByName: recordedByName,
    costCents: clearCost ? null : (costCents ?? this.costCents),
    notes: clearNotes ? null : (notes ?? this.notes),
    createdAt: createdAt,
    hasPendingWrites: hasPendingWrites,
  );
}
