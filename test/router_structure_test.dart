import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

/// Mirrors the shape of the real route tree in `lib/app/router.dart`.
///
/// The real one cannot be instantiated here: it depends on Firebase-backed
/// providers. What is worth protecting is the SHAPE — which path wins, and
/// where the back button lands — because moving waste under the hub silently
/// changed both, and nothing else in the suite would notice a regression.
GoRouter buildTestRouter() => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      builder: (context, state) => const Text('houses'),
      routes: [
        GoRoute(
          path: 'house/new',
          builder: (context, state) => const Text('new house'),
        ),
        GoRoute(
          path: 'house/:houseId',
          builder: (context, state) =>
              Text('hub ${state.pathParameters['houseId']}'),
          routes: [
            GoRoute(
              path: 'members',
              builder: (context, state) => const Text('members'),
            ),
            GoRoute(
              path: 'waste',
              builder: (context, state) => const Text('waste dashboard'),
              routes: [
                GoRoute(
                  path: 'config',
                  builder: (context, state) => const Text('waste config'),
                  routes: [
                    GoRoute(
                      path: ':type',
                      builder: (context, state) =>
                          Text('config ${state.pathParameters['type']}'),
                    ),
                  ],
                ),
                GoRoute(
                  path: 'history',
                  builder: (context, state) => const Text('history'),
                ),
              ],
            ),
            GoRoute(
              path: 'maintenance',
              builder: (context, state) => const Text('maintenance list'),
              routes: [
                GoRoute(
                  path: 'new',
                  builder: (context, state) => const Text('maintenance form'),
                ),
                GoRoute(
                  path: ':maintenanceId/edit',
                  builder: (context, state) =>
                      Text('edit ${state.pathParameters['maintenanceId']}'),
                ),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

Future<void> pumpAt(WidgetTester tester, GoRouter router, String path) async {
  router.go(path);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('every level resolves to its own screen', (tester) async {
    final router = buildTestRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await pumpAt(tester, router, '/house/h1');
    expect(find.text('hub h1'), findsOneWidget);

    await pumpAt(tester, router, '/house/h1/waste');
    expect(find.text('waste dashboard'), findsOneWidget);

    await pumpAt(tester, router, '/house/h1/waste/config/carta');
    expect(find.text('config carta'), findsOneWidget);

    await pumpAt(tester, router, '/house/h1/maintenance');
    expect(find.text('maintenance list'), findsOneWidget);

    await pumpAt(tester, router, '/house/h1/maintenance/m1/edit');
    expect(find.text('edit m1'), findsOneWidget);
  });

  testWidgets('a literal segment still wins over the parameter', (
    tester,
  ) async {
    // `house/new` and `house/:houseId` both match "/house/new"; declaration
    // order decides, and reordering the tree could silently break creating a
    // house.
    final router = buildTestRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await pumpAt(tester, router, '/house/new');
    expect(find.text('new house'), findsOneWidget);
    expect(find.text('hub new'), findsNothing);

    await pumpAt(tester, router, '/house/h1/maintenance/new');
    expect(find.text('maintenance form'), findsOneWidget);
  });

  testWidgets('back walks up one level at a time', (tester) async {
    // Waste moved a level down when the hub took `/house/:houseId`, so the
    // stack a deep waste screen builds is exactly what this protects.
    final router = buildTestRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await pumpAt(tester, router, '/house/h1/waste/config/carta');
    expect(find.text('config carta'), findsOneWidget);

    for (final expected in [
      'waste config',
      'waste dashboard',
      'hub h1',
      'houses',
    ]) {
      await router.routerDelegate.popRoute();
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
    }
  });

  testWidgets('back from maintenance returns to the hub', (tester) async {
    final router = buildTestRouter();
    await tester.pumpWidget(MaterialApp.router(routerConfig: router));

    await pumpAt(tester, router, '/house/h1/maintenance/m1/edit');
    await router.routerDelegate.popRoute();
    await tester.pumpAndSettle();
    expect(find.text('maintenance list'), findsOneWidget);

    await router.routerDelegate.popRoute();
    await tester.pumpAndSettle();
    expect(find.text('hub h1'), findsOneWidget);
  });
}
