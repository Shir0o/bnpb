import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/interaction.dart';
import '../models/relationship.dart';
import '../services/backup_service.dart';
import '../services/reminder_coordinator.dart';
import '../widgets/people_card.dart';

class ContactDetailsPage extends StatefulWidget {
  final Contact contact;
  final Future<void> Function() onDelete;

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
  final TextEditingController _keywordController = TextEditingController();
  final TextEditingController _reminderController = TextEditingController();
  final TextEditingController _photoCueController = TextEditingController();

  List<Interaction> _interactions = [];
  bool _isLoadingInteractions = false;
  String _interactionQuery = '';
  bool _isEditing = false;
  Contact? _editingSnapshot;

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

  List<String> _selectedTags = [];
  List<String> _keywords = [];
  List<String> _reminderCues = [];
  List<String> _photoCues = [];
  List<Contact> _availableContacts = [];
  Map<String, Contact> _contactLookup = {};
  List<String> _availableTags = [];
  bool _isLoadingReferenceData = false;
  List<Relationship> _relationships = [];
  bool _isLoadingRelationships = false;
  Map<int, Interaction> _interactionLookup = {};

  @override
  void initState() {
    super.initState();
    final contact = widget.contact;
    _interactions = List<Interaction>.from(contact.interactions)
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    _interactionLookup = {
      for (final interaction in _interactions)
        if (interaction.id != null) interaction.id!: interaction,
    };
    _applyContactData(contact);

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
    _keywordController.dispose();
    _reminderController.dispose();
    _photoCueController.dispose();
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
      _interactionLookup = {
        for (final interaction in _interactions)
          if (interaction.id != null) interaction.id!: interaction,
      };
      _isLoadingInteractions = false;
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
                onSubmitted: (_) => onAdd(),
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

  String _formatDate(DateTime date) {
    return DateFormat.yMMMd().format(date);
  }

  String? _interactionSummaryFor(int? interactionId) {
    if (interactionId == null) {
      return null;
    }
    return _interactionLookup[interactionId]?.summary;
  }

  Contact _buildContactFromState({List<Interaction>? interactionsOverride}) {
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
      firstMeetingNotes:
          firstMeetingNotesText.isEmpty ? null : firstMeetingNotesText,
      tags: List<String>.from(_selectedTags),
      recognitionKeywords: List<String>.from(_keywords),
      recognitionPhotoUris: List<String>.from(_photoCues),
      recognitionReminders: List<String>.from(_reminderCues),
      interactions:
          List<Interaction>.from(interactionsOverride ?? _interactions),
    );
  }

  void _applyContactData(Contact contact, {bool updateAvailableTags = true}) {
    _firstNameController.text = contact.firstName;
    _middleNameController.text = contact.middleName;
    _lastNameController.text = contact.lastName ?? '';
    _nicknameController.text = contact.nickname ?? '';
    _locationController.text = contact.location ?? '';
    _firstMeetingNotesController.text = contact.firstMeetingNotes ?? '';
    _selectedTags = List<String>.from(contact.tags);
    _keywords = List<String>.from(contact.recognitionKeywords);
    _reminderCues = List<String>.from(contact.recognitionReminders);
    _photoCues = List<String>.from(contact.recognitionPhotoUris);
    if (updateAvailableTags) {
      final merged = {..._availableTags, ..._selectedTags};
      _availableTags = merged.toList()
        ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    }
    _tagController.clear();
    _keywordController.clear();
    _reminderController.clear();
    _photoCueController.clear();
  }

  void _startEditing() {
    setState(() {
      _editingSnapshot = _buildContactFromState();
      _isEditing = true;
      _tagController.clear();
      _keywordController.clear();
      _reminderController.clear();
      _photoCueController.clear();
    });
  }

  void _cancelEditing() {
    setState(() {
      if (_editingSnapshot != null) {
        _applyContactData(_editingSnapshot!);
      }
      _isEditing = false;
      _editingSnapshot = null;
    });
  }

  Future<void> _updateContact() async {
    final updatedContact = _buildContactFromState();
    try {
      await DBHelper().updateContact(updatedContact);
      await ReminderCoordinator().refreshContact(updatedContact.id);
      await BackupService().exportBackup();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contact updated successfully!')),
      );

      Navigator.pop(context, updatedContact);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update contact: $error')),
      );
    }
  }

  void _confirmDelete() {
    final pageContext = context;
    showDialog(
      context: pageContext,
      builder: (dialogContext) {
        return AlertDialog(
          title: const Text('Delete Contact'),
          content: const Text('Are you sure you want to delete this contact?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await widget.onDelete();
                if (!mounted) return;
                Navigator.of(dialogContext).pop();
                Navigator.of(pageContext).pop();
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
    await ReminderCoordinator().cancelInteractionReminder(interaction);

    final nextInteractions = List<Interaction>.from(_interactions)
      ..removeWhere((item) => item.id == interaction.id);
    if (mounted) {
      _applyInteractionListUpdate(nextInteractions);
    }

    await BackupService().exportBackup();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Interaction removed')),
    );
  }

  void _applyInteractionListUpdate(List<Interaction> interactions) {
    final nextInteractions = List<Interaction>.from(interactions)
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
    setState(() {
      _interactions = nextInteractions;
      _interactionLookup = {
        for (final item in nextInteractions)
          if (item.id != null) item.id!: item,
      };
    });
  }

  void _showQuickAddInteractionSheet() async {
    final interaction = await showModalBottomSheet<Interaction>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _LogInteractionSheet(
        contact: widget.contact,
        existingInteractions: List<Interaction>.from(_interactions),
        onInteractionsUpdated: (updated) {
          if (!mounted) return;
          _applyInteractionListUpdate(updated);
        },
      ),
    );

    if (!mounted || interaction == null) {
      return;
    }
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
    final previewContact = _buildContactFromState();
    final displayName = previewContact.fullName;

    final detailSections =
        _isEditing ? _buildEditingSections() : _buildReadOnlySections(previewContact);

    return Scaffold(
      appBar: AppBar(
        title: Text(displayName.isEmpty ? 'Contact Details' : displayName),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Save changes',
              onPressed: _isLoadingReferenceData ? null : _updateContact,
            ),
          IconButton(
            icon: Icon(_isEditing ? Icons.close : Icons.edit),
            tooltip: _isEditing ? 'Cancel edit' : 'Edit contact',
            onPressed: _isEditing ? _cancelEditing : _startEditing,
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
            PeopleCard(
              contact: previewContact,
            ),
            const SizedBox(height: 16),
            ...detailSections,
            if (detailSections.isNotEmpty) const SizedBox(height: 16),
            _buildRelationshipCard(),
            const SizedBox(height: 16),
            _buildInteractionsCard(),
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

  List<Widget> _buildEditingSections() {
    final sections = <Widget>[];
    void addSection(Widget widget) {
      if (sections.isNotEmpty) {
        sections.add(const SizedBox(height: 16));
      }
      sections.add(widget);
    }

    addSection(_buildEditDetailsCard());
    addSection(_buildEditRecognitionCard());
    addSection(_buildEditTagsCard());
    return sections;
  }

  List<Widget> _buildReadOnlySections(Contact contact) {
    final sections = <Widget>[];
    void addSection(Widget? widget) {
      if (widget == null) return;
      if (sections.isNotEmpty) {
        sections.add(const SizedBox(height: 16));
      }
      sections.add(widget);
    }

    addSection(_buildViewMeetingNotesCard(contact));
    addSection(_buildViewRecognitionCard(contact));
    addSection(_buildViewTagsCard(contact));
    return sections;
  }

  Widget _buildEditDetailsCard() {
    return _buildCard(
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
        const SizedBox(height: 16),
        _buildTextField(
          controller: _firstMeetingNotesController,
          label: 'First Meeting Notes (Optional)',
          maxLines: 3,
        ),
      ],
    );
  }

  Widget _buildEditRecognitionCard() {
    return _buildCard(
      children: [
        Text(
          'Recognition cues',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        _buildCueInput(
          label: 'Keywords',
          controller: _keywordController,
          onAdd: _addKeyword,
          entries: _keywords,
          leadingIcon: Icons.style_outlined,
          onRemove: _removeKeyword,
        ),
        const SizedBox(height: 12),
        _buildCueInput(
          label: 'Reminders',
          controller: _reminderController,
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
                      cue.length > 28 ? '${cue.substring(0, 25)}...' : cue,
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
    );
  }

  Widget _buildEditTagsCard() {
    return _buildCard(
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
    );
  }

  Widget? _buildViewMeetingNotesCard(Contact contact) {
    final notes = contact.firstMeetingNotes;
    if (notes == null || notes.isEmpty) {
      return null;
    }
    return _buildCard(
      children: [
        Text(
          'Meeting context',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        _buildDetailLine('First meeting notes', notes),
      ],
    );
  }

  Widget? _buildViewRecognitionCard(Contact contact) {
    final theme = Theme.of(context);
    final sections = <Widget>[];

    if (contact.recognitionKeywords.isNotEmpty) {
      sections.add(Text('Keywords', style: theme.textTheme.labelLarge));
      sections.add(const SizedBox(height: 8));
      sections.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: contact.recognitionKeywords
              .map((keyword) => Chip(label: Text(keyword)))
              .toList(),
        ),
      );
    }

    if (contact.recognitionReminders.isNotEmpty) {
      if (sections.isNotEmpty) {
        sections.add(const SizedBox(height: 12));
      }
      sections.add(Text('Reminders', style: theme.textTheme.labelLarge));
      sections.add(const SizedBox(height: 8));
      sections.add(
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: contact.recognitionReminders
              .map(
                (reminder) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Row(
                    children: [
                      const Icon(Icons.alarm_outlined, size: 18),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          reminder,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              )
              .toList(),
        ),
      );
    }

    if (contact.recognitionPhotoUris.isNotEmpty) {
      if (sections.isNotEmpty) {
        sections.add(const SizedBox(height: 12));
      }
      sections.add(Text('Photo cues', style: theme.textTheme.labelLarge));
      sections.add(const SizedBox(height: 8));
      sections.add(
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: contact.recognitionPhotoUris.map((cue) {
            final provider = _buildImageProviderForCue(cue);
            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Container(
                width: 72,
                height: 72,
                color: theme.colorScheme.surfaceVariant,
                child: provider != null
                    ? Image(image: provider, fit: BoxFit.cover)
                    : Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.photo_outlined),
                            const SizedBox(height: 4),
                            Text(
                              cue.length > 10
                                  ? '${cue.substring(0, 10)}...'
                                  : cue,
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
              ),
            );
          }).toList(),
        ),
      );
    }

    if (sections.isEmpty) {
      return null;
    }

    return _buildCard(
      children: [
        Text(
          'Recognition cues',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        ...sections,
      ],
    );
  }

  Widget? _buildViewTagsCard(Contact contact) {
    if (contact.tags.isEmpty) {
      return null;
    }
    return _buildCard(
      children: [
        Text(
          'Tags',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: contact.tags.map((tag) => Chip(label: Text(tag))).toList(),
        ),
      ],
    );
  }

  Widget _buildDetailLine(String label, String value) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  Widget _buildInteractionsCard() {
    return _buildCard(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Interactions',
                style: Theme.of(context).textTheme.titleMedium,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildInteractionSection(),
      ],
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

      return matchesSummary || matchesLocation || matchesMedium;
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
            hintText: 'Search by summary, medium, or location',
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

  Widget _buildTimelineTile({
    required Interaction interaction,
    required bool isFirst,
    required bool isLast,
  }) {
    final theme = Theme.of(context);
    final indicatorColor = interaction.markForPrayer
        ? theme.colorScheme.secondary
        : theme.colorScheme.primary;

    final onIndicatorColor = interaction.markForPrayer
        ? theme.colorScheme.onSecondary
        : theme.colorScheme.onPrimary;
    final lineColor = theme.colorScheme.outlineVariant;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              width: 48,
              child: Column(
                children: [
                  if (!isFirst)
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 2,
                          color: lineColor,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 8),
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: indicatorColor,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: theme.colorScheme.surface,
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: indicatorColor.withOpacity(0.28),
                          blurRadius: 6,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Icon(
                      interaction.markForPrayer
                          ? Icons.volunteer_activism
                          : Icons.event,
                      size: 16,
                      color: onIndicatorColor,
                    ),
                  ),
                  if (!isLast)
                    Expanded(
                      child: Center(
                        child: Container(
                          width: 2,
                          color: lineColor,
                        ),
                      ),
                    )
                  else
                    const SizedBox(height: 8),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildInteractionCard(interaction),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractionCard(Interaction interaction) {
    final theme = Theme.of(context);
    final mediumLabel = _mediumLabels[interaction.medium] ?? interaction.medium;
    final mediumIcon = _mediumIcons[interaction.medium] ?? Icons.forum_outlined;

    final occurredAtLabel =
        DateFormat.yMMMd().add_jm().format(interaction.occurredAt);
    final metadataPills = <Widget>[
      _buildInfoPill(icon: mediumIcon, label: mediumLabel),
      if (interaction.durationMinutes != null)
        _buildInfoPill(
          icon: Icons.timer_outlined,
          label: '${interaction.durationMinutes} min',
        ),
      if (interaction.markForPrayer)
        _buildInfoPill(
          icon: Icons.self_improvement,
          label: 'Prayer focus',
        ),
    ];

    return Container(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      interaction.summary,
                      style: theme.textTheme.titleSmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      occurredAtLabel,
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (interaction.location != null &&
                        interaction.location!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          interaction.location!,
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    if (interaction.category != null &&
                        interaction.category!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          interaction.category!,
                          style: theme.textTheme.labelSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                ),
              ),
              if (_isEditing)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: 'Edit interaction',
                      onPressed: () => _showEditInteractionSheet(interaction),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline),
                      tooltip: 'Delete interaction',
                      onPressed: () => _deleteInteraction(interaction),
                    ),
                  ],
                ),
            ],
          ),
          if (metadataPills.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: metadataPills,
            ),
          ],
          if (interaction.followUpAt != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(
                  Icons.alarm_outlined,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    DateFormat.MMMd()
                        .add_jm()
                        .format(interaction.followUpAt!),
                    style: theme.textTheme.labelSmall,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showEditInteractionSheet(Interaction interaction) async {
    final updatedInteraction = await showModalBottomSheet<Interaction>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _LogInteractionSheet(
        contact: widget.contact,
        existingInteractions: List<Interaction>.from(_interactions),
        initialInteraction: interaction,
        onInteractionsUpdated: (updated) {
          if (!mounted) return;
          _applyInteractionListUpdate(updated);
        },
      ),
    );

    if (!mounted || updatedInteraction == null) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Interaction updated')),
    );
  }

  Widget _buildInfoPill({
    required IconData icon,
    required String label,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final textStyle = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 16,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: textStyle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
            ),
          ),
        ],
      ),
    );

    if (onTap == null) {
      return pill;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: pill,
      ),
    );
  }
}

class _LogInteractionSheet extends StatefulWidget {
  const _LogInteractionSheet({
    required this.contact,
    required this.existingInteractions,
    this.initialInteraction,
    this.onInteractionsUpdated,
  });

  final Contact contact;
  final List<Interaction> existingInteractions;
  final Interaction? initialInteraction;
  final ValueChanged<List<Interaction>>? onInteractionsUpdated;

  @override
  State<_LogInteractionSheet> createState() => _LogInteractionSheetState();
}

class _LogInteractionSheetState extends State<_LogInteractionSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _summaryController;
  late final TextEditingController _locationController;
  late final TextEditingController _durationController;
  late final TextEditingController _categoryController;

  final SpeechToText _speechToText = SpeechToText();

  DateTime _occurredAt = DateTime.now();
  DateTime? _followUpAt;
  String _medium = 'in_person';
  bool _markForPrayer = false;
  bool _speechInitialized = false;
  bool _hasSpeechCapability = false;
  bool _isListening = false;
  String _speechBaseText = '';

  bool _sheetActive = true;
  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
  bool _isSaveEnabled = false;
  bool _formWasSubmitted = false;
  bool _isSavingInteraction = false;

  bool _calculateSaveEnabled() {
    final summaryFilled = _summaryController.text.trim().isNotEmpty;
    if (!summaryFilled) {
      return false;
    }

    if (!_formWasSubmitted) {
      return true;
    }

    final formState = _formKey.currentState;
    if (formState == null) {
      return summaryFilled;
    }

    return formState.validate();
  }

  void _updateSaveEnabled() {
    final nextValue = _calculateSaveEnabled();
    if (nextValue != _isSaveEnabled) {
      setState(() {
        _isSaveEnabled = nextValue;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    final initial = widget.initialInteraction;
    _summaryController =
        TextEditingController(text: initial != null ? initial.summary : '');
    _locationController = TextEditingController(
      text: initial?.location ?? '',
    );
    _durationController = TextEditingController(
      text: initial?.durationMinutes != null
          ? initial!.durationMinutes.toString()
          : '',
    );
    _categoryController = TextEditingController(text: initial?.category ?? '');
    _occurredAt = initial?.occurredAt ?? DateTime.now();
    _followUpAt = initial?.followUpAt;
    _medium = initial?.medium ?? 'in_person';
    _markForPrayer = initial?.markForPrayer ?? false;
    _speechBaseText = _summaryController.text.trim();
    _summaryController.addListener(_updateSaveEnabled);
    _durationController.addListener(_updateSaveEnabled);
    _isSaveEnabled = _calculateSaveEnabled();
  }

  @override
  void dispose() {
    _sheetActive = false;
    _speechToText.stop();
    _speechToText.cancel();
    _summaryController.removeListener(_updateSaveEnabled);
    _durationController.removeListener(_updateSaveEnabled);
    _summaryController.dispose();
    _locationController.dispose();
    _durationController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _pickDateTime() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (time == null) return;
    setState(() {
      _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _pickFollowUp() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _followUpAt ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2100),
    );
    if (date == null) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_followUpAt ?? DateTime.now()),
    );
    if (time == null) return;
    setState(() {
      _followUpAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  Future<void> _stopListening() async {
    if (!_speechInitialized || !_isListening) return;
    try {
      await _speechToText.stop();
      _speechBaseText = _summaryController.text.trim();
    } catch (_) {
      // Ignore teardown failures.
    } finally {
      if (_sheetActive && mounted) {
        setState(() {
          _isListening = false;
        });
      }
    }
  }

  Future<void> _toggleVoiceInput() async {
    if (_isListening) {
      await _stopListening();
      return;
    }

    if (!_speechInitialized) {
      try {
        final available = await _speechToText.initialize(
          onError: (error) {
            if (!_sheetActive || !mounted) return;
            setState(() {
              _isListening = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Voice capture error: ${error.errorMsg}'),
              ),
            );
          },
          onStatus: (status) {
            if (!_sheetActive || !mounted) return;
            final normalized = status.toLowerCase();
            if (normalized == 'done' || normalized == 'notlistening') {
              setState(() {
                _isListening = false;
              });
              _speechBaseText = _summaryController.text.trim();
            }
          },
        );
        _speechInitialized = true;
        _hasSpeechCapability = available;
        if (!available) {
          if (_sheetActive && mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Speech recognition is unavailable on this device.'),
              ),
            );
          }
          return;
        }
      } catch (error) {
        if (_sheetActive && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Speech recognition failed: $error')),
          );
        }
        return;
      }
    } else if (!_hasSpeechCapability) {
      if (_sheetActive && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Speech recognition permission is not granted.'),
          ),
        );
      }
      return;
    }

    FocusScope.of(context).unfocus();
    _speechBaseText = _summaryController.text.trim();

    try {
      final started = await _speechToText.listen(
        listenMode: ListenMode.dictation,
        onResult: (SpeechRecognitionResult result) {
          if (!_sheetActive || !mounted) {
            return;
          }
          final recognized = result.recognizedWords.trim();
          setState(() {
            final base = _speechBaseText.trim();
            final pieces = <String>[];
            if (base.isNotEmpty) {
              pieces.add(base);
            }
            if (recognized.isNotEmpty) {
              pieces.add(recognized);
            }
            final combined = pieces.join(pieces.length > 1 ? ' ' : '').trim();
            _summaryController.value = TextEditingValue(
              text: combined,
              selection: TextSelection.collapsed(offset: combined.length),
            );
          });
        },
      );
      if (!started) {
        if (_sheetActive && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Unable to start voice capture.')),
          );
        }
        return;
      }
      if (!_sheetActive) {
        await _speechToText.stop();
        return;
      }
      if (mounted) {
        setState(() {
          _isListening = true;
        });
      }
    } catch (error) {
      if (_sheetActive && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Voice capture error: $error')),
        );
      }
    }
  }

  Future<void> _saveInteraction() async {
    final form = _formKey.currentState;
    final isValid = form?.validate() ?? false;
    if (!isValid) {
      setState(() {
        _formWasSubmitted = true;
        _autovalidateMode = AutovalidateMode.onUserInteraction;
      });
      _updateSaveEnabled();
      return;
    }

    if (_isSavingInteraction) {
      return;
    }

    setState(() {
      _isSavingInteraction = true;
    });

    final summary = _summaryController.text.trim();
    final durationText = _durationController.text.trim();
    final durationMinutes =
        durationText.isEmpty ? null : int.tryParse(durationText);
    final categoryText = _categoryController.text.trim();
    final category = categoryText.isEmpty ? null : categoryText;

    final interaction = Interaction(
      id: widget.initialInteraction?.id,
      contactId: widget.contact.id,
      occurredAt: _occurredAt,
      summary: summary,
      medium: _medium,
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      markForPrayer: _markForPrayer,
      followUpAt: _followUpAt,
      durationMinutes: durationMinutes,
      category: category,
    );

    final bool isEditing = widget.initialInteraction != null;
    final previousInteractions =
        List<Interaction>.from(widget.existingInteractions);
    final optimisticInteractions = List<Interaction>.from(previousInteractions);

    if (isEditing) {
      final index = optimisticInteractions.indexWhere(
        (item) => item.id == interaction.id,
      );
      if (index != -1) {
        optimisticInteractions[index] = interaction;
      } else {
        optimisticInteractions.add(interaction);
      }
    } else {
      optimisticInteractions.add(interaction);
    }

    optimisticInteractions.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    widget.onInteractionsUpdated?.call(
      List<Interaction>.from(optimisticInteractions),
    );

    try {
      final dbHelper = DBHelper();
      Interaction savedInteraction;
      if (isEditing) {
        await dbHelper.updateInteraction(interaction);
        savedInteraction = interaction;
      } else {
        savedInteraction = await dbHelper.insertInteraction(interaction);
      }

      await BackupService().exportBackup();

      final committedInteractions = List<Interaction>.from(optimisticInteractions);
      if (!isEditing) {
        final pendingIndex = committedInteractions.indexWhere(
          (item) => identical(item, interaction),
        );
        if (pendingIndex != -1) {
          committedInteractions[pendingIndex] = savedInteraction;
        } else {
          committedInteractions.add(savedInteraction);
          committedInteractions.sort(
            (a, b) => b.occurredAt.compareTo(a.occurredAt),
          );
        }
      }

      widget.onInteractionsUpdated?.call(
        List<Interaction>.from(committedInteractions),
      );

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isEditing
              ? 'Interaction updated'
              : 'Interaction logged'),
        ),
      );

      _sheetActive = false;
      await _stopListening();
      if (mounted) {
        Navigator.of(context).pop(savedInteraction);
      }
    } catch (error) {
      widget.onInteractionsUpdated?.call(
        List<Interaction>.from(previousInteractions),
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _isSavingInteraction = false;
        _isSaveEnabled = _calculateSaveEnabled();
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save interaction: $error'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.initialInteraction != null;
    return WillPopScope(
      onWillPop: () async {
        _sheetActive = false;
        await _stopListening();
        return true;
      },
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          top: 24,
        ),
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            autovalidateMode: _autovalidateMode,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                  Text(
                    isEditing ? 'Edit interaction' : 'Log interaction',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () async {
                      _sheetActive = false;
                      await _stopListening();
                      if (mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _summaryController,
                decoration: InputDecoration(
                  labelText: 'Summary *',
                  border: const OutlineInputBorder(),
                  helperText: _isListening ? 'Listening...' : null,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
                    onPressed: _toggleVoiceInput,
                    tooltip:
                        _isListening ? 'Stop voice capture' : 'Use voice to text',
                  ),
                ),
                textCapitalization: TextCapitalization.sentences,
                maxLines: 2,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Add a short summary first.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                value: _medium,
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
                  setState(() {
                    _medium = value;
                  });
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _locationController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Location (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _durationController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Duration (minutes, optional)',
                  border: OutlineInputBorder(),
                ),
                validator: (value) {
                  final text = value?.trim() ?? '';
                  if (text.isEmpty) {
                    return null;
                  }
                  final parsed = int.tryParse(text);
                  if (parsed == null) {
                    return 'Duration must be a number of minutes.';
                  }
                  if (parsed < 0) {
                    return 'Duration cannot be negative.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _categoryController,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  labelText: 'Category (optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Occurred at'),
                subtitle: Text(
                  DateFormat.yMMMd().add_jm().format(_occurredAt),
                ),
                trailing: const Icon(Icons.edit_outlined),
                onTap: _pickDateTime,
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Mark for prayer'),
                value: _markForPrayer,
                onChanged: (value) {
                  setState(() {
                    _markForPrayer = value;
                  });
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Follow-up reminder'),
                subtitle: Text(
                  _followUpAt != null
                      ? DateFormat.yMMMd().add_jm().format(_followUpAt!)
                      : 'None',
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_followUpAt != null)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () {
                          setState(() {
                            _followUpAt = null;
                          });
                        },
                      ),
                    IconButton(
                      icon: const Icon(Icons.calendar_month_outlined),
                      onPressed: _pickFollowUp,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed:
                      _isSaveEnabled && !_isSavingInteraction ? _saveInteraction : null,
                  child: _isSavingInteraction
                      ? SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              Theme.of(context)
                                  .colorScheme
                                  .onPrimary,
                            ),
                          ),
                        )
                      : Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.check),
                            const SizedBox(width: 8),
                            Text(isEditing ? 'Update' : 'Save'),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }
}
