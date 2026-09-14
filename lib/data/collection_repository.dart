import 'package:cloud_firestore/cloud_firestore.dart';

import '../core/local_date.dart';
import '../core/waste_catalogue.dart';
import '../domain/collection_ledger.dart';
import '../domain/entities/collection_event.dart';
import 'firestore_refs.dart';

/// The ledger of recorded collections. Every counter in the app is derived from
/// what this repository returns.
class CollectionRepository {
  const CollectionRepository(this._refs);

  final FirestoreRefs _refs;

  Query<Map<String, dynamic>> _yearQuery(String houseId, int year) =>
      _refs
          .collections(houseId)
          .where('dateKey', isGreaterThanOrEqualTo: '$year-01-01')
          .where('dateKey', isLessThanOrEqualTo: '$year-12-31')
          .orderBy('dateKey', descending: true);

  /// One listener per open house covers both the history screen and every
  /// counter, and is served from the offline cache when there is no network.
  Stream<List<CollectionEvent>> watchYear(String houseId, int year) =>
      _yearQuery(houseId, year).snapshots().map(_toEvents);

  /// One-shot read, used by the notification scheduler which needs the counts
  /// of every house without holding listeners open.
  Future<List<CollectionEvent>> getYear(String houseId, int year) async =>
      _toEvents(await _yearQuery(houseId, year).get());

  List<CollectionEvent> _toEvents(QuerySnapshot<Map<String, dynamic>> snap) {
    final events = <CollectionEvent>[];
    for (final doc in snap.docs) {
      final event = _toEvent(doc);
      if (event != null) events.add(event);
    }
    return events;
  }

  CollectionEvent? _toEvent(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final type = WasteType.fromId(data['wasteTypeId'] as String?);
    final date = LocalDate.tryParse(data['dateKey'] as String?);
    if (type == null || date == null) return null;
    return CollectionEvent(
      id: doc.id,
      type: type,
      date: date,
      isExtra: data['isExtra'] as bool? ?? false,
      recordedByUid: data['recordedByUid'] as String? ?? '',
      recordedByName: data['recordedByName'] as String? ?? '',
      source: CollectionSource.fromId(data['source'] as String?),
      status: CollectionStatus.fromId(data['status'] as String?),
      note: data['note'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      hasPendingWrites: doc.metadata.hasPendingWrites,
    );
  }

  /// Records a collection for a scheduled pickup.
  ///
  /// The document id is derived from the type and the date, so if two family
  /// members confirm the same pickup — one from the app, one from the
  /// notification, possibly one of them offline — both writes land on the same
  /// document and the count stays 1. No transaction is involved, which also
  /// means this works while offline.
  Future<String> recordScheduled({
    required String houseId,
    required WasteType type,
    required LocalDate date,
    required String uid,
    required String userName,
    CollectionSource source = CollectionSource.app,
    CollectionStatus status = CollectionStatus.done,
    String? note,
  }) async {
    final id = CollectionEvent.scheduledId(type, date);
    await _refs.collections(houseId).doc(id).set({
      'wasteTypeId': type.id,
      'dateKey': date.toKey(),
      'isExtra': false,
      'recordedByUid': uid,
      'recordedByName': userName,
      'source': source.name,
      'status': status.name,
      if (note != null && note.isNotEmpty) 'note': note,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  /// Records an off-schedule collection.
  ///
  /// Extras have no natural key — two extra bags on the same day are genuinely
  /// two events — so the id carries a random suffix and this call is *not*
  /// idempotent. The UI warns about same-day duplicates before calling it.
  Future<String> recordExtra({
    required String houseId,
    required WasteType type,
    required LocalDate date,
    required String uid,
    required String userName,
    required String unique,
    String? note,
  }) async {
    final id = CollectionEvent.extraId(type, date, unique);
    await _refs.collections(houseId).doc(id).set({
      'wasteTypeId': type.id,
      'dateKey': date.toKey(),
      'isExtra': true,
      'recordedByUid': uid,
      'recordedByName': userName,
      'source': CollectionSource.app.name,
      'status': CollectionStatus.done.name,
      if (note != null && note.isNotEmpty) 'note': note,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return id;
  }

  Future<void> deleteEvent(String houseId, String eventId) =>
      _refs.collections(houseId).doc(eventId).delete();

  /// Applies an edit to a recorded collection.
  ///
  /// Because the type and the date are both encoded in the document id, editing
  /// either means moving the document: delete the old one and write the new one
  /// in a single batch, which stays atomic and queues correctly while offline.
  ///
  /// If the destination id already exists — the user moved a collection onto a
  /// day already recorded for that type — the two records merge into one. That
  /// is the arithmetically correct outcome for a scheduled pickup, and the UI
  /// warns before it happens.
  Future<String> updateEvent({
    required String houseId,
    required CollectionEvent original,
    required WasteType type,
    required LocalDate date,
    CollectionStatus? status,
    String? note,
  }) async {
    final newId = idForEvent(
      type: type,
      date: date,
      isExtra: original.isExtra,
      uniqueSuffix: extraSuffixOf(original.id),
    );

    final data = {
      'wasteTypeId': type.id,
      'dateKey': date.toKey(),
      'isExtra': original.isExtra,
      'recordedByUid': original.recordedByUid,
      'recordedByName': original.recordedByName,
      'source': original.source.name,
      'status': (status ?? original.status).name,
      if (note != null && note.isNotEmpty) 'note': note,
      'createdAt': original.createdAt != null
          ? Timestamp.fromDate(original.createdAt!)
          : FieldValue.serverTimestamp(),
    };

    if (newId == original.id) {
      await _refs.collections(houseId).doc(newId).set(data);
      return newId;
    }

    final batch = _refs.batch();
    batch.delete(_refs.collections(houseId).doc(original.id));
    batch.set(_refs.collections(houseId).doc(newId), data);
    await batch.commit();
    return newId;
  }

  /// Whether moving [original] to ([type], [date]) would land on an id that is
  /// already taken, i.e. whether the two records would merge.
  bool wouldMerge({
    required CollectionEvent original,
    required WasteType type,
    required LocalDate date,
    required Iterable<CollectionEvent> existing,
  }) => wouldMergeOnMove(
    original: original,
    type: type,
    date: date,
    existing: existing,
  );
}
