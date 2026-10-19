import 'package:flutter/material.dart';

import '../app/design.dart';
import '../app/theme.dart';
import '../core/waste_catalogue.dart';
import '../domain/quota_calculator.dart';

/// The coloured marker that identifies a waste type.
///
/// One rule, applied everywhere a type appears: a solid tile of the type's own
/// colour with the icon knocked out of it. The summary pills on a house card,
/// the rows in the monitored-waste list and the legends in the statistics all
/// go through this widget, so the colour you learn in one place is the colour
/// you recognise in the others. The earlier pills tinted the icon and washed
/// the background down to 14% alpha, which read as a different, paler palette
/// than the bins themselves.
///
/// Always pairs the colour with the type's icon, because the palette contains
/// two browns (Umido and Verde leggero) that colour alone does not separate
/// reliably.
class WasteAvatar extends StatelessWidget {
  const WasteAvatar({super.key, required this.type, this.size = 44});

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
        borderRadius: BorderRadius.circular(size / 2.8),
      ),
      // 0.62 rather than the 0.55 this used to be: the icon is the only thing
      // in the tile, and at the old ratio it floated in the middle of a field
      // of colour instead of filling it.
      child: Icon(type.icon, size: size * 0.62, color: onWasteColor(color)),
    );
  }
}

/// A type's yearly count, carrying the bin's own colour.
///
/// Used on the house cards. The tile inside is the same [WasteAvatar] the
/// monitored-waste list uses, so the two screens agree about what, say, Carta
/// looks like; the surrounding pill is a quiet tint of the same hue so a row of
/// these reads as a group rather than six loose squares.
class WasteCountTile extends StatelessWidget {
  const WasteCountTile({
    super.key,
    required this.type,
    required this.count,
    this.avatarSize = 34,
  });

  final WasteType type;

  /// Null while the year's ledger is still loading, so the tile can show a
  /// placeholder rather than a zero that would read as "nothing collected".
  final int? count;
  final double avatarSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = wasteColor(context, type);
    const padding = 4.0;

    return Semantics(
      label: '${type.label}: ${count ?? 'in caricamento'}',
      child: Container(
        padding: const EdgeInsets.fromLTRB(padding, padding, 12, padding),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(
            AppRadius.concentric(avatarSize / 2.8 + padding, 0),
          ),
          border: Border.all(color: color.withValues(alpha: 0.32)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ExcludeSemantics(
              child: WasteAvatar(type: type, size: avatarSize),
            ),
            const SizedBox(width: 9),
            Text(
              count?.toString() ?? '–',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A compact type label with its colour, for dense lists.
class WasteChip extends StatelessWidget {
  const WasteChip({super.key, required this.type});

  final WasteType type;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      WasteAvatar(type: type, size: 26),
      const SizedBox(width: 8),
      Text(
        type.label,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
      ),
    ],
  );
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppRadius.chip),
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
            WasteAvatar(type: status.type, size: 30),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                status.type.label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            QuotaBadge(status: status),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress ?? 0,
            minHeight: 7,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(
              status.isExhausted ? theme.colorScheme.error : color,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(detail, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}
