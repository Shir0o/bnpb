import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/prayer_request.dart';
import '../services/ai/ai_services.dart';
import '../services/ai/prayer_clustering_service.dart';
import '../widgets/log_prayer_request_sheet.dart';
import 'prayer_request_details_page.dart';

enum _PrayerViewMode { chronological, themed }

/// Pending requests older than this surface a "still asking" badge.
const Duration _stillAskingThreshold = Duration(days: 28);

/// Displays a chronological list of recorded prayers.
class PrayerDiaryPage extends StatefulWidget {
  const PrayerDiaryPage({super.key});

  @override
  State<PrayerDiaryPage> createState() => _PrayerDiaryPageState();
}

class _PrayerDiaryPageState extends State<PrayerDiaryPage> {
  final DBHelper _dbHelper = DBHelper();
  final Map<String, Contact> _contactLookup = {};
  List<Contact> _contacts = [];
  List<PrayerRequest> _requests = [];
  bool _isLoading = false;

  _PrayerViewMode _viewMode = _PrayerViewMode.chronological;
  bool _aiEnabled = false;
  bool _isClustering = false;
  List<PrayerCluster>? _clusters;
  Object? _clusteringError;

  late final DateFormat _dateFormat;

  @override
  void initState() {
    super.initState();
    _dateFormat = DateFormat.yMMMd();
    _loadRequests();
    _refreshAiAvailability();
  }

  Future<void> _refreshAiAvailability() async {
    final enabled = await AiServices().isReady();
    if (!mounted) return;
    setState(() {
      _aiEnabled = enabled;
      if (!enabled && _viewMode == _PrayerViewMode.themed) {
        _viewMode = _PrayerViewMode.chronological;
      }
    });
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
        // Stale clusters get recomputed lazily next time themed view runs;
        // the service's own cache handles dedupe when content is unchanged.
        _clusters = null;
      });
      if (_viewMode == _PrayerViewMode.themed && mounted) {
        unawaited(_ensureClusters());
      }
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prayer diary'),
        actions: [
          if (_aiEnabled && _requests.length >= 2)
            IconButton(
              tooltip: _viewMode == _PrayerViewMode.themed
                  ? 'Switch to chronological view'
                  : 'Group by theme',
              icon: Icon(
                _viewMode == _PrayerViewMode.themed
                    ? Icons.access_time
                    : Icons.auto_awesome_outlined,
              ),
              onPressed: _toggleViewMode,
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _openLogPrayerRequestSheet,
        tooltip: 'Log prayer request',
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(onRefresh: _loadRequests, child: _buildBody()),
    );
  }

  Future<void> _toggleViewMode() async {
    if (_viewMode == _PrayerViewMode.chronological) {
      setState(() {
        _viewMode = _PrayerViewMode.themed;
      });
      await _ensureClusters();
    } else {
      setState(() {
        _viewMode = _PrayerViewMode.chronological;
      });
    }
  }

  Future<void> _ensureClusters() async {
    if (_clusters != null || _isClustering) return;
    setState(() {
      _isClustering = true;
      _clusteringError = null;
    });
    try {
      final clusters = await AiServices().prayerClustering.cluster(_requests);
      if (!mounted) return;
      setState(() {
        _clusters = clusters;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _clusteringError = error;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isClustering = false;
        });
      }
    }
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

    if (_requests.isEmpty) {
      return _buildEmptyState();
    }

    if (_viewMode == _PrayerViewMode.themed) {
      return _buildThemedList();
    }
    return _buildPrayerList();
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
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 12),
      itemCount: _requests.length,
      itemBuilder: (context, index) {
        final request = _requests[index];
        return _buildPrayerTile(request);
      },
      separatorBuilder: (context, index) =>
          const Divider(height: 0, indent: 72, endIndent: 16),
    );
  }

  Widget _buildThemedList() {
    if (_isClustering && _clusters == null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 200),
          Center(child: CircularProgressIndicator()),
          SizedBox(height: 16),
          Center(child: Text('Grouping by theme…')),
        ],
      );
    }

    if (_clusteringError != null) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
        children: [
          const Icon(Icons.error_outline, size: 48),
          const SizedBox(height: 16),
          Text(
            'Could not group prayers by theme. Falling back to chronological view.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      );
    }

    final clusters = _clusters ?? const <PrayerCluster>[];
    if (clusters.isEmpty) {
      return _buildPrayerList();
    }

    final byId = {
      for (final r in _requests)
        if (r.id != null) r.id!: r,
    };
    final items = <Widget>[];
    final claimed = <int>{};
    for (final cluster in clusters) {
      final requests = cluster.requestIds
          .map((id) => byId[id])
          .whereType<PrayerRequest>()
          .toList();
      if (requests.isEmpty) continue;
      claimed.addAll(cluster.requestIds);
      items.add(_buildThemeHeader(cluster.theme, requests.length));
      for (final request in requests) {
        items.add(_buildPrayerTile(request));
      }
    }

    final leftover = _requests
        .where((r) => r.id == null || !claimed.contains(r.id))
        .toList();
    if (leftover.isNotEmpty) {
      items.add(_buildThemeHeader('Other', leftover.length));
      for (final request in leftover) {
        items.add(_buildPrayerTile(request));
      }
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(vertical: 12),
      children: items,
    );
  }

  Widget _buildThemeHeader(String theme, int count) {
    final theme0 = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Row(
        children: [
          Text(
            theme,
            style: theme0.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '($count)',
            style: theme0.textTheme.bodySmall?.copyWith(
              color: theme0.colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrayerTile(PrayerRequest request) {
    final theme = Theme.of(context);
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

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      leading: Icon(
        _iconForStatus(request.status),
        color: _iconColorForStatus(theme, request.status),
      ),
      title: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Text(request.description)),
          if (stillAskingWeeks != null) ...[
            const SizedBox(width: 8),
            _StillAskingBadge(weeks: stillAskingWeeks),
          ],
        ],
      ),
      subtitle: Text(details),
      trailing: PopupMenuButton<PrayerRequestStatus>(
        tooltip: 'Update status',
        onSelected: (status) => _updateRequestStatus(request, status),
        itemBuilder: (context) {
          return PrayerRequestStatus.values.map((status) {
            return CheckedPopupMenuItem<PrayerRequestStatus>(
              value: status,
              checked: status == request.status,
              child: Row(
                children: [
                  Icon(
                    _iconForStatus(status),
                    color: _iconColorForStatus(theme, status),
                  ),
                  const SizedBox(width: 12),
                  Text(status.label),
                ],
              ),
            );
          }).toList();
        },
        child: Chip(label: Text(request.status.label)),
      ),
      onTap: () => _openPrayerRequestDetails(request),
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

  IconData _iconForStatus(PrayerRequestStatus status) {
    switch (status) {
      case PrayerRequestStatus.pending:
        return Icons.hourglass_top_outlined;
      case PrayerRequestStatus.answered:
        return Icons.celebration_outlined;
      case PrayerRequestStatus.archived:
        return Icons.archive_outlined;
    }
  }

  Color? _iconColorForStatus(ThemeData theme, PrayerRequestStatus status) {
    switch (status) {
      case PrayerRequestStatus.pending:
        return theme.colorScheme.primary;
      case PrayerRequestStatus.answered:
        return theme.colorScheme.secondary;
      case PrayerRequestStatus.archived:
        return theme.colorScheme.outline;
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

class _StillAskingBadge extends StatelessWidget {
  const _StillAskingBadge({required this.weeks});

  final int weeks;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Tooltip(
      message: 'Pending for $weeks weeks',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.tertiaryContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          '${weeks}w',
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.onTertiaryContainer,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
