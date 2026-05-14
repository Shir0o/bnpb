import 'dart:async';

import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../services/backup_service.dart';
import '../services/contact_service.dart';
import '../services/reminder_coordinator.dart';
import 'add_family_page.dart';

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
  final TextEditingController _notesController = TextEditingController();
  final FocusNode _locationFocusNode = FocusNode();

  bool _isSavingContact = false;

  List<String> _locationSuggestions = const [];

  @override
  void initState() {
    super.initState();
    unawaited(_loadSuggestions());
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _nicknameController.dispose();
    _locationController.dispose();
    _firstMeetingNotesController.dispose();
    _notesController.dispose();
    _locationFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadSuggestions() async {
    try {
      final locations = await DBHelper().getDistinctLocations();
      if (!mounted) return;
      setState(() {
        _locationSuggestions = locations;
      });
    } catch (error, stackTrace) {
      debugPrint('Failed to load suggestions: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
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
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
    );

    setState(() {
      _isSavingContact = true;
    });

    try {
      final dbHelper = DBHelper();
      await dbHelper.insertContact(newContact);
      ContactService().notifyContactsChanged();

      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      final colorScheme = Theme.of(context).colorScheme;
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Contact saved: ${newContact.fullName}',
            style: TextStyle(color: colorScheme.onPrimaryContainer),
          ),
          backgroundColor: colorScheme.primaryContainer,
        ),
      );

      unawaited(BackupService().exportBackup());

      await ReminderCoordinator().syncSignificantDates(newContact);

      _resetForm();
      unawaited(_loadSuggestions());
    } catch (error, stackTrace) {
      if (!mounted) {
        return;
      }

      final messenger = ScaffoldMessenger.of(context);
      final colorScheme = Theme.of(context).colorScheme;
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'Failed to save contact: $error',
              style: TextStyle(color: colorScheme.onError),
            ),
            backgroundColor: colorScheme.error,
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
    _notesController.clear();

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
          IconButton(
            tooltip: 'Add family',
            icon: const Icon(Icons.group_add_outlined),
            onPressed: _isSavingContact
                ? null
                : () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const AddFamilyPage(),
                      ),
                    );
                  },
          ),
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
                  _buildSuggestionField(
                    controller: _locationController,
                    focusNode: _locationFocusNode,
                    label: 'Location (Optional)',
                    prefixIcon: Icons.place_outlined,
                    suggestions: _locationSuggestions,
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
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _notesController,
                    label: 'Notes (Optional)',
                    prefixIcon: Icons.notes_outlined,
                    maxLines: 5,
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

  Widget _buildSuggestionField({
    required TextEditingController controller,
    required FocusNode focusNode,
    required String label,
    required List<String> suggestions,
    IconData? prefixIcon,
  }) {
    return RawAutocomplete<String>(
      textEditingController: controller,
      focusNode: focusNode,
      optionsBuilder: (TextEditingValue value) {
        if (suggestions.isEmpty) {
          return const Iterable<String>.empty();
        }
        final query = value.text.trim().toLowerCase();
        if (query.isEmpty) {
          return suggestions;
        }
        return suggestions
            .where((option) => option.toLowerCase().contains(query));
      },
      fieldViewBuilder: (context, textController, focusNode, onFieldSubmitted) {
        return TextFormField(
          controller: textController,
          focusNode: focusNode,
          textCapitalization: TextCapitalization.sentences,
          decoration: _buildInputDecoration(label, prefixIcon: prefixIcon),
          onFieldSubmitted: (_) => onFieldSubmitted(),
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 220),
              child: ListView.builder(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: options.length,
                itemBuilder: (context, index) {
                  final option = options.elementAt(index);
                  return InkWell(
                    onTap: () => onSelected(option),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      child: Text(option),
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );
  }

  /// Helper function to apply a consistent OutlineInputBorder style
  InputDecoration _buildInputDecoration(String label, {IconData? prefixIcon}) {
    return InputDecoration(
      labelText: label,
      prefixIcon: prefixIcon != null ? Icon(prefixIcon) : null,
      border: const OutlineInputBorder(),
    );
  }
}
