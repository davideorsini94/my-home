import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/date_format_it.dart';
import '../../core/local_date.dart';
import '../../core/money_format_it.dart';
import '../../domain/entities/maintenance.dart';
import '../../domain/entities/maintenance_log_entry.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/button_label.dart';
import '../../widgets/async_view.dart';

/// Every execution and skip recorded for one maintenance.
///
/// This is not decoration: it is the repair mechanism. An execution recorded on
/// the wrong day, a cost typed twice, or an entry written by a device with a
/// wrong clock can only be undone here.
Future<void> showMaintenanceHistorySheet(
  BuildContext context, {
  required String houseId,
  required Maintenance maintenance,
}) => showAppSheet<void>(
  context: context,
  builder: (context) =>
      _HistorySheet(houseId: houseId, maintenance: maintenance),
);

class _HistorySheet extends ConsumerWidget {
  const _HistorySheet({required this.houseId, required this.maintenance});

  final String houseId;
  final Maintenance maintenance;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final today = LocalDate.today();
    final log = ref.watch(maintenanceLogProvider(houseId)).value ?? const [];
    final mine = log.where((e) => e.maintenanceId == maintenance.id).toList()
      ..sort((a, b) => b.date.compareTo(a.date));

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Storico di «${maintenance.name}»',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Tocca una voce per correggerla o eliminarla.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          if (mine.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Nessuna esecuzione registrata.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: mine.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) => _EntryTile(
                  houseId: houseId,
                  entry: mine[index],
                  today: today,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryTile extends ConsumerWidget {
  const _EntryTile({
    required this.houseId,
    required this.entry,
    required this.today,
  });

  final String houseId;
  final MaintenanceLogEntry entry;
  final LocalDate today;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isFuture = entry.date > today;

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        entry.isSkipped ? Icons.next_plan_outlined : Icons.check_circle_outline,
        color: entry.isSkipped
            ? theme.colorScheme.onSurfaceVariant
            : theme.colorScheme.primary,
      ),
      title: Row(
        children: [
          Flexible(child: Text(formatLong(entry.date))),
          if (isFuture) ...[
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'data futura',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ],
      ),
      subtitle: Text(
        [
          entry.isSkipped ? 'Saltata' : formatEuro(entry.costCents),
          if (entry.recordedByName.isNotEmpty) 'da ${entry.recordedByName}',
          if (entry.notes?.isNotEmpty ?? false) entry.notes!,
        ].join(' · '),
      ),
      trailing: const Icon(Icons.edit_outlined, size: 18),
      onTap: () => showAppSheet<void>(
        context: context,
        builder: (context) => _EditEntrySheet(houseId: houseId, entry: entry),
      ),
    );
  }
}

class _EditEntrySheet extends ConsumerStatefulWidget {
  const _EditEntrySheet({required this.houseId, required this.entry});

  final String houseId;
  final MaintenanceLogEntry entry;

  @override
  ConsumerState<_EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends ConsumerState<_EditEntrySheet> {
  late LocalDate _date = widget.entry.date;
  late MaintenanceEntryStatus _status = widget.entry.status;
  late final _costController = TextEditingController(
    text: euroEditingValue(widget.entry.costCents),
  );
  late final _notesController = TextEditingController(
    text: widget.entry.notes ?? '',
  );
  bool _busy = false;

  @override
  void dispose() {
    _costController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final cost = tryParseEuroCents(_costController.text);
    if (!cost.valid) {
      showMessage(context, 'Importo non valido.', isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      final notes = _notesController.text.trim();
      await ref
          .read(maintenanceRepositoryProvider)
          .updateEntry(
            houseId: widget.houseId,
            original: widget.entry,
            date: _date,
            status: _status,
            costCents: cost.cents,
            notes: notes.isEmpty ? null : notes,
          );
      ref.read(notificationSyncProvider).requestSync();
      if (mounted) {
        Navigator.of(context).pop();
        showMessage(context, 'Voce aggiornata.');
      }
    } on Exception catch (e) {
      if (mounted) {
        showMessage(context, 'Modifica non riuscita: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare la voce?'),
        content: const Text(
          'La scadenza successiva verrà ricalcolata di conseguenza.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(maintenanceRepositoryProvider)
          .deleteEntry(houseId: widget.houseId, entryId: widget.entry.id);
      ref.read(notificationSyncProvider).requestSync();
      if (mounted) {
        Navigator.of(context).pop();
        showMessage(context, 'Voce eliminata.');
      }
    } on Exception catch (e) {
      if (mounted) {
        showMessage(context, 'Eliminazione non riuscita: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDone = _status == MaintenanceEntryStatus.done;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Correggi la voce',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),

            SegmentedButton<MaintenanceEntryStatus>(
              segments: const [
                ButtonSegment(
                  value: MaintenanceEntryStatus.done,
                  icon: Icon(Icons.check_circle_outline),
                  label: Text('Eseguita'),
                ),
                ButtonSegment(
                  value: MaintenanceEntryStatus.skipped,
                  icon: Icon(Icons.next_plan_outlined),
                  label: Text('Saltata'),
                ),
              ],
              selected: {_status},
              onSelectionChanged: (selection) =>
                  setState(() => _status = selection.first),
            ),

            const SizedBox(height: 12),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: Text(formatLong(_date)),
              subtitle: Text(
                isDone
                    ? 'Giorno in cui è stata eseguita'
                    : 'Scadenza che è stata saltata',
              ),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date.toLocalDateTime(),
                  firstDate: DateTime(DateTime.now().year - 30),
                  lastDate: DateTime(DateTime.now().year + 5, 12, 31),
                );
                if (picked != null) {
                  setState(() => _date = LocalDate.fromDateTime(picked));
                }
              },
            ),

            if (isDone) ...[
              const SizedBox(height: 8),
              TextField(
                controller: _costController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp('[0-9.,]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Costo',
                  hintText: unknownCostLabel,
                  prefixText: '€ ',
                ),
              ),
            ],

            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLength: 200,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Note'),
            ),

            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _busy ? null : _delete,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      minimumSize: const Size(0, 48),
                    ),
                    icon: const Icon(Icons.delete_outline),
                    label: const ButtonLabel('Elimina'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: _busy ? null : _save,
                    child: ButtonLabel(_busy ? 'Salvataggio…' : 'Salva'),
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
