import 'package:flutter/material.dart';

import '../core/waste_catalogue.dart';

const _seed = Color(0xFF00796B);

const _buttonPadding = EdgeInsets.symmetric(horizontal: 16);

ThemeData buildLightTheme() => _build(Brightness.light);
ThemeData buildDarkTheme() => _build(Brightness.dark);

ThemeData _build(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    appBarTheme: AppBarTheme(
      backgroundColor: scheme.surface,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 2,
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    ),
    // The horizontal padding is tighter than the Material default of 24 on
    // each side: half of these buttons sit two or three to a row inside a card,
    // where 48 points of padding is most of the width a label has to live in.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: _buttonPadding,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: _buttonPadding,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 48),
        padding: _buttonPadding,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(),
      filled: true,
    ),
    dividerTheme: const DividerThemeData(space: 1),
  );
}

/// Resolves a waste type's colour for the current theme.
///
/// The catalogue keeps two values per type because the requested palette does
/// not survive a straight inversion: near-black Indifferenziato disappears on a
/// dark surface, and plain yellow Plastica fails contrast on a light one.
Color wasteColor(BuildContext context, WasteType type) =>
    type.colorFor(Theme.of(context).brightness);

/// A readable foreground for text laid over [background].
Color onWasteColor(Color background) =>
    background.computeLuminance() > 0.5 ? Colors.black87 : Colors.white;
