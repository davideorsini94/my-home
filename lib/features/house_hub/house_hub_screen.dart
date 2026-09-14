import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/date_format_it.dart';
import '../../core/local_date.dart';
import '../../core/waste_catalogue.dart';
import '../../domain/maintenance_schedule.dart';
import '../../domain/schedule_engine.dart';

/// What a house contains: waste management and home maintenance.
///
/// This screen took over `/house/:houseId`, which used to be the waste
/// dashboard directly. Each card carries a live one-line summary so the choice
/// is informed rather than blind — whether anything needs doing is exactly what
/// you open the house to find out.
class HouseHubScreen extends ConsumerWidget {
  const HouseHubScreen({super.key, required this.houseId});

  final String houseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final house = ref.watch(houseProvider(houseId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(house.value?.name ?? 'Abitazione'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) => context.go('/house/$houseId/$value'),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'members',
                child: ListTile(
                  leading: Icon(Icons.people_outline),
                  title: Text('Membri e condivisione'),
                ),
              ),
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Rinomina abitazione'),
                ),
              ),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            Text(
              'Cosa vuoi gestire?',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              icon: Icons.delete_outline,
              title: 'Gestione rifiuti',
              description:
                  'Calendario dei ritiri, contatori dei ritiri gratuiti, '
                  'storico e statistiche.',
              summary: _WasteSummary(houseId: houseId),
              onTap: () => context.go('/house/$houseId/waste'),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              icon: Icons.build_outlined,
              title: 'Manutenzioni',
              description:
                  'Caldaia, climatizzatore, fossa biologica: scadenze '
                  'periodiche, costi e chi chiamare.',
              summary: _MaintenanceSummary(houseId: houseId),
              onTap: () => context.go('/house/$houseId/maintenance'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.summary,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget summary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primaryContainer,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      icon,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      title,
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
              const SizedBox(height: 12),
              Text(
                description,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 12),
              summary,
            ],
          ),
        ),
      ),
    );
  }
}

class _WasteSummary extends ConsumerWidget {
  const _WasteSummary({required this.houseId});

  final String houseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(wasteConfigsProvider(houseId)).value ?? const [];
    final enabled = configs.where((c) => c.enabled).toList();
    final today = LocalDate.today();

    if (enabled.isEmpty) {
      return _SummaryLine(
        icon: Icons.tune,
        text: 'Nessun rifiuto monitorato',
      );
    }

    final upcoming =
        enabled
            .expand(
              (c) => nextPickups(c, today, count: 1).map((d) => (c.type, d)),
            )
            .toList()
          ..sort((a, b) => a.$2.compareTo(b.$2));

    if (upcoming.isEmpty) {
      return _SummaryLine(
        icon: Icons.event_busy_outlined,
        text: '${enabled.length} tipi monitorati · nessun ritiro in programma',
      );
    }

    final next = upcoming.first;
    return _SummaryLine(
      icon: Icons.event_outlined,
      text:
          'Prossimo ritiro: ${next.$1.label} ${formatRelative(next.$2, today)}',
    );
  }
}

class _MaintenanceSummary extends ConsumerWidget {
  const _MaintenanceSummary({required this.houseId});

  final String houseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final maintenances =
        ref.watch(maintenancesProvider(houseId)).value ?? const [];
    final log = ref.watch(maintenanceLogProvider(houseId)).value ?? const [];
    final today = LocalDate.today();

    if (maintenances.isEmpty) {
      return _SummaryLine(
        icon: Icons.add_circle_outline,
        text: 'Nessuna manutenzione registrata',
      );
    }

    final statuses = [
      for (final maintenance in maintenances)
        deriveStatus(maintenance, log, today),
    ];
    final due = statuses.where((s) => s.isActionable(today)).length;

    if (due > 0) {
      return _SummaryLine(
        icon: Icons.warning_amber_outlined,
        color: theme.colorScheme.error,
        text: due == 1
            ? '1 manutenzione da fare'
            : '$due manutenzioni da fare',
      );
    }

    final scheduled = statuses.where((s) => s.nextDue != null).toList()
      ..sort((a, b) => a.nextDue!.compareTo(b.nextDue!));
    if (scheduled.isEmpty) {
      return _SummaryLine(
        icon: Icons.schedule,
        text: '${maintenances.length} registrate · nessuna scadenza calcolata',
      );
    }

    final next = scheduled.first;
    return _SummaryLine(
      icon: Icons.event_available_outlined,
      text:
          'Prossima: ${next.maintenance.name} ${formatRelative(next.nextDue!, today)}',
    );
  }
}

class _SummaryLine extends StatelessWidget {
  const _SummaryLine({required this.icon, required this.text, this.color});

  final IconData icon;
  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effective = color ?? theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 16, color: effective),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: theme.textTheme.bodySmall?.copyWith(
              color: effective,
              fontWeight: color == null ? null : FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
