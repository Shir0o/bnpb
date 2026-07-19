import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/interaction.dart';
import '../services/backup_service.dart';
import '../services/ai/ai_services.dart';
import 'ai/follow_up_suggestion_sheet.dart';
import 'ai/tag_suggestion_sheet.dart';
import 'contact_selection_sheet.dart';
import 'contact_avatar.dart';
import 'crisp_switch.dart';
import 'crisp_toast.dart';

const Map<String, IconData> mediumIcons = {
  'in_person': Icons.people_outline,
  'call': Icons.phone_outlined,
  'message': Icons.chat_bubble_outline,
  'online': Icons.videocam_outlined,
  'other': Icons.more_horiz,
};

/// Form for logging a new interaction or editing an existing one. Shared
/// between mobile (shown via [showModalBottomSheet]) and macOS (shown via
/// `showMacModal`) — the content is platform-agnostic; only the presentation
/// container differs per call site.
class LogInteractionSheet extends StatefulWidget {
  const LogInteractionSheet({
    super.key,
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
  State<LogInteractionSheet> createState() => _LogInteractionSheetState();
}

class _LogInteractionSheetState extends State<LogInteractionSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _summaryController;
  late final TextEditingController _locationController;
  late final TextEditingController _durationController;
  late final TextEditingController _notesController;
  late final TextEditingController _occurredTimeController;

  DateTime _occurredAt = DateTime.now();
  DateTime? _followUpAt;
  String _medium = 'in_person';
  bool _markForPrayer = false;

  AutovalidateMode _autovalidateMode = AutovalidateMode.disabled;
  bool _isSaveEnabled = false;
  bool _formWasSubmitted = false;
  bool _isSavingInteraction = false;
  bool _occurredAtManuallyChanged = false;
  bool _aiAvailable = false;
  bool _isSuggestingTags = false;
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
      for (final contact in _availableContacts) contact.id: contact,
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
      useSafeArea: true,
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
        _selectedParticipantIds = {widget.contact.id, ...result};
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
    final name = contact.fullName.isNotEmpty
        ? contact.fullName
        : (contact.nickname?.isNotEmpty == true
            ? contact.nickname!
            : contact.id);

    return FilterChip(
      avatar: ContactAvatar(contact: contact, radius: 12),
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
      _buildParticipantChip(primaryContact, isSelected: true, isEnabled: false),
    );

    // Add selected contacts
    for (final id in _selectedParticipantIds) {
      if (id == widget.contact.id) continue;
      final contact = _contactLookup[id];
      if (contact != null) {
        chips.add(
          _buildParticipantChip(contact, isSelected: true, isEnabled: true),
        );
      } else {
        // Fallback for unknown IDs
        chips.add(
          Chip(label: Text(id), onDeleted: () => _toggleParticipant(id)),
        );
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Participants', style: Theme.of(context).textTheme.titleSmall),
        const SizedBox(height: 8),
        Wrap(spacing: 8, runSpacing: 8, children: chips),
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
    _summaryController = TextEditingController(
      text: initial != null ? initial.summary : '',
    );
    _locationController = TextEditingController(text: initial?.location ?? '');
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
    _summaryController.addListener(_updateSaveEnabled);
    _durationController.addListener(_updateSaveEnabled);
    _durationController.addListener(_updateOccurredAtFromDuration);
    _isSaveEnabled = _calculateSaveEnabled();
    _checkAiAvailability();
  }

  Future<void> _checkAiAvailability() async {
    final ready = await AiServices().isReady();
    if (!mounted) return;
    if (ready != _aiAvailable) {
      setState(() => _aiAvailable = ready);
    }
  }

  // Tokens like "#new_job" already present in the notes field, so we don't
  // re-suggest them.
  Set<String> _existingTagsInNotes() {
    final matches = RegExp(
      r'#([a-z0-9_]+)',
    ).allMatches(_notesController.text.toLowerCase());
    return {for (final m in matches) m.group(1)!};
  }

  Future<void> _suggestTags() async {
    if (_isSuggestingTags) return;
    final source = [
      _summaryController.text.trim(),
      _notesController.text.trim(),
    ].where((s) => s.isNotEmpty).join('\n');
    if (source.isEmpty) {
      CrispToast.show(context, 'Add a summary or note first.');
      return;
    }
    setState(() => _isSuggestingTags = true);
    try {
      final accepted = await TagSuggestionSheet.maybeShow(
        context,
        noteText: source,
        existingTags: _existingTagsInNotes(),
      );
      if (!mounted) return;
      if (accepted != null && accepted.isNotEmpty) {
        final tokens = accepted.map((t) => '#$t').join(' ');
        final current = _notesController.text;
        final separator = current.isEmpty
            ? ''
            : current.endsWith('\n')
                ? ''
                : '\n';
        _notesController.text = '$current$separator$tokens';
        _updateSaveEnabled();
      }
    } catch (error) {
      if (!mounted) return;
      CrispToast.show(context, 'Could not suggest tags: $error');
    } finally {
      if (mounted) setState(() => _isSuggestingTags = false);
    }
  }

  @override
  void dispose() {
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

  String? _applyManualOccurredTime(String value, {bool shouldUpdate = true}) {
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
    final previousInteractions = List<Interaction>.from(
      widget.existingInteractions,
    );
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

      final committedInteractions = List<Interaction>.from(
        optimisticInteractions,
      );
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

      CrispToast.show(
        context,
        isEditing ? 'Interaction updated' : 'Interaction logged',
      );

      if (!isEditing && mounted) {
        await FollowUpSuggestionSheet.maybeShow(
          context,
          contact: widget.contact,
          interaction: savedInteraction,
          onInteractionUpdated: (updated) {
            final list = List<Interaction>.from(committedInteractions);
            final idx = list.indexWhere((i) => i.id == updated.id);
            if (idx >= 0) {
              list[idx] = updated;
              list.sort((a, b) => b.occurredAt.compareTo(a.occurredAt));
              widget.onInteractionsUpdated?.call(list);
            }
          },
        );
      }

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

      CrispToast.show(context, 'Failed to save interaction: $error');
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
      onPopInvokedWithResult: (didPop, result) async {},
      child: SafeArea(
        child: Scaffold(
          backgroundColor: Colors.transparent,
          appBar: AppBar(
            backgroundColor: Colors.transparent,
            elevation: 0,
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () async {
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
                    decoration: const InputDecoration(
                      labelText: 'Summary *',
                      border: OutlineInputBorder(),
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
                      DropdownMenuItem(value: 'call', child: Text('Call')),
                      DropdownMenuItem(
                        value: 'message',
                        child: Text('Message'),
                      ),
                      DropdownMenuItem(
                        value: 'online',
                        child: Text('Online Meeting'),
                      ),
                      DropdownMenuItem(value: 'other', child: Text('Other')),
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
                  if (_aiAvailable)
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton.icon(
                        onPressed: _isSuggestingTags ? null : _suggestTags,
                        icon: const Icon(Icons.auto_awesome_outlined, size: 18),
                        label: const Text('Suggest tags'),
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
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Mark for prayer'),
                    trailing: CrispSwitch(
                      value: _markForPrayer,
                      onChanged: (value) {
                        setState(() {
                          _markForPrayer = value;
                        });
                      },
                    ),
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
        Text('Recent:', style: Theme.of(context).textTheme.labelSmall),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: recentDistinct.map((interaction) {
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: ActionChip(
                  label: Text(
                    interaction.summary,
                    overflow: TextOverflow.ellipsis,
                  ),
                  avatar: Icon(
                    mediumIcons[interaction.medium] ?? Icons.chat,
                    size: 16,
                  ),
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
      _selectedParticipantIds = {widget.contact.id, ...base.participantIds};

      // Update validation state
      _isSaveEnabled = _calculateSaveEnabled();
    });
  }
}
