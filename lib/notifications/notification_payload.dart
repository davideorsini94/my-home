import 'dart:convert';

import '../core/local_date.dart';
import '../core/waste_catalogue.dart';

/// What a scheduled reminder carries, so that the action button can record the
/// collection without the app ever coming to the foreground.
class NotificationPayload {
  const NotificationPayload({
    required this.houseId,
    required this.dateKey,
    required this.types,
  });

  final String houseId;

  /// The pickup day, not the evening the reminder fires.
  final String dateKey;

  /// Every waste type collected that day for that house. A single evening
  /// reminder covers them all, and confirming records them all.
  final List<String> types;

  LocalDate get date => LocalDate.parse(dateKey);

  List<WasteType> get wasteTypes =>
      types.map(WasteType.fromId).whereType<WasteType>().toList();

  String encode() =>
      jsonEncode({'houseId': houseId, 'dateKey': dateKey, 'types': types});

  static NotificationPayload? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final map = jsonDecode(raw) as Map<String, dynamic>;
      final houseId = map['houseId'] as String?;
      final dateKey = map['dateKey'] as String?;
      if (houseId == null || dateKey == null) return null;
      if (LocalDate.tryParse(dateKey) == null) return null;
      final types = ((map['types'] as List?) ?? const [])
          .whereType<String>()
          .toList();
      return NotificationPayload(
        houseId: houseId,
        dateKey: dateKey,
        types: types,
      );
    } on FormatException {
      return null;
    }
  }
}
