import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/prayer_request.dart';
import '../widgets/log_prayer_request_sheet.dart';
import 'prayer_request_details_page.dart';
import '../widgets/hide_on_scroll_scaffold.dart';

/// Pending requests older than this surface a "still asking" badge.
const Duration _stillAskingThreshold = Duration(days: 28);

/// Displays a chronological list of recorded prayers.
class PrayerDiaryPage extends StatefulWidget {
  final String initialFilter;
  const PrayerDiaryPage({super.key, this.initialFilter = 'All'});

  @override
  State<PrayerDiaryPage> createState() => _PrayerDiaryPageState();
}

class _PrayerDiaryPageState extends State<PrayerDiaryPage> {
  final DBHelper _dbHelper = DBHelper();
  final Map<String, Contact> _contactLookup = {};
  List<Contact> _contacts = [];
  List<PrayerRequest> _requests = [];
  bool _isLoading = false;
  late String _selectedFilter;

  late final DateFormat _dateFormat;

  @override
  void initState() {
    super.initState();
    _selectedFilter = widget.initialFilter;
    _dateFormat = DateFormat.yMMMd();
    _loadRequests();
  }

  Future<void> _loadRequests() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        _dbHelper.getPrayerRequests(),
        _dbHelper.getContacts(),
      ]);

      if (!mounted) {
        return;
      }

      final requests = results[0] as List<PrayerRequest>;
      _sortRequests(requests);

      final contacts = List<Contact>.from(results[1] as List<Contact>)
        ..sort(
          (a, b) =>
              a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
        );

      setState(() {
        _requests = requests;
        _contacts = contacts;
        _contactLookup
          ..clear()
          ..addEntries(
            contacts.map((contact) => MapEntry(contact.id, contact)),
          );
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openLogPrayerRequestSheet() async {
    if (_contacts.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a contact before logging a prayer request.'),
        ),
      );
      return;
    }

    bool didSave = false;
    final result = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) {
        return LogPrayerRequestSheet(
          availableContacts: List<Contact>.from(_contacts),
          onSaved: (_) {
            didSave = true;
          },
        );
      },
    );

    if (!mounted || !didSave) {
      return;
    }

    await _loadRequests();

    if (!mounted) {
      return;
    }

    final message = result == 'updated'
        ? 'Prayer request updated.'
        : 'Prayer request added.';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _openPrayerRequestDetails(PrayerRequest request) async {
    final participants = request.participantIds
        .map((id) => _contactLookup[id])
        .whereType<Contact>()
        .toList();

    final didUpdate = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => PrayerRequestDetailsPage(
          request: request,
          initialContacts: participants,
        ),
      ),
    );

    if (!mounted) return;

    if (didUpdate == true) {
      await _loadRequests();
    }
  }

  @override
  Widget build(BuildContext context) {
    return HideOnScrollScaffold(
      appBar: AppBar(title: const Text('Prayer diary')),
      floatingActionButton: FloatingActionButton(
        onPressed: _openLogPrayerRequestSheet,
        tooltip: 'Log prayer request',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(onRefresh: _loadRequests, child: _buildBody()),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _requests.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 200),
          Center(child: CircularProgressIndicator()),
        ],
      );
    }

    return Column(
      children: [
        _buildFilterChips(),
        Expanded(
          child: _requests.isEmpty ? _buildEmptyState() : _buildPrayerList(),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    final filters = ['All', 'Pending', 'Answered', 'Archived'];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      child: Row(
        children: filters.map((f) {
          final isSelected = _selectedFilter == f;
          return Padding(
            padding: const EdgeInsets.only(right: 8),
            child: InkWell(
              onTap: () {
                setState(() {
                  _selectedFilter = f;
                });
              },
              borderRadius: BorderRadius.circular(20),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0xFF0F1512) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isSelected
                        ? const Color(0xFF0F1512)
                        : const Color(0xFFE6EBE7),
                    width: 1,
                  ),
                ),
                child: Text(
                  f,
                  style: TextStyle(
                    color: isSelected ? Colors.white : const Color(0xFF57635C),
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 80),
      children: [
        Icon(
          Icons.self_improvement_outlined,
          size: 56,
          color: theme.colorScheme.outline,
        ),
        const SizedBox(height: 16),
        Text(
          'Keep a record of your prayers and celebrate how they are answered.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
      ],
    );
  }

  Widget _buildPrayerList() {
    final filtered = _requests.where((r) {
      if (_selectedFilter == 'All') return true;
      if (_selectedFilter == 'Pending') {
        return r.status == PrayerRequestStatus.pending;
      }
      if (_selectedFilter == 'Answered') {
        return r.status == PrayerRequestStatus.answered;
      }
      if (_selectedFilter == 'Archived') {
        return r.status == PrayerRequestStatus.archived;
      }
      return true;
    }).toList();

    if (filtered.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Text(
            'No $_selectedFilter prayers found.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final request = filtered[index];
        return _buildPrayerCard(request);
      },
    );
  }

  Widget _buildPrayerCard(PrayerRequest request) {
    final contactNames = request.participantIds
        .map((id) => _displayNameForContact(id))
        .where((name) => name != 'Unknown contact')
        .join(', ');

    final displayNames =
        contactNames.isEmpty ? 'Unknown contact' : contactNames;

    final details = [
      _formatDate(request.answeredAt ?? request.requestedAt),
      displayNames,
    ].where((value) => value.isNotEmpty).join(' • ');

    final stillAskingWeeks = _stillAskingWeeks(request);

    Color statusBg;
    Color statusFg;
    IconData statusIcon;

    switch (request.status) {
      case PrayerRequestStatus.pending:
        statusBg = const Color(0xFFFBEEE9);
        statusFg = const Color(0xFFC25A3F);
        statusIcon = Icons.hourglass_top_outlined;
        break;
      case PrayerRequestStatus.answered:
        statusBg = const Color(0xFFEAF6EF);
        statusFg = const Color(0xFF0D7A4F);
        statusIcon = Icons.celebration_outlined;
        break;
      case PrayerRequestStatus.archived:
        statusBg = const Color(0xFFF1F5F2);
        statusFg = const Color(0xFF8A988F);
        statusIcon = Icons.archive_outlined;
        break;
    }

    final badgeLabel = request.status == PrayerRequestStatus.pending
        ? (stillAskingWeeks != null
            ? '${stillAskingWeeks}w · Pending'
            : 'Pending')
        : request.status.label;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFE6EBE7),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => _openPrayerRequestDetails(request),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: statusBg,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  statusIcon,
                  color: statusFg,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      request.description,
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 16,
                        color: Color(0xFF0F1512),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      details,
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF8A988F),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () {
                  PrayerRequestStatus nextStatus;
                  switch (request.status) {
                    case PrayerRequestStatus.pending:
                      nextStatus = PrayerRequestStatus.answered;
                      break;
                    case PrayerRequestStatus.answered:
                      nextStatus = PrayerRequestStatus.archived;
                      break;
                    case PrayerRequestStatus.archived:
                      nextStatus = PrayerRequestStatus.pending;
                      break;
                  }
                  _updateRequestStatus(request, nextStatus);
                },
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badgeLabel,
                    style: TextStyle(
                      color: statusFg,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _updateRequestStatus(
    PrayerRequest request,
    PrayerRequestStatus status,
  ) async {
    if (request.status == status) {
      return;
    }

    DateTime? answeredAt;
    switch (status) {
      case PrayerRequestStatus.pending:
        answeredAt = null;
        break;
      case PrayerRequestStatus.answered:
        answeredAt = request.answeredAt ?? DateTime.now();
        break;
      case PrayerRequestStatus.archived:
        answeredAt = request.answeredAt;
        break;
    }

    final updated = request.copyWith(status: status, answeredAt: answeredAt);

    final previousRequests = List<PrayerRequest>.from(_requests);
    setState(() {
      _requests = _requests
          .map((entry) => entry.id == request.id ? updated : entry)
          .toList();
      _sortRequests(_requests);
    });

    try {
      await _dbHelper.updatePrayerRequest(updated);
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(_statusChangeMessage(status))));
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _requests = previousRequests;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update status: $error')),
      );
    }
  }

  void _sortRequests(List<PrayerRequest> requests) {
    requests.sort((a, b) {
      // Group 1: Pending (comes first)
      // Group 2: Answered and Archived (comes after)
      final aIsPending = a.status == PrayerRequestStatus.pending;
      final bIsPending = b.status == PrayerRequestStatus.pending;

      if (aIsPending && !bIsPending) return -1;
      if (!aIsPending && bIsPending) return 1;

      // Within groups, sort by date descending
      final aDate = a.answeredAt ?? a.requestedAt;
      final bDate = b.answeredAt ?? b.requestedAt;
      return bDate.compareTo(aDate);
    });
  }

  String _statusChangeMessage(PrayerRequestStatus status) {
    switch (status) {
      case PrayerRequestStatus.pending:
        return 'Prayer request marked as pending.';
      case PrayerRequestStatus.answered:
        return 'Prayer request marked as answered.';
      case PrayerRequestStatus.archived:
        return 'Prayer request archived.';
    }
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
    return _dateFormat.format(date);
  }

  int? _stillAskingWeeks(PrayerRequest request) {
    if (request.status != PrayerRequestStatus.pending) return null;
    final age = DateTime.now().difference(request.requestedAt);
    if (age < _stillAskingThreshold) return null;
    return age.inDays ~/ 7;
  }
}
