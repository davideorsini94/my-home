class AppUser {
  const AppUser({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl,
  });

  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;

  /// Falls back to the email local part so the history never shows a blank
  /// "registrata da".
  String get shortName {
    if (displayName.trim().isNotEmpty) return displayName.trim();
    final at = email.indexOf('@');
    return at > 0 ? email.substring(0, at) : 'Utente';
  }

  Map<String, Object?> toMap() => {
    'displayName': displayName,
    'email': email,
    if (photoUrl != null) 'photoUrl': photoUrl,
  };
}
