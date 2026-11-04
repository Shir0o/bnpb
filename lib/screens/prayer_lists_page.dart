import 'dart:async';

import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../main.dart'; // CrispColorScheme extension on ColorScheme
import '../models/contact.dart';
import '../models/prayer_request.dart';
import '../services/backup_service.dart';
import '../services/contact_service.dart';
import '../services/reminder_coordinator.dart';
import '../widgets/add_people_to_prayer_list_sheet.dart';
import '../widgets/crisp_toast.dart';
import '../widgets/skeleton_loader.dart';
import 'contact_details_page.dart';

/// The single, merged prayer list: every contact on any underlying list.
class PrayerListPage extends StatefulWidget {
  final DBHelper? dbHelper;
  final void Function(BuildContext context, Contact contact)?
      onNavigateToContactDetails;
  const PrayerListPage({
    super.key,
    this.dbHelper,
    this.onNavigateToContactDetails,
  });

  @override
  State<PrayerListPage> createState() => _PrayerListPageState();
}

class _PrayerListPageState extends State<PrayerListPage> {
  late final DBHelper _dbHelper;
  List<Contact> _contacts = [];
  final Map<String, String> _latestOpen = {};
  final Map<String, int> _openCount = {};
  String _query = '';
  bool _isLoading = true;
  late ScaffoldMessengerState _scaffoldMessenger;

  @override
  void initState() {
    super.initState();
    _dbHelper = widget.dbHelper ?? DBHelper();
    _load();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.of(context);
  }

  @override
  void dispose() {
    _scaffoldMessenger.clearSnackBars();
    super.dispose();
  }

  Future<void> _load() async {
    final ids = await _dbHelper.prayerListDao.getAllPrayerListContactIds();
    var contacts = <Contact>[];
    final latest = <String, String>{};
    final counts = <String, int>{};
    if (ids.isNotEmpty) {
      contacts = await _dbHelper.getContacts(contactIds: ids);
      contacts.sort(
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );
      // Newest first, so the first request seen per contact is the latest.
      final pending = await _dbHelper.getPrayerRequests(
        status: PrayerRequestStatus.pending,
      );
      final idSet = ids.toSet();
      for (final r in pending) {
        for (final id in r.participantIds) {
          if (!idSet.contains(id)) continue;
          latest.putIfAbsent(id, () => r.description);
          counts[id] = (counts[id] ?? 0) + 1;
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _latestOpen
        ..clear()
        ..addAll(latest);
      _openCount
        ..clear()
        ..addAll(counts);
      _isLoading = false;
    });
  }

  Future<void> _addContacts() async {
    final selectedIds = await AddPeopleToPrayerListSheet.show(
      context,
      onListIds: _contacts.map((c) => c.id).toSet(),
      dbHelper: _dbHelper,
    );
    if (selectedIds == null || selectedIds.isEmpty) return;
    await _dbHelper.prayerListDao.addContactsToDefaultList(selectedIds);
    await _load();
    unawaited(BackupService().exportBackup());
  }

  Future<void> _removeContact(Contact contact) async {
    setState(() => _contacts.removeWhere((c) => c.id == contact.id));
    await _dbHelper.prayerListDao.removeContactFromAllLists(contact.id);
    await _load();
    unawaited(BackupService().exportBackup());
    if (!mounted) return;
    _scaffoldMessenger.clearSnackBars();
    _scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text('Removed ${contact.fullName} from list'),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            _scaffoldMessenger.hideCurrentSnackBar();
            await _dbHelper.prayerListDao.addContactsToDefaultList([
              contact.id,
            ]);
            await _load();
            unawaited(BackupService().exportBackup());
          },
        ),
      ),
    );
  }

  Future<void> _deleteContact(String contactId) async {
    try {
      await _dbHelper.deleteContact(contactId);
      await ReminderCoordinator().cancelAllForContact(contactId);
      if (mounted) {
        CrispToast.show(context, 'Contact deleted successfully.');
      }
      ContactService().invalidateContacts();
      await _load();
    } catch (e) {
      if (mounted) {
        CrispToast.show(context, 'Failed to delete contact: $e');
      }
    }
  }

  void _navigateToContactDetails(Contact contact) {
    _scaffoldMessenger.clearSnackBars();
    if (widget.onNavigateToContactDetails != null) {
      widget.onNavigateToContactDetails!(context, contact);
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (context) => ContactDetailsPage(
              contact: contact,
              onDelete: () => _deleteContact(contact.id),
            ),
          ),
        )
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final n = _contacts.length;
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: scheme.cardBorder)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Transform.translate(
                        offset: const Offset(-12, 0),
                        child: IconButton(
                          tooltip: 'Back',
                          constraints: const BoxConstraints.tightFor(
                            width: 44,
                            height: 44,
                          ),
                          icon: const Icon(Icons.chevron_left, size: 26),
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Prayer list',
                              style: TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.48,
                              ),
                            ),
                            Text(
                              n == 1 ? '1 person' : '$n people',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: scheme.secondaryText,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Material(
                        color: scheme.primary,
                        shape: const CircleBorder(),
                        child: IconButton(
                          tooltip: 'Add people',
                          constraints: const BoxConstraints.tightFor(
                            width: 44,
                            height: 44,
                          ),
                          color: scheme.onPrimary,
                          icon: const Icon(Icons.add, size: 22),
                          onPressed: _addContacts,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    decoration: BoxDecoration(
                      color: scheme.hairline,
                      borderRadius: BorderRadius.circular(13),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.search,
                          size: 17,
                          color: scheme.secondaryText,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextField(
                            onChanged: (v) => setState(() => _query = v),
                            style: const TextStyle(fontSize: 14),
                            decoration: InputDecoration(
                              hintText: 'Search people',
                              hintStyle: TextStyle(
                                color: scheme.secondaryText,
                              ),
                              border: InputBorder.none,
                              enabledBorder: InputBorder.none,
                              focusedBorder: InputBorder.none,
                              filled: false,
                              isDense: true,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: _buildBody(scheme),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_isLoading) {
      return const _PrayerListSkeleton(key: ValueKey('loading'));
    }

    final q = _query.trim().toLowerCase();
    final visible = q.isEmpty
        ? _contacts
        : _contacts.where((c) => c.fullName.toLowerCase().contains(q)).toList();

    if (visible.isEmpty) {
      return Center(
        key: const ValueKey('empty'),
        child: Text(
          _contacts.isEmpty
              ? 'No one on your prayer list yet.\nTap + to add people.'
              : 'No people match.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13.5, color: scheme.secondaryText),
        ),
      );
    }

    return ListView.builder(
      key: const ValueKey('list'),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: visible.length,
      itemBuilder: (context, index) {
        final contact = visible[index];
        final open = _openCount[contact.id] ?? 0;
        return Dismissible(
          key: ValueKey(contact.id),
          direction: DismissDirection.endToStart,
          background: Container(
            color: scheme.error,
            alignment: AlignmentDirectional.centerEnd,
            padding: const EdgeInsetsDirectional.only(end: 20),
            child: Icon(Icons.delete_outline, color: scheme.onError),
          ),
          onDismissed: (_) => _removeContact(contact),
          child: InkWell(
            onTap: () => _navigateToContactDetails(contact),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 13),
              decoration: BoxDecoration(
                color: scheme.surface,
                border: Border(bottom: BorderSide(color: scheme.hairline)),
              ),
              child: Row(
                children: [
                  CircleInitials(initials: contact.initials),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.fullName,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          _latestOpen[contact.id] ?? 'No requests yet',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.45,
                            color: scheme.secondaryText,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Text(
                    open == 0 ? '\u2014' : '$open open',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: scheme.secondaryText,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: scheme.placeholder,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PrayerListSkeleton extends StatelessWidget {
  const _PrayerListSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: ListView.builder(
        itemCount: 8,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) => ListTile(
          leading: const SkeletonBox(
            width: 40,
            height: 40,
            shape: BoxShape.circle,
          ),
          title: SkeletonBox(width: 140 + (index % 3 * 20.0), height: 16),
          subtitle: const SkeletonBox(width: 100, height: 12),
          trailing: const SkeletonBox(width: 24, height: 24),
        ),
      ),
    );
  }
}
