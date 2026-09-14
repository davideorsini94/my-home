import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/local_date.dart';
import '../domain/entities/maintenance.dart';
import '../domain/entities/maintenance_log_entry.dart';
import 'firestore_refs.dart';

/// Where a ledger entry came from.
enum MaintenanceEntrySource {
  app,
  notification,

  /// Written when a maintenance is created with a last-execution date already
  /// known, so the very first reminder can be computed without waiting for a
  /// real execution.
  seed;

  static MaintenanceEntrySource fromId(String? id) => switch (id) {
    'notification' => MaintenanceEntrySource.notification,
    'seed' => MaintenanceEntrySource.seed,
    _ => MaintenanceEntrySource.app,
  };
}

/// Maintenances and their execution ledger.
///
/// Every write is a blind `set` on a deterministic id — never a read first,
/// then a write. That is what lets the notification buttons settle a
/// maintenance from a background isolate, keeps the app working offline, and
/// makes two members acting on the same occurrence collapse into one record
/// instead of racing.
class MaintenanceRepository {
  const MaintenanceRepository(this._refs);

  final FirestoreRefs _refs;

  // ------------------------------------------------------------ maintenances

  Stream<List<Maintenance>> watchMaintenances(String houseId) =>
      _refs.maintenances(houseId).snapshots().map(_toMaintenances);

  Future<List<Maintenance>> getMaintenances(String houseId) async =>
      _toMaintenances(await _refs.maintenances(houseId).get());

  List<Maintenance> _toMaintenances(QuerySnapshot<Map<String, dynamic>> snap) =>
      snap.docs.map(_toMaintenance).toList();

  Maintenance _toMaintenance(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return Maintenance(
      id: doc.id,
      name: data['name'] as String? ?? 'Manutenzione',
      iconKey: data['iconKey'] as String? ?? 'generic',
      // Null when this client cannot read the unit: the maintenance stays
      // visible and executable, it simply computes no schedule.
      recurrence: Recurrence.fromMap(
        (data['recurrence'] as Map?)?.cast<String, Object?>(),
      ),
      notes: data['notes'] as String?,
      costCents: (data['costCents'] as num?)?.toInt(),
      contact: MaintenanceContact.fromMap(
        (data['contact'] as Map?)?.cast<String, Object?>(),
      ),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      hasPendingWrites: doc.metadata.hasPendingWrites,
    );
  }

  /// Creates a maintenance, optionally seeding its last-execution date.
  ///
  /// The seed entry goes in the same batch as the document: a maintenance that
  /// claimed a last execution the ledger did not contain would compute no due
  /// date at all.
  Future<String> createMaintenance({
    required String houseId,
    required Maintenance maintenance,
    required String uid,
    required String userName,
    LocalDate? lastDone,
  }) async {
    final doc = _refs.maintenances(houseId).doc();
    final batch = _refs.batch();

    batch.set(doc, {
      ...maintenance.toMap(),
      'createdByUid': uid,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    if (lastDone != null) {
      final entry = MaintenanceLogEntry(
        id: MaintenanceLogEntry.doneId(doc.id, lastDone),
        maintenanceId: doc.id,
        date: lastDone,
        status: MaintenanceEntryStatus.done,
        recordedByUid: uid,
        recordedByName: userName,
        costCents: maintenance.costCents,
      );
      batch.set(_refs.maintenanceLog(houseId).doc(entry.id), {
        ...entry.toMap(),
        'source': MaintenanceEntrySource.seed.name,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }

    await batch.commit();
    return doc.id;
  }

  /// Overwrites the maintenance document.
  ///
  /// Explicit clears are sent as [FieldValue.delete] rather than omitted, since
  /// a merge would otherwise leave the old value in place.
  Future<void> updateMaintenance({
    required String houseId,
    required Maintenance maintenance,
  }) => _refs.maintenances(houseId).doc(maintenance.id).set({
    ...maintenance.toMap(),
    if (maintenance.notes == null || maintenance.notes!.isEmpty)
      'notes': FieldValue.delete(),
    if (maintenance.costCents == null) 'costCents': FieldValue.delete(),
    if (maintenance.contact == null) 'contact': FieldValue.delete(),
    'updatedAt': FieldValue.serverTimestamp(),
  }, SetOptions(merge: true));

  /// Deletes a maintenance and its ledger entries.
  ///
  /// Entries go first: interrupted halfway the maintenance still exists and the
  /// delete can simply be retried, whereas removing the parent first would
  /// strand entries nothing can reach.
  Future<void> deleteMaintenance({
    required String houseId,
    required String maintenanceId,
  }) async {
    await _deleteLogOf(houseId, maintenanceId);
    await _refs.maintenances(houseId).doc(maintenanceId).delete();
  }

  Future<void> _deleteLogOf(String houseId, String maintenanceId) async {
    const pageSize = 300;
    while (true) {
      final snap = await _refs
          .maintenanceLog(houseId)
          .where('maintenanceId', isEqualTo: maintenanceId)
          .limit(pageSize)
          .get();
      if (snap.docs.isEmpty) return;
      final batch = _refs.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snap.docs.length < pageSize) return;
    }
  }

  // -------------------------------------------------------------- the ledger

  /// The ledger from [from] onwards.
  ///
  /// A lower bound only. An upper bound would be wrong: skipping a future
  /// occurrence writes an entry keyed to that future date, and hiding it would
  /// make the skip vanish.
  Stream<List<MaintenanceLogEntry>> watchLog(String houseId, LocalDate from) =>
      _refs
          .maintenanceLog(houseId)
          .where('dateKey', isGreaterThanOrEqualTo: from.toKey())
          .snapshots()
          .map(_toEntries);

  Future<List<MaintenanceLogEntry>> getLog(
    String houseId,
    LocalDate from,
  ) async => _toEntries(
    await _refs
        .maintenanceLog(houseId)
        .where('dateKey', isGreaterThanOrEqualTo: from.toKey())
        .get(),
  );

  List<MaintenanceLogEntry> _toEntries(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final entries = <MaintenanceLogEntry>[];
    for (final doc in snap.docs) {
      final entry = _toEntry(doc);
      if (entry != null) entries.add(entry);
    }
    return entries;
  }

  MaintenanceLogEntry? _toEntry(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final maintenanceId = data['maintenanceId'] as String?;
    final date = LocalDate.tryParse(data['dateKey'] as String?);
    final status = MaintenanceEntryStatus.fromId(data['status'] as String?);
    // A malformed or unknown-status entry is skipped rather than guessed at:
    // inventing an execution or hiding one are both worse than ignoring it.
    if (maintenanceId == null || date == null || status == null) return null;
    return MaintenanceLogEntry(
      id: doc.id,
      maintenanceId: maintenanceId,
      date: date,
      status: status,
      recordedByUid: data['recordedByUid'] as String? ?? '',
      recordedByName: data['recordedByName'] as String? ?? '',
      costCents: (data['costCents'] as num?)?.toInt(),
      notes: data['notes'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      hasPendingWrites: doc.metadata.hasPendingWrites,
    );
  }

  /// Records an execution on [date].
  ///
  /// The id derives from the maintenance and the date, so two members
  /// confirming the same execution write one document. Writes the full entry
  /// shape: a merge onto a document that does not exist yet is validated by the
  /// rules as if the delta were the whole document, so a partial write on a new
  /// entry would be rejected.
  Future<String> recordExecution({
    required String houseId,
    required String maintenanceId,
    required LocalDate date,
    required String uid,
    required String userName,
    int? costCents,
    String? notes,
    MaintenanceEntrySource source = MaintenanceEntrySource.app,
  }) async {
    final id = MaintenanceLogEntry.doneId(maintenanceId, date);
    await _refs.maintenanceLog(houseId).doc(id).set({
      'maintenanceId': maintenanceId,
      'dateKey': date.toKey(),
      'status': MaintenanceEntryStatus.done.name,
      'recordedByUid': uid,
      'recordedByName': userName,
      // An execution confirmed from a notification carries no cost, and must
      // not wipe one already recorded from the app for the same day.
      if (costCents != null) 'costCents': costCents,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'source': source.name,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return id;
  }

  /// Records that [dueDate] was deliberately skipped.
  ///
  /// A separate id from an execution, so a skip arriving on the due date — the
  /// normal case, since that is when the reminder fires — cannot overwrite an
  /// execution and the cost recorded with it.
  Future<String> recordSkip({
    required String houseId,
    required String maintenanceId,
    required LocalDate dueDate,
    required String uid,
    required String userName,
    MaintenanceEntrySource source = MaintenanceEntrySource.app,
  }) async {
    final id = MaintenanceLogEntry.skipId(maintenanceId, dueDate);
    await _refs.maintenanceLog(houseId).doc(id).set({
      'maintenanceId': maintenanceId,
      'dateKey': dueDate.toKey(),
      'status': MaintenanceEntryStatus.skipped.name,
      'recordedByUid': uid,
      'recordedByName': userName,
      'source': source.name,
      'createdAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
    return id;
  }

  /// Skips several overdue occurrences at once, in one batch.
  Future<void> recordSkips({
    required String houseId,
    required String maintenanceId,
    required List<LocalDate> dueDates,
    required String uid,
    required String userName,
  }) async {
    if (dueDates.isEmpty) return;
    final batch = _refs.batch();
    for (final dueDate in dueDates) {
      batch.set(
        _refs
            .maintenanceLog(houseId)
            .doc(MaintenanceLogEntry.skipId(maintenanceId, dueDate)),
        {
          'maintenanceId': maintenanceId,
          'dateKey': dueDate.toKey(),
          'status': MaintenanceEntryStatus.skipped.name,
          'recordedByUid': uid,
          'recordedByName': userName,
          'source': MaintenanceEntrySource.app.name,
          'createdAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }
    await batch.commit();
  }

  /// Corrects an existing entry.
  ///
  /// The date and the status are both encoded in the id, so changing either
  /// moves the document: the old one is deleted and the new one written in one
  /// batch, which stays atomic and queues correctly while offline. The full
  /// shape is always written, for the same reason as [recordExecution].
  Future<String> updateEntry({
    required String houseId,
    required MaintenanceLogEntry original,
    required LocalDate date,
    required MaintenanceEntryStatus status,
    int? costCents,
    String? notes,
  }) async {
    final newId = MaintenanceLogEntry.idFor(
      original.maintenanceId,
      date,
      status,
    );
    final data = <String, Object?>{
      'maintenanceId': original.maintenanceId,
      'dateKey': date.toKey(),
      'status': status.name,
      'recordedByUid': original.recordedByUid,
      'recordedByName': original.recordedByName,
      'costCents': status == MaintenanceEntryStatus.done ? costCents : null,
      if (notes != null && notes.isNotEmpty) 'notes': notes,
      'createdAt': original.createdAt != null
          ? Timestamp.fromDate(original.createdAt!)
          : FieldValue.serverTimestamp(),
    };

    if (newId == original.id) {
      await _refs.maintenanceLog(houseId).doc(newId).set({
        ...data,
        if (notes == null || notes.isEmpty) 'notes': FieldValue.delete(),
      }, SetOptions(merge: true));
      return newId;
    }

    final batch = _refs.batch();
    batch.delete(_refs.maintenanceLog(houseId).doc(original.id));
    batch.set(_refs.maintenanceLog(houseId).doc(newId), data);
    await batch.commit();
    return newId;
  }

  Future<void> deleteEntry({
    required String houseId,
    required String entryId,
  }) => _refs.maintenanceLog(houseId).doc(entryId).delete();
}
