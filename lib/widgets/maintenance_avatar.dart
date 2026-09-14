import 'package:flutter/material.dart';

import '../core/maintenance_icons.dart';

/// How urgent a maintenance is, which decides the avatar's colour.
enum MaintenanceTone {
  /// Scheduled, nothing to do yet.
  normal,

  /// Due today or already past due.
  overdue,

  /// Never executed, or no schedule can be computed.
  idle,
}

/// The coloured marker identifying a maintenance in lists and sheets.
class MaintenanceAvatar extends StatelessWidget {
  const MaintenanceAvatar({
    super.key,
    required this.iconKey,
    this.tone = MaintenanceTone.normal,
    this.size = 44,
  });

  final String iconKey;
  final MaintenanceTone tone;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (background, foreground) = switch (tone) {
      MaintenanceTone.overdue => (scheme.errorContainer, scheme.onErrorContainer),
      MaintenanceTone.normal => (scheme.primaryContainer, scheme.onPrimaryContainer),
      MaintenanceTone.idle => (
        scheme.surfaceContainerHighest,
        scheme.onSurfaceVariant,
      ),
    };

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size / 3),
      ),
      child: Icon(
        maintenanceIconFor(iconKey).icon,
        size: size * 0.55,
        color: foreground,
      ),
    );
  }
}
