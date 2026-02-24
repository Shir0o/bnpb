import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/interaction.dart';
import '../models/relationship.dart';
import '../services/backup_service.dart';
import '../services/contact_service.dart';
import '../services/reminder_coordinator.dart';
import '../widgets/contact_details_skeleton.dart';
import '../widgets/contact_selection_sheet.dart';
import '../widgets/people_card.dart';
import '../widgets/relationship_dialog.dart';

// Optimization: Cached DateFormats to avoid expensive parsing during scroll/build loops.
final _cardDateFormatter = DateFormat.yMMMd().add_jm();
final _cardFollowUpFormatter = DateFormat.MMMd().add_jm();

const Map<String, String> _mediumLabels = {
  'in_person': 'In-person',
  'call': 'Call',
  'message': 'Message',
  'online': 'Online Meeting',
  'other': 'Other',
};

const Map<String, IconData> _mediumIcons = {
  'in_person': Icons.people_outline,
  'call': Icons.phone_outlined,
  'message': Icons.chat_bubble_outline,
  'online': Icons.videocam_outlined,
  'other': Icons.more_horiz,
};

class ContactDetailsPage extends StatefulWidget {
  final Contact contact;
  final Future<void> Function() onDelete;

  ContactDetailsPage({
    super.key,
    required this.contact,
    required this.onDelete,
    ContactService? contactService,
    DBHelper? dbHelper,
  })  : _contactService = contactService ?? ContactService(),
        _dbHelper = dbHelper ?? DBHelper();

  final ContactService _contactService;
  final DBHelper _dbHelper;

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
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _tagController = TextEditingController();
  final TextEditingController _interactionSearchController =
      TextEditingController();
  final TextEditingController _keywordController = TextEditingController();
  final TextEditingController _reminderController = TextEditingController();
  final TextEditingController _photoCueController = TextEditingController();

  List<Interaction> _interactions = [];
  List<Interaction> _filteredInteractionsCache = [];

  bool _isLoadingInteractions = false;
  String _interactionQuery = '';
  bool _isEditing = false;
  Contact? _editingSnapshot;
  bool _isInitialLoad = true;

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

  @override
  void initState() {
    super.initState();
    final contact = widget.contact;
    // Interactions are guaranteed to be sorted by occurredAt descending.
    _interactions = List<Interaction>.from(contact.interactions);

    _applyContactData(contact);

    _interactionSearchController.addListener(_updateFilteredInteractions);

    _checkCacheAndLoad();
  }

  void _checkCacheAndLoad() {
    final service = widget._contactService;
    // Always show skeleton first (implied by default _isInitialLoad = true),
    // but decide how long to keep it.

    if (service.hasCachedInteractions(widget.contact.id)) {
      // Cache Hit: Short delay to mask secondary loads (like relationships)
      // and provide a smooth "pop" transition.
      _performInitialLoad(minDelay: const Duration(milliseconds: 300));
    } else {
      // Cache Miss: Longer delay to ensure skeleton is seen and data fetching completes.
      _performInitialLoad(minDelay: const Duration(milliseconds: 750));
    }
  }

  Future<void> _performInitialLoad({required Duration minDelay}) async {
    // Ensure both data fetching AND the minimum delay complete.
    // We include _loadReferenceData here to ensure relationships are ready
    // before the skeleton lifts, avoiding the secondary spinner.
    try {
      await Future.wait([
        _loadReferenceData(),
        _refreshInteractions(),
        Future.delayed(minDelay),
      ]);
    } catch (e) {
      debugPrint('Error performing initial load in ContactDetailsPage: $e');
    }

    if (mounted) {
      setState(() {
        _isInitialLoad = false;
      });
    }
  }

  void _updateFilteredInteractions() {
    final query = _interactionSearchController.text.trim().toLowerCase();
    // _interactions is already sorted by occurredAt desc.
    final sorted = List<Interaction>.from(_interactions);

    if (query.isEmpty) {
      if (mounted) {
        setState(() {
          _filteredInteractionsCache = sorted;
          _interactionQuery = query;
        });
      } else {
        _filteredInteractionsCache = sorted;
        _interactionQuery = query;
      }
      return;
    }

    final filtered = sorted.where((interaction) {
      final mediumLabel =
          _mediumLabels[interaction.medium] ?? interaction.medium;
      final matchesSummary = interaction.summary.toLowerCase().contains(query);
      final matchesLocation =
          (interaction.location ?? '').toLowerCase().contains(query);
      final matchesMedium = mediumLabel.toLowerCase().contains(query);

      return matchesSummary || matchesLocation || matchesMedium;
    }).toList();

    if (mounted) {
      setState(() {
        _filteredInteractionsCache = filtered;
        _interactionQuery = query;
      });
    } else {
      _filteredInteractionsCache = filtered;
      _interactionQuery = query;
    }
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
    _notesController.dispose();
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

    final dbHelper = widget._dbHelper;
    final contacts = await dbHelper.getContacts();
    final tags = await dbHelper.getAllTags();
    final relationships =
        await dbHelper.getRelationshipsForContact(widget.contact.id);

    setState(() {
      _contactLookup = {for (final contact in contacts) contact.id: contact};
      _availableContacts =
          contacts.where((contact) => contact.id != widget.contact.id).toList()
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

  Future<void> _refreshInteractions({bool forceRefresh = false}) async {
    // Only show local spinner if NOT in initial load (which has skeleton).
    if (!_isInitialLoad) {
      setState(() {
        _isLoadingInteractions = true;
      });
    }

    try {
      final interactions = await widget._contactService.getInteractions(
        widget.contact.id,
        forceRefresh: forceRefresh,
      );

      if (!mounted) return;
      setState(() {
        _interactions = List.from(interactions);

        _isLoadingInteractions = false;
        _updateFilteredInteractions();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingInteractions = false;
      });
      debugPrint('Error loading interactions: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to load interactions. Please try again.'),
          backgroundColor: Colors.red,
        ),
      );
    }
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

  ImageProvider<Object>? _resizeProvider(
    ImageProvider<Object>? provider,
    double displaySize,
  ) {
    if (provider == null) return null;
    // We use a multiplier to ensure we have enough resolution for aspect ratios
    // where width < height (portrait), preventing blurriness when using BoxFit.cover.
    // displaySize is the width of the container.
    final cacheWidth =
        (displaySize * MediaQuery.of(context).devicePixelRatio * 1.5).toInt();
    return ResizeImage(
      provider,
      width: cacheWidth,
    );
  }

  Contact _buildContactFromState({List<Interaction>? interactionsOverride}) {
    final lastNameText = _lastNameController.text.trim();
    final nicknameText = _nicknameController.text.trim();
    final locationText = _locationController.text.trim();
    final firstMeetingNotesText = _firstMeetingNotesController.text.trim();
    final notesText = _notesController.text.trim();

    return Contact(
      id: widget.contact.id,
      firstName: _firstNameController.text.trim(),
      middleName: _middleNameController.text.trim(),
      lastName: lastNameText.isEmpty ? null : lastNameText,
      nickname: nicknameText.isEmpty ? null : nicknameText,
      location: locationText.isEmpty ? null : locationText,
      firstMeetingNotes:
          firstMeetingNotesText.isEmpty ? null : firstMeetingNotesText,
      notes: notesText.isEmpty ? null : notesText,
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
    _notesController.text = contact.notes ?? '';
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
      await widget._dbHelper.updateContact(updatedContact);
      await ReminderCoordinator().refreshContact(updatedContact.id);
      widget._contactService.invalidateContacts();
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
                if (!dialogContext.mounted) return;
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

    await widget._dbHelper.deleteInteraction(interaction.id!);
    await ReminderCoordinator().cancelInteractionReminder(interaction);
    widget._contactService.invalidateInteractions(widget.contact.id);

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
    final nextInteractions = List<Interaction>.from(interactions);
    setState(() {
      _interactions = nextInteractions;

      _updateFilteredInteractions();
    });
  }

  void _showQuickAddInteractionSheet() async {
    final allContacts = [widget.contact, ..._availableContacts];
    final interaction = await showModalBottomSheet<Interaction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      sheetAnimationStyle: AnimationStyle(
        duration: const Duration(milliseconds: 600),
        reverseDuration: const Duration(milliseconds: 300),
        curve: Curves.easeInOutCubicEmphasized,
        reverseCurve: Curves.easeInOutCubicEmphasized.flipped,
      ),
      builder: (context) => _LogInteractionSheet(
        contact: widget.contact,
        existingInteractions: List<Interaction>.from(_interactions),
        availableContacts: allContacts,
        onInteractionsUpdated: (updated) {
          if (!mounted) return;
          widget._contactService.invalidateInteractions(widget.contact.id);
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
        await widget._dbHelper.getRelationshipsForContact(widget.contact.id);
    setState(() {
      _relationships = relationships;
      _isLoadingRelationships = false;
    });
  }

  void _showRelationshipDialog({Relationship? relationship}) {
    final isEditing = relationship != null;
    if (isEditing && relationship.sourceContactId != widget.contact.id) {
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

    showDialog(
      context: context,
      builder: (context) {
        return RelationshipDialog(
          currentContact: widget.contact,
          availableContacts: _availableContacts,
          relationship: relationship,
          onSave: (relationshipToSave) async {
            await widget._dbHelper.upsertRelationship(relationshipToSave);
            await _refreshRelationships();
            if (context.mounted) Navigator.pop(context);
          },
        );
      },
    );
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
                await widget._dbHelper.deleteRelationship(relationship.id!);
                await _refreshRelationships();
                if (!context.mounted) return;
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
        .where(
            (relationship) => relationship.sourceContactId == widget.contact.id)
        .toList();
    final incoming = _relationships
        .where(
            (relationship) => relationship.targetContactId == widget.contact.id)
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
                  onPressed: () => _confirmDeleteRelationship(relationship),
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

    final detailSections = _isEditing
        ? _buildEditingSections()
        : _buildReadOnlySections(previewContact);

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
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeOut,
        child: _isInitialLoad
            ? const ContactDetailsSkeleton(key: ValueKey('skeleton'))
            : CustomScrollView(
                key: const ValueKey('content'),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.all(16.0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate(
                        [
                          PeopleCard(
                            contact: previewContact,
                          ),
                          const SizedBox(height: 16),
                          ...detailSections,
                          if (detailSections.isNotEmpty)
                            const SizedBox(height: 16),
                          _buildRelationshipCard(),
                          const SizedBox(height: 16),
                        ],
                      ),
                    ),
                  ),
                  ..._buildInteractionsSlivers(),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 80),
                  ),
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

  List<Widget> _buildInteractionsSlivers() {
    final theme = Theme.of(context);
    final title = Text(
      'Interactions',
      style: theme.textTheme.titleMedium,
    );

    // If loading or empty, just show the header card with appropriate content
    if (_isLoadingInteractions) {
      return [
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          sliver: SliverToBoxAdapter(
            child: _buildCard(
              children: [
                title,
                const SizedBox(height: 12),
                const Center(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: CircularProgressIndicator(),
                  ),
                ),
              ],
            ),
          ),
        ),
      ];
    }

    final header = SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverToBoxAdapter(
        child: _buildCard(
          children: [
            title,
            const SizedBox(height: 12),
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
            if (_filteredInteractionsCache.isEmpty) ...[
              const SizedBox(height: 12),
              const Text(
                'No interactions logged yet. Use the button below to record one.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ],
        ),
      ),
    );

    if (_filteredInteractionsCache.isEmpty) {
      return [header];
    }

    return [
      header,
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        sliver: SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final interaction = _filteredInteractionsCache[index];
              return _buildTimelineTile(
                interaction: interaction,
                isFirst: index == 0,
                isLast: index == _filteredInteractionsCache.length - 1,
              );
            },
            childCount: _filteredInteractionsCache.length,
          ),
        ),
      ),
    ];
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

    addSection(_buildViewTagsCard(contact));
    addSection(_buildViewMeetingNotesCard(contact));
    addSection(_buildViewNotesCard(contact));
    addSection(_buildViewRecognitionCard(contact));
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
        const SizedBox(height: 16),
        _buildTextField(
          controller: _notesController,
          label: 'Notes (Optional)',
          maxLines: 5,
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
                      backgroundImage: _resizeProvider(
                        _buildImageProviderForCue(cue),
                        40,
                      ),
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

  Widget? _buildViewNotesCard(Contact contact) {
    final notes = contact.notes;
    if (notes == null || notes.isEmpty) {
      return null;
    }
    return _buildCard(
      children: [
        Text(
          'Notes',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        Text(
          notes,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
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
                color: theme.colorScheme.surfaceContainerHighest,
                child: provider != null
                    ? Image(
                        image: _resizeProvider(provider, 72)!,
                        fit: BoxFit.cover,
                      )
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
      // Optimization: Replaced IntrinsicHeight + Row with Stack.
      // The interaction card (non-positioned child) determines the height of the Stack.
      // The timeline (CustomPaint) is Positioned to stretch from top to bottom (top: 0, bottom: 0),
      // avoiding the expensive speculative layout pass of IntrinsicHeight.
      child: Stack(
        children: [
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: 48,
            child: CustomPaint(
              painter: _TimelinePainter(
                isFirst: isFirst,
                isLast: isLast,
                color: lineColor,
              ),
              child: Align(
                alignment: Alignment.topCenter,
                child: Container(
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
                        color: indicatorColor.withValues(alpha: 0.28),
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
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 60), // 48 + 12 spacing
            child: _buildInteractionCard(interaction),
          ),
        ],
      ),
    );
  }

  Widget _buildInteractionCard(Interaction interaction) {
    final theme = Theme.of(context);
    final mediumLabel = _mediumLabels[interaction.medium] ?? interaction.medium;
    final mediumIcon = _mediumIcons[interaction.medium] ?? Icons.forum_outlined;

    final occurredAtLabel = _cardDateFormatter.format(interaction.occurredAt);
    final participantBadges = _buildParticipantBadges(interaction);
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

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: interaction.id != null
            ? () => _openInteractionDetails(interaction)
            : null,
        // Optimization: Isolate the complex content from the InkWell ripple animation.
        // The ripple is painted on the Material widget, so wrapping the content prevents
        // it from being repainted on every frame of the splash.
        child: RepaintBoundary(
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.colorScheme.outlineVariant),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      mediumIcon,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  occurredAtLabel,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                              ),
                              Icon(
                                interaction.markForPrayer
                                    ? Icons.self_improvement_outlined
                                    : Icons.event_note_outlined,
                                size: 16,
                                color: interaction.markForPrayer
                                    ? theme.colorScheme.secondary
                                    : theme.colorScheme.primary,
                              ),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Text(
                            interaction.summary,
                            style: theme.textTheme.titleSmall,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          if (participantBadges.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 8,
                              children: participantBadges,
                            ),
                          ],
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
                          if (interaction.notes != null &&
                              interaction.notes!.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                interaction.notes!,
                                style: theme.textTheme.labelSmall,
                                maxLines: 2,
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
                            onPressed: () =>
                                _showEditInteractionSheet(interaction),
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
                          _cardFollowUpFormatter
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
          ),
        ),
      ),
    );
  }

  List<Widget> _buildParticipantBadges(Interaction interaction) {
    if (interaction.participantIds.isEmpty) {
      return const [];
    }

    final theme = Theme.of(context);
    return interaction.participantIds.toSet().map((participantId) {
      final displayName = _displayNameForContactId(participantId);
      final name = displayName.isNotEmpty ? displayName : participantId;
      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

      return Chip(
        avatar: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          foregroundColor: theme.colorScheme.primary,
          child: Text(initial),
        ),
        label: Text(name),
        visualDensity: VisualDensity.compact,
      );
    }).toList();
  }

  void _showEditInteractionSheet(Interaction interaction) async {
    final allContacts = [widget.contact, ..._availableContacts];
    final updatedInteraction = await showModalBottomSheet<Interaction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _LogInteractionSheet(
        contact: widget.contact,
        existingInteractions: List<Interaction>.from(_interactions),
        initialInteraction: interaction,
        availableContacts: allContacts,
        onInteractionsUpdated: (updated) {
          if (!mounted) return;
          ContactService().invalidateInteractions(widget.contact.id);
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

  Future<void> _openInteractionDetails(Interaction interaction) async {
    if (interaction.id == null) {
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => InteractionDetailPage(
          interactionId: interaction.id!,
          initialInteraction: interaction,
          contactLookup: _contactLookup,
        ),
      ),
    );

    if (!mounted) {
      return;
    }

    await _refreshInteractions();
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
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
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

class InteractionDetailPage extends StatefulWidget {
  const InteractionDetailPage({
    super.key,
    required this.interactionId,
    required this.initialInteraction,
    required this.contactLookup,
  });

  final int interactionId;
  final Interaction initialInteraction;
  final Map<String, Contact> contactLookup;

  @override
  State<InteractionDetailPage> createState() => _InteractionDetailPageState();
}

class _InteractionDetailPageState extends State<InteractionDetailPage> {
  late Interaction _interaction;
  late Map<String, Contact> _contactLookup;
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _interaction = widget.initialInteraction;
    _contactLookup = Map<String, Contact>.from(widget.contactLookup);
    _refreshInteraction();
  }

  Future<void> _refreshInteraction() async {
    setState(() {
      _isLoading = true;
    });

    final dbHelper = DBHelper();
    final contacts = await dbHelper.getContacts();
    final lookup = {for (final contact in contacts) contact.id: contact};
    final latestInteraction = await dbHelper.getInteractionById(
      widget.interactionId,
    );

    if (!mounted) {
      return;
    }

    setState(() {
      _contactLookup = lookup;
      if (latestInteraction != null) {
        _interaction = latestInteraction;
      }
      _isLoading = false;
    });
  }

  Contact? get _primaryContact {
    for (final participantId in _interaction.participantIds) {
      final contact = _contactLookup[participantId];
      if (contact != null) {
        return contact;
      }
    }
    return _contactLookup.values.isNotEmpty
        ? _contactLookup.values.first
        : null;
  }

  List<Widget> _buildParticipantBadges() {
    if (_interaction.participantIds.isEmpty) {
      return const [];
    }

    final theme = Theme.of(context);
    return _interaction.participantIds.toSet().map((participantId) {
      final contact = _contactLookup[participantId];
      final name = contact?.fullName.isNotEmpty == true
          ? contact!.fullName
          : (contact?.nickname?.isNotEmpty == true
              ? contact!.nickname!
              : participantId);
      final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

      return Chip(
        avatar: CircleAvatar(
          backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
          foregroundColor: theme.colorScheme.primary,
          child: Text(initial),
        ),
        label: Text(name),
        visualDensity: VisualDensity.compact,
      );
    }).toList();
  }

  Widget _buildDetailTile({
    required IconData icon,
    required String title,
    String? value,
  }) {
    if (value == null || value.isEmpty) {
      return const SizedBox.shrink();
    }

    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(value),
    );
  }

  Future<void> _editInteraction() async {
    final contact = _primaryContact;
    if (contact == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No contacts available to edit this interaction.'),
          ),
        );
      }
      return;
    }

    final updatedInteraction = await showModalBottomSheet<Interaction>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      isDismissible: false,
      enableDrag: false,
      builder: (context) => _LogInteractionSheet(
        contact: contact,
        existingInteractions: const [],
        initialInteraction: _interaction,
        availableContacts: _contactLookup.values.toList(),
      ),
    );

    if (!mounted || updatedInteraction == null) {
      return;
    }

    await _refreshInteraction();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Interaction updated')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final participantBadges = _buildParticipantBadges();
    final mediumLabel =
        _mediumLabels[_interaction.medium] ?? _interaction.medium;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Interaction details'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            onPressed: _isLoading ? null : _editInteraction,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refreshInteraction,
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            if (_isLoading) ...[
              const LinearProgressIndicator(),
              const SizedBox(height: 12),
            ],
            Text(
              _interaction.summary,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              _cardDateFormatter.format(_interaction.occurredAt),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            if (participantBadges.isNotEmpty) ...[
              Text('Participants', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: participantBadges,
              ),
              const SizedBox(height: 16),
            ],
            _buildDetailTile(
              icon: _mediumIcons[_interaction.medium] ??
                  Icons.event_note_outlined,
              title: 'Medium',
              value: mediumLabel,
            ),
            _buildDetailTile(
              icon: Icons.place_outlined,
              title: 'Location',
              value: _interaction.location,
            ),
            _buildDetailTile(
              icon: Icons.notes_outlined,
              title: 'Notes',
              value: _interaction.notes,
            ),
            _buildDetailTile(
              icon: Icons.timer_outlined,
              title: 'Duration',
              value: _interaction.durationMinutes != null
                  ? '${_interaction.durationMinutes} minutes'
                  : null,
            ),
            _buildDetailTile(
              icon: Icons.alarm_outlined,
              title: 'Follow-up',
              value: _interaction.followUpAt != null
                  ? _cardDateFormatter.format(_interaction.followUpAt!)
                  : null,
            ),
            if (_interaction.markForPrayer)
              ListTile(
                leading: Icon(
                  Icons.self_improvement_outlined,
                  color: theme.colorScheme.secondary,
                ),
                title: const Text('Marked for prayer'),
              ),
          ],
        ),
      ),
    );
  }
}

class _LogInteractionSheet extends StatefulWidget {
  const _LogInteractionSheet({
    required this.contact,
    required this.existingInteractions,
    required this.availableContacts,
    this.initialInteraction,
    this.onInteractionsUpdated,
  });

  final Contact contact;
  final List<Interaction> existingInteractions;
  final List<Contact> availableContacts;
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
  late final TextEditingController _notesController;
  late final TextEditingController _occurredTimeController;
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
  bool _occurredAtManuallyChanged = false;
  List<Contact> _availableContacts = [];
  Map<String, Contact> _contactLookup = {};
  Set<String> _selectedParticipantIds = {};

  bool _calculateSaveEnabled() {
    final summaryFilled = _summaryController.text.trim().isNotEmpty;
    if (!summaryFilled) {
      return false;
    }

    final manualTimeError = _applyManualOccurredTime(
      _occurredTimeController.text,
      shouldUpdate: false,
    );
    if (manualTimeError != null) {
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

  void _updateOccurredAtFromDuration() {
    if (_occurredAtManuallyChanged) {
      return;
    }

    final text = _durationController.text.trim();
    if (text.isEmpty) {
      return;
    }

    final durationMinutes = int.tryParse(text);
    if (durationMinutes == null || durationMinutes < 0) {
      return;
    }

    final now = DateTime.now();
    final newOccurredAt = now.subtract(Duration(minutes: durationMinutes));

    // Check if significant change to avoid loop
    if (_occurredAt.difference(newOccurredAt).abs().inMinutes < 1) {
       // Keep existing time if difference is negligible to avoid jitter
       // But user might want exact update.
       // Actually, every keystroke will update it relative to 'now'.
       // So typing '1' -> now-1. Typing '0' -> now-10.
    }

    setState(() {
      _occurredAt = newOccurredAt;
    });

    final newTimeText = DateFormat.jm().format(newOccurredAt);
    if (_occurredTimeController.text != newTimeText) {
      _occurredTimeController.text = newTimeText;
    }
  }

  void _updateSaveEnabled() {
    final nextValue = _calculateSaveEnabled();
    if (nextValue != _isSaveEnabled) {
      setState(() {
        _isSaveEnabled = nextValue;
      });
    }
  }

  void _initContacts() {
    _availableContacts = List.from(widget.availableContacts);
    _availableContacts.sort(
      (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
    );
    _contactLookup = {
      for (final contact in _availableContacts) contact.id: contact
    };
    _selectedParticipantIds = {
      widget.contact.id,
      ..._selectedParticipantIds,
      ...(widget.initialInteraction?.participantIds ?? const <String>{}),
    };
  }

  Future<void> _showParticipantSelectionDialog() async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: AnimationStyle(
        duration: const Duration(milliseconds: 300),
        reverseDuration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      ),
      builder: (context) => ContactSelectionSheet(
        title: 'Select Participants',
        initialSelectedIds: _selectedParticipantIds,
        disabledIds: {widget.contact.id},
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedParticipantIds = {
          widget.contact.id,
          ...result,
        };
      });
    }
  }

  void _toggleParticipant(String contactId) {
    if (contactId == widget.contact.id) {
      return;
    }

    setState(() {
      if (_selectedParticipantIds.contains(contactId)) {
        _selectedParticipantIds.remove(contactId);
      } else {
        _selectedParticipantIds.add(contactId);
      }
    });
  }

  Widget _buildParticipantChip(
    Contact contact, {
    required bool isSelected,
    required bool isEnabled,
  }) {
    final theme = Theme.of(context);
    final name = contact.fullName.isNotEmpty
        ? contact.fullName
        : (contact.nickname?.isNotEmpty == true
            ? contact.nickname!
            : contact.id);
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    return FilterChip(
      avatar: CircleAvatar(
        backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.12),
        foregroundColor: theme.colorScheme.primary,
        child: Text(initial),
      ),
      label: Text(name),
      selected: isSelected,
      onSelected: isEnabled ? (_) => _toggleParticipant(contact.id) : null,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildParticipantsPicker() {
    final chips = <Widget>[];

    // Add primary contact (read-only)
    final primaryContact = _contactLookup[widget.contact.id] ?? widget.contact;
    chips.add(
      _buildParticipantChip(
        primaryContact,
        isSelected: true,
        isEnabled: false,
      ),
    );

    // Add selected contacts
    for (final id in _selectedParticipantIds) {
      if (id == widget.contact.id) continue;
      final contact = _contactLookup[id];
      if (contact != null) {
        chips.add(
          _buildParticipantChip(
            contact,
            isSelected: true,
            isEnabled: true,
          ),
        );
      } else {
        // Fallback for unknown IDs
        chips.add(
          Chip(
            label: Text(id),
            onDeleted: () => _toggleParticipant(id),
          ),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Participants',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: chips,
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _showParticipantSelectionDialog,
          icon: const Icon(Icons.person_add_outlined),
          label: const Text('Add participant'),
        ),
      ],
    );
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
    _notesController = TextEditingController(text: initial?.notes ?? '');
    _occurredAt = initial?.occurredAt ?? DateTime.now();
    _occurredTimeController = TextEditingController(
      text: DateFormat.jm().format(_occurredAt),
    );
    _followUpAt = initial?.followUpAt;
    _medium = initial?.medium ?? 'in_person';
    _markForPrayer = initial?.markForPrayer ?? false;
    _selectedParticipantIds = {
      widget.contact.id,
      ...(initial?.participantIds ?? const <String>{}),
    };
    _initContacts();
    _occurredAtManuallyChanged = widget.initialInteraction != null;
    _speechBaseText = _summaryController.text.trim();
    _summaryController.addListener(_updateSaveEnabled);
    _durationController.addListener(_updateSaveEnabled);
    _durationController.addListener(_updateOccurredAtFromDuration);
    _isSaveEnabled = _calculateSaveEnabled();
  }

  @override
  void dispose() {
    _sheetActive = false;
    _speechToText.stop();
    _speechToText.cancel();
    _summaryController.removeListener(_updateSaveEnabled);
    _durationController.removeListener(_updateSaveEnabled);
    _durationController.removeListener(_updateOccurredAtFromDuration);
    _summaryController.dispose();
    _locationController.dispose();
    _durationController.dispose();
    _notesController.dispose();
    _occurredTimeController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _occurredAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (!mounted || date == null) return;
    setState(() {
      _occurredAtManuallyChanged = true;
      _occurredAt = DateTime(
        date.year,
        date.month,
        date.day,
        _occurredAt.hour,
        _occurredAt.minute,
      );
    });
    // No need to update time text controller as date doesn't affect time string (JM format)
    _updateSaveEnabled();
  }

  Future<void> _pickTime() async {
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_occurredAt),
    );
    if (!mounted || time == null) return;
    setState(() {
      _occurredAtManuallyChanged = true;
      _occurredAt = DateTime(
        _occurredAt.year,
        _occurredAt.month,
        _occurredAt.day,
        time.hour,
        time.minute,
      );
    });
    _occurredTimeController.text = DateFormat.jm().format(_occurredAt);
    _updateSaveEnabled();
  }

  String? _applyManualOccurredTime(
    String value, {
    bool shouldUpdate = true,
  }) {
    final text = value.trim();
    if (text.isEmpty) {
      return 'Enter a time.';
    }

    DateTime? parsed;
    try {
      parsed = DateFormat.jm().parseLoose(text);
    } catch (_) {
      try {
        parsed = DateFormat.Hm().parseLoose(text);
      } catch (_) {
        parsed = null;
      }
    }

    if (parsed == null) {
      return 'Enter a valid time (e.g., 3:45 PM).';
    }

    final normalized = DateTime(
      _occurredAt.year,
      _occurredAt.month,
      _occurredAt.day,
      parsed.hour,
      parsed.minute,
    );

    if (shouldUpdate) {
      setState(() {
        _occurredAtManuallyChanged = true;
        _occurredAt = normalized;
      });
      final normalizedText = DateFormat.jm().format(normalized);
      _occurredTimeController.value = TextEditingValue(
        text: normalizedText,
        selection: TextSelection.collapsed(offset: normalizedText.length),
      );
    }

    return null;
  }

  void _commitManualOccurredTime([String? value]) {
    final error = _applyManualOccurredTime(
      value ?? _occurredTimeController.text,
    );
    if (error != null &&
        _autovalidateMode != AutovalidateMode.onUserInteraction) {
      setState(() {
        _autovalidateMode = AutovalidateMode.onUserInteraction;
      });
    }
    _updateSaveEnabled();
  }

  Future<void> _pickFollowUp() async {
    final date = await showDatePicker(
      context: context,
      initialDate: _followUpAt ?? DateTime.now(),
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime(2100),
    );
    if (!mounted || date == null) return;
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
                content:
                    Text('Speech recognition is unavailable on this device.'),
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

    if (!mounted) return;
    FocusScope.of(context).unfocus();
    _speechBaseText = _summaryController.text.trim();

    try {
      final started = await _speechToText.listen(
        listenOptions: SpeechListenOptions(listenMode: ListenMode.dictation),
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
    final notesText = _notesController.text.trim();
    final notes = notesText.isEmpty ? null : notesText;

    final participants = <String>{
      widget.contact.id,
      ..._selectedParticipantIds,
    };

    final interaction = Interaction(
      id: widget.initialInteraction?.id,
      syncId: widget.initialInteraction?.syncId,
      occurredAt: _occurredAt,
      summary: summary,
      medium: _medium,
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      attachments: widget.initialInteraction?.attachments ?? const [],
      markForPrayer: _markForPrayer,
      followUpAt: _followUpAt,
      durationMinutes: durationMinutes,
      notes: notes,
      participantIds: participants.toList(),
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

      final committedInteractions =
          List<Interaction>.from(optimisticInteractions);
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
          content:
              Text(isEditing ? 'Interaction updated' : 'Interaction logged'),
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
    final theme = Theme.of(context);

    // Using a Scaffold inside the sheet provides automatic body resizing for keyboard
    // and a standard AppBar structure for the actions.
    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) async {
        _sheetActive = false;
        await _stopListening();
      },
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () async {
                _sheetActive = false;
                await _stopListening();
                if (context.mounted) {
                  Navigator.of(context).pop();
                }
              },
            ),
            centerTitle: true,
            title: Text(
              isEditing ? 'Edit interaction' : 'Log interaction',
              style: theme.textTheme.titleMedium,
            ),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8.0),
                child: TextButton(
                  onPressed: _isSaveEnabled && !_isSavingInteraction
                      ? _saveInteraction
                      : null,
                  child: _isSavingInteraction
                      ? SizedBox(
                          height: 16,
                          width: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(
                              theme.colorScheme.primary,
                            ),
                          ),
                        )
                      : Text(
                          isEditing ? 'Update' : 'Save',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                ),
              ),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
            // Ensure we can dismiss keyboard easily
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            child: Form(
              key: _formKey,
              autovalidateMode: _autovalidateMode,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (!isEditing) _buildRecentInteractions(),
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
                        tooltip: _isListening
                            ? 'Stop voice capture'
                            : 'Use voice to text',
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
                    key: ValueKey(_medium),
                    initialValue: _medium,
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
                  _buildParticipantsPicker(),
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
                    controller: _notesController,
                    textCapitalization: TextCapitalization.sentences,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Notes (optional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text('Occurred at', style: theme.textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: InkWell(
                          onTap: _pickDate,
                          borderRadius: BorderRadius.circular(4),
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Date',
                              border: OutlineInputBorder(),
                              suffixIcon: Icon(Icons.calendar_month_outlined),
                            ),
                            child: Text(
                              DateFormat.yMMMd().format(_occurredAt),
                              style: theme.textTheme.bodyLarge,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 2,
                        child: TextFormField(
                          controller: _occurredTimeController,
                          keyboardType: TextInputType.datetime,
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                              RegExp(r'[0-9: apmAPM]'),
                            ),
                          ],
                          decoration: InputDecoration(
                            labelText: 'Time',
                            border: const OutlineInputBorder(),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.access_time),
                              onPressed: _pickTime,
                              tooltip: 'Pick time',
                            ),
                          ),
                          onTapOutside: (_) => _commitManualOccurredTime(),
                          onEditingComplete: () {
                            _commitManualOccurredTime();
                            FocusScope.of(context).unfocus();
                          },
                          onFieldSubmitted: (value) {
                            _commitManualOccurredTime(value);
                          },
                          validator: (value) => _applyManualOccurredTime(
                            value ?? '',
                            shouldUpdate: false,
                          ),
                        ),
                      ),
                    ],
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRecentInteractions() {
    // 1. Get unique interactions based on signature (summary + medium + location)
    // 2. Take top 5 recent ones
    // 3. Display as chips
    final uniqueSignatures = <String>{};
    final recentDistinct = <Interaction>[];

    for (final interaction in widget.existingInteractions) {
      final signature =
          '${interaction.summary.trim()}|${interaction.medium}|${interaction.location ?? ''}';
      if (!uniqueSignatures.contains(signature.toLowerCase())) {
        uniqueSignatures.add(signature.toLowerCase());
        recentDistinct.add(interaction);
      }
      if (recentDistinct.length >= 5) break;
    }

    if (recentDistinct.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 12),
        Text(
          'Recent:',
          style: Theme.of(context).textTheme.labelSmall,
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: recentDistinct.map((interaction) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: Text(interaction.summary,
                      overflow: TextOverflow.ellipsis),
                  avatar: Icon(_mediumIcons[interaction.medium] ?? Icons.chat,
                      size: 16),
                  onPressed: () {
                    _fillFromInteraction(interaction);
                  },
                ),
              );
            }).toList(),
          ),
        ),
        const Divider(height: 24),
      ],
    );
  }

  void _fillFromInteraction(Interaction base) {
    setState(() {
      _summaryController.text = base.summary;
      _medium = base.medium;
      if (base.location != null) {
        _locationController.text = base.location!;
      }
      if (base.durationMinutes != null) {
        _durationController.text = base.durationMinutes.toString();
      }
      if (base.notes != null) {
        _notesController.text = base.notes!;
      }

      _markForPrayer = base.markForPrayer;

      // Reset participants to just base contact + those in the reused interaction
      _selectedParticipantIds = {
        widget.contact.id,
        ...base.participantIds,
      };

      // Update validation state
      _isSaveEnabled = _calculateSaveEnabled();
    });
  }
}

class _TimelinePainter extends CustomPainter {
  final bool isFirst;
  final bool isLast;
  final Color color;

  const _TimelinePainter({
    required this.isFirst,
    required this.isLast,
    required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..style = PaintingStyle.stroke;

    final centerX = size.width / 2;
    // Icon is 24x24 and aligned to top center.
    // Center of the icon is at y = 12.
    const iconCenterY = 12.0;

    if (!isFirst) {
      canvas.drawLine(
        Offset(centerX, 0),
        Offset(centerX, iconCenterY),
        paint,
      );
    }

    if (!isLast) {
      canvas.drawLine(
        Offset(centerX, iconCenterY),
        Offset(centerX, size.height),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _TimelinePainter oldDelegate) {
    return oldDelegate.isFirst != isFirst ||
        oldDelegate.isLast != isLast ||
        oldDelegate.color != color;
  }
}
