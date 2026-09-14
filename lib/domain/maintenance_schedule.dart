import '../core/local_date.dart';
import 'entities/maintenance.dart';
import 'entities/maintenance_log_entry.dart';
import 'recurrence_engine.dart';

/// Hard stop for the due-date search, so a pathological ledger cannot spin.
const int maxSkipDerivation = 1000;

/// The most skips "salta tutto" will ever leave after the last execution.
///
/// Deliberately below [maxSkipDerivation]: skipping in bulk must never be able
/// to push the derivation into its own guard, which is exactly how an earlier
/// design wedged itself.
const int maxSkipsPerMaintenance = 900;

/// The most occurrences a single "salta tutto" will write.
const int maxSkipsPerTap = 200;

/// Everything the UI and the scheduler need to know about one maintenance.
class MaintenanceStatus {
  const MaintenanceStatus({
    required this.maintenance,
    required this.lastExecution,
    required this.nextDue,
    required this.isWedged,
    required this.skipsAfterLastDone,
    required this.ignoredFutureExecutions,
  });

  final Maintenance maintenance;

  /// The newest execution dated on or before today.
  final MaintenanceLogEntry? lastExecution;

  /// Null when the maintenance has never been executed, when this client
  /// cannot read its recurrence, or when it is [isWedged].
  final LocalDate? nextDue;

  /// The derivation ran out of room: too many skips to find an unskipped due.
  ///
  /// Returning the last candidate instead would hand back a date that is
  /// itself already skipped, so "Salta" would rewrite an existing skip and
  /// appear to do nothing, for ever.
  final bool isWedged;

  final int skipsAfterLastDone;

  /// Executions dated in the future, excluded from the derivation.
  ///
  /// A device with a wrong clock can write one; without this exclusion every
  /// later real execution would be older than it and be ignored, locking the
  /// maintenance with no way back.
  final List<MaintenanceLogEntry> ignoredFutureExecutions;

  LocalDate? get lastDone => lastExecution?.date;
  bool get isNeverDone => lastDone == null;
  bool get hasUnknownRecurrence => maintenance.hasUnknownRecurrence;
  bool get hasIgnoredFutureExecutions => ignoredFutureExecutions.isNotEmpty;

  bool isOverdue(LocalDate today) => nextDue != null && nextDue! < today;
  bool isDueToday(LocalDate today) => nextDue == today;

  /// Whether the maintenance is waiting to be settled — due today or overdue.
  bool isActionable(LocalDate today) => nextDue != null && nextDue! <= today;

  /// Days until the next due date; negative when overdue.
  int? daysUntilDue(LocalDate today) =>
      nextDue == null ? null : today.daysUntil(nextDue!);
}

/// Derives the current state of [maintenance] from the ledger.
///
/// Pure and total: no clock of its own, no I/O, every branch returns a status.
MaintenanceStatus deriveStatus(
  Maintenance maintenance,
  Iterable<MaintenanceLogEntry> log,
  LocalDate today,
) {
  final mine = log.where((e) => e.maintenanceId == maintenance.id).toList();

  final future = <MaintenanceLogEntry>[];
  final usable = <MaintenanceLogEntry>[];
  final skipped = <LocalDate>{};
  for (final entry in mine) {
    if (entry.isSkipped) {
      skipped.add(entry.date);
    } else if (entry.date > today) {
      future.add(entry);
    } else {
      usable.add(entry);
    }
  }

  final recurrence = maintenance.recurrence;
  if (usable.isEmpty || recurrence == null) {
    return MaintenanceStatus(
      maintenance: maintenance,
      lastExecution: null,
      nextDue: null,
      isWedged: false,
      skipsAfterLastDone: 0,
      ignoredFutureExecutions: future,
    );
  }

  usable.sort((a, b) => b.date.compareTo(a.date));
  final last = usable.first;

  // Walk forward from the last execution until a due date is not skipped.
  // Because every computed due is strictly after lastDone, and every skip that
  // could shadow an execution is dated on or before it, a `done` on a date
  // always dominates a `skipped` on the same date, whichever was written last.
  var n = 1;
  var due = advance(last.date, recurrence, times: n);
  while (skipped.contains(due) && n < maxSkipDerivation && due.year < 9000) {
    n++;
    due = advance(last.date, recurrence, times: n);
  }

  final wedged = skipped.contains(due) || due.year >= 9000;
  return MaintenanceStatus(
    maintenance: maintenance,
    lastExecution: last,
    nextDue: wedged ? null : due,
    isWedged: wedged,
    skipsAfterLastDone: wedged ? n : n - 1,
    ignoredFutureExecutions: future,
  );
}

/// Where "Salta" would move the next due date, or null if it cannot.
///
/// Re-runs the real derivation with one virtual skip rather than computing the
/// answer independently: a second formula is how the confirmation dialog came
/// to promise one date while the list then showed another.
LocalDate? dueAfterSkip(
  Maintenance maintenance,
  Iterable<MaintenanceLogEntry> log,
  LocalDate today,
) {
  final status = deriveStatus(maintenance, log, today);
  final due = status.nextDue;
  if (due == null) return null;
  return deriveStatus(maintenance, [
    ...log,
    MaintenanceLogEntry.virtualSkip(maintenance.id, due),
  ], today).nextDue;
}

/// The due dates that must be skipped to move the next due past [today].
///
/// Empty when nothing is overdue, or when catching up would need more skips
/// than [maxSkipsPerTap] in one go or leave more than
/// [maxSkipsPerMaintenance] after the last execution — the caller shows a
/// message instead, because silently writing hundreds of entries, or nudging
/// the derivation towards its guard, are both worse than declining.
List<LocalDate> duesToSkipUntilFuture(
  Maintenance maintenance,
  Iterable<MaintenanceLogEntry> log,
  LocalDate today,
) {
  final status = deriveStatus(maintenance, log, today);
  if (!status.isActionable(today)) return const [];

  final entries = log.toList();
  final dues = <LocalDate>[];
  var current = status;

  while (current.nextDue != null && current.nextDue! <= today) {
    if (dues.length >= maxSkipsPerTap) return const [];
    if (current.skipsAfterLastDone + dues.length + 1 > maxSkipsPerMaintenance) {
      return const [];
    }
    final due = current.nextDue!;
    dues.add(due);
    entries.add(MaintenanceLogEntry.virtualSkip(maintenance.id, due));
    current = deriveStatus(maintenance, entries, today);
  }

  return current.nextDue == null ? const [] : dues;
}

/// The oldest ledger date worth loading.
///
/// A lower bound only: skipping a future occurrence writes a future-dated key,
/// so an upper bound would hide entries the derivation needs.
///
/// Ten years, or three times the cadence when that is longer, keeps a rarely
/// serviced item — a septic tank on a five-year cycle — from silently reading
/// as never executed.
LocalDate logLowerBound(
  Iterable<Maintenance> maintenances,
  LocalDate today, {
  int floorYears = 10,
  int capYears = 30,
  int cadenceMultiplier = 3,
}) {
  var years = floorYears;
  for (final maintenance in maintenances) {
    final recurrence = maintenance.recurrence;
    if (recurrence == null) continue;
    final cadenceYears = switch (recurrence.unit) {
      RecurrenceUnit.days => (recurrence.every / 365).ceil(),
      RecurrenceUnit.weeks => (recurrence.every * 7 / 365).ceil(),
      RecurrenceUnit.months => (recurrence.every / 12).ceil(),
      RecurrenceUnit.years => recurrence.every,
    };
    final needed = cadenceYears * cadenceMultiplier;
    if (needed > years) years = needed;
  }
  if (years > capYears) years = capYears;
  return LocalDate(today.year - years, today.month, today.day).addDays(-30);
}

/// List ordering: what needs attention first, then by due date, then by name.
///
/// Wedged and unreadable items sort to the top rather than the bottom: they
/// are broken and invisible otherwise, since neither produces a due date.
int compareForList(MaintenanceStatus a, MaintenanceStatus b, LocalDate today) {
  int rank(MaintenanceStatus s) {
    if (s.isWedged || s.hasUnknownRecurrence) return 0;
    if (s.isActionable(today)) return 1;
    if (s.nextDue != null) return 2;
    return 3; // never executed
  }

  final byRank = rank(a).compareTo(rank(b));
  if (byRank != 0) return byRank;

  if (a.nextDue != null && b.nextDue != null) {
    final byDue = a.nextDue!.compareTo(b.nextDue!);
    if (byDue != 0) return byDue;
  }
  return a.maintenance.name.toLowerCase().compareTo(
    b.maintenance.name.toLowerCase(),
  );
}
