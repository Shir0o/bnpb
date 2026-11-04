import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../main.dart'; // To access CrispColorScheme extension on ColorScheme
import '../models/contact.dart';
import '../models/prayer_request.dart';
import '../widgets/contact_avatar.dart';
import '../widgets/quick_create_contact_dialog.dart';

/// Name shown for [contact] in prayer people pickers.
String prayerPersonName(Contact contact) {
  if (contact.fullName.trim().isNotEmpty) return contact.fullName;
  if (contact.nickname?.trim().isNotEmpty == true) return contact.nickname!;
  return 'Unnamed';
}

/// Per-contact prayer context shown under names when choosing people:
/// prayer list membership and open/answered request counts.
class PrayerPeopleStats {
  const PrayerPeopleStats({
    this.onPrayerList = const {},
    this.openCounts = const {},
    this.answeredCounts = const {},
  });

  final Set<String> onPrayerList;
  final Map<String, int> openCounts;
  final Map<String, int> answeredCounts;

  static Future<PrayerPeopleStats> load() async {
    final db = DBHelper();
    final lists = await db.getPrayerLists();
    final requests = await db.getPrayerRequests();
    final open = <String, int>{};
    final answered = <String, int>{};
    for (final request in requests) {
      final counts = switch (request.status) {
        PrayerRequestStatus.pending => open,
        PrayerRequestStatus.answered => answered,
        PrayerRequestStatus.archived => null,
      };
      if (counts == null) continue;
      for (final id in request.participantIds) {
        counts[id] = (counts[id] ?? 0) + 1;
      }
    }
    return PrayerPeopleStats(
      onPrayerList: {for (final list in lists) ...list.contactIds},
      openCounts: open,
      answeredCounts: answered,
    );
  }

  /// Whether [contactId] is someone the user is actively praying for.
  bool isActive(String contactId) =>
      onPrayerList.contains(contactId) || (openCounts[contactId] ?? 0) > 0;

  /// e.g. "On prayer list · 2 open", "1 answered" or "No requests".
  String subtitleFor(String contactId) {
    final open = openCounts[contactId] ?? 0;
    final parts = [
      if (onPrayerList.contains(contactId)) 'On prayer list',
      if (open > 0) '$open open',
    ];
    if (parts.isNotEmpty) return parts.join(' · ');
    final answered = answeredCounts[contactId] ?? 0;
    return answered > 0 ? '$answered answered' : 'No requests';
  }
}

/// Full-screen "Who is this for?" picker for prayer requests.
///
/// Pops with the selected contacts in selection order when the user taps
/// Done, or `null` when they go back without confirming.
class SelectPrayerPeoplePage extends StatefulWidget {
  const SelectPrayerPeoplePage({
    super.key,
    this.initialSelectedIds = const [],
    this.lockedIds = const {},
  });

  /// Contacts already chosen, in the order they were chosen.
  final List<String> initialSelectedIds;

  /// Selected contacts the user cannot remove here.
  final Set<String> lockedIds;

  static Future<List<Contact>?> open(
    BuildContext context, {
    List<String> initialSelectedIds = const [],
    Set<String> lockedIds = const {},
  }) {
    return Navigator.of(context).push<List<Contact>>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => SelectPrayerPeoplePage(
          initialSelectedIds: initialSelectedIds,
          lockedIds: lockedIds,
        ),
      ),
    );
  }

  @override
  State<SelectPrayerPeoplePage> createState() => _SelectPrayerPeoplePageState();
}

class _SelectPrayerPeoplePageState extends State<SelectPrayerPeoplePage> {
  final TextEditingController _searchController = TextEditingController();
  late final List<String> _selectedIds = [...widget.initialSelectedIds];
  List<Contact> _contacts = [];
  Map<String, Contact> _lookup = {};
  PrayerPeopleStats _stats = const PrayerPeopleStats();
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() => setState(() {}));
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final contacts = await DBHelper().getContacts();
    final stats = await PrayerPeopleStats.load();
    if (!mounted) return;
    contacts.sort(
      (a, b) => prayerPersonName(a)
          .toLowerCase()
          .compareTo(prayerPersonName(b).toLowerCase()),
    );
    setState(() {
      _contacts = contacts;
      _lookup = {for (final c in contacts) c.id: c};
      _stats = stats;
      _isLoading = false;
    });
  }

  void _toggle(String id) {
    if (widget.lockedIds.contains(id)) return;
    setState(() {
      if (!_selectedIds.remove(id)) _selectedIds.add(id);
    });
  }

  Future<void> _createContact() async {
    final created = await QuickCreateContactDialog.show(
      context,
      initialQuery: _searchController.text.trim(),
    );
    if (created == null || !mounted) return;
    _searchController.clear();
    await _load();
    if (!mounted) return;
    setState(() {
      if (!_selectedIds.contains(created.id)) _selectedIds.add(created.id);
    });
  }

  void _done() {
    Navigator.of(context).pop([
      for (final id in _selectedIds)
        if (_lookup[id] != null) _lookup[id]!,
    ]);
  }

  List<Contact> get _visibleContacts {
    final query = _searchController.text.trim().toLowerCase();
    if (query.isEmpty) return _contacts;
    return _contacts.where((c) {
      return prayerPersonName(c).toLowerCase().contains(query) ||
          (c.nickname?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final selected = [
      for (final id in _selectedIds)
        if (_lookup[id] != null) _lookup[id]!,
    ];
    final visible = _visibleContacts;

    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.hairline)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      IconButton(
                        icon: const Icon(Icons.arrow_back),
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      Expanded(
                        child: Text(
                          'Who is this for?',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.3,
                          ),
                        ),
                      ),
                      FilledButton(
                        onPressed: _isLoading ? null : _done,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 38),
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (selected.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              for (final contact in selected)
                                _SelectedChip(
                                  contact: contact,
                                  onRemove:
                                      widget.lockedIds.contains(contact.id)
                                          ? null
                                          : () => _toggle(contact.id),
                                ),
                            ],
                          ),
                        ],
                        if (selected.length > 1) ...[
                          const SizedBox(height: 12),
                          SeparateRequestsNote(count: selected.length),
                        ],
                        const SizedBox(height: 12),
                        TextField(
                          controller: _searchController,
                          textInputAction: TextInputAction.search,
                          decoration: InputDecoration(
                            hintText: 'Search contacts',
                            prefixIcon: const Icon(Icons.search, size: 20),
                            fillColor: colors.hairline,
                            isDense: true,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        _NewContactRow(onTap: _createContact),
                        for (final contact in visible)
                          _PersonRow(
                            contact: contact,
                            subtitle: _stats.subtitleFor(contact.id),
                            selected: _selectedIds.contains(contact.id),
                            locked: widget.lockedIds.contains(contact.id),
                            onTap: () => _toggle(contact.id),
                          ),
                        if (visible.isEmpty)
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 28),
                            child: Text(
                              'No contacts match. Add them as a new contact.',
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: colors.secondaryText,
                              ),
                            ),
                          ),
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Explains that choosing several people creates one request each.
class SeparateRequestsNote extends StatelessWidget {
  const SeparateRequestsNote({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final style = theme.textTheme.bodySmall?.copyWith(
      fontSize: 12.5,
      height: 1.45,
      color: colors.onSurface,
    );
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceTint,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, size: 16, color: colors.secondaryText),
          const SizedBox(width: 8),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: '$count separate requests',
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                    text: ' will be created, one per person, so each can be '
                        'prayed, answered or archived on its own.',
                  ),
                ],
              ),
              style: style,
            ),
          ),
        ],
      ),
    );
  }
}

class _SelectedChip extends StatelessWidget {
  const _SelectedChip({required this.contact, this.onRemove});

  final Contact contact;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final name = prayerPersonName(contact);
    return Container(
      height: 34,
      padding: EdgeInsets.only(left: 4, right: onRemove == null ? 12 : 2),
      decoration: BoxDecoration(
        color: colors.greenTint,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircleAvatar(
            radius: 13,
            backgroundColor: colors.surface,
            child: Text(
              contact.initials,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w800,
                color: colors.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            name,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: colors.onPrimaryContainer,
            ),
          ),
          if (onRemove != null)
            IconButton(
              onPressed: onRemove,
              tooltip: 'Remove $name',
              icon: const Icon(Icons.close, size: 16),
              color: colors.onPrimaryContainer,
              constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              padding: EdgeInsets.zero,
            ),
        ],
      ),
    );
  }
}

class _NewContactRow extends StatelessWidget {
  const _NewContactRow({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.hairline)),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Icon(Icons.add, size: 20, color: colors.primary),
            ),
            const SizedBox(width: 12),
            Text(
              'New contact',
              style: TextStyle(
                fontSize: 14.5,
                fontWeight: FontWeight.w700,
                color: colors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.contact,
    required this.subtitle,
    required this.selected,
    required this.locked,
    required this.onTap,
  });

  final Contact contact;
  final String subtitle;
  final bool selected;
  final bool locked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    return MergeSemantics(
      child: Semantics(
        checked: selected,
        enabled: !locked,
        child: InkWell(
          onTap: locked ? null : onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 60),
            padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: colors.hairline)),
            ),
            child: Row(
              children: [
                ContactAvatar(contact: contact, radius: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        prayerPersonName(contact),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: colors.onSurface,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colors.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
                Opacity(
                  opacity: locked ? 0.5 : 1,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: selected ? colors.primary : colors.surface,
                      borderRadius: BorderRadius.circular(7),
                      border: selected
                          ? null
                          : Border.all(color: colors.faint, width: 2),
                    ),
                    child: selected
                        ? Icon(Icons.check, size: 18, color: colors.onPrimary)
                        : null,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
