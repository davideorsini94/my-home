import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../widgets/async_view.dart';
import 'settings_service.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool? _osNotificationsEnabled;

  @override
  void initState() {
    super.initState();
    _refreshOsPermission();
  }

  Future<void> _refreshOsPermission() async {
    final enabled = await ref
        .read(notificationServiceProvider)
        .areNotificationsEnabled();
    if (mounted) setState(() => _osNotificationsEnabled = enabled);
  }

  Future<void> _pickTime(AppSettings settings) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: settings.notificationTime,
      helpText: 'Orario della notifica',
    );
    if (picked == null) return;
    await ref
        .read(settingsProvider.notifier)
        .update(
          settings.copyWith(
            notificationHour: picked.hour,
            notificationMinute: picked.minute,
          ),
        );
  }

  Future<void> _toggleExactAlarms(AppSettings settings, bool value) async {
    final service = ref.read(notificationServiceProvider);
    if (!value) {
      service.setExactAlarmsPreference(false);
      await ref
          .read(settingsProvider.notifier)
          .update(settings.copyWith(exactAlarms: false));
      return;
    }

    final granted = await service.requestExactAlarmsPermission();
    await ref
        .read(settingsProvider.notifier)
        .update(settings.copyWith(exactAlarms: granted));
    if (!granted && mounted) {
      showMessage(
        context,
        'Permesso non concesso: le notifiche restano approssimative.',
      );
    }
  }

  Future<void> _signOut() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Uscire dall\'account?'),
        content: const Text(
          'I dati restano al sicuro nel cloud e li ritrovi al prossimo accesso.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Esci'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await ref.read(notificationSchedulerProvider).cancelAllForSignOut();
    await ref.read(authRepositoryProvider).signOut();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final user = ref.watch(currentUserProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Impostazioni'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          children: [
            if (_osNotificationsEnabled == false)
              Card(
                margin: const EdgeInsets.all(16),
                color: theme.colorScheme.errorContainer,
                child: ListTile(
                  leading: Icon(
                    Icons.notifications_off_outlined,
                    color: theme.colorScheme.onErrorContainer,
                  ),
                  title: const Text('Notifiche disattivate'),
                  subtitle: const Text(
                    'Il sistema blocca le notifiche dell\'app. Tocca per '
                    'concedere il permesso.',
                  ),
                  onTap: () async {
                    await ref
                        .read(notificationServiceProvider)
                        .requestPermission();
                    await _refreshOsPermission();
                  },
                ),
              ),

            _SectionHeader('Notifiche'),
            SwitchListTile(
              secondary: const Icon(Icons.notifications_outlined),
              title: const Text('Promemoria dei ritiri'),
              subtitle: const Text('Avviso la sera prima di ogni ritiro'),
              value: settings.notificationsEnabled,
              onChanged: (value) => notifier.update(
                settings.copyWith(notificationsEnabled: value),
              ),
            ),
            SwitchListTile(
              secondary: const Icon(Icons.build_outlined),
              title: const Text('Promemoria manutenzioni'),
              subtitle: const Text(
                'Avviso il giorno in cui una manutenzione è in scadenza',
              ),
              value: settings.maintenanceRemindersEnabled,
              onChanged: settings.notificationsEnabled
                  ? (value) => notifier.update(
                      settings.copyWith(maintenanceRemindersEnabled: value),
                    )
                  : null,
            ),
            ListTile(
              leading: const Icon(Icons.schedule),
              title: const Text('Orario della notifica'),
              subtitle: Text(
                '${settings.notificationHour.toString().padLeft(2, '0')}:'
                '${settings.notificationMinute.toString().padLeft(2, '0')} '
                '— la sera prima dei ritiri, il giorno stesso per le manutenzioni',
              ),
              enabled: settings.notificationsEnabled,
              onTap: settings.notificationsEnabled
                  ? () => _pickTime(settings)
                  : null,
            ),
            if (Platform.isAndroid) ...[
              SwitchListTile(
                secondary: const Icon(Icons.alarm),
                title: const Text('Orario preciso'),
                subtitle: const Text(
                  'Senza, il sistema può ritardare la notifica di qualche '
                  'minuto per risparmiare batteria',
                ),
                value: settings.exactAlarms,
                onChanged: settings.notificationsEnabled
                    ? (value) => _toggleExactAlarms(settings, value)
                    : null,
              ),
              const ListTile(
                leading: Icon(Icons.battery_alert_outlined),
                title: Text('Le notifiche non arrivano?'),
                subtitle: Text(
                  'Su alcuni telefoni (Xiaomi, Huawei, Samsung) il risparmio '
                  'energetico blocca le app in background. Escludi Rubbish '
                  'Manager dall\'ottimizzazione batteria nelle impostazioni '
                  'di sistema.',
                  style: TextStyle(height: 1.4),
                ),
                isThreeLine: true,
              ),
            ],

            const Divider(),
            _SectionHeader('Aspetto'),
            ListTile(
              leading: const Icon(Icons.palette_outlined),
              title: const Text('Tema'),
              subtitle: Text(switch (settings.themeMode) {
                ThemeMode.light => 'Chiaro',
                ThemeMode.dark => 'Scuro',
                ThemeMode.system => 'Come il sistema',
              }),
              trailing: SegmentedButton<ThemeMode>(
                segments: const [
                  ButtonSegment(
                    value: ThemeMode.system,
                    icon: Icon(Icons.brightness_auto),
                  ),
                  ButtonSegment(
                    value: ThemeMode.light,
                    icon: Icon(Icons.light_mode),
                  ),
                  ButtonSegment(
                    value: ThemeMode.dark,
                    icon: Icon(Icons.dark_mode),
                  ),
                ],
                selected: {settings.themeMode},
                showSelectedIcon: false,
                onSelectionChanged: (selection) => notifier.update(
                  settings.copyWith(themeMode: selection.first),
                ),
              ),
            ),

            const Divider(),
            _SectionHeader('Account'),
            ListTile(
              leading: CircleAvatar(
                backgroundImage: user?.photoUrl != null
                    ? NetworkImage(user!.photoUrl!)
                    : null,
                child: user?.photoUrl == null
                    ? const Icon(Icons.person_outline)
                    : null,
              ),
              title: Text(user?.shortName ?? 'Non connesso'),
              subtitle: Text(user?.email ?? ''),
            ),
            ListTile(
              leading: Icon(Icons.logout, color: theme.colorScheme.error),
              title: Text(
                'Esci',
                style: TextStyle(color: theme.colorScheme.error),
              ),
              onTap: _signOut,
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      text.toUpperCase(),
      style: Theme.of(context).textTheme.labelSmall?.copyWith(
        color: Theme.of(context).colorScheme.primary,
        fontWeight: FontWeight.bold,
        letterSpacing: 1.2,
      ),
    ),
  );
}
