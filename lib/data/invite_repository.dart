import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';

import '../domain/entities/house.dart';
import '../domain/entities/invite.dart';
import 'firestore_refs.dart';

class InviteException implements Exception {
  const InviteException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// House sharing by invite code.
///
/// The whole flow runs on the free Spark plan: no Cloud Function is involved.
/// The joining user proves possession of the code by writing it into the house
/// document's `joinProof` field, and the security rules verify server-side that
/// the code exists, points at that house and has not expired.
class InviteRepository {
  const InviteRepository(this._refs);

  final FirestoreRefs _refs;

  /// Deliberately excludes 0/O/1/I/L, which get misread when a code is spoken
  /// aloud or copied by hand.
  static const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const _codeLength = 6;
  static const inviteValidity = Duration(days: 7);

  /// Creates an invite for a house and records it as the active code.
  ///
  /// Uses a create-only write so a collision with an existing code fails rather
  /// than hijacking someone else's invite; on collision it simply retries.
  Future<Invite> createInvite({
    required String houseId,
    required String houseName,
    required String createdByUid,
  }) async {
    final random = Random.secure();
    final expiresAt = DateTime.now().add(inviteValidity);

    for (var attempt = 0; attempt < 8; attempt++) {
      final code = List.generate(
        _codeLength,
        (_) => _alphabet[random.nextInt(_alphabet.length)],
      ).join();

      try {
        await _refs.invite(code).set({
          'houseId': houseId,
          'houseName': houseName,
          'createdBy': createdByUid,
          'createdAt': FieldValue.serverTimestamp(),
          'expiresAt': Timestamp.fromDate(expiresAt),
        });
        await _refs.house(houseId).update({'activeInviteCode': code});
        return Invite(
          code: code,
          houseId: houseId,
          houseName: houseName,
          createdBy: createdByUid,
          expiresAt: expiresAt,
        );
      } on FirebaseException catch (e) {
        // A taken code is rejected by the rules' create-only constraint.
        if (e.code == 'permission-denied' || e.code == 'already-exists') {
          continue;
        }
        rethrow;
      }
    }
    throw const InviteException(
      'Non è stato possibile generare un codice. Riprova.',
    );
  }

  Future<Invite?> lookup(String code) async {
    final normalized = normalizeCode(code);
    if (normalized.length != _codeLength) return null;

    final doc = await _refs.invite(normalized).get();
    if (!doc.exists) return null;
    final data = doc.data()!;
    final expiresAt = (data['expiresAt'] as Timestamp?)?.toDate();
    if (expiresAt == null) return null;

    return Invite(
      code: normalized,
      houseId: data['houseId'] as String? ?? '',
      houseName: data['houseName'] as String? ?? 'Abitazione',
      createdBy: data['createdBy'] as String? ?? '',
      expiresAt: expiresAt,
    );
  }

  /// Adds the current user to the house named by the invite.
  ///
  /// This is a single update on the house document; the rules allow it only if
  /// the caller adds nobody but themselves, with the `member` role, and
  /// `joinProof` names a live invite for that house.
  Future<void> joinHouse({
    required Invite invite,
    required String uid,
    required String userName,
  }) async {
    try {
      await _refs.house(invite.houseId).update({
        'members.$uid': HouseRole.member.name,
        'memberUids': FieldValue.arrayUnion([uid]),
        'memberNames.$uid': userName,
        'joinProof': invite.code,
      });
    } on FirebaseException catch (e) {
      if (e.code == 'permission-denied') {
        throw const InviteException(
          'Codice non valido o scaduto, oppure fai già parte di questa abitazione.',
        );
      }
      rethrow;
    }
  }

  Future<void> revokeInvite({
    required String code,
    required String houseId,
  }) async {
    await _refs.invite(code).delete();
    await _refs.house(houseId).update({'activeInviteCode': null});
  }

  static String normalizeCode(String raw) =>
      raw.toUpperCase().replaceAll(RegExp('[^A-Z0-9]'), '');
}
