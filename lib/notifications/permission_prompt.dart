import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/providers.dart';
import '../widgets/async_view.dart';

/// Asks for notification permission at the first moment it actually means
/// something to the user — right after they set up a pickup schedule.
///
/// Android 13+ will not post anything without this grant, and it is never
/// requested implicitly: without an explicit prompt the reminders would simply
/// never appear, with nothing on screen to explain why. Asking at app launch
/// instead would be a permission dialog before the user knows what it is for.
///
/// Returns true when the app may post notifications.
Future<bool> ensureNotificationPermission(
  BuildContext context,
  WidgetRef ref,
) async {
  final service = ref.read(notificationServiceProvider);

  if (await service.areNotificationsEnabled()) return true;
  if (!context.mounted) return false;

  final wantsThem = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: const Icon(Icons.notifications_active_outlined),
      title: const Text('Vuoi il promemoria dei ritiri?'),
      content: const Text(
        'La sera prima di ogni ritiro ti avvisiamo di cosa portare fuori e '
        'quanti ritiri gratuiti restano. Dalla notifica puoi registrare la '
        'raccolta senza aprire l\'app.\n\n'
        'Per farlo serve il permesso di inviare notifiche.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Non ora'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Attiva'),
        ),
      ],
    ),
  );

  if (wantsThem != true) return false;

  await service.requestPermission();
  final granted = await service.areNotificationsEnabled();

  if (!granted && context.mounted) {
    // Android stops showing the system dialog after two refusals, so pointing
    // at the settings is the only remaining route.
    showMessage(
      context,
      'Permesso non concesso. Puoi attivarlo dalle impostazioni di sistema '
      'dell\'app, oppure da Impostazioni qui dentro.',
    );
  }
  return granted;
}
