class Invite {
  const Invite({
    required this.code,
    required this.houseId,
    required this.houseName,
    required this.createdBy,
    required this.expiresAt,
  });

  final String code;
  final String houseId;
  final String houseName;
  final String createdBy;
  final DateTime expiresAt;

  bool get isExpired => DateTime.now().isAfter(expiresAt);
}
