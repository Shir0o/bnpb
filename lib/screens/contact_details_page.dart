import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';

class ContactDetailsPage extends StatefulWidget {
  final Contact contact;
  final VoidCallback onDelete;

  const ContactDetailsPage({
    super.key,
    required this.contact,
    required this.onDelete,
  });

  @override
  State<ContactDetailsPage> createState() => _ContactDetailsPageState();
}

class _ContactDetailsPageState extends State<ContactDetailsPage> {
  final TextEditingController _historyDetailController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _firstMeetingNotesController =
      TextEditingController();
  final TextEditingController _tagController = TextEditingController();

  List<HistoryEntry> history = [];
  DateTime? _selectedDate;

  List<_MethodFormEntry> _methodEntries = [];
  List<String> _selectedTags = [];
  List<Contact> _availableContacts = [];
  Map<String, Contact> _contactLookup = {};
  List<String> _availableTags = [];
  String? _selectedMetThroughId;
  bool _isLoadingReferenceData = false;

  @override
  void initState() {
    super.initState();
    final contact = widget.contact;
    history = List<HistoryEntry>.from(contact.history);
    _firstNameController.text = contact.firstName;
    _middleNameController.text = contact.middleName;
    _lastNameController.text = contact.lastName ?? '';
    _nicknameController.text = contact.nickname ?? '';
    _locationController.text = contact.location ?? '';
    _firstMeetingNotesController.text = contact.firstMeetingNotes ?? '';
    _selectedMetThroughId = contact.metThroughId;
    _selectedTags = List<String>.from(contact.tags);
    _methodEntries = contact.contactMethods
        .map(
          (method) => _MethodFormEntry(
            type: method.type,
            value: method.value,
            label: method.label ?? '',
          ),
        )
        .toList();
    if (_methodEntries.isEmpty) {
      _methodEntries.add(
        _MethodFormEntry(type: 'phone', value: '', label: ''),
      );
    }

    _loadReferenceData();
  }

  @override
  void dispose() {
    _historyDetailController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    _nicknameController.dispose();
    _locationController.dispose();
    _firstMeetingNotesController.dispose();
    _tagController.dispose();
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
      _contactLookup = {for (final contact in contacts) contact.id: contact};
      _availableContacts = contacts
          .where((contact) => contact.id != widget.contact.id)
          .toList()
        ..sort(
          (a, b) => a.fullName.toLowerCase().compareTo(
                b.fullName.toLowerCase(),
              ),
        );
      final mergedTags = {...tags, ..._selectedTags};
      _availableTags = mergedTags.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
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

  Contact _buildContactFromState({List<HistoryEntry>? historyOverride}) {
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

    final lastNameText = _lastNameController.text.trim();
    final nicknameText = _nicknameController.text.trim();
    final locationText = _locationController.text.trim();
    final firstMeetingNotesText = _firstMeetingNotesController.text.trim();

    return Contact(
      id: widget.contact.id,
      firstName: _firstNameController.text.trim(),
      middleName: _middleNameController.text.trim(),
      lastName: lastNameText.isEmpty ? null : lastNameText,
      nickname: nicknameText.isEmpty ? null : nicknameText,
      location: locationText.isEmpty ? null : locationText,
      metThroughId: _selectedMetThroughId,
      firstMeetingNotes:
          firstMeetingNotesText.isEmpty ? null : firstMeetingNotesText,
      contactMethods: methods,
      tags: List<String>.from(_selectedTags),
      history: List<HistoryEntry>.from(historyOverride ?? history),
    );
  }

  Future<void> _updateContact() async {
    final updatedContact = _buildContactFromState();
    await DBHelper().updateContact(updatedContact);
    await _exportBackup();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contact updated successfully!')),
    );

    Navigator.pop(context);
  }

  Future<void> _exportBackup() async {
    final directory = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${directory.path}/backups');

    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }

    final dbFile = File('${directory.path}/contacts.db');
    if (!dbFile.existsSync()) return;

    final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final backupFile = File('${backupDir.path}/backup_$timestamp.db');

    await dbFile.copy(backupFile.path);

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

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Contact'),
          content: const Text('Are you sure you want to delete this contact?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await DBHelper().deleteContact(widget.contact.id);
                widget.onDelete();
                if (mounted) {
                  Navigator.pop(context);
                  Navigator.pop(context);
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _deleteHistoryEntry(int index) async {
    final sortedHistory = List<HistoryEntry>.from(history)
      ..sort((a, b) => b.date.compareTo(a.date));
    final entryToDelete = sortedHistory[index];

    setState(() {
      history.remove(entryToDelete);
    });

    final updatedContact = _buildContactFromState();
    await DBHelper().updateContact(updatedContact);

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('History entry deleted')),
    );
  }

  void _addHistoryItem() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Add History'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _historyDetailController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Enter history detail',
                      border: const OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            const BorderSide(color: Colors.blue, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        _selectedDate != null
                            ? DateFormat.yMMMd().format(_selectedDate!)
                            : 'No date selected',
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (pickedDate != null) {
                            setStateDialog(() {
                              _selectedDate = pickedDate;
                            });
                          }
                        },
                        child: const Text('Pick Date'),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    _historyDetailController.clear();
                    _selectedDate = null;
                    Navigator.pop(context);
                  },
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final detail = _historyDetailController.text.trim();
                    if (detail.isNotEmpty && _selectedDate != null) {
                      final newEntry = HistoryEntry(
                        date: _selectedDate!,
                        detail: detail,
                      );

                      final updatedHistory = List<HistoryEntry>.from(history)
                        ..add(newEntry);

                      setState(() {
                        history = updatedHistory;
                      });

                      final updatedContact = _buildContactFromState(
                        historyOverride: updatedHistory,
                      );
                      await DBHelper().updateContact(updatedContact);

                      if (mounted) {
                        _historyDetailController.clear();
                        _selectedDate = null;
                        Navigator.pop(context);
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please fill in all fields.'),
                        ),
                      );
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _buildContactFromState().fullName;

    final metThroughItems = <DropdownMenuItem<String?>>[
      const DropdownMenuItem<String?>(
        value: null,
        child: Text('None'),
      ),
      ..._availableContacts.map(
        (contact) => DropdownMenuItem<String?>(
          value: contact.id,
          child: Text(
            contact.fullName.isNotEmpty
                ? contact.fullName
                : contact.nickname ?? 'Unnamed Contact',
          ),
        ),
      ),
    ];

    if (_selectedMetThroughId != null &&
        metThroughItems.every((item) => item.value != _selectedMetThroughId)) {
      final fallbackContact = _contactLookup[_selectedMetThroughId!];
      metThroughItems.add(
        DropdownMenuItem<String?>(
          value: _selectedMetThroughId,
          child: Text(
            fallbackContact?.fullName.isNotEmpty == true
                ? fallbackContact!.fullName
                : (fallbackContact?.nickname ?? 'Unknown contact'),
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(displayName.isEmpty ? 'Contact Details' : displayName),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _isLoadingReferenceData ? null : _updateContact,
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            _buildCard(
              children: [
                _buildTextField(
                  controller: _firstNameController,
                  label: 'First Name',
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
                      .map(
                        (entry) => Padding(
                          padding: const EdgeInsets.only(bottom: 12.0),
                          child: _ContactMethodRow(
                            entry: entry,
                            onRemove: _methodEntries.length > 1
                                ? () => _removeMethodEntry(entry)
                                : null,
                          ),
                        ),
                      )
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
                  decoration: _buildInputDecoration('Met Through (Optional)'),
                  items: metThroughItems,
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
                  'Tags',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _tagController,
                  decoration: _buildInputDecoration('Add a tag').copyWith(
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.add),
                      onPressed: _addTagFromInput,
                    ),
                  ),
                  onSubmitted: (_) => _addTagFromInput(),
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
            const SizedBox(height: 16),
            _buildCard(
              children: [
                Text(
                  'History',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _buildHistorySection(),
              ],
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addHistoryItem,
        icon: const Icon(Icons.add),
        label: const Text('Add History'),
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

  TextField _buildTextField({
    required TextEditingController controller,
    required String label,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      textCapitalization: maxLines == 1
          ? TextCapitalization.words
          : TextCapitalization.sentences,
      decoration: _buildInputDecoration(label),
    );
  }

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

  Widget _buildHistorySection() {
    final sortedHistory = List<HistoryEntry>.from(history)
      ..sort((a, b) => b.date.compareTo(a.date));

    if (sortedHistory.isEmpty) {
      return const Text(
        'No history available.',
        style: TextStyle(fontSize: 14, color: Colors.grey),
      );
    }

    return Column(
      children: sortedHistory.asMap().entries.map((entry) {
        final index = entry.key;
        final historyEntry = entry.value;
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(
            historyEntry.detail,
            style: const TextStyle(fontSize: 14),
          ),
          subtitle: Text(
            DateFormat.yMMMd().format(historyEntry.date),
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
          trailing: IconButton(
            icon: const Icon(Icons.delete, color: Colors.red),
            onPressed: () => _deleteHistoryEntry(index),
          ),
        );
      }).toList(),
    );
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
    return Row(
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
    );
  }
}
