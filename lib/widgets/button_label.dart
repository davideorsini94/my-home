import 'package:flutter/material.dart';

/// A button label that shrinks rather than wrapping.
///
/// Buttons that share a row get a half or a third of the card width, and a
/// Material label that does not fit wraps mid-word: "Modifica" came out as
/// "Modific / a". Scaling the text down keeps the word whole and, unlike any
/// fixed padding, it also absorbs the system font-size setting, which can make
/// every label half again as wide on a device the layout was never measured on.
///
/// The scale only kicks in when the label really is too wide: with room to
/// spare the text renders at its normal size, so side-by-side buttons stay
/// visually identical to standalone ones.
class ButtonLabel extends StatelessWidget {
  const ButtonLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => FittedBox(
    fit: BoxFit.scaleDown,
    child: Text(text, maxLines: 1, softWrap: false),
  );
}
