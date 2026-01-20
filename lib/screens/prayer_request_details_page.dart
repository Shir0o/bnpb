import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/prayer_request.dart';
import '../widgets/log_prayer_request_sheet.dart';

/// Displays details for a single [PrayerRequest] and supports editing it.
class PrayerRequestDetailsPage extends StatefulWidget {
  const PrayerRequestDetailsPage({
    super.key,
    required this.request,
    required this.contact,
  });

  /// The prayer request being displayed.
  final PrayerRequest request;

  /// Contact associated with the request.
  final Contact contact;

  @override
  State<PrayerRequestDetailsPage> createState() =>
      _PrayerRequestDetailsPageState();
}

class _PrayerRequestDetailsPageState extends State<PrayerRequestDetailsPage> {
  final DBHelper _dbHelper = DBHelper();

  late PrayerRequest _request;
  late Contact _contact;
  List<Contact> _availableContacts = [];
  bool _isLoadingContacts = false;
  bool _didUpdate = false;

  @override
  void initState() {
    super.initState();
    _request = widget.request;
    _contact = widget.contact;
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    setState(() {
      _isLoadingContacts = true;
    });

    final contacts = await _dbHelper.getContacts();

    if (!mounted) {
      return;
    }

    contacts.sort(
      (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
    );

    setState(() {
      _availableContacts = contacts;
      final matching = contacts.firstWhere(
        (candidate) => candidate.id == _request.contactId,
        orElse: () => _contact,
      );
      _contact = matching;
      _isLoadingContacts = false;
    });
  }

  Future<void> _openEditSheet() async {
    if (_availableContacts.isEmpty && !_isLoadingContacts) {
      await _loadContacts();
      if (!mounted) {
        return;
      }
    }

    bool didSave = false;
    PrayerRequest? savedRequest;

    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return LogPrayerRequestSheet(
          initialRequest: _request,
          availableContacts: List<Contact>.from(_availableContacts),
          initialContact: _contact,
          onSaved: (updated) {
            didSave = true;
            savedRequest = updated;
          },
        );
      },
    );

    if (!mounted || !didSave || savedRequest == null) {
      return;
    }

    Contact? resolvedContact;
    for (final contact in _availableContacts) {
      if (contact.id == savedRequest!.contactId) {
        resolvedContact = contact;
        break;
      }
    }
    resolvedContact ??= await _dbHelper.getContactById(savedRequest!.contactId);

    if (!mounted) {
      return;
    }

    setState(() {
      _request = savedRequest!;
      if (resolvedContact != null) {
        final nonNullableContact = resolvedContact;
        final existingIndex =
            _availableContacts.indexWhere((c) => c.id == nonNullableContact.id);
        if (existingIndex >= 0) {
          _availableContacts[existingIndex] = nonNullableContact;
        } else {
          _availableContacts = List<Contact>.from(_availableContacts)
            ..add(nonNullableContact)
            ..sort(
              (a, b) =>
                  a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
            );
        }
        _contact = nonNullableContact;
      }
      _didUpdate = true;
    });

    if (result != null) {
      final message = result == 'updated'
          ? 'Prayer request updated.'
          : 'Prayer request saved.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }

  String _formatDate(DateTime date) {
    return DateFormat.yMMMd().format(date);
  }

  String get _contactDisplayName {
    if (_contact.fullName.isNotEmpty) {
      return _contact.fullName;
    }
    final nickname = _contact.nickname ?? '';
    return nickname.isNotEmpty ? nickname : 'Unknown contact';
  }

  void _handleBack() {
    Navigator.of(context).pop(_didUpdate);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prayer request details'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _handleBack,
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit prayer request',
            onPressed: _openEditSheet,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _request.description,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  _buildDetailRow(
                    icon: Icons.person_outline,
                    label: 'Contact',
                    value: _contactDisplayName,
                  ),
                  _buildDetailRow(
                    icon: Icons.flag_outlined,
                    label: 'Status',
                    value: _request.status.label,
                  ),
                  _buildDetailRow(
                    icon: Icons.calendar_month_outlined,
                    label: 'Requested on',
                    value: _formatDate(_request.requestedAt),
                  ),
                  if (_request.answeredAt != null)
                    _buildDetailRow(
                      icon: Icons.celebration_outlined,
                      label: 'Answered on',
                      value: _formatDate(_request.answeredAt!),
                    ),
                  if (_request.category != null &&
                      _request.category!.trim().isNotEmpty)
                    _buildDetailRow(
                      icon: Icons.label_outline,
                      label: 'Category',
                      value: _request.category!,
                    ),
                  if (_request.reflectionNotes != null &&
                      _request.reflectionNotes!.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: const [
                              Icon(Icons.notes_outlined),
                              SizedBox(width: 8),
                              Text('Reflection notes'),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            _request.reflectionNotes!,
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: Theme.of(context)
                      .textTheme
                      .labelMedium
                      ?.copyWith(color: Theme.of(context).colorScheme.outline),
                ),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
