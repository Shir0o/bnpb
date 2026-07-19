import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../db/db_helper.dart';
import '../../main.dart' show CrispColorScheme;
import '../../models/contact.dart';
import '../../models/interaction.dart';
import '../../models/prayer_list.dart';
import '../../services/sync_service.dart';
import '../../widgets/contact_avatar.dart';
import '../../widgets/log_interaction_sheet.dart';
import '../../widgets/log_prayer_request_sheet.dart';
import '../../widgets/macos_modal.dart';
import 'macos_contact_details_page.dart';

const Map<String, String> _mediumLabels = {
  'in_person': 'In-person',
  'call': 'Call',
  'message': 'Message',
  'online': 'Online',
  'other': 'Other',
};

class _ContactStats {
  const _ContactStats(this.count, this.minutesThisMonth, this.firstMet);
  final int count;
  final int minutesThisMonth;
  final String firstMet;
}

_ContactStats _statsFor(Contact contact) {
  final now = DateTime.now();
  final minutesThisMonth = contact.interactions
      .where(
        (i) => i.occurredAt.year == now.year && i.occurredAt.month == now.month,
      )
      .fold<int>(0, (sum, i) => sum + (i.durationMinutes ?? 0));

  DateTime? earliest;
  for (final interaction in contact.interactions) {
    if (earliest == null || interaction.occurredAt.isBefore(earliest)) {
      earliest = interaction.occurredAt;
    }
  }
  final firstMet = DateFormat.MMMd().format(earliest ?? contact.updatedAt);

  return _ContactStats(contact.interactions.length, minutesThisMonth, firstMet);
}

/// The "Contacts" section: a searchable, location-grouped directory (middle
/// column) with a detail pane (right) that fills in place when a row is
/// selected — no push navigation. Absorbs the old separate "prayer list"
/// landing view as an on-list checkmark badge per contact.
class MacOSContactsView extends StatefulWidget {
  const MacOSContactsView({super.key, this.onAddContact});

  /// Invoked when the user asks to add a contact — the shell routes this to
  /// the dedicated "Add contact" section.
  final VoidCallback? onAddContact;

  @override
  State<MacOSContactsView> createState() => _MacOSContactsViewState();
}

class _MacOSContactsViewState extends State<MacOSContactsView> {
  final DBHelper _dbHelper = DBHelper();
  final TextEditingController _searchController = TextEditingController();
  final Set<String> _expandedLocations = {};

  List<Contact> _contacts = [];
  Contact? _selectedContact;
  PrayerList? _prayerList;
  bool _isLoading = true;
  String _searchQuery = '';
  StreamSubscription<void>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text);
    });
    _load();
    _syncSubscription = SyncService().onSyncComplete.listen((_) {
      if (mounted) _load();
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final contacts = await _dbHelper.getContacts();
    contacts.sort(
      (a, b) =>
          a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
    );

    final lists = await _dbHelper.getPrayerLists();
    PrayerList? prayerList;
    if (lists.isNotEmpty) {
      prayerList = await _dbHelper.getPrayerList(lists.first.id);
    }

    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _prayerList = prayerList;
      _isLoading = false;
      if (_selectedContact != null) {
        final match =
            contacts.where((c) => c.id == _selectedContact!.id).firstOrNull;
        _selectedContact = match;
      }
      if (_expandedLocations.isEmpty) {
        _expandedLocations.addAll(_groupedContacts(contacts).keys);
      }
    });
  }

  Map<String, List<Contact>> _groupedContacts(List<Contact> source) {
    final query = _searchQuery.trim().toLowerCase();
    final filtered = query.isEmpty
        ? source
        : source
            .where((c) => c.displayName.toLowerCase().contains(query))
            .toList();

    final grouped = <String, List<Contact>>{};
    for (final contact in filtered) {
      final location =
          (contact.location != null && contact.location!.isNotEmpty)
              ? contact.location!
              : 'Unknown';
      grouped.putIfAbsent(location, () => []).add(contact);
    }
    final sortedKeys = grouped.keys.toList()..sort();
    return {for (final key in sortedKeys) key: grouped[key]!};
  }

  bool _isOnPrayerList(String contactId) =>
      _prayerList?.contactIds.contains(contactId) ?? false;

  Future<void> _togglePrayerList(Contact contact) async {
    final list = _prayerList;
    if (list == null) return;
    if (_isOnPrayerList(contact.id)) {
      await _dbHelper.removeContactFromPrayerList(list.id, contact.id);
    } else {
      await _dbHelper.addContactToPrayerList(list.id, contact.id);
    }
    await _load();
  }

  Future<void> _openLogInteraction(Contact contact) async {
    final result = await showMacModal<Interaction>(
      context,
      builder: (_) => LogInteractionSheet(
        contact: contact,
        existingInteractions: contact.interactions,
        availableContacts: _contacts,
        onInteractionsUpdated: (_) {},
      ),
    );
    if (result != null) _load();
  }

  Future<void> _openLogPrayer(Contact contact) async {
    await showMacModal(
      context,
      builder: (_) => LogPrayerRequestSheet(
        availableContacts: _contacts,
        initialContact: contact,
        onSaved: (_) {},
      ),
    );
    _load();
  }

  Future<void> _openEdit(Contact? contact) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MacOSContactDetailsPage(contact: contact),
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final grouped = _groupedContacts(_contacts);

    return Row(
      children: [
        _buildListPane(colorScheme, grouped),
        Expanded(child: _buildDetailPane(colorScheme)),
      ],
    );
  }

  Widget _buildListPane(
    ColorScheme colorScheme,
    Map<String, List<Contact>> grouped,
  ) {
    return Container(
      width: 394,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: colorScheme.cardBorder)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(22, 20, 22, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.baseline,
                  textBaseline: TextBaseline.alphabetic,
                  children: [
                    Text(
                      'Contacts',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 26,
                        color: colorScheme.onSurface,
                        letterSpacing: -0.3,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '${_contacts.length}',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.secondaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceTint,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 18, color: colorScheme.outline),
                      const SizedBox(width: 11),
                      Expanded(
                        child: TextField(
                          controller: _searchController,
                          decoration: InputDecoration.collapsed(
                            hintText: 'Search contacts…',
                            hintStyle:
                                TextStyle(color: colorScheme.placeholder),
                          ),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
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
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
              children: grouped.entries
                  .map((e) => _buildLocationGroup(colorScheme, e.key, e.value))
                  .toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationGroup(
    ColorScheme colorScheme,
    String location,
    List<Contact> contacts,
  ) {
    final expanded = _expandedLocations.contains(location);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          onTap: () => setState(() {
            if (expanded) {
              _expandedLocations.remove(location);
            } else {
              _expandedLocations.add(location);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 11, 6, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Text(
                      location.toUpperCase(),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                        letterSpacing: 0.4,
                        color: colorScheme.secondaryText,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 7,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceTint,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        '${contacts.length}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.secondaryText,
                        ),
                      ),
                    ),
                  ],
                ),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 180),
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    size: 18,
                    color: colorScheme.secondaryText,
                  ),
                ),
              ],
            ),
          ),
        ),
        if (expanded)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              children: contacts
                  .map((c) => _buildContactRow(colorScheme, c))
                  .toList(),
            ),
          ),
      ],
    );
  }

  Widget _buildContactRow(ColorScheme colorScheme, Contact contact) {
    final isSelected = _selectedContact?.id == contact.id;
    final onList = _isOnPrayerList(contact.id);
    final lastInteraction =
        contact.interactions.isNotEmpty ? contact.interactions.first : null;
    final sub = lastInteraction?.summary ?? (contact.notes ?? '');

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => setState(() => _selectedContact = contact),
        child: Container(
          margin: const EdgeInsets.only(bottom: 2),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected ? colorScheme.greenTint : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
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
                      contact.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 15,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    if (sub.isNotEmpty)
                      Text(
                        sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12.5,
                          color: colorScheme.secondaryText,
                        ),
                      ),
                  ],
                ),
              ),
              if (onList)
                Icon(Icons.check, size: 16, color: colorScheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailPane(ColorScheme colorScheme) {
    final contact = _selectedContact;
    if (contact == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: colorScheme.surfaceTint,
                borderRadius: BorderRadius.circular(18),
              ),
              alignment: Alignment.center,
              child: Icon(Icons.people_outline,
                  size: 28, color: colorScheme.faint),
            ),
            const SizedBox(height: 16),
            Text(
              'Select a contact',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: colorScheme.secondaryText,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Choose someone to see their timeline and prayer history.",
              style: TextStyle(fontSize: 13.5, color: colorScheme.outline),
            ),
          ],
        ),
      );
    }

    final stats = _statsFor(contact);
    final onList = _isOnPrayerList(contact.id);

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(34, 28, 34, 40),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ContactAvatar(contact: contact, radius: 37),
              const SizedBox(width: 18),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact.displayName,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 27,
                          color: colorScheme.onSurface,
                          letterSpacing: -0.3,
                        ),
                      ),
                      if ((contact.location ?? '').isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            contact.location!,
                            style: TextStyle(
                              fontSize: 14.5,
                              color: colorScheme.outline,
                            ),
                          ),
                        ),
                      if (onList)
                        Container(
                          margin: const EdgeInsets.only(top: 10),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 11,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.greenTint,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check,
                                  size: 12, color: colorScheme.primary),
                              const SizedBox(width: 6),
                              Text(
                                'On your prayer list',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  _actionButton(
                    colorScheme,
                    icon: Icons.add,
                    label: 'Log',
                    filled: true,
                    onTap: () => _openLogInteraction(contact),
                  ),
                  const SizedBox(width: 8),
                  _actionButton(
                    colorScheme,
                    icon: Icons.volunteer_activism_outlined,
                    label: 'Prayer',
                    filled: false,
                    onTap: () => _openLogPrayer(contact),
                  ),
                  const SizedBox(width: 8),
                  _iconButton(
                    colorScheme,
                    icon: onList ? Icons.favorite : Icons.favorite_border,
                    active: onList,
                    onTap: () => _togglePrayerList(contact),
                  ),
                  const SizedBox(width: 8),
                  _iconButton(
                    colorScheme,
                    icon: Icons.edit_outlined,
                    active: false,
                    onTap: () => _openEdit(contact),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 26),
          Row(
            children: [
              Expanded(
                child: _statCard(colorScheme, '${stats.count}', 'Interactions'),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _statCard(
                  colorScheme,
                  '${stats.minutesThisMonth}',
                  'This month',
                  suffix: ' min',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                  child: _statCard(colorScheme, stats.firstMet, 'First met')),
            ],
          ),
          const SizedBox(height: 26),
          Text(
            'Timeline',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 17,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 14),
          if (contact.interactions.isEmpty)
            _emptyTimeline(colorScheme, contact)
          else
            _timeline(colorScheme, contact),
        ],
      ),
    );
  }

  Widget _actionButton(
    ColorScheme colorScheme, {
    required IconData icon,
    required String label,
    required bool filled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
          decoration: BoxDecoration(
            color: filled ? colorScheme.primary : colorScheme.surfaceTint,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: filled ? colorScheme.onPrimary : colorScheme.iconColor,
              ),
              const SizedBox(width: 7),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w700,
                  color: filled ? colorScheme.onPrimary : colorScheme.iconColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _iconButton(
    ColorScheme colorScheme, {
    required IconData icon,
    required bool active,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: active ? colorScheme.dangerTint : colorScheme.surfaceTint,
            borderRadius: BorderRadius.circular(11),
          ),
          alignment: Alignment.center,
          child: Icon(
            icon,
            size: 18,
            color: active ? colorScheme.error : colorScheme.iconColor,
          ),
        ),
      ),
    );
  }

  Widget _statCard(
    ColorScheme colorScheme,
    String value,
    String label, {
    String suffix = '',
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.cardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: value,
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (suffix.isNotEmpty)
                  TextSpan(
                    text: suffix,
                    style:
                        TextStyle(fontSize: 14, color: colorScheme.onSurface),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeline(ColorScheme colorScheme, Contact contact) {
    final sorted = List<Interaction>.from(contact.interactions)
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    return Column(
      children: sorted.map((interaction) {
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.cardBorder),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    _mediumLabels[interaction.medium] ?? interaction.medium,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    DateFormat.yMMMd().format(interaction.occurredAt),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.outline,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                interaction.summary,
                style: TextStyle(
                  fontSize: 13.5,
                  color: colorScheme.secondaryText,
                  height: 1.5,
                ),
              ),
              if (interaction.durationMinutes != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule,
                          size: 12, color: colorScheme.outline),
                      const SizedBox(width: 5),
                      Text(
                        '${interaction.durationMinutes} min',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      }).toList(),
    );
  }

  Widget _emptyTimeline(ColorScheme colorScheme, Contact contact) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 30, horizontal: 16),
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.faint),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'No interactions yet',
            style: TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
              color: colorScheme.outline,
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(11),
              onTap: () => _openLogInteraction(contact),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
                decoration: BoxDecoration(
                  color: colorScheme.primary,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  'Log first interaction',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onPrimary,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
