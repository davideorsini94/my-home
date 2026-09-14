import '../../core/maintenance_icons.dart';

/// The unit a maintenance recurrence is expressed in.
///
/// Each carries its own cap. The caps are not arbitrary tidiness: without them
/// a recurrence of 1000 years pushes computed dates past year 9999, where
/// `LocalDate.toKey()` produces an 11-character string that the security rules
/// reject and `LocalDate.parse` refuses to read back.
enum RecurrenceUnit {
  days(maxEvery: 3660),
  weeks(maxEvery: 520),
  months(maxEvery: 600),
  years(maxEvery: 50);

  const RecurrenceUnit({required this.maxEvery});

  final int maxEvery;

  /// Null — never a silent default — for an id this client does not know.
  /// Mapping an unknown unit onto `months` would make an older client compute
  /// wrong due dates and write skips keyed to them, corrupting shared data.
  static RecurrenceUnit? fromId(String? id) {
    for (final unit in RecurrenceUnit.values) {
      if (unit.name == id) return unit;
    }
    return null;
  }

  String label(int every) => switch (this) {
    RecurrenceUnit.days => every == 1 ? 'giorno' : 'giorni',
    RecurrenceUnit.weeks => every == 1 ? 'settimana' : 'settimane',
    RecurrenceUnit.months => every == 1 ? 'mese' : 'mesi',
    RecurrenceUnit.years => every == 1 ? 'anno' : 'anni',
  };
}

class Recurrence {
  /// The assert documents intent but is stripped in release builds, so it is
  /// not the gate. [Recurrence.clamped] is what every UI path goes through and
  /// the security rules are what actually stop a bad value reaching Firestore.
  Recurrence({required this.every, required this.unit})
    : assert(
        every >= 1 && every <= unit.maxEvery,
        'every must be between 1 and ${unit.maxEvery} for $unit',
      );

  final int every;
  final RecurrenceUnit unit;

  /// The release-safe constructor: forces [every] into the unit's range instead
  /// of trusting the caller.
  factory Recurrence.clamped(int every, RecurrenceUnit unit) => Recurrence(
    every: every < 1 ? 1 : (every > unit.maxEvery ? unit.maxEvery : every),
    unit: unit,
  );

  Map<String, Object?> toMap() => {'every': every, 'unit': unit.name};

  /// Null when the unit is unknown to this client — see [RecurrenceUnit.fromId].
  static Recurrence? fromMap(Map<String, Object?>? map) {
    if (map == null) return null;
    final unit = RecurrenceUnit.fromId(map['unit'] as String?);
    if (unit == null) return null;
    final every = (map['every'] as num?)?.toInt() ?? 1;
    return Recurrence.clamped(every, unit);
  }

  /// "ogni 6 mesi", "ogni anno"
  String get label =>
      every == 1 ? 'ogni ${unit.label(1)}' : 'ogni $every ${unit.label(every)}';

  @override
  bool operator ==(Object other) =>
      other is Recurrence && other.every == every && other.unit == unit;

  @override
  int get hashCode => Object.hash(every, unit);

  @override
  String toString() => label;
}

/// A phone contact copied into the app.
///
/// Deliberately a copy rather than a device address-book reference: the house
/// is shared, and a reference would resolve to nothing on another member's
/// phone. The address-book picker only prefills these two fields.
class MaintenanceContact {
  const MaintenanceContact({this.name, required this.phone});

  final String? name;
  final String phone;

  /// What the call confirmation refers to: the name when we have one, the
  /// number otherwise, so the dialog is never vague about who is being called.
  String get label => name?.trim().isNotEmpty == true ? name!.trim() : phone;

  bool get hasName => name?.trim().isNotEmpty == true;

  Map<String, Object?> toMap() => {
    if (hasName) 'name': name!.trim(),
    'phone': phone,
  };

  static MaintenanceContact? fromMap(Map<String, Object?>? map) {
    final phone = (map?['phone'] as String?)?.trim();
    if (phone == null || phone.isEmpty) return null;
    return MaintenanceContact(name: map?['name'] as String?, phone: phone);
  }
}

/// A recurring home maintenance task belonging to a house.
///
/// Note what is NOT here: there is no `nextDueDate` and no `lastDoneDate`.
/// Both are derived from the execution ledger, for the same reason the waste
/// counters are derived — a stored value would need a compensating write on
/// every edit, and one missed pairing would drift with no source of truth to
/// repair it from.
class Maintenance {
  const Maintenance({
    required this.id,
    required this.name,
    required this.iconKey,
    required this.recurrence,
    this.notes,
    this.costCents,
    this.contact,
    this.createdAt,
    this.hasPendingWrites = false,
  });

  final String id;
  final String name;

  /// A stable string key, never an icon codepoint: codepoints shift between
  /// Flutter versions and icon tree-shaking keys off them.
  final String iconKey;

  /// Null means this client cannot interpret the stored recurrence. The
  /// maintenance stays visible and executable, but computes no due date — see
  /// [RecurrenceUnit.fromId].
  final Recurrence? recurrence;

  final String? notes;

  /// Cents, so money never goes through a double. Null renders as "N.D.".
  final int? costCents;

  final MaintenanceContact? contact;
  final DateTime? createdAt;
  final bool hasPendingWrites;

  bool get hasUnknownRecurrence => recurrence == null;
  bool get canCall => contact != null;
  MaintenanceIcon get icon => maintenanceIconFor(iconKey);

  Map<String, Object?> toMap() => {
    'name': name,
    'iconKey': iconKey,
    if (recurrence != null) 'recurrence': recurrence!.toMap(),
    if (notes != null && notes!.isNotEmpty) 'notes': notes,
    if (costCents != null) 'costCents': costCents,
    if (contact != null) 'contact': contact!.toMap(),
  };

  Maintenance copyWith({
    String? name,
    String? iconKey,
    Recurrence? recurrence,
    String? notes,
    int? costCents,
    MaintenanceContact? contact,
    bool clearNotes = false,
    bool clearCost = false,
    bool clearContact = false,
  }) => Maintenance(
    id: id,
    name: name ?? this.name,
    iconKey: iconKey ?? this.iconKey,
    recurrence: recurrence ?? this.recurrence,
    notes: clearNotes ? null : (notes ?? this.notes),
    costCents: clearCost ? null : (costCents ?? this.costCents),
    contact: clearContact ? null : (contact ?? this.contact),
    createdAt: createdAt,
    hasPendingWrites: hasPendingWrites,
  );
}
