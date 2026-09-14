import '../../core/local_date.dart';
import '../../core/waste_catalogue.dart';

/// Where a collection record came from.
enum CollectionSource {
  app,
  notification;

  static CollectionSource fromId(String? id) =>
      id == 'notification' ? CollectionSource.notification : CollectionSource.app;
}

/// What happened to a scheduled pickup.
enum CollectionStatus {
  /// The waste really was put out, so it consumes an allowance.
  done,

  /// The pickup was deliberately skipped: nothing was put out, so it must not
  /// count, but it is still on record so the reminder stops asking.
  skipped;

  /// Documents written before skipping existed carry no status at all, and
  /// they were all real collections — hence the default.
  static CollectionStatus fromId(String? id) =>
      id == 'skipped' ? CollectionStatus.skipped : CollectionStatus.done;
}

/// One recorded collection — the ledger entry that every counter is derived
/// from.
///
/// The document id is deterministic for scheduled pickups
/// (`<wasteType>_<dateKey>`), which is what makes recording idempotent: two
/// family members confirming the same pickup write the same document instead of
/// double-counting. Off-schedule extras get a random suffix, because two extras
/// on the same day are genuinely two events.
class CollectionEvent {
  const CollectionEvent({
    required this.id,
    required this.type,
    required this.date,
    required this.isExtra,
    required this.recordedByUid,
    required this.recordedByName,
    required this.source,
    this.status = CollectionStatus.done,
    this.note,
    this.createdAt,
    this.hasPendingWrites = false,
  });

  final String id;
  final WasteType type;
  final LocalDate date;
  final bool isExtra;
  final String recordedByUid;
  final String recordedByName;
  final CollectionSource source;
  final CollectionStatus status;
  final String? note;
  final DateTime? createdAt;

  bool get isSkipped => status == CollectionStatus.skipped;

  /// Whether this record consumes a free collection.
  bool get countsTowardsQuota => !isSkipped;

  /// True while the write is still queued locally and not yet acknowledged by
  /// the server, so the UI can show a "in attesa di sincronizzazione" hint.
  final bool hasPendingWrites;

  /// The document id for a scheduled pickup. Deterministic by design.
  static String scheduledId(WasteType type, LocalDate date) =>
      '${type.id}_${date.toKey()}';

  /// The document id for an off-schedule extra; [unique] must be random.
  static String extraId(WasteType type, LocalDate date, String unique) =>
      '${type.id}_${date.toKey()}_x_$unique';

  Map<String, Object?> toMap() => {
    'wasteTypeId': type.id,
    'dateKey': date.toKey(),
    'isExtra': isExtra,
    'recordedByUid': recordedByUid,
    'recordedByName': recordedByName,
    'source': source.name,
    'status': status.name,
    if (note != null && note!.isNotEmpty) 'note': note,
  };

  CollectionEvent copyWith({
    String? id,
    WasteType? type,
    LocalDate? date,
    bool? isExtra,
    CollectionStatus? status,
    String? note,
  }) => CollectionEvent(
    id: id ?? this.id,
    type: type ?? this.type,
    date: date ?? this.date,
    isExtra: isExtra ?? this.isExtra,
    recordedByUid: recordedByUid,
    recordedByName: recordedByName,
    source: source,
    status: status ?? this.status,
    note: note ?? this.note,
    createdAt: createdAt,
    hasPendingWrites: hasPendingWrites,
  );
}
