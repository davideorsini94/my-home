import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/date_format_it.dart';
import '../../core/local_date.dart';
import '../../core/waste_catalogue.dart';
import '../../domain/entities/collection_event.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/async_view.dart';
import '../../widgets/waste_badges.dart';

Future<void> showRecordExtraSheet(
  BuildContext context,
  WidgetRef ref,
  String houseId,
) => showAppSheet<void>(
  context: context,
  builder: (context) => _RecordExtraSheet(houseId: houseId),
);

/// Records an off-schedule collection.
///
/// Extras have no deterministic id — two extra bags on the same day are two
/// real events — so this sheet is the one place in the app where a double tap
/// really would double-count. It therefore shows what is already recorded today
/// before committing.
class _RecordExtraSheet extends ConsumerStatefulWidget {
  const _RecordExtraSheet({required this.houseId});

  final String houseId;

  @override
  ConsumerState<_RecordExtraSheet> createState() => _RecordExtraSheetState();
}

class _RecordExtraSheetState extends ConsumerState<_RecordExtraSheet> {
  WasteType? _type;
  LocalDate _date = LocalDate.today();
  final _noteController = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final type = _type;
    final user = ref.read(currentUserProvider);
    if (type == null || user == null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(collectionRepositoryProvider)
          .recordExtra(
            houseId: widget.houseId,
            type: type,
            date: _date,
            uid: user.uid,
            userName: user.shortName,
            unique: DateTime.now().microsecondsSinceEpoch.toRadixString(36),
            note: _noteController.text.trim(),
          );
      ref.read(notificationSyncProvider).requestSync();
      if (mounted) {
        Navigator.of(context).pop();
        showMessage(context, 'Raccolta extra registrata.');
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
    final configs =
        ref.watch(wasteConfigsProvider(widget.houseId)).value ?? const [];
    final enabled = configs.where((c) => c.enabled).toList();
    final events =
        ref.watch(currentYearCollectionsProvider(widget.houseId)).value ??
        const <CollectionEvent>[];

    final sameDay = events.where((e) => e.date == _date).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Registra raccolta extra',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Per un ritiro fuori calendario. Conta comunque nel totale '
              'annuale.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 20),

            if (enabled.isEmpty)
              const Text('Nessun rifiuto monitorato in questa abitazione.')
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final config in enabled)
                    ChoiceChip(
                      avatar: Icon(
                        config.type.icon,
                        size: 18,
                        color: config.type.colorFor(theme.brightness),
                      ),
                      label: Text(config.type.label),
                      selected: _type == config.type,
                      onSelected: (_) => setState(() => _type = config.type),
                    ),
                ],
              ),

            const SizedBox(height: 20),
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
                  firstDate: DateTime(DateTime.now().year - 1),
                  lastDate: DateTime.now(),
                );
                if (picked != null) {
                  setState(() => _date = LocalDate.fromDateTime(picked));
                }
              },
            ),

            if (sameDay.isNotEmpty) ...[
              const SizedBox(height: 8),
              Card(
                color: theme.colorScheme.secondaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Già registrate in questa data',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 12,
                        runSpacing: 4,
                        children: [
                          for (final event in sameDay)
                            WasteChip(type: event.type),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 16),
            TextField(
              controller: _noteController,
              maxLength: 80,
              decoration: const InputDecoration(
                labelText: 'Nota (facoltativa)',
                hintText: 'Es. sacco extra',
              ),
            ),

            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _type == null || _busy ? null : _save,
                child: Text(_busy ? 'Registrazione…' : 'Registra'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
