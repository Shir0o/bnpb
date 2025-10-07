import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timeline_tile/timeline_tile.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/interaction.dart';
import '../models/relationship.dart';

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
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _nicknameController = TextEditingController();
  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _firstMeetingNotesController =
      TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _interactionSearchController =
      TextEditingController();

  List<Interaction> _interactions = [];
  bool _isLoadingInteractions = false;
  String _interactionQuery = '';

  static const Map<String, String> _mediumLabels = {
    'in_person': 'In-person',
    'call': 'Call',
    'message': 'Message',
    'online': 'Online Meeting',
    'other': 'Other',
  };

  static const Map<String, IconData> _mediumIcons = {
    'in_person': Icons.people_outline,
    'call': Icons.phone_outlined,
    'message': Icons.chat_bubble_outline,
    'online': Icons.videocam_outlined,
    'other': Icons.more_horiz,
  };

  List<_MethodFormEntry> _methodEntries = [];
  List<String> _selectedTags = [];
  List<Contact> _availableContacts = [];
  Map<String, Contact> _contactLookup = {};
  List<String> _availableTags = [];
  String? _selectedMetThroughId;
  bool _isLoadingReferenceData = false;
  List<Relationship> _relationships = [];
  bool _isLoadingRelationships = false;

  @override
  void initState() {
    super.initState();
    final contact = widget.contact;
    _interactions = List<Interaction>.from(contact.interactions)
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
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

    _interactionSearchController.addListener(() {
      setState(() {
        _interactionQuery = _interactionSearchController.text.trim();
      });
    });

    _loadReferenceData();
    _refreshInteractions();
  }

  @override
  void dispose() {
    _interactionSearchController.dispose();
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
      _isLoadingRelationships = true;
    });

    final dbHelper = DBHelper();
    final contacts = await dbHelper.getContacts();
    final tags = await dbHelper.getAllTags();
    final relationships =
        await dbHelper.getRelationshipsForContact(widget.contact.id);

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
      _relationships = relationships;
      _isLoadingRelationships = false;
    });
  }

  Future<void> _refreshInteractions() async {
    setState(() {
      _isLoadingInteractions = true;
    });

    final interactions =
        await DBHelper().getInteractionsForContact(widget.contact.id);

    if (!mounted) return;
    setState(() {
      _interactions = interactions
        ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      _isLoadingInteractions = false;
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

  Contact _buildContactFromState({List<Interaction>? interactionsOverride}) {
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
      interactions:
          List<Interaction>.from(interactionsOverride ?? _interactions),
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

  Future<void> _deleteInteraction(Interaction interaction) async {
    if (interaction.id == null) return;

    await DBHelper().deleteInteraction(interaction.id!);
    setState(() {
      _interactions.removeWhere((item) => item.id == interaction.id);
    });

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Interaction removed')),
    );
  }

  void _showQuickAddInteractionSheet() {
    showModalBottomSheet<Interaction>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final summaryController = TextEditingController();
        final locationController = TextEditingController();
        DateTime occurredAt = DateTime.now();
        DateTime? followUpAt;
        String medium = 'in_person';
        bool markForPrayer = false;
        List<AttachmentReference> attachments = [];

        return StatefulBuilder(
          builder: (context, setStateSheet) {
            Future<void> pickDateTime() async {
              final date = await showDatePicker(
                context: context,
                initialDate: occurredAt,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (date == null) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(occurredAt),
              );
              if (time == null) return;
              setStateSheet(() {
                occurredAt = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
              });
            }

            Future<void> pickFollowUp() async {
              final date = await showDatePicker(
                context: context,
                initialDate: followUpAt ?? DateTime.now(),
                firstDate: DateTime.now().subtract(const Duration(days: 1)),
                lastDate: DateTime(2100),
              );
              if (date == null) return;
              final time = await showTimePicker(
                context: context,
                initialTime: TimeOfDay.fromDateTime(followUpAt ?? DateTime.now()),
              );
              if (time == null) return;
              setStateSheet(() {
                followUpAt = DateTime(
                  date.year,
                  date.month,
                  date.day,
                  time.hour,
                  time.minute,
                );
              });
            }

            Future<void> addFileAttachment() async {
              final result = await FilePicker.platform.pickFiles();
              final file = result?.files.single;
              final path = file?.path;
              if (path == null) return;
              setStateSheet(() {
                attachments = List<AttachmentReference>.from(attachments)
                  ..add(
                    AttachmentReference(
                      uri: path,
                      source: AttachmentSource.local,
                      label: file?.name,
                    ),
                  );
              });
            }

            Future<void> addLinkAttachment() async {
              final linkController = TextEditingController();
              final labelController = TextEditingController();
              final link = await showDialog<String>(
                context: context,
                builder: (context) {
                  return AlertDialog(
                    title: const Text('Add Link'),
                    content: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextField(
                          controller: linkController,
                          decoration: const InputDecoration(
                            labelText: 'URL',
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: labelController,
                          decoration: const InputDecoration(
                            labelText: 'Label (optional)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        onPressed: () {
                          final link = linkController.text.trim();
                          if (link.isEmpty) {
                            Navigator.pop(context);
                            return;
                          }
                          final label = labelController.text.trim();
                          Navigator.pop(
                            context,
                            jsonEncode({
                              'uri': link,
                              'label': label.isEmpty ? null : label,
                            }),
                          );
                        },
                        child: const Text('Add'),
                      ),
                    ],
                  );
                },
              );

              if (link == null) return;
              final decoded = jsonDecode(link) as Map<String, dynamic>;
              setStateSheet(() {
                attachments = List<AttachmentReference>.from(attachments)
                  ..add(
                    AttachmentReference(
                      uri: decoded['uri'] as String,
                      source: AttachmentSource.cloud,
                      label: decoded['label'] as String?,
                    ),
                  );
              });
            }

            void removeAttachment(AttachmentReference attachment) {
              setStateSheet(() {
                attachments = List<AttachmentReference>.from(attachments)
                  ..removeWhere((item) => item.uri == attachment.uri);
              });
            }

            Future<void> saveInteraction() async {
              final summary = summaryController.text.trim();
              if (summary.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Add a short summary first.')),
                );
                return;
              }

              final interaction = Interaction(
                contactId: widget.contact.id,
                occurredAt: occurredAt,
                summary: summary,
                medium: medium,
                location:
                    locationController.text.trim().isEmpty
                        ? null
                        : locationController.text.trim(),
                attachments: attachments,
                markForPrayer: markForPrayer,
                followUpAt: followUpAt,
              );

              final savedInteraction =
                  await DBHelper().insertInteraction(interaction);

              if (!mounted) return;
              Navigator.pop(context, savedInteraction);
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
                top: 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Log interaction',
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: summaryController,
                      decoration: const InputDecoration(
                        labelText: 'Summary',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.sentences,
                      maxLines: 2,
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: medium,
                      decoration: const InputDecoration(
                        labelText: 'Medium',
                        border: OutlineInputBorder(),
                      ),
                      items: const [
                        DropdownMenuItem(
                          value: 'in_person',
                          child: Text('In-person'),
                        ),
                        DropdownMenuItem(
                          value: 'call',
                          child: Text('Call'),
                        ),
                        DropdownMenuItem(
                          value: 'message',
                          child: Text('Message'),
                        ),
                        DropdownMenuItem(
                          value: 'online',
                          child: Text('Online Meeting'),
                        ),
                        DropdownMenuItem(
                          value: 'other',
                          child: Text('Other'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setStateSheet(() {
                          medium = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: locationController,
                      decoration: const InputDecoration(
                        labelText: 'Location (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Occurred at'),
                      subtitle: Text(
                        DateFormat.yMMMd().add_jm().format(occurredAt),
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: pickDateTime,
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Mark for prayer'),
                      value: markForPrayer,
                      onChanged: (value) {
                        setStateSheet(() {
                          markForPrayer = value;
                        });
                      },
                    ),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Follow-up reminder'),
                      subtitle: Text(
                        followUpAt != null
                            ? DateFormat.yMMMd().add_jm().format(followUpAt!)
                            : 'None',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (followUpAt != null)
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () {
                                setStateSheet(() {
                                  followUpAt = null;
                                });
                              },
                            ),
                          IconButton(
                            icon: const Icon(Icons.calendar_month_outlined),
                            onPressed: pickFollowUp,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Attachments',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    if (attachments.isEmpty)
                      const Text(
                        'Add quick notes, files, or shared links.',
                        style: TextStyle(color: Colors.grey),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: attachments
                            .map(
                              (attachment) => InputChip(
                                label: Text(
                                  attachment.label ??
                                      attachment.uri.split('/').last,
                                ),
                                avatar: Icon(
                                  attachment.source == AttachmentSource.local
                                      ? Icons.insert_drive_file_outlined
                                      : Icons.cloud_outlined,
                                ),
                                onDeleted: () => removeAttachment(attachment),
                              ),
                            )
                            .toList(),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: addFileAttachment,
                          icon: const Icon(Icons.attach_file),
                          label: const Text('Device file'),
                        ),
                        const SizedBox(width: 12),
                        OutlinedButton.icon(
                          onPressed: addLinkAttachment,
                          icon: const Icon(Icons.link),
                          label: const Text('Add link'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: saveInteraction,
                        icon: const Icon(Icons.check),
                        label: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((interaction) {
      if (interaction == null) return;
      setState(() {
        _interactions = List<Interaction>.from(_interactions)
          ..add(interaction)
          ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Interaction logged')), 
      );
    });
  }

  Future<void> _refreshRelationships() async {
    setState(() {
      _isLoadingRelationships = true;
    });
    final relationships =
        await DBHelper().getRelationshipsForContact(widget.contact.id);
    setState(() {
      _relationships = relationships;
      _isLoadingRelationships = false;
    });
  }

  void _showRelationshipDialog({Relationship? relationship}) {
    final isEditing = relationship != null;
    if (isEditing && relationship!.sourceContactId != widget.contact.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Edit this connection from the contact who created it.',
          ),
        ),
      );
      return;
    }

    if (_availableContacts.isEmpty && !isEditing) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add another contact first to create a relationship.'),
        ),
      );
      return;
    }

    String? selectedContactId;
    final dropdownContacts = List<Contact>.from(_availableContacts);
    if (isEditing) {
      selectedContactId = relationship!.targetContactId;
      final fallback = _contactLookup[selectedContactId];
      if (fallback != null &&
          dropdownContacts.every((contact) => contact.id != fallback.id)) {
        dropdownContacts.add(fallback);
      }
    } else {
      selectedContactId =
          dropdownContacts.isNotEmpty ? dropdownContacts.first.id : null;
    }

    final typeController =
        TextEditingController(text: relationship?.type ?? '');
    final notesController =
        TextEditingController(text: relationship?.notes ?? '');

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEditing ? 'Edit Relationship' : 'Add Relationship'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: selectedContactId,
                decoration: const InputDecoration(
                  labelText: 'Connected contact',
                  border: OutlineInputBorder(),
                ),
                items: dropdownContacts
                    .map(
                      (contact) => DropdownMenuItem<String>(
                        value: contact.id,
                        child: Text(
                          contact.fullName.isNotEmpty
                              ? contact.fullName
                              : (contact.nickname ?? 'Unnamed Contact'),
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  selectedContactId = value;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: typeController,
                decoration: const InputDecoration(
                  labelText: 'Relationship type',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: notesController,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Notes (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context);
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                final typeText = typeController.text.trim();
                final targetId = selectedContactId;

                if (typeText.isEmpty || targetId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please select a contact and type.'),
                    ),
                  );
                  return;
                }

                final relationshipToSave = Relationship(
                  id: relationship?.id,
                  sourceContactId: widget.contact.id,
                  targetContactId: targetId,
                  type: typeText,
                  notes: notesController.text.trim().isEmpty
                      ? null
                      : notesController.text.trim(),
                );

                await DBHelper().upsertRelationship(relationshipToSave);
                await _refreshRelationships();

                if (!mounted) return;
                Navigator.pop(context);
              },
              child: Text(isEditing ? 'Save' : 'Add'),
            ),
          ],
        );
      },
    ).whenComplete(() {
      typeController.dispose();
      notesController.dispose();
    });
  }

  void _confirmDeleteRelationship(Relationship relationship) {
    if (relationship.id == null) {
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove Relationship'),
          content: Text(
            'Remove the "${relationship.type}" connection with ${_displayNameForContactId(relationship.targetContactId)}?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await DBHelper().deleteRelationship(relationship.id!);
                await _refreshRelationships();
                if (!mounted) return;
                Navigator.pop(context);
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

  String _displayNameForContactId(String contactId) {
    final contact = _contactLookup[contactId];
    if (contact == null) {
      return 'Unknown contact';
    }
    final fullName = contact.fullName;
    if (fullName.isNotEmpty) {
      return fullName;
    }
    final nickname = contact.nickname ?? '';
    return nickname.isNotEmpty ? nickname : 'Unknown contact';
  }

  Widget _buildRelationshipCard() {
    final outgoing = _relationships
        .where((relationship) =>
            relationship.sourceContactId == widget.contact.id)
        .toList();
    final incoming = _relationships
        .where((relationship) =>
            relationship.targetContactId == widget.contact.id)
        .toList();

    return _buildCard(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Relationships',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextButton.icon(
              onPressed: _showRelationshipDialog,
              icon: const Icon(Icons.add),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_isLoadingRelationships)
          const Center(child: CircularProgressIndicator())
        else if (outgoing.isEmpty && incoming.isEmpty)
          const Text('No relationships recorded yet.')
        else ...[
          if (outgoing.isNotEmpty) ...[
            Text(
              'Connections from this contact',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            ...outgoing.map((relationship) =>
                _buildRelationshipTile(relationship, isOutgoing: true)),
          ],
          if (incoming.isNotEmpty) ...[
            if (outgoing.isNotEmpty) const Divider(height: 24),
            Text(
              'Connections to this contact',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            ...incoming.map((relationship) =>
                _buildRelationshipTile(relationship, isOutgoing: false)),
          ],
        ],
      ],
    );
  }

  Widget _buildRelationshipTile(Relationship relationship,
      {required bool isOutgoing}) {
    final otherContactId = isOutgoing
        ? relationship.targetContactId
        : relationship.sourceContactId;
    final otherName = _displayNameForContactId(otherContactId);
    final notes = relationship.notes;
    final subtitleChildren = <Widget>[
      Text('Type: ${relationship.type}'),
      if (notes != null && notes.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(notes),
        ),
      if (!isOutgoing)
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'Managed from $otherName',
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        ),
    ];

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: CircleAvatar(
        child: Text(
          otherName.isNotEmpty ? otherName[0].toUpperCase() : '?',
        ),
      ),
      title: Text(otherName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: subtitleChildren,
      ),
      trailing: isOutgoing
          ? Wrap(
              spacing: 4,
              children: [
                IconButton(
                  icon: const Icon(Icons.edit_outlined),
                  tooltip: 'Edit relationship',
                  onPressed: () =>
                      _showRelationshipDialog(relationship: relationship),
                ),
                IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: 'Remove relationship',
                  onPressed: () =>
                      _confirmDeleteRelationship(relationship),
                ),
              ],
            )
          : null,
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
            _buildRelationshipCard(),
            const SizedBox(height: 16),
            _buildCard(
              children: [
                Text(
                  'Interactions',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _buildInteractionSection(),
              ],
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showQuickAddInteractionSheet,
        icon: const Icon(Icons.add),
        label: const Text('Log Interaction'),
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

  List<Interaction> get _filteredInteractions {
    final query = _interactionQuery.toLowerCase();
    final sorted = List<Interaction>.from(_interactions)
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    if (query.isEmpty) {
      return sorted;
    }

    return sorted.where((interaction) {
      final mediumLabel = _mediumLabels[interaction.medium] ?? interaction.medium;
      final matchesSummary = interaction.summary.toLowerCase().contains(query);
      final matchesLocation =
          (interaction.location ?? '').toLowerCase().contains(query);
      final matchesMedium = mediumLabel.toLowerCase().contains(query);
      final matchesAttachments = interaction.attachments.any((attachment) {
        final value = (attachment.label ?? attachment.uri).toLowerCase();
        return value.contains(query);
      });

      return matchesSummary ||
          matchesLocation ||
          matchesMedium ||
          matchesAttachments;
    }).toList();
  }

  Widget _buildInteractionSection() {
    final filtered = _filteredInteractions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _interactionSearchController,
          decoration: InputDecoration(
            hintText: 'Search by summary, medium, location, or attachment',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _interactionQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () => _interactionSearchController.clear(),
                  )
                : null,
            border: const OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        if (_isLoadingInteractions)
          const Center(child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(),
          ))
        else if (filtered.isEmpty)
          const Text(
            'No interactions logged yet. Use the button below to record one.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          )
        else
          Column(
            children: filtered.asMap().entries.map((entry) {
              final index = entry.key;
              final interaction = entry.value;
              return _buildTimelineTile(
                interaction: interaction,
                isFirst: index == 0,
                isLast: index == filtered.length - 1,
              );
            }).toList(),
          ),
      ],
    );
  }

  TimelineTile _buildTimelineTile({
    required Interaction interaction,
    required bool isFirst,
    required bool isLast,
  }) {
    final theme = Theme.of(context);
    final indicatorColor = interaction.markForPrayer
        ? theme.colorScheme.secondary
        : theme.colorScheme.primary;

    return TimelineTile(
      alignment: TimelineAlign.manual,
      lineXY: 0.15,
      isFirst: isFirst,
      isLast: isLast,
      beforeLineStyle: LineStyle(
        color: theme.colorScheme.outlineVariant,
        thickness: 2,
      ),
      afterLineStyle: LineStyle(
        color: theme.colorScheme.outlineVariant,
        thickness: 2,
      ),
      indicatorStyle: IndicatorStyle(
        width: 32,
        height: 32,
        indicator: Container(
          decoration: BoxDecoration(
            color: indicatorColor,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: indicatorColor.withOpacity(0.3),
                blurRadius: 6,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Icon(
            interaction.markForPrayer
                ? Icons.volunteer_activism
                : Icons.event,
            size: 18,
            color: theme.colorScheme.onPrimary,
          ),
        ),
      ),
      startChild: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              DateFormat.MMMd().format(interaction.occurredAt),
              style: theme.textTheme.bodySmall,
            ),
            Text(
              DateFormat.jm().format(interaction.occurredAt),
              style: theme.textTheme.labelSmall,
            ),
            if (interaction.followUpAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    const Icon(Icons.alarm_outlined, size: 14),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        DateFormat.MMMd().add_jm().format(interaction.followUpAt!),
                        style: theme.textTheme.labelSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
      endChild: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: _buildInteractionCard(interaction),
      ),
    );
  }

  Widget _buildInteractionCard(Interaction interaction) {
    final theme = Theme.of(context);
    final mediumLabel = _mediumLabels[interaction.medium] ?? interaction.medium;
    final mediumIcon = _mediumIcons[interaction.medium] ?? Icons.forum_outlined;

    return Container(
      margin: const EdgeInsets.only(left: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  interaction.summary,
                  style: theme.textTheme.titleSmall,
                ),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Delete interaction',
                onPressed: () => _deleteInteraction(interaction),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              Chip(
                avatar: Icon(mediumIcon, size: 18),
                label: Text(mediumLabel),
              ),
              if (interaction.location != null && interaction.location!.isNotEmpty)
                Chip(
                  avatar: const Icon(Icons.place_outlined, size: 18),
                  label: Text(interaction.location!),
                ),
              if (interaction.markForPrayer)
                Chip(
                  avatar: const Icon(Icons.self_improvement, size: 18),
                  label: const Text('Prayer focus'),
                ),
            ],
          ),
          if (interaction.attachments.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: interaction.attachments
                  .map(
                    (attachment) => InputChip(
                      label: Text(
                        attachment.label ??
                            attachment.uri.split('/').last,
                      ),
                      avatar: Icon(
                        attachment.source == AttachmentSource.local
                            ? Icons.insert_drive_file_outlined
                            : Icons.cloud_outlined,
                        size: 18,
                      ),
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(attachment.uri),
                          ),
                        );
                      },
                    ),
                  )
                  .toList(),
            ),
          ],
        ],
      ),
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
