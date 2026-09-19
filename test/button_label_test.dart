import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_home/app/theme.dart';
import 'package:my_home/widgets/button_label.dart';

/// The maintenance card's action row: three buttons sharing a card that is
/// itself inset inside a 360dp-wide phone.
Widget _threeUp({required Widget Function(String) label, double scale = 1.0}) {
  Widget button(String text) => Expanded(
    child: OutlinedButton(
      onPressed: () {},
      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
      child: label(text),
    ),
  );

  return MaterialApp(
    theme: buildLightTheme(),
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(scale)),
      child: Scaffold(
        body: Center(
          child: SizedBox(
            // 360dp screen − 16 list padding − 16 card padding, both sides.
            width: 296,
            child: Row(
              children: [
                button('Modifica'),
                const SizedBox(width: 8),
                button('Salta'),
                const SizedBox(width: 8),
                button('Esegui'),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

/// The height one line of this label would take, measured from the label that
/// is actually on screen so it carries the real style.
///
/// Measured rather than assumed because the test font is not the device font:
/// every glyph is a square em, so even "Salta" is too wide here to use as a
/// known-single-line yardstick.
double _singleLineHeight(WidgetTester tester, String text) {
  final paragraph = tester.renderObject<RenderParagraph>(find.text(text));
  final painter = TextPainter(
    text: paragraph.text,
    textDirection: TextDirection.ltr,
    textScaler: paragraph.textScaler,
    maxLines: 1,
  )..layout();
  return painter.height;
}

void main() {
  group('ButtonLabel', () {
    testWidgets('a plain label really does wrap in this layout', (
      tester,
    ) async {
      // The control case. If Material ever stops wrapping button labels this
      // fails, and the FittedBox below can go.
      await tester.pumpWidget(_threeUp(label: Text.new));

      final wrapped = tester.renderObject<RenderParagraph>(
        find.text('Modifica'),
      );
      expect(
        wrapped.size.height,
        greaterThan(_singleLineHeight(tester, 'Modifica')),
      );
    });

    testWidgets('keeps the longest label on one line', (tester) async {
      await tester.pumpWidget(_threeUp(label: ButtonLabel.new));

      final label = tester.renderObject<RenderParagraph>(find.text('Modifica'));
      expect(label.size.height, _singleLineHeight(tester, 'Modifica'));
    });

    testWidgets('paints the label inside its button', (tester) async {
      await tester.pumpWidget(_threeUp(label: ButtonLabel.new));

      final button = tester.getRect(find.byType(OutlinedButton).first);
      final label = tester.getRect(find.text('Modifica'));
      expect(label.width, lessThanOrEqualTo(button.width));
      expect(label.left, greaterThanOrEqualTo(button.left - 0.01));
      expect(label.right, lessThanOrEqualTo(button.right + 0.01));
    });

    testWidgets('survives a 1.5x system font size', (tester) async {
      await tester.pumpWidget(_threeUp(label: ButtonLabel.new, scale: 1.5));

      final button = tester.getRect(find.byType(OutlinedButton).first);
      final label = tester.getRect(find.text('Modifica'));
      expect(label.width, lessThanOrEqualTo(button.width));
      expect(
        tester.renderObject<RenderParagraph>(find.text('Modifica')).size.height,
        _singleLineHeight(tester, 'Modifica'),
      );
    });

    testWidgets('leaves a label that fits at full size', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: buildLightTheme(),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 296,
                child: OutlinedButton(
                  onPressed: () {},
                  child: const ButtonLabel('Modifica'),
                ),
              ),
            ),
          ),
        ),
      );

      final label = tester.renderObject<RenderParagraph>(find.text('Modifica'));
      expect(tester.getRect(find.text('Modifica')).width, label.size.width);
    });
  });
}
