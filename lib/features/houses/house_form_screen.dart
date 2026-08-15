import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../widgets/async_view.dart';

/// Creates a house, or renames an existing one when [houseId] is given.
class HouseFormScreen extends ConsumerStatefulWidget {
  const HouseFormScreen({super.key, this.houseId});

  final String? houseId;

  @override
  ConsumerState<HouseFormScreen> createState() => _HouseFormScreenState();
}

class _HouseFormScreenState extends ConsumerState<HouseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _controller = TextEditingController();
  bool _busy = false;
  bool _prefilled = false;

  bool get _isEditing => widget.houseId != null;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final user = ref.read(currentUserProvider);
    if (user == null) return;

    setState(() => _busy = true);
    final repository = ref.read(houseRepositoryProvider);
    try {
      if (_isEditing) {
        await repository.renameHouse(widget.houseId!, _controller.text);
        if (mounted) context.go('/house/${widget.houseId}');
      } else {
        final id = await repository.createHouse(
          name: _controller.text,
          ownerUid: user.uid,
          ownerName: user.shortName,
        );
        // Straight into the waste setup: a house with nothing monitored does
        // nothing useful, so this is the natural next step.
        if (mounted) context.go('/house/$id/waste');
      }
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
    if (_isEditing && !_prefilled) {
      final house = ref.watch(houseProvider(widget.houseId!)).value;
      if (house != null) {
        _controller.text = house.name;
        _prefilled = true;
      }
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Modifica abitazione' : 'Nuova abitazione'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => _isEditing
              ? context.go('/house/${widget.houseId}')
              : context.go('/'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              TextFormField(
                controller: _controller,
                autofocus: !_isEditing,
                maxLength: 40,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Nome abitazione',
                  hintText: 'Es. Casa di via Roma',
                  prefixIcon: Icon(Icons.home_outlined),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) return 'Dai un nome all\'abitazione';
                  if (text.length > 40) return 'Massimo 40 caratteri';
                  return null;
                },
                onFieldSubmitted: (_) => _save(),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _busy ? null : _save,
                child: Text(_busy ? 'Salvataggio…' : 'Salva'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
