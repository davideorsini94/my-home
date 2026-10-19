/// The design tokens and the glass material the whole interface is built from.
///
/// The vocabulary comes from Apple's Liquid Glass guidance, adapted to what
/// Flutter can actually draw. Two rules from that guidance shape everything
/// here, and both are easy to get wrong:
///
/// 1. Glass belongs to the *functional* layer — bars, sheets, floating
///    controls — and must stay out of the content layer. Apple is explicit
///    that glass in the content layer "can result in unnecessary complexity
///    and a confusing visual hierarchy". So cards and lists in this app are
///    ordinary surfaces; only what floats above them is glass.
/// 2. Use it sparingly. Glass exists to draw attention to the content beneath
///    it, so every extra pane of it works against the content.
///
/// Flutter renders its own widget tree and cannot call SwiftUI's `glassEffect`,
/// so [GlassSurface] approximates the material from the pieces Flutter does
/// have: a backdrop blur, a tint that lifts or drops the luminosity of whatever
/// shows through, and a hairline highlight along the lit edge.
library;

import 'dart:ui';

import 'package:flutter/material.dart';

/// Corner radii.
///
/// Nested shapes are concentric with their container: an inner radius is the
/// outer radius minus the padding between the two. [concentric] writes that
/// arithmetic down instead of leaving it to be eyeballed, which is what keeps
/// an avatar inside a card from looking either boxy or over-rounded.
abstract final class AppRadius {
  /// Sheets sit at the top of the stack and carry the largest curvature.
  static const sheet = 28.0;
  static const card = 22.0;
  static const control = 16.0;
  static const field = 14.0;
  static const chip = 14.0;

  /// A shape nested inside [outer] with [padding] between the two edges.
  static double concentric(double outer, double padding) =>
      (outer - padding).clamp(4.0, outer);

  static BorderRadius all(double radius) => BorderRadius.circular(radius);
}

/// Vertical and horizontal rhythm.
///
/// Liquid Glass gives lists and forms more room than before — taller rows,
/// more padding — so the content can breathe under the floating layer.
abstract final class AppSpacing {
  static const screenH = 16.0;
  static const cardPadding = 18.0;
  static const rowGap = 12.0;
  static const sectionGap = 28.0;
}

/// How opaque the glass is, per brightness.
///
/// The regular variant of Liquid Glass "blurs and adjusts the luminosity of
/// background content to maintain legibility". Dark mode can afford to be more
/// transparent because light text over a darkened blur stays readable; light
/// mode needs more body or dark content scrolling underneath bleeds through as
/// grey smears behind the title.
double _glassAlpha(Brightness brightness) =>
    brightness == Brightness.dark ? 0.66 : 0.76;

/// A pane of the functional layer: translucent, blurred, floating over content.
///
/// Honours high contrast by dropping to a solid surface. Flutter does not
/// expose iOS's "Reduce Transparency" switch, so "Increase Contrast" is the
/// nearest signal available, and it is the one that matters most for keeping
/// controls legible.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.child,
    this.borderRadius = BorderRadius.zero,
    this.blur = 24,
    this.tint,
    this.highlightEdge = true,
  });

  final Widget child;
  final BorderRadius borderRadius;
  final double blur;

  /// Overrides the neutral tint. Apple asks for colour in the functional layer
  /// to be judicious and meaningful, so this stays null almost everywhere.
  final Color? tint;

  /// The lit rim along the top edge, which is what reads as "glass" rather than
  /// "translucent rectangle". Dropped where panes meet, to avoid a double line.
  final bool highlightEdge;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = tint ?? scheme.surface;

    if (MediaQuery.highContrastOf(context)) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: base,
          borderRadius: borderRadius,
          border: Border.all(color: scheme.outline),
        ),
        child: child,
      );
    }

    final isDark = theme.brightness == Brightness.dark;

    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: borderRadius,
            // A vertical lift rather than a flat wash: glass catches more light
            // where it faces the viewer, and the gradient is what keeps a wide
            // bar from looking like frosted plastic.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                base.withValues(alpha: _glassAlpha(theme.brightness)),
                base.withValues(alpha: _glassAlpha(theme.brightness) - 0.08),
              ],
            ),
            border: highlightEdge
                ? Border.all(
                    color: isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.white.withValues(alpha: 0.55),
                    width: 0.5,
                  )
                : null,
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The fade that keeps a bar legible while content slides under it.
///
/// Apple calls this the scroll edge effect: content approaching a bar is
/// blurred and loses opacity so the bar's own text never has to compete with
/// it. System bars get it for free; a custom one has to draw it.
class ScrollEdgeEffect extends StatelessWidget {
  const ScrollEdgeEffect({
    super.key,
    this.height = 28,
    this.alignment = Alignment.topCenter,
  });

  final double height;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.highContrastOf(context)) return const SizedBox.shrink();
    final surface = Theme.of(context).colorScheme.surface;
    final fromTop = alignment == Alignment.topCenter;

    return IgnorePointer(
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: fromTop ? Alignment.topCenter : Alignment.bottomCenter,
              end: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
              colors: [
                surface.withValues(alpha: 0.55),
                surface.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A screen whose bar floats in glass over content that scrolls beneath it.
///
/// Apple's guidance is that content extends behind the bars rather than being
/// cut off by an opaque one — that is the whole point of the material: you can
/// see what you are scrolling past. Two things follow, and both live here so no
/// screen has to remember them:
///
/// * the glass pane is painted at the top of the body, underneath the bar's own
///   title and buttons, so the blur samples the scrolling content rather than a
///   flat bar colour;
/// * the body's [MediaQuery] top padding is widened by the bar height, and
///   [glassListPadding] reads it back. Getting this pair wrong hides the first
///   row of every list behind the title, which is why the two sit together.
///
/// Takes the [AppBar] each screen already builds, rather than a title and a
/// list of actions, so adopting it is a rename and the bars keep whatever they
/// each need — a popup menu, a live house name, a back button.
///
/// [body] is a builder, not a widget, and deliberately so: the widened padding
/// only exists below this widget, and a screen that built its body with its own
/// `build` context would read the original inset and slide its first row under
/// the bar. Handing the body a context from inside makes that mistake
/// impossible to write rather than merely documented.
class GlassScaffold extends StatelessWidget {
  const GlassScaffold({
    super.key,
    required this.body,
    this.appBar,
    this.floatingActionButton,
    this.floatingActionButtonLocation,
  });

  final PreferredSizeWidget? appBar;
  final WidgetBuilder body;
  final Widget? floatingActionButton;
  final FloatingActionButtonLocation? floatingActionButtonLocation;

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final topInset = media.padding.top + (appBar?.preferredSize.height ?? 0);

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: appBar,
      floatingActionButton: floatingActionButton,
      floatingActionButtonLocation: floatingActionButtonLocation,
      body: Stack(
        children: [
          MediaQuery(
            data: media.copyWith(
              padding: media.padding.copyWith(top: topInset),
            ),
            child: Builder(builder: body),
          ),
          if (appBar != null)
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Column(
                  children: [
                    SizedBox(
                      height: topInset,
                      child: const GlassSurface(
                        highlightEdge: false,
                        child: SizedBox.expand(),
                      ),
                    ),
                    const ScrollEdgeEffect(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Padding for a scrolling body inside a [GlassScaffold].
///
/// The top inset already carries the status bar plus the bar height, because
/// [GlassScaffold] put it there.
EdgeInsets glassListPadding(
  BuildContext context, {
  double horizontal = AppSpacing.screenH,
  double bottom = 24,
  double extraTop = 8,
}) => EdgeInsets.fromLTRB(
  horizontal,
  MediaQuery.paddingOf(context).top + extraTop,
  horizontal,
  bottom,
);
