import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../widgets/async_view.dart';

/// The maintenances of a house.
///
/// Registered from the moment the hub links to it, so the card never lands on
/// a "page not found". The list and its actions arrive in the next phase.
class MaintenanceListScreen extends ConsumerWidget {
  const MaintenanceListScreen({super.key, required this.houseId});

  final String houseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maintenances = ref.watch(maintenancesProvider(houseId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manutenzioni'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/house/$houseId'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: AsyncView(
          value: maintenances,
          onRetry: () => ref.invalidate(maintenancesProvider(houseId)),
          builder: (context, list) => const EmptyState(
            icon: Icons.build_outlined,
            title: 'Nessuna manutenzione',
            message:
                'Qui terrai traccia delle manutenzioni periodiche di casa — '
                'caldaia, climatizzatore, fossa biologica — con le loro '
                'scadenze, i costi e chi chiamare.',
          ),
        ),
      ),
    );
  }
}
