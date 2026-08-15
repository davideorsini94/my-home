import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/date_format_it.dart';
import '../../core/waste_catalogue.dart';
import '../../domain/entities/waste_config.dart';
import '../../widgets/async_view.dart';
import '../../widgets/waste_badges.dart';

/// Picks which waste types this house monitors, and links to each one's setup.
class WasteConfigListScreen extends ConsumerWidget {
  const WasteConfigListScreen({super.key, required this.houseId});

  final String houseId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configs = ref.watch(wasteConfigsProvider(houseId));
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Rifiuti monitorati'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/house/$houseId'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: AsyncView(
          value: configs,
          onRetry: () => ref.invalidate(wasteConfigsProvider(houseId)),
          builder: (context, list) {
            final byType = {for (final c in list) c.type: c};

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  'Attiva solo i rifiuti che vuoi monitorare in questa '
                  'abitazione, poi imposta per ciascuno i ritiri gratuiti e i '
                  'giorni di raccolta.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                for (final type in WasteType.values) ...[
                  _WasteRow(houseId: houseId, type: type, config: byType[type]),
                  const SizedBox(height: 10),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _WasteRow extends ConsumerWidget {
  const _WasteRow({
    required this.houseId,
    required this.type,
    required this.config,
  });

  final String houseId;
  final WasteType type;
  final WasteConfig? config;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final enabled = config?.enabled ?? false;
    final rule = config?.primaryRule;

    final summary = !enabled
        ? 'Non monitorato'
        : [
            if (rule != null && rule.weekdays.isNotEmpty)
              formatSchedule(rule.weekdays, rule.intervalWeeks)
            else
              'Giorni di ritiro da impostare',
            _policyLabel(config!.policy),
          ].join(' · ');

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            value: enabled,
            secondary: WasteAvatar(type: type),
            title: Text(
              type.label,
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            subtitle: Text(summary),
            onChanged: (value) async {
              final repository = ref.read(wasteConfigRepositoryProvider);
              try {
                if (value && config == null) {
                  // First activation seeds a sensible default so the type is
                  // immediately usable; the editor refines it.
                  await repository.saveConfig(
                    houseId,
                    WasteConfig(
                      type: type,
                      enabled: true,
                      policy: const QuotaPolicy.unlimited(),
                      rules: const [],
                    ),
                  );
                } else {
                  await repository.setEnabled(houseId, type, value);
                }
                ref.read(notificationSyncProvider).requestSync();
                if (value && context.mounted) {
                  context.go('/house/$houseId/waste/${type.id}');
                }
              } on Exception catch (e) {
                if (context.mounted) {
                  showMessage(
                    context,
                    'Modifica non riuscita: $e',
                    isError: true,
                  );
                }
              }
            },
          ),
          if (enabled)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 8, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () =>
                        context.go('/house/$houseId/waste/${type.id}'),
                    icon: const Icon(Icons.tune, size: 18),
                    label: const Text('Configura'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _policyLabel(QuotaPolicy policy) => switch (policy.kind) {
    QuotaKind.unlimited => 'gratuiti illimitati',
    QuotaKind.paid => 'tutti a pagamento',
    QuotaKind.limited => '${policy.yearlyQuota ?? 0} gratuiti/anno',
  };
}
