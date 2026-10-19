import 'package:flutter/material.dart';

import '../app/design.dart';

/// Shows a modal sheet that stays clear of the system bars.
///
/// Every sheet in the app goes through here. `showModalBottomSheet` applies
/// `SafeArea(bottom: false)` internally — it deliberately extends the sheet
/// under the navigation bar — so on a gesture-navigation phone the last
/// control ends up behind the bar and untappable. The padding below restores
/// that inset.
///
/// The order matters: the keyboard inset is applied outside the [SafeArea],
/// because when the keyboard is open Flutter zeroes `padding.bottom` and moves
/// the space into `viewInsets`. Nesting them this way adds whichever one is
/// actually present, and never both.
///
/// The sheet belongs to the functional layer, so it is a pane of glass with the
/// largest corner radius in the app, and the content behind it stays visible
/// through the blur. The drag handle is drawn inside that pane rather than by
/// `showModalBottomSheet`: the framework puts its own handle above the builder's
/// widget, which with a transparent sheet background would leave it floating
/// over the page underneath with nothing behind it to read against.
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  backgroundColor: Colors.transparent,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: GlassSurface(
      blur: 30,
      borderRadius: const BorderRadius.vertical(
        top: Radius.circular(AppRadius.sheet),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _DragHandle(),
            Flexible(child: builder(context)),
          ],
        ),
      ),
    ),
  ),
);

class _DragHandle extends StatelessWidget {
  const _DragHandle();

  @override
  Widget build(BuildContext context) => Semantics(
    label: 'Trascina per chiudere',
    child: Container(
      margin: const EdgeInsets.only(top: 12, bottom: 4),
      width: 36,
      height: 4,
      decoration: BoxDecoration(
        color: Theme.of(
          context,
        ).colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(2),
      ),
    ),
  );
}
