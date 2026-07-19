import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../db/db_helper.dart';
import '../../main.dart' show CrispColorScheme;
import '../../models/contact.dart';
import '../../models/prayer_list.dart';
import '../../models/prayer_request.dart';
import '../../services/sync_service.dart';
import '../../widgets/contact_avatar.dart';
import '../../widgets/contact_selection_sheet.dart';
import '../../widgets/crisp_toast.dart';
import '../../widgets/log_prayer_request_sheet.dart';
import '../../widgets/macos_modal.dart';
import 'macos_contact_details_page.dart';
import 'prayer_diary_entry.dart';

/// Desktop "Prayer" section: the prayer diary (left column) and "My prayer
/// list" (right column) shown side by side in one pane, matching the Crisp
/// Utility desktop design. The right column absorbs the old dedicated
/// "Prayer List" landing view that macOS used to have.
class MacOSPrayerDiaryView extends StatefulWidget {
  const MacOSPrayerDiaryView({super.key});

  @override
  State<MacOSPrayerDiaryView> createState() => _MacOSPrayerDiaryViewState();
}

class _MacOSPrayerDiaryViewState extends State<MacOSPrayerDiaryView> {
  static final _monthDayYearFormat = DateFormat('MMMM d, y');

  final DBHelper _dbHelper = DBHelper();
  final Map<String, Contact> _contactLookup = {};
  List<Contact> _contacts = [];
  List<PrayerRequest> _requests = [];
  PrayerList? _prayerList;
  List<Contact> _prayerListContacts = [];
  bool _isLoading = false;
  String? _editingRequestId;
  String _searchQuery = '';
  StreamSubscription<void>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _loadData();
    _syncSubscription = SyncService().onSyncComplete.listen((_) {
      if (mounted) _loadData();
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);

    try {
      final results = await Future.wait([
        _dbHelper.getPrayerRequests(),
        _dbHelper.getContacts(),
        _dbHelper.getPrayerLists(),
      ]);

      if (!mounted) return;

      final requests = results[0] as List<PrayerRequest>;
      final contacts = List<Contact>.from(results[1] as List<Contact>)
        ..sort(
          (a, b) =>
              a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
        );
      final lists = results[2] as List<PrayerList>;

      _sortRequests(requests);

      PrayerList? prayerList;
      List<Contact> prayerListContacts = const [];
      if (lists.isNotEmpty) {
        prayerList = await _dbHelper.getPrayerList(lists.first.id);
        if (prayerList != null) {
          prayerListContacts = contacts
              .where((c) => prayerList!.contactIds.contains(c.id))
              .toList();
        }
      }

      if (!mounted) return;
      setState(() {
        _requests = requests;
        _contacts = contacts;
        _prayerList = prayerList;
        _prayerListContacts = prayerListContacts;
        _contactLookup
          ..clear()
          ..addEntries(contacts.map((c) => MapEntry(c.id, c)));
      });
    } catch (e) {
      debugPrint('Error loading prayer diary data: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _sortRequests(List<PrayerRequest> requests) {
    requests.sort((a, b) {
      final aIsPending = a.status == PrayerRequestStatus.pending;
      final bIsPending = b.status == PrayerRequestStatus.pending;
      if (aIsPending && !bIsPending) return -1;
      if (!aIsPending && bIsPending) return 1;
      final aDate = a.answeredAt ?? a.requestedAt;
      final bDate = b.answeredAt ?? b.requestedAt;
      return bDate.compareTo(aDate);
    });
  }

  Future<void> _openLogPrayerRequestSheet() async {
    if (_contacts.isEmpty) {
      CrispToast.show(
        context,
        'Add a contact before logging a prayer request.',
      );
      return;
    }

    bool didSave = false;
    await showMacModal<String>(
      context,
      builder: (_) => LogPrayerRequestSheet(
        availableContacts: List<Contact>.from(_contacts),
        onSaved: (_) => didSave = true,
      ),
    );

    if (mounted && didSave) {
      await _loadData();
    }
  }

  Future<void> _openContactPicker() async {
    final list = _prayerList;
    if (list == null) return;
    final currentIds = list.contactIds.toSet();
    final selectedIds = await showMacModal<List<String>>(
      context,
      builder: (_) => ContactSelectionSheet(
        disabledIds: currentIds,
        title: 'Add to ${list.name}',
      ),
    );
    if (selectedIds != null && selectedIds.isNotEmpty) {
      for (final id in selectedIds) {
        await _dbHelper.addContactToPrayerList(list.id, id);
      }
      await _loadData();
    }
  }

  Future<void> _openContact(Contact contact) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MacOSContactDetailsPage(contact: contact),
      ),
    );
    _loadData();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      color: colorScheme.surface,
      child: Row(
        children: [
          Expanded(child: _buildDiaryColumn(colorScheme)),
          Container(width: 1, color: colorScheme.cardBorder),
          _buildMyPrayerListColumn(colorScheme),
        ],
      ),
    );
  }

  Widget _buildDiaryColumn(ColorScheme colorScheme) {
    return Column(
      children: [
        _buildHeader(colorScheme),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildContent(colorScheme),
        ),
      ],
    );
  }

  Widget _buildHeader(ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(26, 22, 26, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Prayer diary',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 26,
                    color: colorScheme.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(11),
                  onTap: _openLogPrayerRequestSheet,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 15, vertical: 9),
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add, size: 16, color: colorScheme.onPrimary),
                        const SizedBox(width: 7),
                        Text(
                          'Log request',
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
            decoration: BoxDecoration(
              color: colorScheme.surfaceTint,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                Icon(Icons.search, size: 17, color: colorScheme.outline),
                const SizedBox(width: 9),
                Expanded(
                  child: TextField(
                    onChanged: (v) =>
                        setState(() => _searchQuery = v.toLowerCase()),
                    decoration: InputDecoration.collapsed(
                      hintText: 'Search prayer requests…',
                      hintStyle: TextStyle(color: colorScheme.placeholder),
                    ),
                    style:
                        TextStyle(fontSize: 14, color: colorScheme.onSurface),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent(ColorScheme colorScheme) {
    final filteredRequests = _requests.where((req) {
      if (_searchQuery.isEmpty) return true;
      final matchDescription =
          req.description.toLowerCase().contains(_searchQuery);
      final matchContacts = req.participantIds.any(
        (id) => _displayNameForContact(id).toLowerCase().contains(_searchQuery),
      );
      return matchDescription || matchContacts;
    }).toList();

    if (filteredRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.menu_book_outlined, size: 44, color: colorScheme.faint),
            const SizedBox(height: 14),
            Text(
              'No prayer entries found',
              style: TextStyle(fontSize: 14, color: colorScheme.outline),
            ),
          ],
        ),
      );
    }

    final grouped = <String, List<PrayerRequest>>{};
    for (final req in filteredRequests) {
      final date = req.answeredAt ?? req.requestedAt;
      grouped.putIfAbsent(_getDateGroupKey(date), () => []).add(req);
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(26, 0, 26, 24),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final key = grouped.keys.elementAt(index);
        final requests = grouped[key]!;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateHeader(
              colorScheme,
              key,
              requests.first.answeredAt ?? requests.first.requestedAt,
            ),
            ...requests.map((req) => _buildEntry(req)),
          ],
        );
      },
    );
  }

  String _getDateGroupKey(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final checkDate = DateTime(date.year, date.month, date.day);
    if (checkDate == today) return 'Today';
    if (checkDate == yesterday) return 'Yesterday';
    return 'Older';
  }

  Widget _buildDateHeader(
      ColorScheme colorScheme, String title, DateTime date) {
    final dateStr = title == 'Older' ? '' : _monthDayYearFormat.format(date);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 11),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.4,
              color: colorScheme.secondaryText,
            ),
          ),
          if (dateStr.isNotEmpty)
            Text(
              dateStr,
              style: TextStyle(fontSize: 11.5, color: colorScheme.outline),
            ),
        ],
      ),
    );
  }

  Widget _buildEntry(PrayerRequest request) {
    final participants = request.participantIds
        .map((id) => _contactLookup[id])
        .whereType<Contact>()
        .toList();

    return PrayerDiaryEntry(
      request: request,
      contacts: participants,
      isEditing: _editingRequestId == request.syncId,
      onEditStart: () => setState(() => _editingRequestId = request.syncId),
      onEditSave: _onEntryEditSave,
      onEditCancel: () => setState(() => _editingRequestId = null),
    );
  }

  Future<void> _onEntryEditSave(PrayerRequest updatedRequest) async {
    try {
      if (updatedRequest.id != null) {
        await _dbHelper.updatePrayerRequest(updatedRequest);
      } else {
        await _dbHelper.insertPrayerRequest(updatedRequest);
      }
      if (!mounted) return;
      setState(() {
        _editingRequestId = null;
        final index =
            _requests.indexWhere((r) => r.syncId == updatedRequest.syncId);
        if (index != -1) {
          _requests[index] = updatedRequest;
          _sortRequests(_requests);
        }
      });
    } catch (e) {
      debugPrint('Error updating prayer request: $e');
      if (mounted) CrispToast.show(context, 'Failed to update request: $e');
    }
  }

  String _displayNameForContact(String contactId) {
    final contact = _contactLookup[contactId];
    if (contact == null) return 'Unknown';
    if (contact.fullName.isNotEmpty) return contact.fullName;
    final nickname = contact.nickname ?? '';
    return nickname.isNotEmpty ? nickname : 'Unknown';
  }

  Widget _buildMyPrayerListColumn(ColorScheme colorScheme) {
    return SizedBox(
      width: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 22, 22, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'My prayer list',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 19,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_prayerListContacts.length} people you\'re covering',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(9),
                    onTap: _openContactPicker,
                    child:
                        Icon(Icons.add, size: 20, color: colorScheme.primary),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: _prayerListContacts.isEmpty
                ? Center(
                    child: Text(
                      'No one on your list yet.',
                      style:
                          TextStyle(fontSize: 13, color: colorScheme.outline),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                    children: _prayerListContacts
                        .map((c) => _buildPrayerListRow(colorScheme, c))
                        .toList(),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildPrayerListRow(ColorScheme colorScheme, Contact contact) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _openContact(contact),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              ContactAvatar(contact: contact, radius: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      contact.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    if ((contact.location ?? '').isNotEmpty)
                      Text(
                        contact.location!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12.5, color: colorScheme.outline),
                      ),
                  ],
                ),
              ),
              Icon(Icons.check, size: 16, color: colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }
}
