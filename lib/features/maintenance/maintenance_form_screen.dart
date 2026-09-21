import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/date_format_it.dart';
import '../../core/local_date.dart';
import '../../core/maintenance_icons.dart';
import '../../core/money_format_it.dart';
import '../../domain/entities/maintenance.dart';
import '../../domain/entities/maintenance_log_entry.dart';
import '../../domain/maintenance_schedule.dart';
import '../../notifications/permission_prompt.dart';
import '../../widgets/async_view.dart';
import '../../widgets/button_label.dart';
import '../../widgets/maintenance_avatar.dart';
import 'contact_field.dart';
import 'icon_picker_sheet.dart';

/// Creates a maintenance, or edits and deletes an existing one.
class MaintenanceFormScreen extends ConsumerStatefulWidget {
  const MaintenanceFormScreen({
    super.key,
    required this.houseId,
    this.maintenanceId,
  });

  final String houseId;
  final String? maintenanceId;

  @override
  ConsumerState<MaintenanceFormScreen> createState() =>
      _MaintenanceFormScreenState();
}

class _MaintenanceFormScreenState extends ConsumerState<MaintenanceFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _notesController = TextEditingController();
  final _costController = TextEditingController();

  String _iconKey = defaultMaintenanceIconKey;
  int _every = 1;
  RecurrenceUnit _unit = RecurrenceUnit.years;
  LocalDate? _lastDone;
  MaintenanceContact? _contact;

  bool _loaded = false;
  bool _busy = false;

  bool get _isEditing => widget.maintenanceId != null;

  @override
  void dispose() {
    _nameController.dispose();
    _notesController.dispose();
    _costController.dispose();
    super.dispose();
  }

  void _hydrate(Maintenance? maintenance) {
    if (_loaded || maintenance == null) return;
    _nameController.text = maintenance.name;
    _notesController.text = maintenance.notes ?? '';
    _costController.text = euroEditingValue(maintenance.costCents);
    _iconKey = maintenance.iconKey;
    final recurrence = maintenance.recurrence;
    if (recurrence != null) {
      _every = recurrence.every;
      _unit = recurrence.unit;
    }
    _contact = maintenance.contact;
    _loaded = true;
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
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

    try {
      final maintenance = Maintenance(
        id: widget.maintenanceId ?? '',
        name: _nameController.text.trim(),
        iconKey: _iconKey,
        recurrence: Recurrence.clamped(_every, _unit),
        notes: notes.isEmpty ? null : notes,
        costCents: cost.cents,
        contact: _contact,
      );

      if (_isEditing) {
        await repository.updateMaintenance(
          houseId: widget.houseId,
          maintenance: maintenance,
        );
      } else {
        await repository.createMaintenance(
          houseId: widget.houseId,
          maintenance: maintenance,
          uid: user.uid,
          userName: user.shortName,
          lastDone: _lastDone,
        );
        // Reminders only start once a last execution exists, so asking for the
        // permission is only meaningful when one was just seeded.
        if (_lastDone != null && mounted) {
          await ensureNotificationPermission(context, ref);
        }
      }

      ref.read(notificationSyncProvider).requestSync();
      if (mounted) context.go('/house/${widget.houseId}/maintenance');
    } on Exception catch (e) {
      if (mounted) {
        showMessage(context, 'Salvataggio non riuscito: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare la manutenzione?'),
        content: Text(
          'Verranno eliminate «${_nameController.text.trim()}» e tutte le '
          'esecuzioni registrate, per tutti i membri dell\'abitazione. '
          'L\'operazione non è reversibile.',
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
          .deleteMaintenance(
            houseId: widget.houseId,
            maintenanceId: widget.maintenanceId!,
          );
      ref.read(notificationSyncProvider).requestSync();
      if (mounted) context.go('/house/${widget.houseId}/maintenance');
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

    if (_isEditing) {
      final list = ref.watch(maintenancesProvider(widget.houseId)).value;
      if (list != null) {
        _hydrate(list.where((m) => m.id == widget.maintenanceId).firstOrNull);
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          _isEditing ? 'Modifica manutenzione' : 'Nuova manutenzione',
        ),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.go('/house/${widget.houseId}/maintenance'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
            children: [
              Row(
                children: [
                  MaintenanceAvatar(iconKey: _iconKey, size: 56),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () async {
                        final picked = await showIconPickerSheet(
                          context,
                          selectedKey: _iconKey,
                        );
                        if (picked != null) setState(() => _iconKey = picked);
                      },
                      icon: const Icon(Icons.palette_outlined, size: 18),
                      label: ButtonLabel(maintenanceIconLabel(_iconKey)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              TextFormField(
                controller: _nameController,
                autofocus: !_isEditing,
                maxLength: 60,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nome della manutenzione',
                  hintText: 'Es. Revisione caldaia',
                  prefixIcon: Icon(Icons.build_outlined),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Dai un nome alla manutenzione';
                  if (text.length > 60) return 'Massimo 60 caratteri';
                  return null;
                },
              ),

              const SizedBox(height: 8),
              _SectionTitle('Ogni quanto va fatta'),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          SizedBox(
                            width: 96,
                            child: TextFormField(
                              initialValue: '$_every',
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly,
                              ],
                              decoration: const InputDecoration(
                                labelText: 'Ogni',
                              ),
                              onChanged: (value) => setState(
                                () => _every = int.tryParse(value) ?? 1,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: DropdownButtonFormField<RecurrenceUnit>(
                              initialValue: _unit,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Unità',
                              ),
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
                        Recurrence.clamped(_every, _unit).label,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (_every > _unit.maxEvery)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(
                            'Massimo ${_unit.maxEvery} ${_unit.label(_unit.maxEvery)}.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              if (!_isEditing) ...[
                const SizedBox(height: 20),
                _SectionTitle('Ultima esecuzione'),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                        leading: const Icon(Icons.event_available_outlined),
                        title: Text(
                          _lastDone == null
                              ? 'Mai eseguita'
                              : formatLong(_lastDone!),
                        ),
                        subtitle: Text(
                          _lastDone == null
                              // Without a last execution there is nothing to
                              // count from, so the schedule starts at the
                              // first "Esegui" instead.
                              ? 'Lascia vuoto se non lo sai: i promemoria '
                                    'partiranno dalla prima esecuzione che '
                                    'registri.'
                              : 'Prossima scadenza: '
                                    '${formatLong(_previewNextDue()!)}',
                        ),
                        trailing: const Icon(Icons.edit_calendar_outlined),
                        isThreeLine: _lastDone == null,
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate:
                                _lastDone?.toLocalDateTime() ?? DateTime.now(),
                            firstDate: DateTime(DateTime.now().year - 30),
                            lastDate: DateTime.now(),
                            helpText: 'Ultima esecuzione',
                          );
                          if (picked != null) {
                            setState(
                              () => _lastDone = LocalDate.fromDateTime(picked),
                            );
                          }
                        },
                      ),
                      if (_lastDone != null)
                        TextButton(
                          onPressed: () => setState(() => _lastDone = null),
                          child: const Text('Non lo so'),
                        ),
                    ],
                  ),
                ),
              ],

              const SizedBox(height: 20),
              _SectionTitle('Dettagli'),
              TextFormField(
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
                  helperText: 'Lascia vuoto se non lo sai',
                ),
                validator: (value) => tryParseEuroCents(value ?? '').valid
                    ? null
                    : 'Importo non valido',
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _notesController,
                maxLength: 200,
                maxLines: 3,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  hintText: 'Es. modello caldaia, codice contratto…',
                  alignLabelWithHint: true,
                ),
              ),

              const SizedBox(height: 12),
              ContactField(
                contact: _contact,
                onChanged: (contact) => setState(() => _contact = contact),
              ),

              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Salvataggio…' : 'Salva'),
              ),

              if (_isEditing) ...[
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: _busy ? null : _delete,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                    minimumSize: const Size(0, 48),
                  ),
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Elimina manutenzione'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The due date the seeded execution would produce.
  ///
  /// Runs the real derivation against a throwaway ledger rather than applying
  /// the recurrence directly, so the preview can never promise a date the list
  /// then contradicts.
  LocalDate? _previewNextDue() {
    final lastDone = _lastDone;
    if (lastDone == null) return null;
    const previewId = 'preview';
    return deriveStatus(
      Maintenance(
        id: previewId,
        name: previewId,
        iconKey: _iconKey,
        recurrence: Recurrence.clamped(_every, _unit),
      ),
      [
        MaintenanceLogEntry(
          id: MaintenanceLogEntry.doneId(previewId, lastDone),
          maintenanceId: previewId,
          date: lastDone,
          status: MaintenanceEntryStatus.done,
          recordedByUid: '',
          recordedByName: '',
        ),
      ],
      LocalDate.today(),
    ).nextDue;
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}
