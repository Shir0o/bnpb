import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/prayer_request.dart';
import '../services/reminder_coordinator.dart';

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
  String? _selectedContactId;
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
    final presetContactId = widget.initialContact?.id ??
        widget.initialRequest?.contactId ??
        (widget.availableContacts.length == 1
            ? widget.availableContacts.first.id
            : null);
    if (presetContactId != null &&
        widget.availableContacts.any((contact) => contact.id == presetContactId)) {
      _selectedContactId = presetContactId;
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

    if (_selectedContactId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select who this prayer request is for.')),
      );
      return;
    }

    final selectedContact = widget.availableContacts.firstWhere(
      (contact) => contact.id == _selectedContactId,
      orElse: () => throw StateError('Selected contact missing'),
    );

    setState(() {
      _isSaving = true;
    });

    final cleanedCategory = _categoryController.text.trim();
    final cleanedReflection = _reflectionController.text.trim();

    final payload = PrayerRequest(
      id: widget.initialRequest?.id,
      contactId: selectedContact.id,
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

      await ReminderCoordinator()
          .syncPrayerRequestReminder(selectedContact, savedRequest);

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
    final mediaQuery = MediaQuery.of(context);
    final contactLocked = widget.initialContact != null;
    final canSave =
        !(_selectedContactId == null && !contactLocked) && !_isSaving;

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 24,
        bottom: mediaQuery.viewInsets.bottom + 24,
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  widget.initialRequest == null
                      ? 'Log a prayer request'
                      : 'Update prayer request',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(
                labelText: 'Contact',
                border: OutlineInputBorder(),
              ),
              value: _selectedContactId,
              onChanged: contactLocked
                  ? null
                  : (value) {
                      setState(() {
                        _selectedContactId = value;
                      });
                    },
              items: widget.availableContacts
                  .map(
                    (contact) => DropdownMenuItem<String>(
                      value: contact.id,
                      child: Text(contact.fullName.isNotEmpty
                          ? contact.fullName
                          : (contact.nickname ?? contact.firstName)),
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _descriptionController,
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
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: canSave ? _save : null,
                icon: _isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.check_circle_outline),
                label: Text(
                  widget.initialRequest == null
                      ? 'Save request'
                      : 'Update request',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
