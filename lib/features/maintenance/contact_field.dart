import 'package:flutter/material.dart';
import 'package:flutter_native_contact_picker/flutter_native_contact_picker.dart';

import '../../core/phone_number.dart';
import '../../domain/entities/maintenance.dart';
import '../../widgets/app_sheet.dart';
import '../../widgets/button_label.dart';
import '../../widgets/async_view.dart';

/// Name and phone number of whoever performs the maintenance.
///
/// The number can be typed or picked from the phone's address book. The picker
/// is the operating system's own: the app never requests contacts permission
/// and never reads the address book — the user chooses one contact and only
/// that contact's name and number come back.
///
/// What gets stored is always a COPY. A reference to an address-book entry
/// would resolve to nothing on another member's phone, and the house is shared.
class ContactField extends StatefulWidget {
  const ContactField({
    super.key,
    required this.contact,
    required this.onChanged,
  });

  final MaintenanceContact? contact;
  final ValueChanged<MaintenanceContact?> onChanged;

  @override
  State<ContactField> createState() => _ContactFieldState();
}

class _ContactFieldState extends State<ContactField> {
  /// Guards against the plugin's `multiple_requests` error, and against the
  /// Android path where a null activity leaves the future pending for ever.
  bool _picking = false;

  Future<void> _pickFromAddressBook() async {
    if (_picking) return;

    // `lifecycleState` is nullable, and a bare `!= resumed` would be true while
    // it is still null — silently doing nothing with no explanation.
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    if (lifecycle != null && lifecycle != AppLifecycleState.resumed) {
      showMessage(
        context,
        'Riprova quando l\'app è in primo piano, oppure scrivi il numero a mano.',
      );
      return;
    }

    setState(() => _picking = true);
    try {
      // The plugin never completes its future if the host activity is missing,
      // so the call is bounded rather than trusted.
      final contact = await FlutterNativeContactPicker()
          .selectPhoneNumber()
          .timeout(const Duration(minutes: 3));
      if (contact == null || !mounted) return;

      final phone =
          contact.selectedPhoneNumber ??
          (contact.phoneNumbers?.isNotEmpty == true
              ? contact.phoneNumbers!.first
              : null);

      if (phone == null || !isDialablePhone(phone)) {
        // A contact with no usable number cannot be called, so saving it would
        // only produce a "Chiama" button that fails.
        showMessage(
          context,
          'Quel contatto non ha un numero di telefono. Scrivilo a mano.',
          isError: true,
        );
        return;
      }

      final name = contact.fullName?.trim();
      widget.onChanged(
        MaintenanceContact(
          name: name == null || name.isEmpty ? null : name,
          phone: phone.trim(),
        ),
      );
    } on Exception catch (e) {
      if (mounted) {
        // Never a dead end: the manual field is right there.
        showMessage(
          context,
          'Rubrica non disponibile. Puoi scrivere il numero a mano. ($e)',
          isError: true,
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  Future<void> _editManually() async {
    final result = await showAppSheet<MaintenanceContact?>(
      context: context,
      builder: (context) => _ManualContactSheet(contact: widget.contact),
    );
    if (result != null) widget.onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contact = widget.contact;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.contacts_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text('Chi chiamare', style: theme.textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 10),

            if (contact == null)
              Text(
                'Nessun contatto associato.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  child: Icon(
                    contact.hasName
                        ? Icons.person_outline
                        : Icons.phone_outlined,
                  ),
                ),
                title: Text(contact.label),
                subtitle: contact.hasName
                    ? Text(formatPhoneForDisplay(contact.phone))
                    : null,
                trailing: IconButton(
                  tooltip: 'Rimuovi',
                  icon: const Icon(Icons.close),
                  onPressed: () => widget.onChanged(null),
                ),
              ),

            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _picking ? null : _pickFromAddressBook,
                    icon: _picking
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.contacts_outlined, size: 18),
                    label: const ButtonLabel('Dalla rubrica'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _editManually,
                    icon: const Icon(Icons.keyboard_outlined, size: 18),
                    label: const ButtonLabel('A mano'),
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            Text(
              'Il numero viene copiato nell\'app e resta visibile a tutti i '
              'membri dell\'abitazione, così chiunque può chiamare.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ManualContactSheet extends StatefulWidget {
  const _ManualContactSheet({required this.contact});

  final MaintenanceContact? contact;

  @override
  State<_ManualContactSheet> createState() => _ManualContactSheetState();
}

class _ManualContactSheetState extends State<_ManualContactSheet> {
  late final _nameController = TextEditingController(
    text: widget.contact?.name ?? '',
  );
  late final _phoneController = TextEditingController(
    text: widget.contact?.phone ?? '',
  );
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _save() {
    final phone = _phoneController.text.trim();
    if (!isDialablePhone(phone)) {
      setState(() => _error = 'Inserisci un numero di telefono valido.');
      return;
    }
    final name = _nameController.text.trim();
    Navigator.of(
      context,
    ).pop(MaintenanceContact(name: name.isEmpty ? null : name, phone: phone));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Contatto',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              maxLength: 60,
              decoration: const InputDecoration(
                labelText: 'Nome (facoltativo)',
                hintText: 'Es. Idraulico Rossi',
                prefixIcon: Icon(Icons.person_outline),
              ),
            ),
            TextField(
              controller: _phoneController,
              keyboardType: TextInputType.phone,
              maxLength: 30,
              decoration: InputDecoration(
                labelText: 'Numero di telefono',
                hintText: 'Es. 333 1234567',
                prefixIcon: const Icon(Icons.phone_outlined),
                errorText: _error,
              ),
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _save(),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _save,
                child: const Text('Salva contatto'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
