import 'package:cloud_firestore/cloud_firestore.dart';

/// Single place where collection paths are spelled out, so a typo cannot creep
/// into one repository and not another.
class FirestoreRefs {
  const FirestoreRefs(this._db);

  final FirebaseFirestore _db;

  CollectionReference<Map<String, dynamic>> get users =>
      _db.collection('users');

  DocumentReference<Map<String, dynamic>> user(String uid) => users.doc(uid);

  CollectionReference<Map<String, dynamic>> get houses =>
      _db.collection('houses');

  DocumentReference<Map<String, dynamic>> house(String houseId) =>
      houses.doc(houseId);

  CollectionReference<Map<String, dynamic>> wasteConfigs(String houseId) =>
      house(houseId).collection('wasteConfigs');

  CollectionReference<Map<String, dynamic>> collections(String houseId) =>
      house(houseId).collection('collections');

  CollectionReference<Map<String, dynamic>> maintenances(String houseId) =>
      house(houseId).collection('maintenances');

  CollectionReference<Map<String, dynamic>> maintenanceLog(String houseId) =>
      house(houseId).collection('maintenanceLog');

  CollectionReference<Map<String, dynamic>> get invites =>
      _db.collection('invites');

  DocumentReference<Map<String, dynamic>> invite(String code) =>
      invites.doc(code);

  WriteBatch batch() => _db.batch();
}
