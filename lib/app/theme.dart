import 'package:flutter/material.dart';

import '../core/waste_catalogue.dart';

const _seed = Color(0xFF00796B);

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
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 48),
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
