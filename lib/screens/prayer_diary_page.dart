import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../main.dart'; // To access CrispColorScheme extension on ColorScheme
import '../models/contact.dart';
import '../models/prayer_request.dart';
import '../widgets/crisp_toast.dart';
import '../widgets/log_prayer_request_sheet.dart';
import '../widgets/prayer_diary_card.dart';
import 'prayer_request_details_page.dart';

/// Displays every prayer request with its prayer record and quick actions.
class PrayerDiaryPage extends StatefulWidget {
  /// Initial tab: 'All', 'Pending' (or 'Praying'), 'Answered' or 'Archived'.
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
  Map<int, List<DateTime>> _prayedDates = {};
  bool _isLoading = false;

  /// Selected tab; null means All.
  PrayerRequestStatus? _filter;

  static const _tabs = <(String, PrayerRequestStatus?)>[
    ('All', null),
    ('Praying', PrayerRequestStatus.pending),
    ('Answered', PrayerRequestStatus.answered),
    ('Archived', PrayerRequestStatus.archived),
  ];

  @override
  void initState() {
    super.initState();
    _filter = switch (widget.initialFilter) {
      'Pending' || 'Praying' => PrayerRequestStatus.pending,
      'Answered' => PrayerRequestStatus.answered,
      'Archived' => PrayerRequestStatus.archived,
      _ => null,
    };
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
      final prayedDates = await _loadPrayedDates(requests);

      if (!mounted) {
        return;
      }

      final contacts = List<Contact>.from(results[1] as List<Contact>)
        ..sort(
          (a, b) =>
              a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
        );

      setState(() {
        _requests = requests;
        _prayedDates = prayedDates;
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

  /// The prayer record decorates the list, so a failure here leaves the
  /// requests visible with an empty record rather than blanking the page.
  Future<Map<int, List<DateTime>>> _loadPrayedDates(
    List<PrayerRequest> requests,
  ) async {
    try {
      return await _dbHelper.prayerRequestDao.getPrayedDates(
        requests.map((r) => r.id).whereType<int>().toList(),
      );
    } catch (error) {
      debugPrint('Failed to load prayed dates: $error');
      return {};
    }
  }

  Future<void> _openLogPrayerRequestSheet() async {
    if (_contacts.isEmpty) {
      if (!mounted) {
        return;
      }
      CrispToast.show(
        context,
        'Add a contact before logging a prayer request.',
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
    CrispToast.show(context, message);
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

  Future<void> _togglePrayed(PrayerRequest request) async {
    final id = request.id;
    if (id == null) return;
    final now = DateTime.now();
    try {
      final logged = await _dbHelper.prayerRequestDao.togglePrayedToday(
        id,
        now: now,
      );
      if (!mounted) return;
      setState(() {
        final dates = (_prayedDates[id] ?? const <DateTime>[])
            .where(
              (d) =>
                  d.year != now.year ||
                  d.month != now.month ||
                  d.day != now.day,
            )
            .toList();
        if (logged) dates.add(now);
        _prayedDates = {..._prayedDates, id: dates};
      });
    } catch (error) {
      if (!mounted) return;
      CrispToast.show(context, 'Failed to update prayer record: $error');
    }
  }

  Future<void> _setStatus(
    PrayerRequest request,
    PrayerRequestStatus status,
    String? comment,
  ) async {
    final id = request.id;
    if (id == null) return;
    try {
      await _dbHelper.prayerRequestDao.setStatus(id, status, comment: comment);
      if (!mounted) return;
      CrispToast.show(context, _statusChangeMessage(status));
      await _loadRequests();
    } catch (error) {
      if (!mounted) return;
      CrispToast.show(context, 'Failed to update status: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colorScheme.surfaceTint,
      appBar: AppBar(
        centerTitle: false,
        titleSpacing: 0,
        title: const Text('Prayer diary'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton.filled(
              tooltip: 'Log prayer request',
              onPressed: _openLogPrayerRequestSheet,
              style: IconButton.styleFrom(
                backgroundColor: colorScheme.primary,
                foregroundColor: colorScheme.onPrimary,
                fixedSize: const Size(44, 44),
              ),
              icon: const Icon(Icons.add, size: 20),
            ),
          ),
        ],
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
        _buildTabs(),
        Expanded(
          child: _requests.isEmpty ? _buildEmptyState() : _buildPrayerList(),
        ),
      ],
    );
  }

  Widget _buildTabs() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.cardBorder)),
      ),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: colorScheme.hairline,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            for (final (label, status) in _tabs)
              Expanded(child: _buildTab(label, status, colorScheme)),
          ],
        ),
      ),
    );
  }

  Widget _buildTab(
    String label,
    PrayerRequestStatus? status,
    ColorScheme colorScheme,
  ) {
    final selected = _filter == status;
    final count = status == null
        ? _requests.length
        : _requests.where((r) => r.status == status).length;
    final style = TextStyle(
      fontSize: 12,
      fontWeight: FontWeight.w700,
      color: selected ? colorScheme.onSurface : colorScheme.secondaryText,
    );

    return Semantics(
      selected: selected,
      button: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _filter = status),
        child: Container(
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected ? colorScheme.surface : null,
            borderRadius: BorderRadius.circular(9),
            border: selected ? Border.all(color: colorScheme.cardBorder) : null,
          ),
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: style),
                const SizedBox(width: 4),
                Text('$count', style: style),
              ],
            ),
          ),
        ),
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
    final filtered = _filter == null
        ? _requests
        : _requests.where((r) => r.status == _filter).toList();

    if (filtered.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
            child: Text(
              'Nothing here yet.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: Theme.of(context).colorScheme.secondaryText,
              ),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final request = filtered[index];
        return PrayerDiaryCard(
          key: ValueKey(request.id ?? request.syncId),
          request: request,
          names: _namesFor(request),
          initials: _initialsFor(request),
          prayedDates: _prayedDates[request.id] ?? const [],
          onOpen: () => _openPrayerRequestDetails(request),
          onTogglePrayed: () => _togglePrayed(request),
          onSetStatus: (status, comment) =>
              _setStatus(request, status, comment),
        );
      },
    );
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
        return 'Prayer request reopened.';
      case PrayerRequestStatus.answered:
        return 'Prayer request marked as answered.';
      case PrayerRequestStatus.archived:
        return 'Prayer request archived.';
    }
  }

  String _namesFor(PrayerRequest request) {
    final names = request.participantIds
        .map(_displayNameForContact)
        .whereType<String>()
        .join(', ');
    return names.isEmpty ? 'Unknown contact' : names;
  }

  String _initialsFor(PrayerRequest request) {
    for (final id in request.participantIds) {
      final contact = _contactLookup[id];
      if (contact != null) return contact.initials;
    }
    return '?';
  }

  String? _displayNameForContact(String contactId) {
    final contact = _contactLookup[contactId];
    if (contact == null) {
      return null;
    }

    if (contact.fullName.isNotEmpty) {
      return contact.fullName;
    }

    final nickname = contact.nickname ?? '';
    return nickname.isNotEmpty ? nickname : null;
  }
}
