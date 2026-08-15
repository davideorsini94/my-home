import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/date_format_it.dart';
import '../../core/local_date.dart';
import '../../core/waste_catalogue.dart';
import '../../domain/entities/house.dart';
import '../../domain/entities/waste_config.dart';
import '../../domain/quota_calculator.dart';
import '../../domain/schedule_engine.dart';
import '../../widgets/async_view.dart';

class HouseListScreen extends ConsumerWidget {
  const HouseListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final houses = ref.watch(myHousesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Le mie abitazioni'),
        actions: [
          IconButton(
            tooltip: 'Unisciti con un codice',
            icon: const Icon(Icons.group_add_outlined),
            onPressed: () => context.go('/join'),
          ),
          IconButton(
            tooltip: 'Impostazioni',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => context.go('/settings'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/house/new'),
        icon: const Icon(Icons.add_home_outlined),
        label: const Text('Nuova abitazione'),
      ),
      body: SafeArea(
        top: false,
        child: AsyncView(
          value: houses,
          onRetry: () => ref.invalidate(myHousesProvider),
          builder: (context, list) {
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.home_outlined,
                title: 'Nessuna abitazione',
                message:
                    'Crea la tua prima abitazione, oppure unisciti a una '
                    'esistente con il codice di invito che ti hanno condiviso.',
                action: OutlinedButton.icon(
                  onPressed: () => context.go('/join'),
                  icon: const Icon(Icons.group_add_outlined),
                  label: const Text('Unisciti con un codice'),
                ),
              );
            }

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _HouseCard(house: list[index]),
            );
          },
        ),
      ),
    );
  }
}

/// Per-type collection counts for the current year, as coloured pills.
///
/// Reads the same year ledger the dashboard uses, so the number here and the
/// number inside the house can never disagree.
class _YearSummary extends ConsumerWidget {
  const _YearSummary({required this.houseId, required this.configs});

  final String houseId;
  final List<WasteConfig> configs;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final events = ref.watch(currentYearCollectionsProvider(houseId));

    return AnimatedSize(
      duration: const Duration(milliseconds: 150),
      alignment: Alignment.topLeft,
      child: events.when(
        loading: () => _pills(context, null),
        error: (_, _) => Text(
          'Conteggi non disponibili',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        data: (list) => _pills(context, countByType(list, LocalDate.today().year)),
      ),
    );
  }

  Widget _pills(BuildContext context, Map<WasteType, int>? counts) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      for (final config in configs)
        _CountPill(
          type: config.type,
          // Null while loading, so the pill shows a placeholder rather than a
          // zero that would briefly read as "nothing collected".
          count: counts?[config.type] ?? (counts == null ? null : 0),
        ),
    ],
  );
}

class _CountPill extends StatelessWidget {
  const _CountPill({required this.type, required this.count});

  final WasteType type;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = type.colorFor(theme.brightness);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(type.icon, size: 15, color: color),
          const SizedBox(width: 5),
          Text(
            count?.toString() ?? '–',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }
}

class _HouseCard extends ConsumerWidget {
  const _HouseCard({required this.house});

  final House house;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final configs = ref.watch(wasteConfigsProvider(house.id)).value ?? const [];
    final enabled = configs.where((c) => c.enabled).toList();
    final today = LocalDate.today();

    // The soonest upcoming pickup across every monitored type.
    final upcoming =
        enabled
            .expand(
              (c) => nextPickups(c, today, count: 1).map((d) => (c.type, d)),
            )
            .toList()
          ..sort((a, b) => a.$2.compareTo(b.$2));

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.go('/house/${house.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      house.name,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                house.members.length == 1
                    ? 'Solo tu'
                    : '${house.members.length} membri',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              if (enabled.isEmpty)
                Text(
                  'Nessun rifiuto monitorato',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                )
              else ...[
                Text(
                  'Raccolte ${today.year}',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 8),
                _YearSummary(houseId: house.id, configs: enabled),
                if (upcoming.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.event_outlined,
                        size: 15,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Prossimo ritiro: ${upcoming.first.$1.label} '
                          '${formatRelative(upcoming.first.$2, today)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}
