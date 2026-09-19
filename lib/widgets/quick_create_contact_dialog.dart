import 'dart:async';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../services/backup_service.dart';
import '../services/contact_service.dart';
import 'crisp_toast.dart';

/// A lightweight dialog to quickly create a contact with just First Name,
/// Last Name, and Location without having to navigate to the full AddContactPage.
class QuickCreateContactDialog extends StatefulWidget {
  final String? initialFirstName;
  final String? initialLastName;
  final String? initialLocation;

  const QuickCreateContactDialog({
    super.key,
    this.initialFirstName,
    this.initialLastName,
    this.initialLocation,
  });

  /// Displays the quick create dialog and returns the created [Contact], or null if dismissed.
  static Future<Contact?> show(
    BuildContext context, {
    String? initialFirstName,
    String? initialLastName,
    String? initialLocation,
    String? initialQuery,
  }) {
    String? firstName = initialFirstName;
    String? lastName = initialLastName;

    if (initialQuery != null && initialQuery.trim().isNotEmpty) {
      final parts = initialQuery.trim().split(RegExp(r'\s+'));
      if (parts.length > 1) {
        firstName ??= parts.first;
        lastName ??= parts.sublist(1).join(' ');
      } else {
        firstName ??= initialQuery.trim();
      }
    }

    return showDialog<Contact>(
      context: context,
      builder: (ctx) => QuickCreateContactDialog(
        initialFirstName: firstName,
        initialLastName: lastName,
        initialLocation: initialLocation,
      ),
    );
  }

  @override
  State<QuickCreateContactDialog> createState() =>
      _QuickCreateContactDialogState();
}

class _QuickCreateContactDialogState extends State<QuickCreateContactDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _locationController;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _firstNameController =
        TextEditingController(text: widget.initialFirstName ?? '');
    _lastNameController =
        TextEditingController(text: widget.initialLastName ?? '');
    _locationController =
        TextEditingController(text: widget.initialLocation ?? '');
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _locationController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final firstName = _firstNameController.text.trim();
    final lastName = _lastNameController.text.trim();
    final location = _locationController.text.trim();

    final contact = Contact(
      id: const Uuid().v4(),
      firstName: firstName,
      lastName: lastName.isNotEmpty ? lastName : null,
      location: location.isNotEmpty ? location : null,
    );

    try {
      await DBHelper().insertContact(contact);
      ContactService().notifyContactsChanged();
      unawaited(BackupService().exportBackup());

      if (mounted) {
        CrispToast.show(context, 'Contact created: ${contact.fullName}');
        Navigator.of(context).pop(contact);
      }
    } catch (e) {
      debugPrint('Error creating contact in quick dialog: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        CrispToast.show(context, 'Failed to create contact');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.person_add_outlined),
          SizedBox(width: 8),
          Text('Quick Create Contact'),
        ],
      ),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _firstNameController,
                autofocus: (widget.initialFirstName ?? '').isEmpty,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'First Name *',
                  isDense: true,
                ),
                validator: (val) {
                  if (val == null || val.trim().isEmpty) {
                    return 'First name is required';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _lastNameController,
                autofocus: (widget.initialFirstName ?? '').isNotEmpty &&
                    (widget.initialLastName ?? '').isEmpty,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Last Name',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _locationController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'Location',
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create & Select'),
        ),
      ],
    );
  }
}
