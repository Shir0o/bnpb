import 'dart:async';

import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../services/backup_service.dart';
import '../services/reminder_coordinator.dart';

class AddContactPage extends StatefulWidget {
  const AddContactPage({super.key});

  @override
  State<AddContactPage> createState() => _AddContactPageState();
}

class _AddContactPageState extends State<AddContactPage>
    with AutomaticKeepAliveClientMixin {
  final _formKey = GlobalKey<FormState>();

  // Controllers for text fields
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _firstMeetingNotesController =
      TextEditingController();

  bool _isSavingContact = false;

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _nicknameController.dispose();
    _locationController.dispose();
    _firstMeetingNotesController.dispose();
    super.dispose();
  }

  /// Saves a new contact while keeping the UI responsive by optimistically
  /// disabling the save button, surfacing feedback immediately, and offloading
  /// non-critical post-save work.
  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();

    final newContact = Contact(
      id: DateTime.now().toIso8601String(),
      firstName: _firstNameController.text.trim(),
      middleName: _middleNameController.text.trim(),
      lastName: _lastNameController.text.trim().isEmpty
          ? null
          : _lastNameController.text.trim(),
      nickname: _nicknameController.text.trim().isEmpty
          ? null
          : _nicknameController.text.trim(),
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      firstMeetingNotes: _firstMeetingNotesController.text.trim().isEmpty
          ? null
          : _firstMeetingNotesController.text.trim(),
    );

    setState(() {
      _isSavingContact = true;
    });

    try {
      final dbHelper = DBHelper();
      await dbHelper.insertContact(newContact);

      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('Contact saved: ${newContact.fullName}'),
          backgroundColor: Colors.green,
        ),
      );

      unawaited(BackupService().exportBackup());

      await ReminderCoordinator().syncSignificantDates(newContact);

      _resetForm();
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text('Failed to save contact: $error'),
            backgroundColor: Colors.red,
          ),
        );

      debugPrint('Failed to save contact: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      if (mounted) {
        setState(() {
          _isSavingContact = false;
        });
      }
    }
  }

  void _resetForm() {
    _formKey.currentState?.reset();
    _firstNameController.clear();
    _middleNameController.clear();
    _lastNameController.clear();
    _nicknameController.clear();
    _locationController.clear();
    _firstMeetingNotesController.clear();

    setState(() {});
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Contact'),
        actions: [
          if (_isSavingContact)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16.0),
              child: Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton.icon(
                onPressed: _saveContact,
                icon: const Icon(Icons.save_alt),
                label: const Text('Save'),
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildCard(
                children: [
                  _buildTextField(
                    controller: _firstNameController,
                    label: 'First Name',
                    prefixIcon: Icons.person_outline,
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter first name'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _middleNameController,
                    label: 'Middle Name (Optional)',
                    prefixIcon: Icons.person_outline,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _lastNameController,
                    label: 'Last Name (Optional)',
                    prefixIcon: Icons.person_outline,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _nicknameController,
                    label: 'Nickname (Optional)',
                    prefixIcon: Icons.badge_outlined,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _locationController,
                    label: 'Location (Optional)',
                    prefixIcon: Icons.place_outlined,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildCard(
                children: [
                  _buildTextField(
                    controller: _firstMeetingNotesController,
                    label: 'First Meeting Notes (Optional)',
                    prefixIcon: Icons.handshake_outlined,
                    maxLines: 3,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Card _buildCard({required List<Widget> children}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  TextFormField _buildTextField({
    required TextEditingController controller,
    required String label,
    String? Function(String?)? validator,
    int maxLines = 1,
    IconData? prefixIcon,
  }) {
    return TextFormField(
      controller: controller,
      textCapitalization: TextCapitalization.sentences,
      decoration: _buildInputDecoration(label, prefixIcon: prefixIcon),
      validator: validator,
      maxLines: maxLines,
    );
  }

  /// Helper function to apply a consistent OutlineInputBorder style
  InputDecoration _buildInputDecoration(String label, {IconData? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
      border: const OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.blue, width: 2),
      ),
    );
  }
}
