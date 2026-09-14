import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/date_format_it.dart';
import '../../core/waste_catalogue.dart';
import '../../domain/entities/collection_event.dart';
import '../../domain/quota_calculator.dart';
import '../../domain/statistics.dart';
import '../../widgets/async_view.dart';
import '../../widgets/waste_badges.dart';
import 'edit_event_sheet.dart';

/// Every collection recorded for a house in a given year, editable.
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key, required this.houseId});

  final String houseId;

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  late int _year = DateTime.now().year;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final events = ref.watch(
      collectionsProvider((houseId: widget.houseId, year: _year)),
    );
    final configs =
        ref.watch(wasteConfigsProvider(widget.houseId)).value ?? const [];
    final currentYear = DateTime.now().year;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Storico raccolte'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/house/${widget.houseId}/waste'),
        ),
        actions: [
          PopupMenuButton<int>(
            tooltip: 'Anno',
            initialValue: _year,
            onSelected: (year) => setState(() => _year = year),
            itemBuilder: (context) => [
              for (final year in availableYears(currentYear))
                PopupMenuItem(value: year, child: Text('$year')),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text('$_year', style: theme.textTheme.titleMedium),
                  const Icon(Icons.arrow_drop_down),
                ],
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: AsyncView(
          value: events,
          onRetry: () => ref.invalidate(
            collectionsProvider((houseId: widget.houseId, year: _year)),
          ),
          builder: (context, list) {
            if (list.isEmpty) {
              return EmptyState(
                icon: Icons.history,
                title: 'Nessuna raccolta nel $_year',
                message:
                    'Le raccolte che registri, dall\'app o dalla notifica, '
                    'compaiono qui e restano modificabili.',
              );
            }

            final statuses = quotaStatusesFor(
              configs: configs,
              events: list,
              year: _year,
            );

            // Already sorted newest-first by the query; group into months.
            final groups = <String, List<CollectionEvent>>{};
            for (final event in list) {
              groups
                  .putIfAbsent(formatMonthYear(event.date), () => [])
                  .add(event);
            }

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                if (statuses.isNotEmpty) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Totali $_year',
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 12),
                          for (var i = 0; i < statuses.length; i++) ...[
                            if (i > 0)
                              const Padding(
                                padding: EdgeInsets.symmetric(vertical: 10),
                                child: Divider(),
                              ),
                            QuotaProgress(status: statuses[i]),
                          ],
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                ],
                for (final entry in groups.entries) ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                    child: Text(
                      entry.key,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  ),
                  Card(
                    child: Column(
                      children: [
                        for (var i = 0; i < entry.value.length; i++) ...[
                          if (i > 0) const Divider(height: 1),
                          _EventTile(
                            houseId: widget.houseId,
                            event: entry.value[i],
                            siblings: list,
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _EventTile extends StatelessWidget {
  const _EventTile({
    required this.houseId,
    required this.event,
    required this.siblings,
  });

  final String houseId;
  final CollectionEvent event;
  final List<CollectionEvent> siblings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      // A skipped record is dimmed so a glance down the list separates what was
      // actually collected from what was deliberately not.
      leading: Opacity(
        opacity: event.isSkipped ? 0.45 : 1,
        child: WasteAvatar(type: event.type, size: 40),
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              event.type.label,
              style: theme.textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (event.isExtra) ...[
            const SizedBox(width: 8),
            _Tag(
              label: 'extra',
              background: theme.colorScheme.secondaryContainer,
              foreground: theme.colorScheme.onSecondaryContainer,
            ),
          ],
          if (event.isSkipped) ...[
            const SizedBox(width: 8),
            _Tag(
              label: 'saltata',
              background: theme.colorScheme.surfaceContainerHighest,
              foreground: theme.colorScheme.onSurfaceVariant,
            ),
          ],
        ],
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(formatLong(event.date)),
          Text(
            'Registrata da ${event.recordedByName}'
            '${event.source == CollectionSource.notification ? ' · da notifica' : ''}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (event.note?.isNotEmpty ?? false)
            Text(
              event.note!,
              style: theme.textTheme.bodySmall?.copyWith(
                fontStyle: FontStyle.italic,
              ),
            ),
        ],
      ),
      isThreeLine: true,
      trailing: event.hasPendingWrites
          ? Tooltip(
              message: 'In attesa di sincronizzazione',
              child: Icon(
                Icons.cloud_upload_outlined,
                size: 20,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          : const Icon(Icons.edit_outlined, size: 20),
      onTap: () => showEditEventSheet(context, houseId, event, siblings),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag({
    required this.label,
    required this.background,
    required this.foreground,
  });

  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
    decoration: BoxDecoration(
      color: background,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Text(
      label,
      style: Theme.of(
        context,
      ).textTheme.labelSmall?.copyWith(color: foreground),
    ),
  );
}
