import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../core/waste_catalogue.dart';
import '../domain/quota_calculator.dart';

/// The coloured marker that identifies a waste type.
///
/// Always pairs the colour with the type's icon, because the palette contains
/// two browns (Umido and Verde leggero) that colour alone does not separate
/// reliably.
class WasteAvatar extends StatelessWidget {
  const WasteAvatar({super.key, required this.type, this.size = 40});

  final WasteType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final color = wasteColor(context, type);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(
        type.icon,
        size: size * 0.55,
        color: onWasteColor(color),
      ),
    );
  }
}

/// A compact type label with its colour, for dense lists.
class WasteChip extends StatelessWidget {
  const WasteChip({super.key, required this.type});

  final WasteType type;

  @override
  Widget build(BuildContext context) {
    final color = wasteColor(context, type);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(type.icon, size: 18, color: color),
        const SizedBox(width: 6),
        Text(
          type.label,
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

/// "3/12 gratuiti", turning red once the free allowance is gone.
class QuotaBadge extends StatelessWidget {
  const QuotaBadge({super.key, required this.status});

  final QuotaStatus status;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isBillable = status.isExhausted || status.isAlwaysPaid;
    final background = isBillable
        ? scheme.errorContainer
        : scheme.surfaceContainerHighest;
    final foreground = isBillable
        ? scheme.onErrorContainer
        : scheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.shortLabel,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Progress towards the yearly free allowance.
class QuotaProgress extends StatelessWidget {
  const QuotaProgress({super.key, required this.status});

  final QuotaStatus status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = wasteColor(context, status.type);

    final String detail;
    final double? progress;
    if (status.isUnlimited) {
      detail = '${status.used} raccolte · gratuite illimitate';
      progress = null;
    } else if (status.isAlwaysPaid) {
      detail = '${status.used} raccolte · tutte a pagamento';
      progress = null;
    } else {
      final quota = status.quota ?? 0;
      detail = quota == 0
          ? '${status.used} raccolte · nessuna gratuita'
          : '${status.used} su $quota gratuite'
                '${status.billed > 0 ? ' · ${status.billed} a pagamento' : ''}';
      progress = quota == 0 ? 1 : (status.used / quota).clamp(0.0, 1.0);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(status.type.icon, size: 18, color: color),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                status.type.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            QuotaBadge(status: status),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress ?? 0,
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(
              status.isExhausted ? theme.colorScheme.error : color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(detail, style: theme.textTheme.bodySmall),
      ],
    );
  }
}
