import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/waste_catalogue.dart';
import 'design.dart';

const _seed = Color(0xFF00796B);

const _buttonPadding = EdgeInsets.symmetric(horizontal: 18);

ThemeData buildLightTheme() => _build(Brightness.light);
ThemeData buildDarkTheme() => _build(Brightness.dark);

ThemeData _build(Brightness brightness) {
  final scheme = ColorScheme.fromSeed(seedColor: _seed, brightness: brightness);
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: scheme.surface,
    // Bars carry no background of their own: GlassScaffold paints the glass
    // behind them, and a colour here would sit on top of the blur and flatten
    // it. Apple's advice for adopting the material is exactly this — remove
    // custom backgrounds from navigation elements and let the layer do its job.
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      foregroundColor: scheme.onSurface,
      centerTitle: false,
      elevation: 0,
      scrolledUnderElevation: 0,
      // With a transparent bar Flutter can no longer infer which status bar
      // icons to ask for, and it guessed light ones over our pale glass — the
      // clock came out nearly invisible. The glass always takes the tone of the
      // surface beneath it, so the answer follows the theme, not the bar.
      systemOverlayStyle: brightness == Brightness.light
          ? SystemUiOverlayStyle.dark.copyWith(
              statusBarColor: Colors.transparent,
            )
          : SystemUiOverlayStyle.light.copyWith(
              statusBarColor: Colors.transparent,
            ),
    ),
    // The content layer. Deliberately not glass: these are what the floating
    // layer is meant to let you see, and stacking glass on glass is the first
    // thing Apple's guidance warns against.
    cardTheme: CardThemeData(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: scheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.all(AppRadius.card),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
    ),
    // Taller rows, as the refreshed list metrics ask for: content needs room to
    // breathe once it is being read through a floating layer.
    listTileTheme: ListTileThemeData(
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      minVerticalPadding: 10,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.all(AppRadius.control),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      // Transparent so the sheet's own glass shows; the shape is applied by the
      // sheet body, which clips the blur to the same radius.
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      modalElevation: 0,
      // Drawn by showAppSheet instead, inside the glass pane: the framework's
      // handle is laid out above the builder's widget, which over a transparent
      // sheet would float on the page behind with nothing to read against.
      showDragHandle: false,
    ),
    dialogTheme: DialogThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.all(AppRadius.sheet),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.all(AppRadius.control),
      ),
    ),
    // Controls take rounder forms so they nestle into the curvature around
    // them. The horizontal padding is tighter than the Material default of 24
    // per side: half of these buttons sit two or three to a row inside a card,
    // where 48 points of padding is most of the width a label has to live in.
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 50),
        padding: _buttonPadding,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.all(AppRadius.control),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 50),
        padding: _buttonPadding,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.all(AppRadius.control),
        ),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        minimumSize: const Size(0, 50),
        padding: _buttonPadding,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.all(AppRadius.control),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.all(AppRadius.chip),
        ),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 3,
      highlightElevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.all(AppRadius.control + 4),
      ),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.all(AppRadius.chip),
      ),
      side: BorderSide(color: scheme.outlineVariant),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      border: OutlineInputBorder(
        borderRadius: AppRadius.all(AppRadius.field),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: AppRadius.all(AppRadius.field),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: AppRadius.all(AppRadius.field),
        borderSide: BorderSide(color: scheme.primary, width: 1.6),
      ),
    ),
    dividerTheme: DividerThemeData(
      space: 1,
      color: scheme.outlineVariant.withValues(alpha: 0.6),
    ),
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
