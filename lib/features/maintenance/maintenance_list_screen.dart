import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/date_format_it.dart';
import '../../core/local_date.dart';
import '../../core/money_format_it.dart';
import '../../domain/entities/maintenance.dart';
import '../../domain/maintenance_schedule.dart';
import '../../widgets/async_view.dart';
import '../../widgets/button_label.dart';
import '../../widgets/maintenance_avatar.dart';
import 'maintenance_actions.dart';
import 'maintenance_history_sheet.dart';

/// The maintenances of a house, most urgent first.
class MaintenanceListScreen extends ConsumerWidget {
  const MaintenanceListScreen({super.key, required this.houseId});

  final String houseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final maintenances = ref.watch(maintenancesProvider(houseId));
    final log = ref.watch(maintenanceLogProvider(houseId));
    final today = LocalDate.today();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Manutenzioni'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/house/$houseId'),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.go('/house/$houseId/maintenance/new'),
        icon: const Icon(Icons.add),
        label: const Text('Nuova manutenzione'),
      ),
      body: SafeArea(
        top: false,
        child: AsyncView(
          value: maintenances,
          onRetry: () => ref.invalidate(maintenancesProvider(houseId)),
          builder: (context, list) {
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.build_outlined,
                title: 'Nessuna manutenzione',
                message:
                    'Qui tieni traccia delle manutenzioni periodiche di casa — '
                    'caldaia, climatizzatore, fossa biologica — con le loro '
                    'scadenze, i costi e chi chiamare.',
                action: FilledButton.icon(
                  onPressed: () =>
                      context.go('/house/$houseId/maintenance/new'),
                  icon: const Icon(Icons.add),
                  label: const Text('Aggiungi la prima'),
                ),
              );
            }

            final entries = log.value ?? const [];
            final statuses = [
              for (final maintenance in list)
                deriveStatus(maintenance, entries, today),
            ]..sort((a, b) => compareForList(a, b, today));

            return ListView.separated(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              itemCount: statuses.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (context, index) => _MaintenanceCard(
                houseId: houseId,
                status: statuses[index],
                today: today,
                logLoaded: log.hasValue,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _MaintenanceCard extends ConsumerWidget {
  const _MaintenanceCard({
    required this.houseId,
    required this.status,
    required this.today,
    required this.logLoaded,
  });

  final String houseId;
  final MaintenanceStatus status;
  final LocalDate today;
  final bool logLoaded;

  Maintenance get maintenance => status.maintenance;

  MaintenanceTone get _tone {
    if (status.isActionable(today)) return MaintenanceTone.overdue;
    if (status.nextDue != null) return MaintenanceTone.normal;
    return MaintenanceTone.idle;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final contact = maintenance.contact;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                MaintenanceAvatar(iconKey: maintenance.iconKey, tone: _tone),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        maintenance.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      _StatusLine(
                        status: status,
                        today: today,
                        logLoaded: logLoaded,
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Storico',
                  icon: const Icon(Icons.history),
                  onPressed: () => showMaintenanceHistorySheet(
                    context,
                    houseId: houseId,
                    maintenance: maintenance,
                  ),
                ),
                if (contact != null)
                  IconButton(
                    tooltip: 'Chiama ${contact.label}',
                    icon: const Icon(Icons.phone_outlined),
                    onPressed: () => showCallDialog(context, contact: contact),
                  ),
              ],
            ),

            const SizedBox(height: 10),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                if (maintenance.recurrence != null)
                  _Meta(
                    icon: Icons.repeat,
                    text: maintenance.recurrence!.label,
                  ),
                _Meta(
                  icon: Icons.euro_outlined,
                  text: formatEuro(maintenance.costCents),
                ),
              ],
            ),

            if (maintenance.notes?.isNotEmpty ?? false) ...[
              const SizedBox(height: 8),
              Text(
                maintenance.notes!,
                style: theme.textTheme.bodySmall?.copyWith(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],

            if (status.hasIgnoredFutureExecutions) ...[
              const SizedBox(height: 8),
              _Warning(
                // A device with a wrong date wrote this. It is excluded from the
                // calculation rather than allowed to lock the maintenance, but
                // the user should know it is there.
                text:
                    'C\'è un\'esecuzione registrata con una data futura: '
                    'non viene conteggiata. Correggila dallo storico.',
              ),
            ],
            if (status.hasUnknownRecurrence) ...[
              const SizedBox(height: 8),
              _Warning(
                text:
                    'Ricorrenza non riconosciuta: aggiorna l\'app per '
                    'calcolare le scadenze.',
              ),
            ],
            if (status.isWedged) ...[
              const SizedBox(height: 8),
              _Warning(
                text:
                    'Troppe scadenze saltate per calcolare la prossima. '
                    'Registra un\'esecuzione per ripartire.',
              ),
            ],

            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => context.go(
                      '/house/$houseId/maintenance/${maintenance.id}/edit',
                    ),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                    child: const ButtonLabel('Modifica'),
                  ),
                ),
                // Skipping is only meaningful when there is a due date to move.
                if (status.nextDue != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => showSkipDialog(
                        context,
                        ref,
                        houseId: houseId,
                        status: status,
                      ),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(0, 40),
                      ),
                      child: const ButtonLabel('Salta'),
                    ),
                  ),
                ],
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.tonal(
                    onPressed: () => showExecuteSheet(
                      context,
                      houseId: houseId,
                      status: status,
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 40),
                    ),
                    child: const ButtonLabel('Esegui'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({
    required this.status,
    required this.today,
    required this.logLoaded,
  });

  final MaintenanceStatus status;
  final LocalDate today;
  final bool logLoaded;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (!logLoaded) {
      return Text(
        'Caricamento…',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final (text, color) = _describe(theme);
    return Text(
      text,
      style: theme.textTheme.bodySmall?.copyWith(
        color: color,
        fontWeight: color == null ? null : FontWeight.w600,
      ),
    );
  }

  (String, Color?) _describe(ThemeData theme) {
    if (status.isWedged) {
      return ('Scadenza non calcolabile', theme.colorScheme.error);
    }
    if (status.hasUnknownRecurrence) return ('Ricorrenza sconosciuta', null);
    if (status.isNeverDone) return ('Mai eseguita', null);

    final due = status.nextDue!;
    final last = status.lastDone!;
    if (due < today) {
      final days = due.daysUntil(today);
      return (
        'In ritardo di ${days == 1 ? '1 giorno' : '$days giorni'} '
            '· ultima: ${formatShortInContext(last, today)}',
        theme.colorScheme.error,
      );
    }
    if (due == today) {
      return (
        'Da fare oggi · ultima: ${formatShortInContext(last, today)}',
        theme.colorScheme.error,
      );
    }
    return (
      'Prossima: ${formatRelative(due, today)} · ultima: ${formatShortInContext(last, today)}',
      null,
    );
  }
}

class _Meta extends StatelessWidget {
  const _Meta({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 4),
        Text(
          text,
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _Warning extends StatelessWidget {
  const _Warning({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.tertiaryContainer,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            size: 16,
            color: theme.colorScheme.onTertiaryContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onTertiaryContainer,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
