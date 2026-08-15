import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../data/invite_repository.dart';
import '../../domain/entities/invite.dart';
import '../../widgets/async_view.dart';

/// Joins a house using an invite code.
class JoinHouseScreen extends ConsumerStatefulWidget {
  const JoinHouseScreen({super.key, this.initialCode});

  final String? initialCode;

  @override
  ConsumerState<JoinHouseScreen> createState() => _JoinHouseScreenState();
}

class _JoinHouseScreenState extends ConsumerState<JoinHouseScreen> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialCode ?? '',
  );
  Invite? _found;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _lookup() async {
    setState(() {
      _busy = true;
      _error = null;
      _found = null;
    });

    try {
      final invite = await ref
          .read(inviteRepositoryProvider)
          .lookup(_controller.text);
      if (invite == null) {
        setState(() => _error = 'Codice non trovato. Controlla e riprova.');
      } else if (invite.isExpired) {
        setState(
          () => _error =
              'Questo codice è scaduto. Chiedine uno nuovo a chi ti ha invitato.',
        );
      } else {
        setState(() => _found = invite);
      }
    } on Exception catch (e) {
      setState(() => _error = 'Ricerca non riuscita: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _join() async {
    final invite = _found;
    final user = ref.read(currentUserProvider);
    if (invite == null || user == null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(inviteRepositoryProvider)
          .joinHouse(invite: invite, uid: user.uid, userName: user.shortName);
      ref.read(notificationSyncProvider).requestSync();
      if (mounted) {
        context.go('/house/${invite.houseId}');
        showMessage(context, 'Ti sei unito a «${invite.houseName}».');
      }
    } on InviteException catch (e) {
      setState(() => _error = e.message);
    } on Exception catch (e) {
      setState(() => _error = 'Accesso all\'abitazione non riuscito: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Unisciti a un\'abitazione'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(
              'Inserisci il codice di invito che ti hanno condiviso. '
              'Da quel momento vedrete gli stessi ritiri e gli stessi contatori.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            TextField(
              controller: _controller,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              textAlign: TextAlign.center,
              maxLength: 6,
              style: theme.textTheme.headlineMedium?.copyWith(
                letterSpacing: 8,
                fontWeight: FontWeight.bold,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp('[a-zA-Z0-9]')),
                TextInputFormatter.withFunction(
                  (oldValue, newValue) =>
                      newValue.copyWith(text: newValue.text.toUpperCase()),
                ),
              ],
              decoration: const InputDecoration(
                hintText: 'ABC123',
                counterText: '',
              ),
              onChanged: (_) => setState(() {
                _found = null;
                _error = null;
              }),
              onSubmitted: (_) => _lookup(),
            ),
            const SizedBox(height: 16),

            if (_error != null)
              Card(
                color: theme.colorScheme.errorContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Icon(
                        Icons.error_outline,
                        color: theme.colorScheme.onErrorContainer,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error!,
                          style: TextStyle(
                            color: theme.colorScheme.onErrorContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            if (_found != null)
              Card(
                color: theme.colorScheme.primaryContainer,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Icon(
                        Icons.home_outlined,
                        size: 32,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _found!.houseName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: _busy ? null : _join,
                          child: Text(_busy ? 'Accesso…' : 'Unisciti'),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else
              FilledButton(
                onPressed: _busy || _controller.text.length < 6
                    ? null
                    : _lookup,
                child: Text(_busy ? 'Ricerca…' : 'Cerca abitazione'),
              ),
          ],
        ),
      ),
    );
  }
}
