import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
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

class _AddContactPageState extends State<AddContactPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers for text fields
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _firstMeetingNotesController =
      TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _keywordController = TextEditingController();
  final TextEditingController _reminderController = TextEditingController();
  final TextEditingController _photoCueController = TextEditingController();

  final List<String> _selectedTags = [];
  final List<String> _keywords = [];
  final List<String> _reminderCues = [];
  final List<String> _photoCues = [];

  List<String> _availableTags = [];
  bool _isLoadingReferenceData = false;
  bool _isSavingContact = false;

  @override
  void initState() {
    super.initState();
    _loadReferenceData();
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _nicknameController.dispose();
    _locationController.dispose();
    _firstMeetingNotesController.dispose();
    _tagController.dispose();
    _keywordController.dispose();
    _reminderController.dispose();
    _photoCueController.dispose();
    super.dispose();
  }

  Future<void> _loadReferenceData() async {
    setState(() {
      _isLoadingReferenceData = true;
    });

    final dbHelper = DBHelper();
    final tags = await dbHelper.getAllTags();

    setState(() {
      _availableTags = tags;
      _isLoadingReferenceData = false;
    });
  }

  /// Saves a new contact while keeping the UI responsive by optimistically
  /// disabling the save button, surfacing feedback immediately, and offloading
  /// non-critical post-save work.
  Future<void> _saveContact() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    FocusScope.of(context).unfocus();

    if (_keywordController.text.trim().isNotEmpty) {
      _addKeyword();
    }
    if (_reminderController.text.trim().isNotEmpty) {
      _addReminder();
    }
    if (_photoCueController.text.trim().isNotEmpty) {
      _addPhotoCueFromInput();
    }

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
      tags: List<String>.from(_selectedTags),
      recognitionKeywords: List<String>.from(_keywords),
      recognitionPhotoUris: List<String>.from(_photoCues),
      recognitionReminders: List<String>.from(_reminderCues),
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
      await _loadReferenceData();
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
    _tagController.clear();
    _keywordController.clear();
    _reminderController.clear();
    _photoCueController.clear();
    _selectedTags.clear();
    _keywords.clear();
    _reminderCues.clear();
    _photoCues.clear();

    setState(() {});
  }

  void _addTagFromInput() {
    final text = _tagController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      if (!_selectedTags.contains(text)) {
        _selectedTags.add(text);
      }
      _tagController.clear();
    });
  }

  void _toggleSuggestedTag(String tag) {
    setState(() {
      if (_selectedTags.contains(tag)) {
        _selectedTags.remove(tag);
      } else {
        _selectedTags.add(tag);
      }
    });
  }

  void _removeTag(String tag) {
    setState(() {
      _selectedTags.remove(tag);
    });
  }

  void _addKeyword() {
    final text = _keywordController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      if (!_keywords.contains(text)) {
        _keywords.add(text);
      }
      _keywordController.clear();
    });
  }

  void _removeKeyword(String keyword) {
    setState(() {
      _keywords.remove(keyword);
    });
  }

  void _addReminder() {
    final text = _reminderController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      if (!_reminderCues.contains(text)) {
        _reminderCues.add(text);
      }
      _reminderController.clear();
    });
  }

  void _removeReminder(String reminder) {
    setState(() {
      _reminderCues.remove(reminder);
    });
  }

  void _addPhotoCue(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return;
    setState(() {
      if (!_photoCues.contains(trimmed)) {
        _photoCues.add(trimmed);
      }
    });
  }

  void _addPhotoCueFromInput() {
    final text = _photoCueController.text.trim();
    if (text.isEmpty) return;
    _addPhotoCue(text);
    _photoCueController.clear();
  }

  Future<void> _pickPhotoCue() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image);
    if (result == null || result.files.isEmpty) {
      return;
    }
    final path = result.files.single.path;
    if (path != null) {
      _addPhotoCue(path);
    }
  }

  void _removePhotoCue(String cue) {
    setState(() {
      _photoCues.remove(cue);
    });
  }

  Widget _buildCueInput({
    required String label,
    required TextEditingController controller,
    required VoidCallback onAdd,
    required List<String> entries,
    required IconData leadingIcon,
    required void Function(String value) onRemove,
    ValueChanged<String>? onSubmitted,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                decoration: _buildInputDecoration('Add $label').copyWith(
                  suffixIcon: IconButton(
                    icon: const Icon(Icons.add),
                    onPressed: onAdd,
                  ),
                ),
                onSubmitted: (value) {
                  if (onSubmitted != null) {
                    onSubmitted(value);
                  } else {
                    onAdd();
                  }
                },
              ),
            ),
          ],
        ),
        if (entries.isNotEmpty) ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: entries
                .map(
                  (entry) => InputChip(
                    avatar: Icon(leadingIcon, size: 18),
                    label: Text(entry),
                    onDeleted: () => onRemove(entry),
                  ),
                )
                .toList(),
          ),
        ],
      ],
    );
  }

  ImageProvider<Object>? _buildImageProviderForCue(String cue) {
    final uri = Uri.tryParse(cue);
    if (uri != null && uri.hasAbsolutePath) {
      final scheme = uri.scheme.toLowerCase();
      if (scheme == 'http' || scheme == 'https' || scheme == 'data') {
        return NetworkImage(cue);
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Contact'),
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
                    validator: (value) => value == null || value.trim().isEmpty
                        ? 'Enter first name'
                        : null,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _middleNameController,
                    label: 'Middle Name (Optional)',
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _lastNameController,
                    label: 'Last Name (Optional)',
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _nicknameController,
                    label: 'Nickname (Optional)',
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    controller: _locationController,
                    label: 'Location (Optional)',
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildCard(
                children: [
                  _buildTextField(
                    controller: _firstMeetingNotesController,
                    label: 'First Meeting Notes (Optional)',
                    maxLines: 3,
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildCard(
                children: [
                  Text(
                    'Recognition cues',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  _buildCueInput(
                    label: 'Keywords',
                    controller: _keywordController,
                    onSubmitted: (_) => _addKeyword(),
                    onAdd: _addKeyword,
                    entries: _keywords,
                    leadingIcon: Icons.style_outlined,
                    onRemove: _removeKeyword,
                  ),
                  const SizedBox(height: 12),
                  _buildCueInput(
                    label: 'Reminders',
                    controller: _reminderController,
                    onSubmitted: (_) => _addReminder(),
                    onAdd: _addReminder,
                    entries: _reminderCues,
                    leadingIcon: Icons.alarm_add_outlined,
                    onRemove: _removeReminder,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Photo cues',
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: 8),
                  if (_photoCues.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _photoCues
                          .map(
                            (cue) => InputChip(
                              label: Text(
                                cue.length > 28
                                    ? '${cue.substring(0, 25)}...'
                                    : cue,
                              ),
                              avatar: CircleAvatar(
                                backgroundImage: _buildImageProviderForCue(cue),
                                child: _buildImageProviderForCue(cue) == null
                                    ? const Icon(Icons.photo_outlined)
                                    : null,
                              ),
                              onDeleted: () => _removePhotoCue(cue),
                            ),
                          )
                          .toList(),
                    ),
                  if (_photoCues.isNotEmpty) const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _photoCueController,
                          decoration: _buildInputDecoration(
                            'Link or path to a helpful photo',
                          ).copyWith(
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: _addPhotoCueFromInput,
                            ),
                          ),
                          onSubmitted: (_) => _addPhotoCueFromInput(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: _pickPhotoCue,
                      icon: const Icon(Icons.image_outlined),
                      label: const Text('Pick image from device'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildCard(
                children: [
                  Text(
                    'Tags',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _tagController,
                          decoration:
                              _buildInputDecoration('Add a tag').copyWith(
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: _addTagFromInput,
                            ),
                          ),
                          onSubmitted: (_) => _addTagFromInput(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  if (_selectedTags.isNotEmpty)
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: _selectedTags
                          .map(
                            (tag) => InputChip(
                              label: Text(tag),
                              onDeleted: () => _removeTag(tag),
                            ),
                          )
                          .toList(),
                    ),
                  if (_availableTags.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _availableTags
                            .map(
                              (tag) => FilterChip(
                                label: Text(tag),
                                selected: _selectedTags.contains(tag),
                                onSelected: (_) => _toggleSuggestedTag(tag),
                              ),
                            )
                            .toList(),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: _isLoadingReferenceData || _isSavingContact
                    ? null
                    : _saveContact,
                child: _isSavingContact
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Save Contact'),
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
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
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
  }) {
    return TextFormField(
      controller: controller,
      textCapitalization: TextCapitalization.sentences,
      decoration: _buildInputDecoration(label),
      validator: validator,
      maxLines: maxLines,
    );
  }

  /// Helper function to apply a consistent OutlineInputBorder style
  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.blue, width: 2),
      ),
    );
  }
}
