enum HouseRole {
  owner,
  member;

  static HouseRole fromId(String? id) =>
      id == 'owner' ? HouseRole.owner : HouseRole.member;

  String get label => this == HouseRole.owner ? 'Proprietario' : 'Membro';
}

class House {
  const House({
    required this.id,
    required this.name,
    required this.ownerUid,
    required this.members,
    required this.memberNames,
    this.activeInviteCode,
    this.createdAt,
  });

  final String id;
  final String name;
  final String ownerUid;

  /// uid -> role. Lives on the house document so security rules can check
  /// membership from `resource.data` without an extra read.
  final Map<String, HouseRole> members;

  /// uid -> display name, denormalised here on purpose: the rules keep
  /// `users/{uid}` readable only by its owner, so this is the only way one
  /// member can see another's name without opening up the profile collection.
  final Map<String, String> memberNames;

  /// The invite code currently handed out for this house, if any, so the
  /// members screen can show and revoke it.
  final String? activeInviteCode;

  final DateTime? createdAt;

  List<String> get memberUids => members.keys.toList();
  bool isOwner(String uid) => ownerUid == uid;
  bool isMember(String uid) => members.containsKey(uid);

  /// Members ordered with the owner first, then alphabetically.
  List<HouseMember> get memberList {
    final list = [
      for (final entry in members.entries)
        HouseMember(
          uid: entry.key,
          role: entry.value,
          displayName: memberNames[entry.key],
        ),
    ];
    list.sort((a, b) {
      if (a.role != b.role) return a.role == HouseRole.owner ? -1 : 1;
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return list;
  }
}

class HouseMember {
  const HouseMember({required this.uid, required this.role, this.displayName});

  final String uid;
  final HouseRole role;
  final String? displayName;

  String get label =>
      displayName?.trim().isNotEmpty == true ? displayName!.trim() : 'Utente';

  String get initials {
    final parts = label.split(RegExp(r'\s+')).where((p) => p.isNotEmpty);
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.characters1();
    return '${parts.first.characters1()}${parts.last.characters1()}';
  }
}

extension on String {
  String characters1() => isEmpty ? '' : substring(0, 1).toUpperCase();
}
