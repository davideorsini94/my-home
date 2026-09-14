import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app/providers.dart';
import '../../core/date_format_it.dart';
import '../../core/local_date.dart';
import '../../core/money_format_it.dart';
import '../../core/phone_number.dart';
import '../../domain/entities/maintenance.dart';
import '../../domain/entities/maintenance_log_entry.dart';
import '../../domain/maintenance_schedule.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/async_view.dart';

/// Records an execution, letting cost, notes and cadence be adjusted first.
Future<void> showExecuteSheet(
  BuildContext context, {
  required String houseId,
  required MaintenanceStatus status,
}) => showAppSheet<void>(
  context: context,
  builder: (context) => _ExecuteSheet(houseId: houseId, status: status),
);

class _ExecuteSheet extends ConsumerStatefulWidget {
  const _ExecuteSheet({required this.houseId, required this.status});

  final String houseId;
  final MaintenanceStatus status;

  @override
  ConsumerState<_ExecuteSheet> createState() => _ExecuteSheetState();
}

class _ExecuteSheetState extends ConsumerState<_ExecuteSheet> {
  late final _costController = TextEditingController(
    text: euroEditingValue(widget.status.maintenance.costCents),
  );
  final _notesController = TextEditingController();
  late int _every = widget.status.maintenance.recurrence?.every ?? 1;
  late RecurrenceUnit _unit =
      widget.status.maintenance.recurrence?.unit ?? RecurrenceUnit.years;
  bool _busy = false;

  Maintenance get _maintenance => widget.status.maintenance;

  @override
  void dispose() {
    _costController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _confirm() async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    final cost = tryParseEuroCents(_costController.text);
    if (!cost.valid) {
      showMessage(context, 'Importo non valido.', isError: true);
      return;
    }

    setState(() => _busy = true);
    final repository = ref.read(maintenanceRepositoryProvider);
    final notes = _notesController.text.trim();
    // Captured before the write, so a slow or retried save still records the
    // day the button was pressed.
    final today = LocalDate.today();

    try {
      await repository.recordExecution(
        houseId: widget.houseId,
        maintenanceId: _maintenance.id,
        date: today,
        uid: user.uid,
        userName: user.shortName,
        costCents: cost.cents,
        notes: notes.isEmpty ? null : notes,
      );

      final edited = Recurrence.clamped(_every, _unit);
      if (edited != _maintenance.recurrence ||
          cost.cents != _maintenance.costCents) {
        await repository.updateMaintenance(
          houseId: widget.houseId,
          maintenance: _maintenance.copyWith(
            recurrence: edited,
            costCents: cost.cents,
            clearCost: cost.cents == null,
          ),
        );
      }

      ref.read(notificationSyncProvider).requestSync();
      if (mounted) {
        Navigator.of(context).pop();
        showMessage(context, 'Manutenzione registrata.');
      }
    } on Exception catch (e) {
      if (mounted) {
        showMessage(context, 'Registrazione non riuscita: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final today = LocalDate.today();
    final log =
        ref.watch(maintenanceLogProvider(widget.houseId)).value ?? const [];
    final alreadyToday = log.any(
      (e) => e.maintenanceId == _maintenance.id && e.isDone && e.date == today,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Registra l\'esecuzione',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '«${_maintenance.name}» risulterà eseguita oggi, '
              '${formatLong(today)}.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            if (alreadyToday) ...[
              const SizedBox(height: 12),
              Card(
                color: theme.colorScheme.secondaryContainer,
                child: const ListTile(
                  leading: Icon(Icons.info_outline),
                  title: Text('Già registrata oggi'),
                  subtitle: Text(
                    'Confermando aggiornerai la registrazione di oggi, '
                    'non ne aggiungerai una seconda.',
                  ),
                ),
              ),
            ],

            const SizedBox(height: 20),
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
            const SizedBox(height: 12),
            TextField(
              controller: _notesController,
              maxLength: 200,
              maxLines: 2,
              textCapitalization: TextCapitalization.sentences,
              decoration: const InputDecoration(
                labelText: 'Note di questa esecuzione',
                hintText: 'Es. sostituita valvola',
              ),
            ),

            const SizedBox(height: 8),
            Text('Ogni quanto va ripetuta', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Row(
              children: [
                SizedBox(
                  width: 96,
                  child: TextFormField(
                    initialValue: '$_every',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    decoration: const InputDecoration(labelText: 'Ogni'),
                    onChanged: (value) =>
                        setState(() => _every = int.tryParse(value) ?? 1),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<RecurrenceUnit>(
                    value: _unit,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Unità'),
                    items: [
                      for (final unit in RecurrenceUnit.values)
                        DropdownMenuItem(
                          value: unit,
                          child: Text(unit.label(_every)),
                        ),
                    ],
                    onChanged: (value) =>
                        setState(() => _unit = value ?? _unit),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Prossima scadenza: '
              '${formatLong(_previewNextDue(today))}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),

            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _busy ? null : _confirm,
                child: Text(_busy ? 'Registrazione…' : 'Conferma esecuzione'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Where the next due date lands if this execution is confirmed now.
  LocalDate _previewNextDue(LocalDate today) {
    final entry = MaintenanceLogEntry(
      id: MaintenanceLogEntry.doneId(_maintenance.id, today),
      maintenanceId: _maintenance.id,
      date: today,
      status: MaintenanceEntryStatus.done,
      recordedByUid: '',
      recordedByName: '',
    );
    final log =
        ref.read(maintenanceLogProvider(widget.houseId)).value ?? const [];
    return deriveStatus(
          _maintenance.copyWith(recurrence: Recurrence.clamped(_every, _unit)),
          [...log, entry],
          today,
        ).nextDue ??
        today;
  }
}

/// Skips the upcoming occurrence, explaining exactly what that means.
Future<void> showSkipDialog(
  BuildContext context,
  WidgetRef ref, {
  required String houseId,
  required MaintenanceStatus status,
}) async {
  final due = status.nextDue;
  final user = ref.read(currentUserProvider);
  if (due == null || user == null) return;

  final today = LocalDate.today();
  final log = ref.read(maintenanceLogProvider(houseId)).value ?? const [];
  final after = dueAfterSkip(status.maintenance, log, today);
  final catchUp = duesToSkipUntilFuture(status.maintenance, log, today);
  final isBehind = catchUp.length > 1;

  final theme = Theme.of(context);
  final choice = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.next_plan_outlined),
      title: const Text('Saltare questa scadenza?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'La scadenza del ${formatLong(due)} verrà considerata saltata: '
            'la manutenzione NON risulterà eseguita e la data dell\'ultima '
            'esecuzione resta quella di prima.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Text(
            after == null
                ? 'Il promemoria passerà alla scadenza successiva.'
                : 'Il prossimo promemoria arriverà il ${formatLong(after)}.',
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          if (isBehind) ...[
            const SizedBox(height: 12),
            Text(
              'Ci sono ${catchUp.length} scadenze arretrate. Puoi saltarle '
              'tutte in una volta e ripartire dalla prossima futura.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop('cancel'),
          child: const Text('Annulla'),
        ),
        if (isBehind)
          TextButton(
            onPressed: () => Navigator.of(context).pop('all'),
            child: Text('Salta tutte (${catchUp.length})'),
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop('one'),
          child: const Text('Salta'),
        ),
      ],
    ),
  );

  if (choice == null || choice == 'cancel') return;

  final repository = ref.read(maintenanceRepositoryProvider);
  try {
    if (choice == 'all') {
      if (catchUp.isEmpty) {
        // The engine declines when catching up would need an unreasonable
        // number of entries; saying so beats writing hundreds silently.
        if (context.mounted) {
          showMessage(
            context,
            'Troppe scadenze arretrate per saltarle in una volta. '
            'Registra un\'esecuzione per ripartire.',
            isError: true,
          );
        }
        return;
      }
      await repository.recordSkips(
        houseId: houseId,
        maintenanceId: status.maintenance.id,
        dueDates: catchUp,
        uid: user.uid,
        userName: user.shortName,
      );
    } else {
      await repository.recordSkip(
        houseId: houseId,
        maintenanceId: status.maintenance.id,
        dueDate: due,
        uid: user.uid,
        userName: user.shortName,
      );
    }
    ref.read(notificationSyncProvider).requestSync();
    if (context.mounted) showMessage(context, 'Scadenza saltata.');
  } on Exception catch (e) {
    if (context.mounted) {
      showMessage(context, 'Operazione non riuscita: $e', isError: true);
    }
  }
}

/// Confirms, then hands the number to the system dialer.
///
/// Opens the dialer prefilled rather than placing the call: dialling directly
/// would need the CALL_PHONE permission, and the user still presses the green
/// button themselves.
Future<void> showCallDialog(
  BuildContext context, {
  required MaintenanceContact contact,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.phone_outlined),
      title: const Text('Chiamare questo contatto?'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (contact.hasName)
            Text(
              contact.label,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          const SizedBox(height: 4),
          Text(
            formatPhoneForDisplay(contact.phone),
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(true),
          icon: const Icon(Icons.phone, size: 18),
          label: const Text('Chiama'),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  try {
    final launched = await launchUrl(
      telUri(contact.phone),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && context.mounted) {
      showMessage(
        context,
        'Nessuna app telefono disponibile su questo dispositivo.',
        isError: true,
      );
    }
  } on Exception catch (e) {
    if (context.mounted) {
      showMessage(context, 'Chiamata non riuscita: $e', isError: true);
    }
  }
}
