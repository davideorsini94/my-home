import 'package:flutter/material.dart';

/// The fixed catalogue of waste types. Stored in Firestore as the enum [name],
/// so these identifiers are part of the persisted data format — never rename.
enum WasteType {
  indifferenziato,
  carta,
  plastica,
  umido,
  verde,
  vetro;

  String get id => name;

  static WasteType? fromId(String? id) {
    if (id == null) return null;
    for (final t in WasteType.values) {
      if (t.name == id) return t;
    }
    return null;
  }
}

/// Presentation metadata for a waste type.
///
/// Colour is never the only channel: every type also carries a distinct icon,
/// because [WasteType.umido] and [WasteType.verde] are both browns and would be
/// hard to tell apart for colour-blind users or in low light.
class WasteTypeInfo {
  const WasteTypeInfo({
    required this.label,
    required this.lightColor,
    required this.darkColor,
    required this.icon,
  });

  final String label;
  final Color lightColor;
  final Color darkColor;
  final IconData icon;

  Color colorFor(Brightness brightness) =>
      brightness == Brightness.dark ? darkColor : lightColor;
}

const Map<WasteType, WasteTypeInfo> wasteCatalogue = {
  // Requested "grigio scuro tendente al nero". Near-black is invisible against
  // dark surfaces, so dark mode uses a light cool grey that reads as the same
  // neutral identity.
  WasteType.indifferenziato: WasteTypeInfo(
    label: 'Indifferenziato',
    lightColor: Color(0xFF424242),
    darkColor: Color(0xFFB0BEC5),
    icon: Icons.delete_outline,
  ),
  WasteType.carta: WasteTypeInfo(
    label: 'Carta',
    lightColor: Color(0xFF0288D1),
    darkColor: Color(0xFF4FC3F7),
    icon: Icons.description_outlined,
  ),
  // Pure yellow fails contrast on white, so light mode uses a dark amber.
  WasteType.plastica: WasteTypeInfo(
    label: 'Plastica',
    lightColor: Color(0xFFF9A825),
    darkColor: Color(0xFFFDD835),
    icon: Icons.local_drink_outlined,
  ),
  WasteType.umido: WasteTypeInfo(
    label: 'Umido',
    lightColor: Color(0xFF5D4037),
    darkColor: Color(0xFFBCAAA4),
    icon: Icons.compost_outlined,
  ),
  // "Marrone chiaro": pulled towards camel so it does not collide with Umido.
  WasteType.verde: WasteTypeInfo(
    label: 'Verde leggero',
    lightColor: Color(0xFFA0703B),
    darkColor: Color(0xFFD7B98E),
    icon: Icons.grass_outlined,
  ),
  WasteType.vetro: WasteTypeInfo(
    label: 'Vetro',
    lightColor: Color(0xFF2E7D32),
    darkColor: Color(0xFF81C784),
    icon: Icons.wine_bar_outlined,
  ),
};

extension WasteTypeDisplay on WasteType {
  WasteTypeInfo get info => wasteCatalogue[this]!;
  String get label => info.label;
  IconData get icon => info.icon;
  Color colorFor(Brightness brightness) => info.colorFor(brightness);
}
