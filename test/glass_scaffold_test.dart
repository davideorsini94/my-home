import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:my_home/app/design.dart';
import 'package:my_home/app/theme.dart';

/// The bar floats over the content, so the body has to leave room for it. Get
/// this wrong and the first row of every list hides behind the title — which is
/// invisible in a widget test, silent in review, and obvious only on a device.
void main() {
  const statusBar = 59.0;

  Widget harness({required WidgetBuilder body}) => MaterialApp(
    theme: buildLightTheme(),
    home: GlassScaffold(
      appBar: AppBar(title: const Text('Titolo')),
      body: body,
    ),
  );

  testWidgets('the first item of a list clears the floating bar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: statusBar);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(
        body: (context) => ListView(
          padding: glassListPadding(context),
          children: const [
            SizedBox(key: Key('primo'), height: 40, width: double.infinity),
          ],
        ),
      ),
    );

    final top = tester.getRect(find.byKey(const Key('primo'))).top;
    expect(
      top,
      greaterThanOrEqualTo(statusBar + kToolbarHeight),
      reason: 'il primo elemento finisce sotto la barra in vetro',
    );
  });

  testWidgets('a body nested under a SafeArea still clears the bar', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.padding = const FakeViewPadding(top: statusBar, bottom: 34);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      harness(
        body: (context) => SafeArea(
          top: false,
          child: ListView(
            padding: glassListPadding(context),
            children: const [
              SizedBox(key: Key('primo'), height: 40, width: double.infinity),
            ],
          ),
        ),
      ),
    );

    expect(
      tester.getRect(find.byKey(const Key('primo'))).top,
      greaterThanOrEqualTo(statusBar + kToolbarHeight),
    );
  });
}
