import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/date_format_it.dart';
import '../../core/local_date.dart';
import '../../core/waste_catalogue.dart';
import '../../domain/entities/collection_event.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/button_label.dart';
import '../../widgets/async_view.dart';

Future<void> showEditEventSheet(
  BuildContext context,
  String houseId,
  CollectionEvent event,
  List<CollectionEvent> siblings,
) => showAppSheet<void>(
  context: context,
  builder: (context) =>
      _EditEventSheet(houseId: houseId, event: event, siblings: siblings),
);

/// Corrects or removes a recorded collection.
///
/// The counters need no repair of their own: they are derived from these
/// records, so fixing the record fixes every total that depends on it.
class _EditEventSheet extends ConsumerStatefulWidget {
  const _EditEventSheet({
    required this.houseId,
    required this.event,
    required this.siblings,
  });

  final String houseId;
  final CollectionEvent event;
  final List<CollectionEvent> siblings;

  @override
  ConsumerState<_EditEventSheet> createState() => _EditEventSheetState();
}

class _EditEventSheetState extends ConsumerState<_EditEventSheet> {
  late WasteType _type = widget.event.type;
  late LocalDate _date = widget.event.date;
  late CollectionStatus _status = widget.event.status;
  late final TextEditingController _noteController = TextEditingController(
    text: widget.event.note ?? '',
  );
  bool _busy = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _wouldMerge => ref
      .read(collectionRepositoryProvider)
      .wouldMerge(
        original: widget.event,
        type: _type,
        date: _date,
        existing: widget.siblings,
      );

  Future<void> _save() async {
    if (_wouldMerge) {
      final confirmed = await _confirm(
        title: 'Unione di due raccolte',
        message:
            'Esiste già una raccolta di ${_type.label} il '
            '${formatNumeric(_date)}. Le due registrazioni verranno unite in '
            'una sola e il contatore diminuirà di uno.',
        confirmLabel: 'Unisci',
      );
      if (confirmed != true) return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(collectionRepositoryProvider)
          .updateEvent(
            houseId: widget.houseId,
            original: widget.event,
            type: _type,
            date: _date,
            status: _status,
            note: _noteController.text.trim(),
          );
      ref.read(notificationSyncProvider).requestSync();
      if (mounted) {
        Navigator.of(context).pop();
        showMessage(context, 'Raccolta aggiornata.');
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
    final confirmed = await _confirm(
      title: 'Eliminare la raccolta?',
      message:
          'La registrazione verrà eliminata e il contatore di '
          '${widget.event.type.label} si aggiornerà automaticamente.',
      confirmLabel: 'Elimina',
      destructive: true,
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(collectionRepositoryProvider)
          .deleteEvent(widget.houseId, widget.event.id);
      ref.read(notificationSyncProvider).requestSync();
      if (mounted) {
        Navigator.of(context).pop();
        showMessage(context, 'Raccolta eliminata.');
      }
    } on Exception catch (e) {
      if (mounted) {
        showMessage(context, 'Eliminazione non riuscita: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<bool?> _confirm({
    required String title,
    required String message,
    required String confirmLabel,
    bool destructive = false,
  }) => showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Annulla'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: destructive
              ? FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.error,
                  foregroundColor: Theme.of(context).colorScheme.onError,
                )
              : null,
          child: Text(confirmLabel),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configs =
        ref.watch(wasteConfigsProvider(widget.houseId)).value ?? const [];
    final types = configs.where((c) => c.enabled).map((c) => c.type).toSet()
      ..add(widget.event.type);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Modifica raccolta',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Registrata da ${widget.event.recordedByName}'
              '${widget.event.isExtra ? ' · extra' : ''}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            Text('Tipo di rifiuto', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final type in types)
                  ChoiceChip(
                    avatar: Icon(
                      type.icon,
                      size: 18,
                      color: type.colorFor(theme.brightness),
                    ),
                    label: Text(type.label),
                    selected: _type == type,
                    onSelected: (_) => setState(() => _type = type),
                  ),
              ],
            ),

            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_today_outlined),
              title: const Text('Data'),
              subtitle: Text(formatLong(_date)),
              trailing: const Icon(Icons.edit_calendar_outlined),
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _date.toLocalDateTime(),
                  firstDate: DateTime(DateTime.now().year - 2),
                  lastDate: DateTime(DateTime.now().year + 1, 12, 31),
                );
                if (picked != null) {
                  setState(() => _date = LocalDate.fromDateTime(picked));
                }
              },
            ),

            if (_wouldMerge)
              Card(
                color: theme.colorScheme.tertiaryContainer,
                child: const ListTile(
                  leading: Icon(Icons.merge_outlined),
                  title: Text('Esiste già una raccolta per quel giorno'),
                  subtitle: Text('Le due registrazioni verranno unite.'),
                ),
              ),

            if (!widget.event.isExtra) ...[
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                secondary: const Icon(Icons.next_plan_outlined),
                title: const Text('Ritiro saltato'),
                subtitle: Text(
                  _status == CollectionStatus.skipped
                      ? 'Resta nello storico ma non conta nel totale annuale'
                      : 'Attiva se quel giorno non hai portato fuori nulla',
                ),
                value: _status == CollectionStatus.skipped,
                onChanged: (value) => setState(
                  () => _status = value
                      ? CollectionStatus.skipped
                      : CollectionStatus.done,
                ),
              ),
            ],

            const SizedBox(height: 12),
            TextField(
              controller: _noteController,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Nota'),
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
