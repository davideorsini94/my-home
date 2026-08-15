import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/date_format_it.dart';
import '../../core/local_date.dart';
import '../../core/waste_catalogue.dart';
import '../../domain/entities/waste_config.dart';
import '../../domain/schedule_engine.dart';
import '../../notifications/permission_prompt.dart';
import '../../widgets/async_view.dart';
import '../../widgets/waste_badges.dart';

/// Sets the free-collection policy and the pickup schedule for one waste type.
class WasteConfigEditScreen extends ConsumerStatefulWidget {
  const WasteConfigEditScreen({
    super.key,
    required this.houseId,
    required this.type,
  });

  final String houseId;
  final WasteType type;

  @override
  ConsumerState<WasteConfigEditScreen> createState() =>
      _WasteConfigEditScreenState();
}

class _WasteConfigEditScreenState extends ConsumerState<WasteConfigEditScreen> {
  QuotaKind _kind = QuotaKind.unlimited;
  int _quota = 12;
  Set<int> _weekdays = {};
  int _intervalWeeks = 1;
  LocalDate _anchor = LocalDate.today();
  bool _loaded = false;
  bool _busy = false;

  void _hydrate(WasteConfig? config) {
    if (_loaded || config == null) return;
    _kind = config.policy.kind;
    _quota = config.policy.yearlyQuota ?? 12;
    final rule = config.primaryRule;
    if (rule != null) {
      _weekdays = {...rule.weekdays};
      _intervalWeeks = rule.intervalWeeks;
      _anchor = rule.anchorDate;
    }
    _loaded = true;
  }

  Future<void> _save() async {
    if (_weekdays.isEmpty) {
      showMessage(context, 'Scegli almeno un giorno di ritiro.', isError: true);
      return;
    }

    setState(() => _busy = true);
    try {
      await ref
          .read(wasteConfigRepositoryProvider)
          .saveConfig(
            widget.houseId,
            WasteConfig(
              type: widget.type,
              enabled: true,
              policy: QuotaPolicy(
                kind: _kind,
                yearlyQuota: _kind == QuotaKind.limited ? _quota : null,
              ),
              rules: [
                ScheduleRule(
                  weekdays: _weekdays,
                  intervalWeeks: _intervalWeeks,
                  anchorDate: _anchor,
                ),
              ],
            ),
          );
      // A schedule now exists, so the reminder permission finally has a
      // meaning the user can judge. Asked before navigating away.
      if (mounted) await ensureNotificationPermission(context, ref);
      ref.read(notificationSyncProvider).requestSync();
      if (mounted) context.go('/house/${widget.houseId}/waste');
    } on Exception catch (e) {
      if (mounted) {
        showMessage(context, 'Salvataggio non riuscito: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final configs = ref.watch(wasteConfigsProvider(widget.houseId));

    configs.whenData((list) {
      _hydrate(list.where((c) => c.type == widget.type).firstOrNull);
    });

    final preview = _weekdays.isEmpty
        ? const <LocalDate>[]
        : nextPickups(
            WasteConfig(
              type: widget.type,
              enabled: true,
              policy: const QuotaPolicy.unlimited(),
              rules: [
                ScheduleRule(
                  weekdays: _weekdays,
                  intervalWeeks: _intervalWeeks,
                  anchorDate: _anchor,
                ),
              ],
            ),
            LocalDate.today(),
            count: 3,
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.type.label),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/house/${widget.houseId}/waste'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
          children: [
            Row(
              children: [
                WasteAvatar(type: widget.type, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.type.label,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            _SectionTitle('Ritiri gratuiti'),
            Card(
              child: Column(
                children: [
                  RadioListTile<QuotaKind>(
                    value: QuotaKind.limited,
                    groupValue: _kind,
                    title: const Text('Numero limitato all\'anno'),
                    subtitle: const Text(
                      'Oltre il limite i ritiri sono a pagamento',
                    ),
                    onChanged: (v) => setState(() => _kind = v!),
                  ),
                  if (_kind == QuotaKind.limited)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              '$_quota ritiri gratuiti all\'anno',
                              style: theme.textTheme.bodyMedium,
                            ),
                          ),
                          IconButton.filledTonal(
                            onPressed: _quota > 1
                                ? () => setState(() => _quota--)
                                : null,
                            icon: const Icon(Icons.remove),
                          ),
                          const SizedBox(width: 8),
                          IconButton.filledTonal(
                            onPressed: _quota < 500
                                ? () => setState(() => _quota++)
                                : null,
                            icon: const Icon(Icons.add),
                          ),
                        ],
                      ),
                    ),
                  RadioListTile<QuotaKind>(
                    value: QuotaKind.unlimited,
                    groupValue: _kind,
                    title: const Text('Illimitati'),
                    subtitle: const Text('Nessun limite, sempre gratuiti'),
                    onChanged: (v) => setState(() => _kind = v!),
                  ),
                  RadioListTile<QuotaKind>(
                    value: QuotaKind.paid,
                    groupValue: _kind,
                    title: const Text('Tutti a pagamento'),
                    subtitle: const Text('Nessun ritiro gratuito'),
                    onChanged: (v) => setState(() => _kind = v!),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),
            _SectionTitle('Giorni di ritiro'),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (
                          var day = DateTime.monday;
                          day <= DateTime.sunday;
                          day++
                        )
                          FilterChip(
                            label: Text(
                              weekdayShort(day)[0].toUpperCase() +
                                  weekdayShort(day).substring(1),
                            ),
                            selected: _weekdays.contains(day),
                            onSelected: (selected) => setState(() {
                              if (selected) {
                                _weekdays.add(day);
                              } else {
                                _weekdays.remove(day);
                              }
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    Text('Frequenza', style: theme.textTheme.labelLarge),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<int>(
                      value: _intervalWeeks,
                      // Without this the field sizes itself to its widest item
                      // and overflows the card on narrow screens.
                      isExpanded: true,
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.repeat),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 1,
                          child: Text('Ogni settimana'),
                        ),
                        DropdownMenuItem(
                          value: 2,
                          child: Text('Ogni 2 settimane'),
                        ),
                        DropdownMenuItem(
                          value: 3,
                          child: Text('Ogni 3 settimane'),
                        ),
                        DropdownMenuItem(
                          value: 4,
                          child: Text('Ogni 4 settimane'),
                        ),
                      ],
                      onChanged: (v) => setState(() => _intervalWeeks = v ?? 1),
                    ),
                    if (_intervalWeeks == 2)
                      Padding(
                        padding: const EdgeInsets.only(top: 6, left: 12),
                        child: Text(
                          'Corrisponde a "ogni 15 giorni"',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (_intervalWeeks > 1) ...[
                      const SizedBox(height: 16),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_outlined),
                        title: const Text('Settimana di riferimento'),
                        subtitle: Text(
                          '${formatNumeric(_anchor)} — un giorno qualsiasi di '
                          'una settimana in cui il ritiro avviene',
                        ),
                        trailing: const Icon(Icons.edit_calendar_outlined),
                        onTap: () async {
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: _anchor.toLocalDateTime(),
                            firstDate: DateTime(DateTime.now().year - 2),
                            lastDate: DateTime(DateTime.now().year + 2),
                            helpText: 'Settimana di riferimento',
                          );
                          if (picked != null) {
                            setState(
                              () => _anchor = LocalDate.fromDateTime(picked),
                            );
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),

            if (preview.isNotEmpty) ...[
              const SizedBox(height: 20),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Prossimi ritiri',
                        style: theme.textTheme.labelLarge,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        preview.map(formatShort).join(' · '),
                        style: theme.textTheme.bodyMedium,
                      ),
                    ],
                  ),
                ),
              ),
            ],

            const SizedBox(height: 24),
            FilledButton(
              onPressed: _busy ? null : _save,
              child: Text(_busy ? 'Salvataggio…' : 'Salva configurazione'),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: Theme.of(
        context,
      ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
    ),
  );
}
