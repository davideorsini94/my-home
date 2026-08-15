import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/entities/app_user.dart';
import 'firestore_refs.dart';

class AuthException implements Exception {
  const AuthException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// Google-only authentication.
///
/// On Android the web OAuth client id is read from `google-services.json`
/// (the `client_type: 3` entry that appears once Google Sign-In is enabled in
/// the Firebase console), so [GoogleSignIn.initialize] needs no arguments.
class AuthRepository {
  AuthRepository({
    required FirebaseAuth auth,
    required FirestoreRefs refs,
    GoogleSignIn? googleSignIn,
  }) : _auth = auth,
       _refs = refs,
       _google = googleSignIn ?? GoogleSignIn.instance;

  final FirebaseAuth _auth;
  final FirestoreRefs _refs;
  final GoogleSignIn _google;

  bool _googleInitialized = false;

  Stream<AppUser?> authStateChanges() =>
      _auth.authStateChanges().map(_toAppUser);

  AppUser? get currentUser => _toAppUser(_auth.currentUser);

  AppUser? _toAppUser(User? user) {
    if (user == null) return null;
    return AppUser(
      uid: user.uid,
      displayName: user.displayName ?? '',
      email: user.email ?? '',
      photoUrl: user.photoURL,
    );
  }

  Future<void> _ensureGoogleInitialized() async {
    if (_googleInitialized) return;
    await _google.initialize();
    _googleInitialized = true;
  }

  Future<AppUser> signInWithGoogle() async {
    await _ensureGoogleInitialized();

    if (!_google.supportsAuthenticate()) {
      throw const AuthException(
        'Accesso con Google non supportato su questo dispositivo.',
      );
    }

    final GoogleSignInAccount account;
    try {
      account = await _google.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthException('Accesso annullato.');
      }
      throw AuthException('Accesso con Google non riuscito: ${e.code.name}.');
    }

    final idToken = account.authentication.idToken;
    if (idToken == null) {
      throw const AuthException(
        'Google non ha restituito le credenziali. Verifica la configurazione '
        'del progetto Firebase (impronta SHA-1).',
      );
    }

    try {
      final credential = GoogleAuthProvider.credential(idToken: idToken);
      final result = await _auth.signInWithCredential(credential);
      final user = _toAppUser(result.user);
      if (user == null) throw const AuthException('Accesso non riuscito.');
      await _upsertProfile(user);
      return user;
    } on FirebaseAuthException catch (e) {
      throw AuthException(_messageFor(e));
    }
  }

  /// Mirrors the profile into Firestore so the history can show who recorded a
  /// collection even for members whose account we cannot read from the client.
  Future<void> _upsertProfile(AppUser user) async {
    try {
      await _refs.user(user.uid).set({
        ...user.toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } on FirebaseException {
      // A stale profile must never block sign-in; it is refreshed next launch.
    }
  }

  Future<void> signOut() async {
    try {
      await _google.signOut();
    } on Exception {
      // Signing out of Firebase is what matters; the Google session may already
      // be gone.
    }
    await _auth.signOut();
  }

  String _messageFor(FirebaseAuthException e) => switch (e.code) {
    'account-exists-with-different-credential' =>
      'Esiste già un account con questa email, creato con un altro metodo di accesso.',
    'invalid-credential' => 'Credenziali Google non valide o scadute.',
    'user-disabled' => 'Questo account è stato disabilitato.',
    'network-request-failed' =>
      'Nessuna connessione. Controlla la rete e riprova.',
    'operation-not-allowed' =>
      'Accesso con Google non abilitato nel progetto Firebase.',
    _ => 'Accesso non riuscito (${e.code}).',
  };
}
