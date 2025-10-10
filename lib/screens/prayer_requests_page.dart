import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/prayer_request.dart';
import 'contact_details_page.dart';

/// Displays a full list of prayer requests with filtering and refresh support.
class PrayerRequestsPage extends StatefulWidget {
  const PrayerRequestsPage({super.key, this.initialStatus});

  /// Optional status to preselect when opening the page.
  final PrayerRequestStatus? initialStatus;

  @override
  State<PrayerRequestsPage> createState() => _PrayerRequestsPageState();
}

class _PrayerRequestsPageState extends State<PrayerRequestsPage> {
  final DBHelper _dbHelper = DBHelper();
  final Map<String, Contact> _contactLookup = {};
  final Map<PrayerRequestStatus, int> _prayerCounts = {
    for (final status in PrayerRequestStatus.values) status: 0,
  };

  bool _isLoading = false;
  PrayerRequestStatus? _selectedStatus;
  List<PrayerRequest> _requests = [];

  @override
  void initState() {
    super.initState();
    _selectedStatus = widget.initialStatus;
    _refreshRequests();
  }

  Future<void> _refreshRequests() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        _dbHelper.getPrayerRequestCounts(),
        _dbHelper.getPrayerRequests(
          status: _selectedStatus,
          latestAnsweredFirst: _selectedStatus == PrayerRequestStatus.answered,
        ),
        _dbHelper.getContacts(),
      ]);

      if (!mounted) return;

      final counts = results[0] as Map<PrayerRequestStatus, int>;
      final requests = results[1] as List<PrayerRequest>;
      final contacts = results[2] as List<Contact>;

      _contactLookup
        ..clear()
        ..addEntries(contacts.map((contact) => MapEntry(contact.id, contact)));

      setState(() {
        _prayerCounts
          ..clear()
          ..addAll({
            for (final status in PrayerRequestStatus.values)
              status: counts[status] ?? 0,
          });
        _requests = requests;
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _onStatusSelected(PrayerRequestStatus? status) {
    setState(() {
      if (status == null) {
        _selectedStatus = null;
      } else if (_selectedStatus == status) {
        _selectedStatus = null;
      } else {
        _selectedStatus = status;
      }
    });
    _refreshRequests();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prayer requests'),
      ),
      body: RefreshIndicator(
        onRefresh: _refreshRequests,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            _buildFilterSection(),
            if (_isLoading && _requests.isEmpty)
              SizedBox(
                height: MediaQuery.of(context).size.height * 0.4,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              )
            else if (_requests.isEmpty)
              _buildEmptyState()
            else
              ..._requests.map(_buildRequestTile),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildFilterSection() {
    final theme = Theme.of(context);
    final totalCount =
        _prayerCounts.values.fold<int>(0, (sum, count) => sum + count);

    final chips = <Widget>[
      FilterChip(
        label: Text('All ($totalCount)'),
        selected: _selectedStatus == null,
        onSelected: (_) => _onStatusSelected(null),
      ),
      ...PrayerRequestStatus.values.map(
        (status) => FilterChip(
          label: Text('${status.label} (${_prayerCounts[status] ?? 0})'),
          selected: _selectedStatus == status,
          onSelected: (_) => _onStatusSelected(status),
        ),
      ),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Filter by status', style: theme.textTheme.titleSmall),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: chips,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    final message = _selectedStatus == null
        ? 'No prayer requests recorded yet.'
        : 'No ${_selectedStatus!.label.toLowerCase()} prayer requests found.';

    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(
            Icons.self_improvement_outlined,
            size: 48,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRequestTile(PrayerRequest request) {
    switch (request.status) {
      case PrayerRequestStatus.pending:
        return _buildPendingTile(request);
      case PrayerRequestStatus.answered:
        return _buildAnsweredTile(request);
      case PrayerRequestStatus.archived:
        return _buildArchivedTile(request);
    }
  }

  Widget _buildPendingTile(PrayerRequest request) {
    final contactName = _displayNameForContact(request.contactId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: const Icon(Icons.hourglass_top_outlined),
        title: Text(request.description),
        subtitle: Text(
          '${_formatDate(request.requestedAt)} • $contactName',
        ),
        onTap: () => _openContactDetails(request.contactId),
      ),
    );
  }

  Widget _buildAnsweredTile(PrayerRequest request) {
    final theme = Theme.of(context);
    final contactName = _displayNameForContact(request.contactId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: ListTile(
          dense: true,
          leading: Icon(
            Icons.celebration_outlined,
            color: theme.colorScheme.onSecondaryContainer,
          ),
          title: Text(
            request.description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
          subtitle: Text(
            '${_formatDate(request.answeredAt ?? request.requestedAt)} • $contactName',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ),
          onTap: () => _openContactDetails(request.contactId),
        ),
      ),
    );
  }

  Widget _buildArchivedTile(PrayerRequest request) {
    final theme = Theme.of(context);
    final contactName = _displayNameForContact(request.contactId);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        leading: Icon(
          Icons.archive_outlined,
          color: theme.colorScheme.outline,
        ),
        title: Text(request.description),
        subtitle: Text(
          '${_formatDate(request.requestedAt)} • $contactName',
        ),
        onTap: () => _openContactDetails(request.contactId),
      ),
    );
  }

  void _openContactDetails(String contactId) {
    final contact = _contactLookup[contactId];
    if (contact == null) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ContactDetailsPage(contact: contact),
      ),
    );
  }

  String _displayNameForContact(String contactId) {
    final contact = _contactLookup[contactId];
    if (contact == null) {
      return 'Unknown contact';
    }

    if (contact.fullName.isNotEmpty) {
      return contact.fullName;
    }

    final nickname = contact.nickname ?? '';
    return nickname.isNotEmpty ? nickname : 'Unknown contact';
  }

  String _formatDate(DateTime date) {
    return DateFormat.yMMMd().format(date);
  }
}
