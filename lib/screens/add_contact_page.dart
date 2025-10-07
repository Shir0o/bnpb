import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../services/reminder_coordinator.dart';
import '../constants/storage.dart';

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

  final List<_MethodFormEntry> _methodEntries = [];
  final List<String> _selectedTags = [];
  final List<String> _keywords = [];
  final List<String> _reminderCues = [];
  final List<String> _photoCues = [];

  List<Contact> _availableContacts = [];
  List<String> _availableTags = [];
  String? _selectedMetThroughId;
  bool _isLoadingReferenceData = false;

  @override
  void initState() {
    super.initState();
    _addMethodEntry();
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
    for (final entry in _methodEntries) {
      entry.dispose();
    }
    super.dispose();
  }

  Future<void> _loadReferenceData() async {
    setState(() {
      _isLoadingReferenceData = true;
    });

    final dbHelper = DBHelper();
    final contacts = await dbHelper.getContacts();
    final tags = await dbHelper.getAllTags();

    setState(() {
      _availableContacts = contacts;
      _availableTags = tags;
      _isLoadingReferenceData = false;
    });
  }

  void _addMethodEntry({ContactMethod? method}) {
    setState(() {
      _methodEntries.add(
        _MethodFormEntry(
          type: method?.type ?? 'phone',
          value: method?.value ?? '',
          label: method?.label ?? '',
        ),
      );
    });
  }

  void _removeMethodEntry(_MethodFormEntry entry) {
    setState(() {
      _methodEntries.remove(entry);
      entry.dispose();
    });
  }

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

    final methods = _methodEntries
        .map(
          (entry) => ContactMethod(
            type: entry.type,
            value: entry.valueController.text.trim(),
            label: entry.labelController.text.trim().isEmpty
                ? null
                : entry.labelController.text.trim(),
          ),
        )
        .where((method) => method.value.isNotEmpty)
        .toList();

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
      metThroughId: _selectedMetThroughId,
      firstMeetingNotes: _firstMeetingNotesController.text.trim().isEmpty
          ? null
          : _firstMeetingNotesController.text.trim(),
      contactMethods: methods,
      tags: List<String>.from(_selectedTags),
      recognitionKeywords: List<String>.from(_keywords),
      recognitionPhotoUris: List<String>.from(_photoCues),
      recognitionReminders: List<String>.from(_reminderCues),
    );

    final dbHelper = DBHelper();
    await dbHelper.insertContact(newContact);
    await ReminderCoordinator().syncSignificantDates(newContact);

    await _exportBackup();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Contact saved: ${newContact.fullName}'),
        backgroundColor: Colors.green,
      ),
    );

    _resetForm();
    await _loadReferenceData();
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
    _selectedMetThroughId = null;
    _selectedTags.clear();
    _keywords.clear();
    _reminderCues.clear();
    _photoCues.clear();

    for (final entry in _methodEntries) {
      entry.dispose();
    }
    _methodEntries.clear();
    _addMethodEntry();

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
    final metThroughOptions = _availableContacts
        .map((contact) => DropdownMenuItem<String?>(
              value: contact.id,
              child: Text(contact.fullName.isNotEmpty
                  ? contact.fullName
                  : contact.nickname ?? 'Unnamed Contact'),
            ))
        .toList();

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
                    validator: (value) =>
                        value == null || value.trim().isEmpty
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
                  Text(
                    'Contact Methods',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 12),
                  Column(
                    children: _methodEntries
                        .map((entry) => Padding(
                              padding: const EdgeInsets.only(bottom: 12.0),
                              child: _ContactMethodRow(
                                entry: entry,
                                onRemove: _methodEntries.length > 1
                                    ? () => _removeMethodEntry(entry)
                                    : null,
                              ),
                            ))
                        .toList(),
                  ),
                  OutlinedButton.icon(
                    onPressed: _addMethodEntry,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Contact Method'),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildCard(
                children: [
                  DropdownButtonFormField<String?>(
                    value: _selectedMetThroughId,
                    decoration: _buildInputDecoration(
                      'Met Through (Optional)',
                    ),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('None'),
                      ),
                      ...metThroughOptions,
                    ],
                    onChanged: (value) {
                      setState(() {
                        _selectedMetThroughId = value;
                      });
                    },
                  ),
                  const SizedBox(height: 16),
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
                                backgroundImage:
                                    _buildImageProviderForCue(cue),
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
                onPressed: _isLoadingReferenceData ? null : _saveContact,
                child: const Text('Save Contact'),
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

  Future<void> _exportBackup() async {
    final directory = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${directory.path}/backups');

    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }

    final dbFile = File(
        '${directory.path}/${StorageConstants.databaseFileName}');
    if (!dbFile.existsSync()) return;

    final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final backupFile = File('${backupDir.path}/backup_$timestamp.db');

    await dbFile.copy(backupFile.path);

    // Retain only the latest 5 backups
    final backups = backupDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.contains('backup_'))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    while (backups.length > 5) {
      backups.removeLast().deleteSync();
    }
  }
}

class _MethodFormEntry {
  _MethodFormEntry({
    required String type,
    required String value,
    required String label,
  })  : type = type,
        valueController = TextEditingController(text: value),
        labelController = TextEditingController(text: label);

  String type;
  final TextEditingController valueController;
  final TextEditingController labelController;

  void dispose() {
    valueController.dispose();
    labelController.dispose();
  }
}

class _ContactMethodRow extends StatefulWidget {
  const _ContactMethodRow({
    required this.entry,
    this.onRemove,
  });

  final _MethodFormEntry entry;
  final VoidCallback? onRemove;

  @override
  State<_ContactMethodRow> createState() => _ContactMethodRowState();
}

class _ContactMethodRowState extends State<_ContactMethodRow> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: DropdownButtonFormField<String>(
                value: widget.entry.type,
                decoration: const InputDecoration(
                  labelText: 'Type',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 'phone', child: Text('Phone')),
                  DropdownMenuItem(value: 'email', child: Text('Email')),
                  DropdownMenuItem(value: 'other', child: Text('Other')),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    widget.entry.type = value;
                  });
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 4,
              child: TextField(
                controller: widget.entry.valueController,
                decoration: const InputDecoration(
                  labelText: 'Handle',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 3,
              child: TextField(
                controller: widget.entry.labelController,
                decoration: const InputDecoration(
                  labelText: 'Label (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            if (widget.onRemove != null) ...[
              const SizedBox(width: 12),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Remove method',
                onPressed: widget.onRemove,
              ),
            ],
          ],
        ),
      ],
    );
  }
}
