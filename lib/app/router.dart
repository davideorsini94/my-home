import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/waste_catalogue.dart';
import '../features/auth/login_screen.dart';
import '../features/collections/history_screen.dart';
import '../features/dashboard/dashboard_screen.dart';
import '../features/houses/house_form_screen.dart';
import '../features/house_hub/house_hub_screen.dart';
import '../features/houses/house_list_screen.dart';
import '../features/maintenance/maintenance_form_screen.dart';
import '../features/maintenance/maintenance_list_screen.dart';
import '../features/members/join_house_screen.dart';
import '../features/members/members_screen.dart';
import '../features/settings/settings_screen.dart';
import '../features/statistics/statistics_screen.dart';
import '../features/waste_config/waste_config_edit_screen.dart';
import '../features/waste_config/waste_config_list_screen.dart';
import 'providers.dart';

/// Rebuilds the router's redirect whenever the auth state changes.
class _AuthListenable extends ChangeNotifier {
  _AuthListenable(this._ref) {
    _subscription = _ref.listen(authStateProvider, (_, _) => notifyListeners());
  }

  final Ref _ref;
  late final ProviderSubscription<Object?> _subscription;

  @override
  void dispose() {
    _subscription.close();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final listenable = _AuthListenable(ref);
  ref.onDispose(listenable.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: listenable,
    redirect: (context, state) {
      final auth = ref.read(authStateProvider);
      // Hold on the splash until Firebase has restored the session, otherwise
      // the login screen flashes on every cold start.
      if (auth.isLoading) {
        return state.matchedLocation == '/splash' ? null : '/splash';
      }

      final signedIn = auth.value != null;
      final atLogin = state.matchedLocation == '/login';
      final atSplash = state.matchedLocation == '/splash';

      if (!signedIn) return atLogin ? null : '/login';
      if (atLogin || atSplash) return '/';
      return null;
    },
    routes: [
      GoRoute(
        path: '/splash',
        builder: (context, state) => const _SplashScreen(),
      ),
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(
        path: '/',
        builder: (context, state) => const HouseListScreen(),
        routes: [
          GoRoute(
            path: 'settings',
            builder: (context, state) => const SettingsScreen(),
          ),
          GoRoute(
            path: 'join',
            builder: (context, state) =>
                JoinHouseScreen(initialCode: state.uri.queryParameters['code']),
          ),
          GoRoute(
            path: 'house/new',
            builder: (context, state) => const HouseFormScreen(),
          ),
          GoRoute(
            path: 'house/:houseId',
            builder: (context, state) =>
                HouseHubScreen(houseId: state.pathParameters['houseId']!),
            routes: [
              GoRoute(
                path: 'edit',
                builder: (context, state) =>
                    HouseFormScreen(houseId: state.pathParameters['houseId']),
              ),
              GoRoute(
                path: 'members',
                builder: (context, state) =>
                    MembersScreen(houseId: state.pathParameters['houseId']!),
              ),
              // Waste used to live at /house/:houseId itself; the hub took that
              // place, so everything about it moved one level down.
              GoRoute(
                path: 'waste',
                builder: (context, state) =>
                    DashboardScreen(houseId: state.pathParameters['houseId']!),
                routes: [
                  GoRoute(
                    path: 'config',
                    builder: (context, state) => WasteConfigListScreen(
                      houseId: state.pathParameters['houseId']!,
                    ),
                    routes: [
                      GoRoute(
                        path: ':type',
                        builder: (context, state) {
                          final type = WasteType.fromId(
                            state.pathParameters['type'],
                          );
                          if (type == null) return const _UnknownRouteScreen();
                          return WasteConfigEditScreen(
                            houseId: state.pathParameters['houseId']!,
                            type: type,
                          );
                        },
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'history',
                    builder: (context, state) => HistoryScreen(
                      houseId: state.pathParameters['houseId']!,
                    ),
                  ),
                  GoRoute(
                    path: 'stats',
                    builder: (context, state) => StatisticsScreen(
                      houseId: state.pathParameters['houseId']!,
                    ),
                  ),
                ],
              ),
              GoRoute(
                path: 'maintenance',
                builder: (context, state) => MaintenanceListScreen(
                  houseId: state.pathParameters['houseId']!,
                ),
                routes: [
                  // Declared before ':maintenanceId/edit' so the literal wins.
                  GoRoute(
                    path: 'new',
                    builder: (context, state) => MaintenanceFormScreen(
                      houseId: state.pathParameters['houseId']!,
                    ),
                  ),
                  GoRoute(
                    path: ':maintenanceId/edit',
                    builder: (context, state) => MaintenanceFormScreen(
                      houseId: state.pathParameters['houseId']!,
                      maintenanceId: state.pathParameters['maintenanceId'],
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    ],
    errorBuilder: (context, state) => const _UnknownRouteScreen(),
  );
});

class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _UnknownRouteScreen extends StatelessWidget {
  const _UnknownRouteScreen();

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Pagina non trovata')),
    body: SafeArea(
      top: false,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Questa pagina non esiste.'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => context.go('/'),
                child: const Text('Torna alle abitazioni'),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
