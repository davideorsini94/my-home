import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/providers.dart';
import '../../core/waste_catalogue.dart';
import '../../data/auth_repository.dart';
import '../../widgets/async_view.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  bool _busy = false;

  Future<void> _signIn() async {
    setState(() => _busy = true);
    try {
      await ref.read(authRepositoryProvider).signInWithGoogle();
      // Navigation is handled by the router's auth redirect.
    } on AuthException catch (e) {
      if (mounted) showMessage(context, e.message, isError: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _BinCluster(),
                const SizedBox(height: 32),
                Text(
                  'Rubbish Manager',
                  style: theme.textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Tieni traccia dei ritiri dei rifiuti di casa e '
                  'condividili con la tua famiglia.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 40),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _busy ? null : _signIn,
                    icon: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.login),
                    label: Text(
                      _busy ? 'Accesso in corso…' : 'Accedi con Google',
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Serve un account Google per condividere le abitazioni '
                  'con gli altri membri della famiglia.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The six catalogue colours as a row of bins — doubles as a legend.
class _BinCluster extends StatelessWidget {
  const _BinCluster();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      alignment: WrapAlignment.center,
      children: [
        for (final type in WasteType.values)
          Container(
            width: 44,
            height: 52,
            decoration: BoxDecoration(
              color: type.colorFor(brightness),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(6),
                bottom: Radius.circular(10),
              ),
            ),
            child: Icon(
              type.icon,
              size: 22,
              color: type.colorFor(brightness).computeLuminance() > 0.5
                  ? Colors.black87
                  : Colors.white,
            ),
          ),
      ],
    );
  }
}
