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

const kPrimaryColor = Color(0xFF0D7CF2);
const kBorderColor = Color(0xFFE5E5E5);
const kBgLight = Color(0xFFF5F7F8);
const kTextPrimary = Color(0xFF1C1C1E);
const kTextSecondary = Color(0xFF9CA3AF);

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

    final loadedContacts =
        await _dbHelper.getContacts(contactIds: freshList.contactIds);

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
      builder: (context) => ContactSelectionSheet(
        alreadySelectedIds: currentIds,
        title: 'Add to ${_activeList!.name}',
      ),
    );

    if (selectedIds != null && selectedIds.isNotEmpty) {
      for (final id in selectedIds) {
        await _dbHelper.addContactToPrayerList(_activeList!.id, id);
      }
      await _loadListContacts(_activeList!);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Row(
      children: [
        // Contact List
        Container(
          width: 300,
          decoration: const BoxDecoration(
            border: Border(
              right: BorderSide(color: Color(0xFFE5E5E5)),
            ),
            color: Colors.white,
          ),
          child: Column(
            children: [
              // List Header
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: const BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Color(0xFFE5E5E5)),
                  ),
                  color: Color(0xFFF9FAFB), // Slight bg for header
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${_contacts.length} ACTIVE',
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                      ),
                    ),
                    Row(
                      children: [
                        IconButton(
                          onPressed: _onAddContact,
                          icon: const Icon(Icons.add),
                          iconSize: 20,
                          color: Theme.of(context).primaryColor,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Add Contact',
                        ),
                        const SizedBox(width: 12),
                        Icon(Icons.filter_list,
                            size: 18, color: Theme.of(context).primaryColor),
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
                          style: GoogleFonts.inter(
                              color: Colors.grey[400], fontSize: 12),
                        ),
                      )
                    : ListView.separated(
                        itemCount: _contacts.length,
                        separatorBuilder: (context, index) =>
                            const Divider(height: 1, color: Color(0xFFF3F4F6)),
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

    final avatarColor = getAvatarColor(contact.initials);

    return Material(
      color: isSelected ? kPrimaryColor : Colors.white,
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
                      ? Colors.white.withOpacity(0.2)
                      : avatarColor.withOpacity(0.1),
                  shape: BoxShape.circle,
                  border: isSelected
                      ? Border.all(color: Colors.white.withOpacity(0.2))
                      : null,
                ),
                alignment: Alignment.center,
                child: Text(
                  contact.initials,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : avatarColor,
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
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: isSelected ? Colors.white : Colors.black,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: Text(
                            dateStr,
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              color: isSelected
                                  ? Colors.white.withOpacity(0.9)
                                  : kTextSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      snippet,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isSelected
                            ? Colors.white.withOpacity(0.8)
                            : Colors.grey[500],
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
    final activeRequests = contact.prayerRequests
        .where((r) => r.status == PrayerRequestStatus.pending)
        .toList();
    // Sort interactions by date desc
    final recentInteractions = List<Interaction>.from(contact.interactions)
      ..sort((a, b) => b.occurredAt.compareTo(a.occurredAt));

    final avatarColor = getAvatarColor(contact.initials);

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: kBorderColor)),
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
                              avatarColor.withOpacity(0.7),
                              avatarColor,
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          shape: BoxShape.circle,
                          boxShadow: [
                            BoxShadow(
                                color: avatarColor.withOpacity(0.3),
                                blurRadius: 8,
                                offset: const Offset(0, 4))
                          ]),
                      alignment: Alignment.center,
                      child: Text(
                        contact.initials,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w600,
                          color: Colors.white,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contact.displayName,
                          style: GoogleFonts.inter(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                            color: kTextPrimary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (contact.tags.isNotEmpty)
                              ...contact.tags.map((tag) => Padding(
                                    padding: const EdgeInsets.only(right: 8),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 8, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: kBgLight,
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        tag,
                                        style: GoogleFonts.inter(
                                          fontSize: 11,
                                          color: kTextSecondary,
                                        ),
                                      ),
                                    ),
                                  )),
                            Text(
                              'Last prayed: Today', // Placeholder
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: kTextSecondary,
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
                      foregroundColor: kPrimaryColor,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      backgroundColor: Colors.blue.withOpacity(0.05),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6))),
                  child: Text('Edit',
                      style: GoogleFonts.inter(
                          fontSize: 13, fontWeight: FontWeight.w500)),
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
                        style: GoogleFonts.inter(
                            color: Colors.grey[400], fontSize: 13),
                      ),
                    )
                  else
                    ...activeRequests.map((req) => _buildRequestItem(req)),
                  const SizedBox(height: 24),
                  const Divider(color: kBorderColor, height: 1),
                  const SizedBox(height: 24),
                  Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSectionTitle('Interactions'),
                        IconButton(
                            onPressed: () {},
                            icon: const Icon(Icons.add, size: 18),
                            color: kTextSecondary,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            style: IconButton.styleFrom(
                                hoverColor: kBgLight,
                                padding: const EdgeInsets.all(4)))
                      ]),
                  const SizedBox(height: 16),
                  if (recentInteractions.isEmpty)
                    Text(
                      'No recent interactions.',
                      style: GoogleFonts.inter(
                          color: Colors.grey[400], fontSize: 13),
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
    return Text(
      title.toUpperCase(),
      style: GoogleFonts.inter(
        fontSize: 11,
        fontWeight: FontWeight.bold,
        color: const Color(0xFF9CA3AF),
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _buildRequestItem(PrayerRequest request) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
                top: 2), // Align checkbox with text top line
            child: SizedBox(
                width: 16,
                height: 16,
                child: Checkbox(
                  value: false, // Pending requests are unchecked
                  onChanged: (val) {
                    // TODO: Handle marking as answered
                  },
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(4)),
                  side: const BorderSide(color: Color(0xFFD1D5DB)),
                  activeColor: kPrimaryColor,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                )),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(
                  top: 0.5), // Subtle alignment adjustment
              child: Text(
                request.description,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: kTextPrimary,
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
    return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.transparent),
            // Hover effect can be done with InkWell or logic, simplified here
          ),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Avatar
            Container(
                margin: const EdgeInsets.only(top: 2),
                child: SizedBox(
                    width: 28,
                    height: 28,
                    child: Stack(children: [
                      Container(
                        decoration: BoxDecoration(
                          color:
                              getAvatarColor(contact.initials).withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Text(contact.initials,
                            style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: getAvatarColor(contact.initials))),
                      )
                    ]))),
            const SizedBox(width: 12),
            Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Row(children: [
                    Text(formatDate(interaction.occurredAt),
                        style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: kTextPrimary)),
                    const SizedBox(width: 8),
                    Text(formatTime(interaction.occurredAt),
                        style: GoogleFonts.inter(
                            fontSize: 11, color: kTextSecondary)),
                    const SizedBox(width: 8),
                    Icon(getMediumIcon(interaction.medium),
                        size: 14, color: kTextSecondary),
                    if (interaction.durationMinutes != null) ...[
                      const Spacer(),
                      Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                              color: kBgLight,
                              borderRadius: BorderRadius.circular(4)),
                          child: Text('${interaction.durationMinutes}m',
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w500,
                                  color: kTextSecondary)))
                    ]
                  ]),
                  const SizedBox(height: 4),
                  Text(interaction.summary,
                      style: GoogleFonts.inter(
                          fontSize: 13, color: Colors.grey[700], height: 1.5))
                ]))
          ]),
        ));
  }
}
