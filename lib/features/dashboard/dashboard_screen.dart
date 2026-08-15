import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/date_format_it.dart';
import '../../core/local_date.dart';
import '../../core/waste_catalogue.dart';
import '../../domain/entities/collection_event.dart';
import '../../domain/entities/waste_config.dart';
import '../../domain/quota_calculator.dart';
import '../../domain/schedule_engine.dart';
import '../../widgets/async_view.dart';
import '../../widgets/waste_badges.dart';
import '../collections/record_extra_sheet.dart';

/// An upcoming pickup, joined with whether it has already been recorded.
class _UpcomingPickup {
  const _UpcomingPickup({
    required this.config,
    required this.date,
    required this.status,
    required this.recorded,
  });

  final WasteConfig config;
  final LocalDate date;
  final QuotaStatus status;
  final CollectionEvent? recorded;

  bool get isRecorded => recorded != null;
}

class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key, required this.houseId});

  final String houseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final house = ref.watch(houseProvider(houseId));
    final configs = ref.watch(wasteConfigsProvider(houseId));
    final events = ref.watch(currentYearCollectionsProvider(houseId));

    // Any change in the ledger or the schedules can change what tomorrow's
    // reminder should say, so rewrite the pending notifications.
    ref.listen(currentYearCollectionsProvider(houseId), (_, _) {
      ref.read(notificationSyncProvider).requestSync();
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(house.value?.name ?? 'Abitazione'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
        actions: [
          IconButton(
            tooltip: 'Storico',
            icon: const Icon(Icons.history),
            onPressed: () => context.go('/house/$houseId/history'),
          ),
          PopupMenuButton<String>(
            onSelected: (value) => context.go('/house/$houseId/$value'),
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'waste',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Rifiuti monitorati'),
                ),
              ),
              PopupMenuItem(
                value: 'stats',
                child: ListTile(
                  leading: Icon(Icons.insights_outlined),
                  title: Text('Statistiche'),
                ),
              ),
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
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => showRecordExtraSheet(context, ref, houseId),
        icon: const Icon(Icons.add),
        label: const Text('Raccolta extra'),
      ),
      body: SafeArea(
        top: false,
        child: AsyncView(
          value: configs,
          onRetry: () => ref.invalidate(wasteConfigsProvider(houseId)),
          builder: (context, configList) {
            final enabled = configList.where((c) => c.enabled).toList();

            if (enabled.isEmpty) {
              return EmptyState(
                icon: Icons.delete_outline,
                title: 'Nessun rifiuto monitorato',
                message:
                    'Scegli quali tipi di rifiuto vuoi seguire in questa '
                    'abitazione e imposta i giorni di ritiro.',
                action: FilledButton.icon(
                  onPressed: () => context.go('/house/$houseId/waste'),
                  icon: const Icon(Icons.tune),
                  label: const Text('Configura i rifiuti'),
                ),
              );
            }

            return AsyncView(
              value: events,
              onRetry: () =>
                  ref.invalidate(currentYearCollectionsProvider(houseId)),
              builder: (context, eventList) => _DashboardBody(
                houseId: houseId,
                configs: enabled,
                events: eventList,
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DashboardBody extends ConsumerWidget {
  const _DashboardBody({
    required this.houseId,
    required this.configs,
    required this.events,
  });

  final String houseId;
  final List<WasteConfig> configs;
  final List<CollectionEvent> events;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = LocalDate.today();
    final year = today.year;
    final statuses = quotaStatusesFor(
      configs: configs,
      events: events,
      year: year,
    );
    final statusByType = {for (final s in statuses) s.type: s};

    final upcoming = <_UpcomingPickup>[];
    for (final config in configs) {
      // Starts yesterday so a pickup that was missed last night is still
      // recordable — the bins go out the evening before, and people confirm
      // late.
      for (final date in pickupsInRange(
        config,
        today.addDays(-1),
        today.addDays(14),
      )) {
        upcoming.add(
          _UpcomingPickup(
            config: config,
            date: date,
            status: statusByType[config.type]!,
            recorded: events
                .where(
                  (e) => !e.isExtra && e.type == config.type && e.date == date,
                )
                .firstOrNull,
          ),
        );
      }
    }
    upcoming.sort((a, b) {
      final byDate = a.date.compareTo(b.date);
      return byDate != 0
          ? byDate
          : a.config.type.index.compareTo(b.config.type.index);
    });

    final withoutSchedule = configs
        .where((c) => c.primaryRule?.weekdays.isEmpty ?? true)
        .toList();

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        if (withoutSchedule.isNotEmpty) ...[
          Card(
            color: theme.colorScheme.tertiaryContainer,
            child: ListTile(
              leading: const Icon(Icons.event_busy_outlined),
              title: const Text('Giorni di ritiro mancanti'),
              subtitle: Text(
                withoutSchedule.map((c) => c.type.label).join(', '),
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => context.go('/house/$houseId/waste'),
            ),
          ),
          const SizedBox(height: 16),
        ],

        Text(
          'Prossimi ritiri',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),

        if (upcoming.isEmpty)
          Card(
            child: const Padding(
              padding: EdgeInsets.all(16),
              child: Text('Nessun ritiro nei prossimi 14 giorni.'),
            ),
          )
        else
          ...upcoming.map(
            (pickup) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _PickupCard(
                houseId: houseId,
                pickup: pickup,
                today: today,
              ),
            ),
          ),

        const SizedBox(height: 24),
        Text(
          'Contatori $year',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                for (var i = 0; i < statuses.length; i++) ...[
                  if (i > 0)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Divider(),
                    ),
                  QuotaProgress(status: statuses[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _PickupCard extends ConsumerStatefulWidget {
  const _PickupCard({
    required this.houseId,
    required this.pickup,
    required this.today,
  });

  final String houseId;
  final _UpcomingPickup pickup;
  final LocalDate today;

  @override
  ConsumerState<_PickupCard> createState() => _PickupCardState();
}

class _PickupCardState extends ConsumerState<_PickupCard> {
  bool _busy = false;

  /// Only pickups that have arrived can be confirmed; a future one has not
  /// happened yet.
  bool get _isActionable => widget.today.daysUntil(widget.pickup.date) <= 1;

  Future<void> _record() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(collectionRepositoryProvider)
          .recordScheduled(
            houseId: widget.houseId,
            type: widget.pickup.config.type,
            date: widget.pickup.date,
            uid: user.uid,
            userName: user.shortName,
          );
      ref.read(notificationSyncProvider).requestSync();
    } on Exception catch (e) {
      if (mounted) {
        showMessage(context, 'Registrazione non riuscita: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _undo() async {
    final event = widget.pickup.recorded;
    if (event == null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(collectionRepositoryProvider)
          .deleteEvent(widget.houseId, event.id);
      ref.read(notificationSyncProvider).requestSync();
    } on Exception catch (e) {
      if (mounted) {
        showMessage(context, 'Annullamento non riuscito: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pickup = widget.pickup;
    final color = wasteColor(context, pickup.config.type);
    final isToday = pickup.date == widget.today;

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
        child: Row(
          children: [
            Container(
              width: 4,
              height: 48,
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 12),
            WasteAvatar(type: pickup.config.type, size: 40),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pickup.config.type.label,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    formatRelative(pickup.date, widget.today) +
                        (isToday ? '' : ' · ${formatShort(pickup.date)}'),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 6),
                  QuotaBadge(status: pickup.status),
                ],
              ),
            ),
            if (_busy)
              const Padding(
                padding: EdgeInsets.all(12),
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else if (pickup.isRecorded)
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle, color: theme.colorScheme.primary),
                  TextButton(
                    onPressed: _undo,
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Annulla'),
                  ),
                ],
              )
            else if (_isActionable)
              FilledButton.tonal(
                onPressed: _record,
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  minimumSize: Size.zero,
                ),
                child: const Text('Fatta'),
              ),
          ],
        ),
      ),
    );
  }
}
