import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:share_plus/share_plus.dart';

import '../../app/providers.dart';
import '../../domain/entities/house.dart';
import '../../widgets/async_view.dart';
import '../../widgets/button_label.dart';

/// Who shares this house, and how to invite someone else.
class MembersScreen extends ConsumerStatefulWidget {
  const MembersScreen({super.key, required this.houseId});

  final String houseId;

  @override
  ConsumerState<MembersScreen> createState() => _MembersScreenState();
}

class _MembersScreenState extends ConsumerState<MembersScreen> {
  bool _busy = false;

  Future<void> _generateInvite(House house) async {
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(inviteRepositoryProvider)
          .createInvite(
            houseId: house.id,
            houseName: house.name,
            createdByUid: user.uid,
          );
    } on Exception catch (e) {
      if (mounted) {
        showMessage(
          context,
          'Creazione codice non riuscita: $e',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _revokeInvite(House house) async {
    final code = house.activeInviteCode;
    if (code == null) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(inviteRepositoryProvider)
          .revokeInvite(code: code, houseId: house.id);
      if (mounted) showMessage(context, 'Codice revocato.');
    } on Exception catch (e) {
      if (mounted) {
        showMessage(context, 'Revoca non riuscita: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _removeMember(House house, HouseMember member) async {
    final isSelf = member.uid == ref.read(currentUserProvider)?.uid;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          isSelf ? 'Abbandonare l\'abitazione?' : 'Rimuovere il membro?',
        ),
        content: Text(
          isSelf
              ? 'Non vedrai più «${house.name}» né le sue raccolte. '
                    'Potrai rientrare con un nuovo codice di invito.'
              : '${member.label} non vedrà più questa abitazione. '
                    'Le raccolte che ha registrato restano nello storico.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: Text(isSelf ? 'Abbandona' : 'Rimuovi'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref
          .read(houseRepositoryProvider)
          .removeMember(house.id, member.uid);
      ref.read(notificationSyncProvider).requestSync();
      if (isSelf && mounted) context.go('/');
    } on Exception catch (e) {
      if (mounted) {
        showMessage(context, 'Operazione non riuscita: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteHouse(House house) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminare l\'abitazione?'),
        content: Text(
          'Verranno eliminate «${house.name}», la sua configurazione e '
          'tutto lo storico delle raccolte, per tutti i membri. '
          'L\'operazione non è reversibile.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Annulla'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            child: const Text('Elimina'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busy = true);
    try {
      await ref.read(houseRepositoryProvider).deleteHouse(house.id);
      ref.read(notificationSyncProvider).requestSync();
      if (mounted) context.go('/');
    } on Exception catch (e) {
      if (mounted) {
        showMessage(context, 'Eliminazione non riuscita: $e', isError: true);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final house = ref.watch(houseProvider(widget.houseId));
    final uid = ref.watch(currentUserProvider)?.uid;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Membri e condivisione'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/house/${widget.houseId}'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: AsyncView(
          value: house,
          onRetry: () => ref.invalidate(houseProvider(widget.houseId)),
          builder: (context, houseOrNull) {
            if (houseOrNull == null) {
              return const EmptyState(
                icon: Icons.home_outlined,
                title: 'Abitazione non disponibile',
                message: 'Potrebbe essere stata eliminata.',
              );
            }
            final house = houseOrNull;
            final isOwner = uid != null && house.isOwner(uid);
            final code = house.activeInviteCode;

            return ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              children: [
                Text(
                  'Chi condivide questa abitazione vede gli stessi ritiri e '
                  'gli stessi contatori: non importa chi porta fuori il '
                  'pattume, il conteggio prosegue.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 20),

                Card(
                  child: Column(
                    children: [
                      for (var i = 0; i < house.memberList.length; i++) ...[
                        if (i > 0) const Divider(height: 1),
                        _MemberTile(
                          member: house.memberList[i],
                          isSelf: house.memberList[i].uid == uid,
                          canRemove:
                              (isOwner &&
                                  house.memberList[i].role !=
                                      HouseRole.owner) ||
                              (house.memberList[i].uid == uid && !isOwner),
                          busy: _busy,
                          onRemove: () =>
                              _removeMember(house, house.memberList[i]),
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),
                Text(
                  'Invita qualcuno',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),

                if (code == null)
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            'Genera un codice da condividere. Chi lo inserisce '
                            'entra in questa abitazione. Vale 7 giorni e puoi '
                            'revocarlo quando vuoi.',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 16),
                          FilledButton.icon(
                            onPressed: _busy
                                ? null
                                : () => _generateInvite(house),
                            icon: const Icon(Icons.qr_code_2),
                            label: const ButtonLabel('Genera codice di invito'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          SelectableText(
                            code,
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              letterSpacing: 6,
                              fontFeatures: const [
                                FontFeature.tabularFigures(),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () async {
                                    await Clipboard.setData(
                                      ClipboardData(text: code),
                                    );
                                    if (context.mounted) {
                                      showMessage(context, 'Codice copiato.');
                                    }
                                  },
                                  icon: const Icon(Icons.copy, size: 18),
                                  label: const ButtonLabel('Copia'),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: FilledButton.icon(
                                  onPressed: () => SharePlus.instance.share(
                                    ShareParams(
                                      text:
                                          'Unisciti a «${house.name}» su '
                                          'Rubbish Manager con il codice $code',
                                    ),
                                  ),
                                  icon: const Icon(Icons.share, size: 18),
                                  label: const ButtonLabel('Condividi'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          TextButton(
                            onPressed: _busy
                                ? null
                                : () => _revokeInvite(house),
                            child: const Text('Revoca codice'),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (isOwner) ...[
                  const SizedBox(height: 32),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : () => _deleteHouse(house),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: theme.colorScheme.error,
                      minimumSize: const Size(0, 48),
                    ),
                    icon: const Icon(Icons.delete_forever_outlined),
                    label: const ButtonLabel('Elimina abitazione'),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Solo il proprietario può eliminare l\'abitazione. '
                    'Il trasferimento della proprietà non è previsto.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.member,
    required this.isSelf,
    required this.canRemove,
    required this.busy,
    required this.onRemove,
  });

  final HouseMember member;
  final bool isSelf;
  final bool canRemove;
  final bool busy;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: CircleAvatar(child: Text(member.initials)),
      title: Text(isSelf ? '${member.label} (tu)' : member.label),
      subtitle: Text(member.role.label),
      trailing: canRemove
          ? IconButton(
              tooltip: isSelf ? 'Abbandona' : 'Rimuovi',
              icon: Icon(
                isSelf ? Icons.logout : Icons.person_remove_outlined,
                color: theme.colorScheme.error,
              ),
              onPressed: busy ? null : onRemove,
            )
          : null,
    );
  }
}
