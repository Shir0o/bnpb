import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:googleapis/calendar/v3.dart' as gcal;
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:timeline_tile/timeline_tile.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/interaction.dart';
import '../models/prayer_request.dart';
import '../models/relationship.dart';
import '../services/calendar_integration_service.dart';
import '../services/reminder_coordinator.dart';
import '../widgets/people_card.dart';

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
  final TextEditingController _keywordController = TextEditingController();
  final TextEditingController _reminderController = TextEditingController();
  final TextEditingController _photoCueController = TextEditingController();
  final CalendarIntegrationService _calendarIntegrationService =
      CalendarIntegrationService();

  bool _isImportingCalendar = false;

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
  List<String> _keywords = [];
  List<String> _reminderCues = [];
  List<String> _photoCues = [];
  List<Contact> _availableContacts = [];
  Map<String, Contact> _contactLookup = {};
  List<String> _availableTags = [];
  String? _selectedMetThroughId;
  bool _isLoadingReferenceData = false;
  List<Relationship> _relationships = [];
  bool _isLoadingRelationships = false;
  List<PrayerRequest> _prayerRequests = [];
  bool _isLoadingPrayers = false;
  PrayerRequestStatus? _selectedPrayerStatus = PrayerRequestStatus.pending;
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
    _prayerRequests = List<PrayerRequest>.from(contact.prayerRequests)
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    _selectedPrayerStatus = _prayerRequests.any(
            (request) => request.status == PrayerRequestStatus.pending)
        ? PrayerRequestStatus.pending
        : null;
    _firstNameController.text = contact.firstName;
    _middleNameController.text = contact.middleName;
    _lastNameController.text = contact.lastName ?? '';
    _nicknameController.text = contact.nickname ?? '';
    _locationController.text = contact.location ?? '';
    _firstMeetingNotesController.text = contact.firstMeetingNotes ?? '';
    _selectedMetThroughId = contact.metThroughId;
    _selectedTags = List<String>.from(contact.tags);
    _keywords = List<String>.from(contact.recognitionKeywords);
    _reminderCues = List<String>.from(contact.recognitionReminders);
    _photoCues = List<String>.from(contact.recognitionPhotoUris);
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
    _refreshPrayerRequests();
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
      _interactionLookup = {
        for (final interaction in _interactions)
          if (interaction.id != null) interaction.id!: interaction,
      };
      _isLoadingInteractions = false;
    });
  }

  Future<void> _importFromCalendar() async {
    final now = DateTime.now();
    final initialRange = DateTimeRange(
      start: now.subtract(const Duration(days: 30)),
      end: now,
    );

    final selectedRange = await showDateRangePicker(
      context: context,
      initialDateRange: initialRange,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 2),
    );

    if (selectedRange == null) {
      return;
    }

    if (!mounted) return;

    setState(() {
      _isImportingCalendar = true;
    });

    try {
      final googleSignIn = GoogleSignIn(
        scopes: const [gcal.CalendarApi.calendarReadonlyScope],
      );
      GoogleSignInAccount? account;
      try {
        account = await googleSignIn.signInSilently();
      } catch (_) {
        account = null;
      }
      account ??= await googleSignIn.signIn();

      if (account == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Google sign-in cancelled.')),
        );
        return;
      }

      final authHeaders = await account.authHeaders;
      final client = _GoogleAuthClient(authHeaders);
      try {
        final calendarApi = gcal.CalendarApi(client);
        final importedInteractions =
            await _calendarIntegrationService.importForContact(
          contact: _buildContactFromState(),
          calendarApi: calendarApi,
          start: selectedRange.start,
          end: selectedRange.end.add(const Duration(days: 1)),
        );

        await _refreshInteractions();

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              importedInteractions.isEmpty
                  ? 'No matching calendar events found.'
                  : 'Imported ${importedInteractions.length} calendar event${importedInteractions.length == 1 ? '' : 's'}.',
            ),
          ),
        );
      } finally {
        client.close();
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Calendar import failed: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isImportingCalendar = false;
        });
      }
    }
  }

  Future<void> _refreshPrayerRequests() async {
    setState(() {
      _isLoadingPrayers = true;
    });

    final requests =
        await DBHelper().getPrayerRequestsForContact(widget.contact.id);

    if (!mounted) return;
    setState(() {
      _prayerRequests = requests
        ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
      if (_selectedPrayerStatus != null &&
          !_prayerRequests.any((request) => request.status == _selectedPrayerStatus)) {
        _selectedPrayerStatus = null;
      }
      _isLoadingPrayers = false;
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

  List<PrayerRequest> get _filteredPrayerRequests {
    final filter = _selectedPrayerStatus;
    final sorted = List<PrayerRequest>.from(_prayerRequests)
      ..sort((a, b) => b.requestedAt.compareTo(a.requestedAt));
    if (filter == null) {
      return sorted;
    }
    return sorted.where((request) => request.status == filter).toList();
  }

  int _countPrayerRequestsFor(PrayerRequestStatus status) {
    return _prayerRequests
        .where((request) => request.status == status)
        .length;
  }

  Color _statusBackgroundColor(
    PrayerRequestStatus status,
    ThemeData theme,
  ) {
    final scheme = theme.colorScheme;
    switch (status) {
      case PrayerRequestStatus.pending:
        return scheme.tertiaryContainer;
      case PrayerRequestStatus.answered:
        return scheme.secondaryContainer;
      case PrayerRequestStatus.archived:
        return scheme.surfaceVariant;
    }
  }

  Color _statusForegroundColor(
    PrayerRequestStatus status,
    ThemeData theme,
  ) {
    final scheme = theme.colorScheme;
    switch (status) {
      case PrayerRequestStatus.pending:
        return scheme.onTertiaryContainer;
      case PrayerRequestStatus.answered:
        return scheme.onSecondaryContainer;
      case PrayerRequestStatus.archived:
        return scheme.onSurfaceVariant;
    }
  }

  IconData _statusIcon(PrayerRequestStatus status) {
    switch (status) {
      case PrayerRequestStatus.pending:
        return Icons.hourglass_top_outlined;
      case PrayerRequestStatus.answered:
        return Icons.volunteer_activism_outlined;
      case PrayerRequestStatus.archived:
        return Icons.inventory_2_outlined;
    }
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

  Future<void> _updatePrayerStatus(
    PrayerRequest request,
    PrayerRequestStatus status,
  ) async {
    final updated = request.copyWith(
      status: status,
      answeredAt: status == PrayerRequestStatus.answered
          ? (request.answeredAt ?? DateTime.now())
          : status == PrayerRequestStatus.pending
              ? null
              : request.answeredAt,
    );

    await DBHelper().updatePrayerRequest(updated);
    await _refreshPrayerRequests();

    if (!mounted) return;

    final message = () {
      switch (status) {
        case PrayerRequestStatus.pending:
          return 'Prayer request reopened.';
        case PrayerRequestStatus.answered:
          return 'Prayer marked as answered. Celebrate!';
        case PrayerRequestStatus.archived:
          return 'Prayer request archived.';
      }
    }();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _showPrayerRequestSheet({PrayerRequest? request}) {
    showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        final descriptionController =
            TextEditingController(text: request?.description ?? '');
        final reflectionController =
            TextEditingController(text: request?.reflectionNotes ?? '');
        final categoryController =
            TextEditingController(text: request?.category ?? '');
        DateTime requestedAt = request?.requestedAt ?? DateTime.now();
        DateTime? answeredAt = request?.answeredAt;
        PrayerRequestStatus status =
            request?.status ?? PrayerRequestStatus.pending;
        int? interactionId = request?.interactionId;

        return StatefulBuilder(
          builder: (context, setSheetState) {
            Future<void> pickRequestedDate() async {
              final selected = await showDatePicker(
                context: context,
                initialDate: requestedAt,
                firstDate: DateTime(2000),
                lastDate: DateTime(2100),
              );
              if (selected == null) return;
              setSheetState(() {
                requestedAt = DateTime(
                  selected.year,
                  selected.month,
                  selected.day,
                );
              });
            }

            Future<void> pickAnsweredDate() async {
              final initial = answeredAt ?? DateTime.now();
              final selected = await showDatePicker(
                context: context,
                initialDate: initial,
                firstDate: requestedAt,
                lastDate: DateTime(2100),
              );
              if (selected == null) return;
              setSheetState(() {
                answeredAt = DateTime(
                  selected.year,
                  selected.month,
                  selected.day,
                );
              });
            }

            void updateStatus(PrayerRequestStatus newStatus) {
              setSheetState(() {
                status = newStatus;
                if (status == PrayerRequestStatus.answered) {
                  answeredAt ??= DateTime.now();
                } else if (status == PrayerRequestStatus.pending) {
                  answeredAt = null;
                }
              });
            }

            Future<void> save() async {
              final description = descriptionController.text.trim();
              if (description.isEmpty) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Write a short prayer description first.'),
                  ),
                );
                return;
              }

              final cleanedCategory = categoryController.text.trim();
              final cleanedReflection = reflectionController.text.trim();

              final payload = PrayerRequest(
                id: request?.id,
                contactId: widget.contact.id,
                interactionId: interactionId,
                description: description,
                status: status,
                requestedAt: requestedAt,
                answeredAt: status == PrayerRequestStatus.answered
                    ? (answeredAt ?? DateTime.now())
                    : null,
                category: cleanedCategory.isEmpty ? null : cleanedCategory,
                reflectionNotes:
                    cleanedReflection.isEmpty ? null : cleanedReflection,
              );

              PrayerRequest savedRequest;
              if (request == null) {
                savedRequest = await DBHelper().insertPrayerRequest(payload);
              } else {
                await DBHelper().updatePrayerRequest(payload);
                savedRequest = payload;
              }

              final contactSnapshot = _buildContactFromState();
              await ReminderCoordinator()
                  .syncPrayerRequestReminder(contactSnapshot, savedRequest);

              if (!mounted) return;
              Navigator.pop(context, request == null ? 'created' : 'updated');
            }

            return Padding(
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 24,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          request == null
                              ? 'New prayer request'
                              : 'Edit prayer request',
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
                      controller: descriptionController,
                      decoration: const InputDecoration(
                        labelText: 'Request',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 2,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 16),
                    SegmentedButton<PrayerRequestStatus>(
                      segments: PrayerRequestStatus.values
                          .map(
                            (option) => ButtonSegment<PrayerRequestStatus>(
                              value: option,
                              label: Text(option.label),
                              icon: Icon(_statusIcon(option)),
                            ),
                          )
                          .toList(),
                      selected: {status},
                      onSelectionChanged: (selection) {
                        if (selection.isEmpty) return;
                        updateStatus(selection.first);
                      },
                    ),
                    const SizedBox(height: 16),
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.calendar_month_outlined),
                      title: const Text('Requested on'),
                      subtitle: Text(_formatDate(requestedAt)),
                      onTap: pickRequestedDate,
                    ),
                    if (status == PrayerRequestStatus.answered) ...[
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.celebration_outlined),
                        title: const Text('Answered on'),
                        subtitle: Text(
                          answeredAt != null
                              ? _formatDate(answeredAt!)
                              : 'Set an answer date',
                        ),
                        trailing: Wrap(
                          spacing: 4,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.today_outlined),
                              tooltip: 'Use today',
                              onPressed: () {
                                setSheetState(() {
                                  answeredAt = DateTime.now();
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: pickAnsweredDate,
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int?>(
                      decoration: const InputDecoration(
                        labelText: 'Linked interaction (optional)',
                        border: OutlineInputBorder(),
                      ),
                      value: interactionId,
                      items: [
                        const DropdownMenuItem<int?>(
                          value: null,
                          child: Text('No linked interaction'),
                        ),
                        ..._interactions
                            .where((interaction) => interaction.id != null)
                            .map(
                              (interaction) => DropdownMenuItem<int?>(
                                value: interaction.id,
                                child: Text(
                                  '${_formatDate(interaction.occurredAt)} • ${interaction.summary}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                      ],
                      onChanged: (value) {
                        setSheetState(() {
                          interactionId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: categoryController,
                      decoration: const InputDecoration(
                        labelText: 'Category (optional)',
                        border: OutlineInputBorder(),
                      ),
                      textCapitalization: TextCapitalization.words,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: reflectionController,
                      decoration: const InputDecoration(
                        labelText: 'Reflection / praise notes',
                        border: OutlineInputBorder(),
                      ),
                      minLines: 2,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: save,
                        icon: const Icon(Icons.check_circle_outline),
                        label: Text(request == null ? 'Save request' : 'Update request'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((result) {
      if (result == null) return;
      _refreshPrayerRequests();
      if (!mounted) return;
      final message = result == 'created'
          ? 'Prayer request added.'
          : 'Prayer request updated.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    });
  }

  void _confirmPrayerDelete(PrayerRequest request) {
    if (request.id == null) {
      return;
    }

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete prayer request'),
          content: const Text(
            'This will remove the prayer from the contact\'s timeline. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(context);
                await _deletePrayerRequest(request);
              },
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _deletePrayerRequest(PrayerRequest request) async {
    if (request.id == null) {
      return;
    }
    await DBHelper().deletePrayerRequest(request.id!);
    await ReminderCoordinator().cancelPrayerRequestReminder(request);
    await _refreshPrayerRequests();

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Prayer request removed.')),
    );
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
      recognitionKeywords: List<String>.from(_keywords),
      recognitionPhotoUris: List<String>.from(_photoCues),
      recognitionReminders: List<String>.from(_reminderCues),
      interactions:
          List<Interaction>.from(interactionsOverride ?? _interactions),
    );
  }

  Future<void> _updateContact() async {
    final updatedContact = _buildContactFromState();
    await DBHelper().updateContact(updatedContact);
    await ReminderCoordinator().refreshContact(updatedContact.id);
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
                await ReminderCoordinator()
                    .cancelAllForContact(widget.contact.id);
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
    await ReminderCoordinator().cancelInteractionReminder(interaction);
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
        final durationController = TextEditingController();
        final categoryController = TextEditingController();
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

              final durationText = durationController.text.trim();
              final durationMinutes = durationText.isEmpty
                  ? null
                  : int.tryParse(durationText);
              if (durationText.isNotEmpty && durationMinutes == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Duration must be a number of minutes.'),
                  ),
                );
                return;
              }
              if (durationMinutes != null && durationMinutes < 0) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Duration cannot be negative.'),
                  ),
                );
                return;
              }

              final categoryText = categoryController.text.trim();
              final category = categoryText.isEmpty ? null : categoryText;

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
                durationMinutes: durationMinutes,
                category: category,
              );

              final savedInteraction =
                  await DBHelper().insertInteraction(interaction);

              final contactSnapshot = _buildContactFromState(
                interactionsOverride: List<Interaction>.from(_interactions)
                  ..add(savedInteraction),
              );
              await ReminderCoordinator()
                  .syncInteractionReminder(contactSnapshot, savedInteraction);

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
                    TextField(
                      controller: durationController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Duration (minutes, optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: categoryController,
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
        _interactionLookup = {
          for (final item in _interactions)
            if (item.id != null) item.id!: item,
        };
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
    final previewContact = _buildContactFromState();
    final displayName = previewContact.fullName;

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
            PeopleCard(
              contact: previewContact,
            ),
            const SizedBox(height: 16),
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
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Prayer requests',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    FilledButton.tonalIcon(
                      onPressed: () => _showPrayerRequestSheet(),
                      icon: const Icon(Icons.self_improvement_outlined),
                      label: const Text('Add prayer'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildPrayerSection(),
              ],
            ),
            const SizedBox(height: 16),
            _buildCard(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Interactions',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                    if (_isImportingCalendar)
                      const Padding(
                        padding: EdgeInsets.only(right: 12),
                        child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    FilledButton.tonalIcon(
                      onPressed:
                          _isImportingCalendar ? null : _importFromCalendar,
                      icon: const Icon(Icons.calendar_month_outlined),
                      label: const Text('Import'),
                    ),
                  ],
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

  Widget _buildPrayerSection() {
    final theme = Theme.of(context);
    final requests = _filteredPrayerRequests;
    final filters = <PrayerRequestStatus?>[null, ...PrayerRequestStatus.values];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: filters.map((status) {
            final isSelected = status == null
                ? _selectedPrayerStatus == null
                : _selectedPrayerStatus == status;
            final count = status == null
                ? _prayerRequests.length
                : _countPrayerRequestsFor(status);
            final label = status == null
                ? 'All ($count)'
                : '${status.label} ($count)';
            return ChoiceChip(
              label: Text(label),
              selected: isSelected,
              onSelected: (selected) {
                setState(() {
                  if (status == null) {
                    _selectedPrayerStatus = null;
                  } else {
                    _selectedPrayerStatus = selected ? status : null;
                  }
                });
              },
            );
          }).toList(),
        ),
        const SizedBox(height: 12),
        if (_isLoadingPrayers)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator()),
          ),
        if (!_isLoadingPrayers && requests.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _prayerRequests.isEmpty
                  ? 'Log a prayer to start tracking how you are supporting this contact.'
                  : 'No prayers match this filter right now.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.outline,
              ),
            ),
          ),
        if (!_isLoadingPrayers && requests.isNotEmpty)
          Column(
            children: requests
                .map((request) => _buildPrayerRequestTile(request))
                .toList(),
          ),
      ],
    );
  }

  Widget _buildPrayerRequestTile(PrayerRequest request) {
    final theme = Theme.of(context);
    final metadataChips = <Widget>[
      Chip(
        avatar: Icon(
          _statusIcon(request.status),
          size: 18,
          color: _statusForegroundColor(request.status, theme),
        ),
        backgroundColor: _statusBackgroundColor(request.status, theme),
        label: Text(
          request.status.label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: _statusForegroundColor(request.status, theme),
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
      Chip(
        avatar: const Icon(Icons.calendar_today_outlined, size: 18),
        label: Text('Requested ${_formatDate(request.requestedAt)}'),
      ),
    ];

    if (request.answeredAt != null) {
      metadataChips.add(
        Chip(
          avatar: const Icon(Icons.celebration_outlined, size: 18),
          label: Text('Answered ${_formatDate(request.answeredAt!)}'),
        ),
      );
    }

    if ((request.category ?? '').isNotEmpty) {
      metadataChips.add(
        Chip(
          avatar: const Icon(Icons.label_outline, size: 18),
          label: Text(request.category!),
        ),
      );
    }

    final linkedSummary = _interactionSummaryFor(request.interactionId);
    if (linkedSummary != null) {
      metadataChips.add(
        InputChip(
          avatar: const Icon(Icons.timeline_outlined, size: 18),
          label: Text(linkedSummary),
          onPressed: () {
            final interaction = _interactionLookup[request.interactionId];
            if (interaction == null) return;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  '${_formatDate(interaction.occurredAt)} • ${interaction.summary}',
                ),
              ),
            );
          },
        ),
      );
    }

    final actionButtons = <Widget>[
      if (request.status != PrayerRequestStatus.answered)
        TextButton.icon(
          onPressed: () =>
              _updatePrayerStatus(request, PrayerRequestStatus.answered),
          icon: const Icon(Icons.check_circle_outline),
          label: const Text('Mark answered'),
        ),
      if (request.status != PrayerRequestStatus.pending)
        TextButton.icon(
          onPressed: () =>
              _updatePrayerStatus(request, PrayerRequestStatus.pending),
          icon: const Icon(Icons.restart_alt_outlined),
          label: const Text('Reopen'),
        ),
      if (request.status != PrayerRequestStatus.archived)
        TextButton.icon(
          onPressed: () =>
              _updatePrayerStatus(request, PrayerRequestStatus.archived),
          icon: const Icon(Icons.archive_outlined),
          label: const Text('Archive'),
        ),
      TextButton.icon(
        onPressed: () => _showPrayerRequestSheet(request: request),
        icon: const Icon(Icons.edit_outlined),
        label: const Text('Edit'),
      ),
    ];

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      color: theme.colorScheme.surfaceVariant.withOpacity(0.35),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    request.description,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (value) {
                    switch (value) {
                      case 'edit':
                        _showPrayerRequestSheet(request: request);
                        break;
                      case 'delete':
                        _confirmPrayerDelete(request);
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    const PopupMenuItem(
                      value: 'edit',
                      child: Text('Edit'),
                    ),
                    const PopupMenuItem(
                      value: 'delete',
                      child: Text('Delete'),
                    ),
                  ],
                  icon: const Icon(Icons.more_vert),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (metadataChips.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: metadataChips,
              ),
            if ((request.reflectionNotes ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                request.reflectionNotes!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: actionButtons,
            ),
          ],
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
              if (interaction.durationMinutes != null)
                Chip(
                  avatar: const Icon(Icons.timer_outlined, size: 18),
                  label: Text('${interaction.durationMinutes} min'),
                ),
              if (interaction.location != null && interaction.location!.isNotEmpty)
                Chip(
                  avatar: const Icon(Icons.place_outlined, size: 18),
                  label: Text(interaction.location!),
                ),
              if (interaction.category != null && interaction.category!.isNotEmpty)
                Chip(
                  avatar: const Icon(Icons.label_outline, size: 18),
                  label: Text(interaction.category!),
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

class _GoogleAuthClient extends http.BaseClient {
  _GoogleAuthClient(this._headers);

  final Map<String, String> _headers;
  final http.Client _client = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    request.headers.addAll(_headers);
    return _client.send(request);
  }

  @override
  void close() {
    _client.close();
    super.close();
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
