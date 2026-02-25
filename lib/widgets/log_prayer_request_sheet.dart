import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/prayer_request.dart';
import '../services/reminder_coordinator.dart';
import 'contact_selection_sheet.dart';

/// Shared bottom sheet for creating or editing a [PrayerRequest].
class LogPrayerRequestSheet extends StatefulWidget {
  const LogPrayerRequestSheet({
    super.key,
    this.initialRequest,
    required this.availableContacts,
    this.initialContact,
    required this.onSaved,
  });

  /// Existing request to edit, if any.
  final PrayerRequest? initialRequest;

  /// Contacts the user can associate with the request.
  final List<Contact> availableContacts;

  /// Contact to preselect when launching the sheet.
  final Contact? initialContact;

  /// Callback triggered after the request is persisted.
  final ValueChanged<PrayerRequest> onSaved;

  @override
  State<LogPrayerRequestSheet> createState() => _LogPrayerRequestSheetState();
}

class _LogPrayerRequestSheetState extends State<LogPrayerRequestSheet> {
  late final TextEditingController _descriptionController;
  late final TextEditingController _reflectionController;
  late final TextEditingController _categoryController;
  late DateTime _requestedAt;
  DateTime? _answeredAt;
  late PrayerRequestStatus _status;
  final Set<String> _selectedParticipantIds = {};
  late final Map<String, Contact> _contactLookup;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _descriptionController =
        TextEditingController(text: widget.initialRequest?.description ?? '');
    _reflectionController = TextEditingController(
      text: widget.initialRequest?.reflectionNotes ?? '',
    );
    _categoryController = TextEditingController(
      text: widget.initialRequest?.category ?? '',
    );
    _requestedAt = widget.initialRequest?.requestedAt ?? DateTime.now();
    _answeredAt = widget.initialRequest?.answeredAt;
    _status = widget.initialRequest?.status ?? PrayerRequestStatus.pending;

    _contactLookup = {
      for (final contact in widget.availableContacts) contact.id: contact
    };

    if (widget.initialRequest != null) {
      _selectedParticipantIds.addAll(widget.initialRequest!.participantIds);
    } else if (widget.initialContact != null) {
      _selectedParticipantIds.add(widget.initialContact!.id);
    } else if (widget.availableContacts.length == 1) {
      _selectedParticipantIds.add(widget.availableContacts.first.id);
    }
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _reflectionController.dispose();
    _categoryController.dispose();
    super.dispose();
  }

  Future<void> _pickRequestedDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _requestedAt,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() {
      _requestedAt = DateTime(selected.year, selected.month, selected.day);
    });
  }

  Future<void> _pickAnsweredDate() async {
    final initial = _answeredAt ?? DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: _requestedAt,
      lastDate: DateTime(2100),
    );
    if (selected == null) return;
    setState(() {
      _answeredAt = DateTime(selected.year, selected.month, selected.day);
    });
  }

  void _updateStatus(PrayerRequestStatus nextStatus) {
    setState(() {
      _status = nextStatus;
      if (_status == PrayerRequestStatus.answered) {
        _answeredAt ??= DateTime.now();
      } else if (_status == PrayerRequestStatus.pending) {
        _answeredAt = null;
      }
    });
  }

  Future<void> _showContactSelection() async {
    final result = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ContactSelectionSheet(
        title: 'Select Contacts',
        initialSelectedIds: _selectedParticipantIds,
        disabledIds: widget.initialContact != null ? {widget.initialContact!.id} : {},
      ),
    );

    if (result != null && mounted) {
      setState(() {
        _selectedParticipantIds.clear();
        if (widget.initialContact != null) {
          _selectedParticipantIds.add(widget.initialContact!.id);
        }
        _selectedParticipantIds.addAll(result);
      });
    }
  }

  Future<void> _save() async {
    if (_isSaving) {
      return;
    }
    final description = _descriptionController.text.trim();
    if (description.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Write a short prayer description first.'),
        ),
      );
      return;
    }

    if (_selectedParticipantIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select at least one contact for this prayer request.')),
      );
      return;
    }

    setState(() {
      _isSaving = true;
    });

    final cleanedCategory = _categoryController.text.trim();
    final cleanedReflection = _reflectionController.text.trim();

    final payload = PrayerRequest(
      id: widget.initialRequest?.id,
      participantIds: _selectedParticipantIds.toList(),
      description: description,
      status: _status,
      requestedAt: _requestedAt,
      answeredAt: _status == PrayerRequestStatus.answered
          ? (_answeredAt ?? DateTime.now())
          : null,
      category: cleanedCategory.isEmpty ? null : cleanedCategory,
      reflectionNotes: cleanedReflection.isEmpty ? null : cleanedReflection,
    );

    try {
      PrayerRequest savedRequest;
      if (widget.initialRequest == null) {
        savedRequest = await DBHelper().insertPrayerRequest(payload);
      } else {
        await DBHelper().updatePrayerRequest(payload);
        savedRequest = payload;
      }

      // Sync reminders for all participants
      for (final contactId in _selectedParticipantIds) {
        final contact = _contactLookup[contactId];
        if (contact != null) {
          await ReminderCoordinator()
              .syncPrayerRequestReminder(contact, savedRequest);
        }
      }

      widget.onSaved(savedRequest);

      if (!mounted) return;
      Navigator.of(context)
          .pop(widget.initialRequest == null ? 'created' : 'updated');
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save prayer request: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat.yMMMd().format(date);
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isEditing = widget.initialRequest != null;

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.transparent,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
          ),
          centerTitle: true,
          title: Text(
            isEditing ? 'Update prayer request' : 'Log a prayer request',
            style: theme.textTheme.titleMedium,
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 8.0),
              child: TextButton(
                onPressed: _selectedParticipantIds.isNotEmpty && !_isSaving
                    ? _save
                    : null,
                child: _isSaving
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
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Associated Contacts',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ..._selectedParticipantIds.map((id) {
                    final contact = _contactLookup[id];
                    final name = contact?.fullName ?? id;
                    final isInitial = widget.initialContact?.id == id;

                    return Chip(
                      label: Text(name),
                      onDeleted: isInitial
                          ? null
                          : () {
                              setState(() {
                                _selectedParticipantIds.remove(id);
                              });
                            },
                      deleteIconColor: theme.colorScheme.error,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      side: BorderSide(
                        color: theme.colorScheme.outlineVariant,
                      ),
                    );
                  }),
                  ActionChip(
                    avatar: const Icon(Icons.add, size: 18),
                    label: const Text('Add Contact'),
                    onPressed: _showContactSelection,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    side: BorderSide(
                      color: theme.colorScheme.primary,
                      style: BorderStyle.solid,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
              TextField(
                controller: _descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Request',
                  border: OutlineInputBorder(),
                  alignLabelWithHint: true,
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
                selected: {_status},
                onSelectionChanged: (selection) {
                  if (selection.isEmpty) return;
                  _updateStatus(selection.first);
                },
              ),
              const SizedBox(height: 16),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.calendar_month_outlined),
                title: const Text('Requested on'),
                subtitle: Text(_formatDate(_requestedAt)),
                onTap: _pickRequestedDate,
              ),
              if (_status == PrayerRequestStatus.answered) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.celebration_outlined),
                  title: const Text('Answered on'),
                  subtitle: Text(
                    _answeredAt != null
                        ? _formatDate(_answeredAt!)
                        : 'Set an answer date',
                  ),
                  trailing: Wrap(
                    spacing: 4,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.today_outlined),
                        tooltip: 'Use today',
                        onPressed: () {
                          setState(() {
                            _answeredAt = DateTime.now();
                          });
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: _pickAnsweredDate,
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _categoryController,
                decoration: const InputDecoration(
                  labelText: 'Category (optional)',
                  border: OutlineInputBorder(),
                ),
                textCapitalization: TextCapitalization.words,
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _reflectionController,
                decoration: const InputDecoration(
                  labelText: 'Notes',
                  border: OutlineInputBorder(),
                ),
                minLines: 2,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}
