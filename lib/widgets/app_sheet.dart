import 'package:flutter/material.dart';

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
Future<T?> showAppSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) => showModalBottomSheet<T>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (context) => Padding(
    padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
    child: SafeArea(top: false, child: builder(context)),
  ),
);
