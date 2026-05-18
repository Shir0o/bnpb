import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dart:async';

import 'contact_view_helpers.dart';
import '../../db/db_helper.dart';
import '../../models/contact.dart';
import '../../models/interaction.dart';
import '../../models/prayer_list.dart';
import '../../models/prayer_request.dart';
import '../../services/sync_service.dart';
import '../../widgets/contact_selection_sheet.dart';

class MacOSActiveContactsView extends StatefulWidget {
  const MacOSActiveContactsView({super.key});

  @override
  State<MacOSActiveContactsView> createState() =>
      _MacOSActiveContactsViewState();
}

class _MacOSActiveContactsViewState extends State<MacOSActiveContactsView> {
  final DBHelper _dbHelper = DBHelper();
  PrayerList? _activeList;
  List<Contact> _contacts = [];
  Contact? _selectedContact;
  bool _isLoading = true;
  StreamSubscription<void>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _loadPrayerList();
    _syncSubscription = SyncService().onSyncComplete.listen((_) {
      if (mounted) {
        _loadPrayerList();
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadPrayerList() async {
    setState(() => _isLoading = true);

    // 1. Get or create a default Prayer List
    final lists = await _dbHelper.getPrayerLists();
    PrayerList targetList;

    if (lists.isEmpty) {
      targetList = PrayerList.create(
        name: 'My Prayer List',
        description: 'People I am praying for',
      );
      await _dbHelper.insertPrayerList(targetList);
    } else {
      targetList = lists.first;
    }

    // 2. Load contacts for this list
    await _loadListContacts(targetList);
  }

  Future<void> _loadListContacts(PrayerList list) async {
    // Re-fetch list to ensure we have the latest contact IDs
    final freshList = await _dbHelper.getPrayerList(list.id);
    if (freshList == null) return;

    final loadedContacts = await _dbHelper.getContacts(
      contactIds: freshList.contactIds,
    );

    // Initial selected contact logic
    Contact? nextSelected = _selectedContact;
    if (loadedContacts.isNotEmpty && _selectedContact == null) {
      nextSelected = loadedContacts.first;
    } else if (loadedContacts.isNotEmpty && _selectedContact != null) {
      // Refresh the selected contact data if it's in the list
      final found =
          loadedContacts.where((c) => c.id == _selectedContact!.id).firstOrNull;
      if (found != null) {
        nextSelected = found;
      } else {
        // If selected contact was removed, select the first one
        nextSelected = loadedContacts.first;
      }
    } else if (loadedContacts.isEmpty) {
      nextSelected = null;
    }

    if (mounted) {
      setState(() {
        _activeList = freshList;
        _contacts = loadedContacts;
        _selectedContact = nextSelected;
        _isLoading = false;
      });
    }
  }

  Future<void> _onAddContact() async {
    if (_activeList == null) return;

    final currentIds = _activeList!.contactIds.toSet();

    final selectedIds = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      sheetAnimationStyle: AnimationStyle(
        duration: const Duration(milliseconds: 300),
        reverseDuration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
      ),
      builder: (context) => ContactSelectionSheet(
        disabledIds: currentIds,
        title: 'Add to ${_activeList!.name}',
      ),
    );

    if (selectedIds != null && selectedIds.isNotEmpty) {
      await _dbHelper.addContactsToPrayerList(_activeList!.id, selectedIds);
      await _loadListContacts(_activeList!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Row(
      children: [
        // Contact List
        Container(
          width: 300,
          decoration: BoxDecoration(
            border:
                Border(right: BorderSide(color: colorScheme.outlineVariant)),
            color: colorScheme.surfaceContainerLowest,
          ),
          child: Column(
            children: [
              // List Header
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  color: colorScheme.surfaceContainerLow,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_contacts.length} ACTIVE',
                      style: GoogleFonts.googleSans(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _onAddContact,
                          icon: const Icon(Icons.add),
                          iconSize: 20,
                          color: colorScheme.primary,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Add Contact',
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          Icons.filter_list,
                          size: 18,
                          color: colorScheme.primary,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // List Items
              Expanded(
                child: _contacts.isEmpty
                    ? Center(
                        child: Text(
                          'No active contacts.\nClick + to add.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.googleSans(
                            color: colorScheme.outline,
                            fontSize: 12,
                          ),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _contacts.length,
                        separatorBuilder: (context, index) => Divider(
                            height: 1, color: colorScheme.outlineVariant),
                        itemBuilder: (context, index) {
                          final contact = _contacts[index];
                          final isSelected = _selectedContact?.id == contact.id;
                          return _buildContactTile(contact, isSelected);
                        },
                      ),
              ),
            ],
          ),
        ),
        // Detail View
        Expanded(
          child: _selectedContact != null
              ? _buildDetailView(_selectedContact!)
              : const Center(child: Text('Select a contact')),
        ),
      ],
    );
  }

  Widget _buildContactTile(Contact contact, bool isSelected) {
    final colorScheme = Theme.of(context).colorScheme;
    // Determine last update
    // Interactions are sorted (newest first)
    final lastInteraction =
        contact.interactions.isNotEmpty ? contact.interactions.first : null;
    final lastRequest = contact.prayerRequests.isNotEmpty
        ? contact.prayerRequests.last
        : null; // Ideally requests should be sorted

    DateTime? lastDate;
    String snippet = '';

    if (lastInteraction != null) {
      lastDate = lastInteraction.occurredAt;
      snippet = lastInteraction.summary;
    }

    if (lastRequest != null) {
      if (lastDate == null || lastRequest.requestedAt.isAfter(lastDate)) {
        lastDate = lastRequest.requestedAt;
        snippet = lastRequest.description;
      }
    }

    if (lastDate == null) {
      snippet = contact.notes ?? '';
      lastDate = contact.updatedAt;
    }

    final dateStr = formatDate(lastDate);

    final avatarColor = getAvatarColor(contact.initials, colorScheme);

    return Material(
      color:
          isSelected ? colorScheme.primary : colorScheme.surfaceContainerLowest,
      child: InkWell(
        onTap: () => setState(() => _selectedContact = contact),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.onPrimary.withValues(alpha: 0.2)
                      : avatarColor.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(
                          color: colorScheme.onPrimary.withValues(alpha: 0.2),
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  contact.initials,
                  style: GoogleFonts.googleSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? colorScheme.onPrimary : avatarColor,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Text Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Flexible(
                          child: Text(
                            contact.displayName,
                            style: GoogleFonts.googleSans(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isSelected
                                  ? colorScheme.onPrimary
                                  : colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            dateStr,
                            style: GoogleFonts.googleSans(
                              fontSize: 11,
                              color: isSelected
                                  ? colorScheme.onPrimary.withValues(alpha: 0.9)
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      snippet,
                      style: GoogleFonts.googleSans(
                        fontSize: 12,
                        color: isSelected
                            ? colorScheme.onPrimary.withValues(alpha: 0.8)
                            : colorScheme.onSurfaceVariant,
                        height: 1.3,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailView(Contact contact) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeRequests = contact.prayerRequests
        .where((r) => r.status == PrayerRequestStatus.pending)
        .toList();
    // Sort interactions by date desc
    final recentInteractions = List<Interaction>.from(contact.interactions)
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    final avatarColor = getAvatarColor(contact.initials, colorScheme);

    return Container(
      color: colorScheme.surfaceContainerLowest,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: colorScheme.outlineVariant),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            avatarColor.withValues(alpha: 0.7),
                            avatarColor,
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: avatarColor.withValues(alpha: 0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        contact.initials,
                        style: GoogleFonts.googleSans(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.displayName,
                          style: GoogleFonts.googleSans(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Text(
                              'Last prayed: Today', // Placeholder
                              style: GoogleFonts.googleSans(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                TextButton(
                  onPressed: () {}, // Edit action
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.primary,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    backgroundColor:
                        colorScheme.primary.withValues(alpha: 0.08),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  child: Text(
                    'Edit',
                    style: GoogleFonts.googleSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Content Scroll
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSectionTitle('Active Requests'),
                  const SizedBox(height: 12),
                  if (activeRequests.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 24),
                      child: Text(
                        'No active prayer requests.',
                        style: GoogleFonts.googleSans(
                          color: colorScheme.outline,
                          fontSize: 13,
                        ),
                      ),
                    )
                  else
                    ...activeRequests.map((req) => _buildRequestItem(req)),
                  const SizedBox(height: 24),
                  Divider(color: colorScheme.outlineVariant, height: 1),
                  const SizedBox(height: 24),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildSectionTitle('Interactions'),
                      IconButton(
                        onPressed: () {},
                        icon: const Icon(Icons.add, size: 18),
                        color: colorScheme.onSurfaceVariant,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        style: IconButton.styleFrom(
                          hoverColor: colorScheme.surfaceContainerLow,
                          padding: const EdgeInsets.all(4),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (recentInteractions.isEmpty)
                    Text(
                      'No recent interactions.',
                      style: GoogleFonts.googleSans(
                        color: colorScheme.outline,
                        fontSize: 13,
                      ),
                    )
                  else
                    ...recentInteractions
                        .take(10)
                        .map((i) => _buildSessionItem(i, contact)),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    final colorScheme = Theme.of(context).colorScheme;

    return Text(
      title.toUpperCase(),
      style: GoogleFonts.googleSans(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: colorScheme.onSurfaceVariant,
      ),
    );
  }

  Widget _buildRequestItem(PrayerRequest request) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              top: 2,
            ), // Align checkbox with text top line
            child: SizedBox(
              width: 16,
              height: 16,
              child: Checkbox(
                value: false, // Pending requests are unchecked
                onChanged: (val) async {
                  if (val == true) {
                    final updated = request.copyWith(
                      status: PrayerRequestStatus.answered,
                      answeredAt: DateTime.now(),
                    );
                    await _dbHelper.updatePrayerRequest(updated);
                    if (mounted && _activeList != null) {
                      await _loadListContacts(_activeList!);
                    }
                  }
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
                side: BorderSide(color: colorScheme.outlineVariant),
                activeColor: colorScheme.primary,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                top: 0.5,
              ), // Subtle alignment adjustment
              child: Text(
                request.description,
                style: GoogleFonts.googleSans(
                  fontSize: 14,
                  color: colorScheme.onSurface,
                  height: 1.5, // Relaxed line height for readability
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionItem(Interaction interaction, Contact contact) {
    final colorScheme = Theme.of(context).colorScheme;
    final avatarColor = getAvatarColor(contact.initials, colorScheme);

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.transparent),
          // Hover effect can be done with InkWell or logic, simplified here
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar
            Container(
              margin: const EdgeInsets.only(top: 2),
              child: SizedBox(
                width: 28,
                height: 28,
                child: Stack(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: avatarColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        contact.initials,
                        style: GoogleFonts.googleSans(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: avatarColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        formatDate(interaction.occurredAt),
                        style: GoogleFonts.googleSans(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        formatTime(interaction.occurredAt),
                        style: GoogleFonts.googleSans(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(
                        getMediumIcon(interaction.medium),
                        size: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                      if (interaction.durationMinutes != null) ...[
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            '${interaction.durationMinutes}m',
                            style: GoogleFonts.googleSans(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    interaction.summary,
                    style: GoogleFonts.googleSans(
                      fontSize: 13,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
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
