import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/prayer_request.dart';
import '../widgets/contact_avatar.dart';
import '../widgets/crisp_toast.dart';
import '../widgets/log_prayer_request_sheet.dart';
import '../widgets/hide_on_scroll_scaffold.dart';

/// Displays details for a single [PrayerRequest] and supports editing it.
class PrayerRequestDetailsPage extends StatefulWidget {
  const PrayerRequestDetailsPage({
    super.key,
    required this.request,
    this.initialContacts = const [],
  });

  /// The prayer request being displayed.
  final PrayerRequest request;

  /// Contacts associated with the request.
  final List<Contact> initialContacts;

  @override
  State<PrayerRequestDetailsPage> createState() =>
      _PrayerRequestDetailsPageState();
}

class _PrayerRequestDetailsPageState extends State<PrayerRequestDetailsPage> {
  final DBHelper _dbHelper = DBHelper();

  late PrayerRequest _request;
  List<Contact> _contacts = [];
  List<Contact> _availableContacts = [];
  bool _isLoadingContacts = false;
  bool _didUpdate = false;

  late final DateFormat _dateFormat;

  @override
  void initState() {
    super.initState();
    _dateFormat = DateFormat.yMMMd();
    _request = widget.request;
    _contacts = List.from(widget.initialContacts);
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
      final contactLookup = {for (final c in contacts) c.id: c};
      _contacts = _request.participantIds
          .map((id) => contactLookup[id])
          .whereType<Contact>()
          .toList();
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
      useSafeArea: true,
      builder: (context) {
        return LogPrayerRequestSheet(
          initialRequest: _request,
          availableContacts: List<Contact>.from(_availableContacts),
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

    setState(() {
      _request = savedRequest!;
      final contactLookup = {for (final c in _availableContacts) c.id: c};
      _contacts = _request.participantIds
          .map((id) => contactLookup[id])
          .whereType<Contact>()
          .toList();
      _didUpdate = true;
    });

    if (result != null) {
      final message = result == 'updated'
          ? 'Prayer request updated.'
          : 'Prayer request saved.';
      CrispToast.show(context, message);
    }
  }

  String _formatDate(DateTime date) {
    return _dateFormat.format(date);
  }

  List<Widget> _buildParticipantBadges() {
    if (_contacts.isEmpty) {
      return const [];
    }

    final theme = Theme.of(context);
    return _contacts.map((contact) {
      final name = contact.fullName.isNotEmpty
          ? contact.fullName
          : (contact.nickname?.isNotEmpty == true
              ? contact.nickname!
              : 'Unnamed');

      return Chip(
        avatar: ContactAvatar(contact: contact, radius: 12),
        label: Text(name),
        labelStyle: theme.textTheme.labelMedium,
        visualDensity: VisualDensity.compact,
        side: BorderSide(color: theme.colorScheme.outlineVariant),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      );
    }).toList();
  }

  Widget _buildCard({required List<Widget> children, Color? color}) {
    final theme = Theme.of(context);
    return Card(
      elevation: 0,
      color: color ?? theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: color == null
            ? BorderSide(color: theme.colorScheme.outlineVariant, width: 0.5)
            : BorderSide.none,
      ),
      child: Column(children: children),
    );
  }

  Widget _buildDetailTile({
    required IconData icon,
    required String title,
    String? value,
  }) {
    if (value == null || value.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(
        title,
        style: theme.textTheme.labelMedium?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      subtitle: Text(
        value,
        style: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurface,
        ),
      ),
      dense: true,
    );
  }

  void _handleBack() {
    Navigator.of(context).pop(_didUpdate);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final participantBadges = _buildParticipantBadges();

    return HideOnScrollScaffold(
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
      body: RefreshIndicator(
        onRefresh: _loadContacts,
        child: ListView(
          padding: const EdgeInsets.all(16),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            // Header Section
            Text(
              _request.description,
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(
                  Icons.calendar_today_outlined,
                  size: 16,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
                Text(
                  _formatDate(_request.requestedAt),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Participants Section
            if (participantBadges.isNotEmpty) ...[
              Text(
                'Participants',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: participantBadges),
              const SizedBox(height: 24),
            ],

            // Details Card
            Text(
              'Details',
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            _buildCard(
              children: [
                _buildDetailTile(
                  icon: _request.status == PrayerRequestStatus.answered
                      ? Icons.volunteer_activism_outlined
                      : Icons.hourglass_top_outlined,
                  title: 'Status',
                  value: _request.status.label,
                ),
                if (_request.answeredAt != null)
                  _buildDetailTile(
                    icon: Icons.celebration_outlined,
                    title: 'Answered on',
                    value: _formatDate(_request.answeredAt!),
                  ),
                _buildDetailTile(
                  icon: Icons.label_outline,
                  title: 'Category',
                  value: _request.category,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Reflection Notes Section
            if (_request.reflectionNotes != null &&
                _request.reflectionNotes!.trim().isNotEmpty) ...[
              Text(
                'Reflection notes',
                style: theme.textTheme.titleSmall?.copyWith(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              _buildCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Text(
                      _request.reflectionNotes!,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),
            ],

            // Answered styling
            if (_request.status == PrayerRequestStatus.answered)
              _buildCard(
                color: theme.colorScheme.secondaryContainer,
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.celebration_outlined,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                    title: Text(
                      'Praise report - Answered!',
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
