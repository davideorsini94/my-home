import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/entities/house.dart';
import 'firestore_refs.dart';

class HouseRepository {
  const HouseRepository(this._refs);

  final FirestoreRefs _refs;

  /// Houses the user belongs to.
  ///
  /// The `array-contains` filter is not just an optimisation: the security
  /// rules only allow a list query that is constrained this way, so a broader
  /// query would be rejected outright.
  Stream<List<House>> watchMyHouses(String uid) => _refs.houses
      .where('memberUids', arrayContains: uid)
      .snapshots()
      .map(
        (snap) =>
            snap.docs.map(_toHouse).toList()
              ..sort(
                (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
              ),
      );

  Stream<House?> watchHouse(String houseId) =>
      _refs.house(houseId).snapshots().map((doc) {
        if (!doc.exists) return null;
        return _toHouse(doc);
      });

  Future<House?> getHouse(String houseId) async {
    final doc = await _refs.house(houseId).get();
    return doc.exists ? _toHouse(doc) : null;
  }

  Future<String> createHouse({
    required String name,
    required String ownerUid,
    required String ownerName,
  }) async {
    final doc = _refs.houses.doc();
    await doc.set({
      'name': name.trim(),
      'ownerUid': ownerUid,
      'members': {ownerUid: HouseRole.owner.name},
      'memberUids': [ownerUid],
      'memberNames': {ownerUid: ownerName},
      'createdAt': FieldValue.serverTimestamp(),
    });
    return doc.id;
  }

  /// Keeps the denormalised name in step with the account's current one.
  Future<void> refreshMyName({
    required String houseId,
    required String uid,
    required String name,
  }) => _refs.house(houseId).update({'memberNames.$uid': name});

  Future<void> renameHouse(String houseId, String name) =>
      _refs.house(houseId).update({'name': name.trim()});

  Future<void> setActiveInviteCode(String houseId, String? code) =>
      _refs.house(houseId).update({'activeInviteCode': code});

  /// Removes [uid] from the house — used both by the owner removing someone and
  /// by a member leaving. The security rules forbid removing the owner.
  Future<void> removeMember(String houseId, String uid) =>
      _refs.house(houseId).update({
        'members.$uid': FieldValue.delete(),
        'memberNames.$uid': FieldValue.delete(),
        'memberUids': FieldValue.arrayRemove([uid]),
      });

  /// Deletes the house and everything under it.
  ///
  /// The house document goes last: if the process is interrupted the house
  /// still exists and the deletion can simply be retried, whereas deleting the
  /// parent first would leave unreachable orphan subcollections.
  Future<void> deleteHouse(String houseId) async {
    await _deleteAll(_refs.collections(houseId));
    await _deleteAll(_refs.wasteConfigs(houseId));
    await _deleteAll(_refs.maintenanceLog(houseId));
    await _deleteAll(_refs.maintenances(houseId));
    await _refs.house(houseId).delete();
  }

  Future<void> _deleteAll(CollectionReference<Map<String, dynamic>> ref) async {
    // Firestore caps a batch at 500 writes.
    const pageSize = 400;
    while (true) {
      final snap = await ref.limit(pageSize).get();
      if (snap.docs.isEmpty) return;
      final batch = _refs.batch();
      for (final doc in snap.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();
      if (snap.docs.length < pageSize) return;
    }
  }

  House _toHouse(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final rawMembers = (data['members'] as Map?)?.cast<String, Object?>() ?? {};
    final rawNames = (data['memberNames'] as Map?)?.cast<String, Object?>() ?? {};
    return House(
      id: doc.id,
      name: data['name'] as String? ?? 'Abitazione',
      ownerUid: data['ownerUid'] as String? ?? '',
      members: {
        for (final entry in rawMembers.entries)
          entry.key: HouseRole.fromId(entry.value as String?),
      },
      memberNames: {
        for (final entry in rawNames.entries)
          if (entry.value is String) entry.key: entry.value as String,
      },
      activeInviteCode: data['activeInviteCode'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}
