import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'dart:async';

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
    return Material(
      color: isSelected ? const Color(0xFF0D7CF2) : Colors.white,
      child: InkWell(
        onTap: () => setState(() => _selectedContact = contact),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Avatar
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.2)
                      : Colors.blue[50],
                  shape: BoxShape.circle,
                ),
                alignment: Alignment.center,
                child: Text(
                  contact.initials,
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.blue[700],
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
                        Text(
                          'Today', // Placeholder for last interaction
                          style: GoogleFonts.inter(
                            fontSize: 11,
                            color: isSelected
                                ? Colors.white.withValues(alpha: 0.9)
                                : Colors.grey[400],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Last notes here...', // Placeholder
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: isSelected
                            ? Colors.white.withValues(alpha: 0.8)
                            : Colors.grey[500],
                        height: 1.4,
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

    return Container(
      color: Colors.white,
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
            decoration: const BoxDecoration(
              border: Border(bottom: BorderSide(color: Color(0xFFF3F4F6))),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Color(0xFF60A5FA), Color(0xFF2563EB)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        contact.initials,
                        style: GoogleFonts.inter(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
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
                            color: const Color(0xFF111827),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            if (contact.tags.isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFF3F4F6),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  contact.tags.first,
                                  style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: const Color(0xFF6B7280),
                                  ),
                                ),
                              ),
                            if (contact.tags.isNotEmpty)
                              const SizedBox(width: 8),
                            Text(
                              'Last prayed: Today', // Placeholder
                              style: GoogleFonts.inter(
                                fontSize: 12,
                                color: const Color(0xFF6B7280),
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
                  child: Text('Edit', style: GoogleFonts.inter(fontSize: 13)),
                ),
              ],
            ),
          ),
          // Content Scroll
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
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
                  const Divider(),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Recent Sessions'),
                  const SizedBox(height: 16),
                  if (recentInteractions.isEmpty)
                    Text(
                      'No recent interactions.',
                      style: GoogleFonts.inter(
                          color: Colors.grey[400], fontSize: 13),
                    )
                  else
                    ...recentInteractions
                        .take(5)
                        .map((i) => _buildSessionItem(i)),
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
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              Icons.check_box_outline_blank,
              size: 18,
              color: const Color(0xFFD1D5DB),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              request.description,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: const Color(0xFF111827),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSessionItem(Interaction interaction) {
    // Basic date formatting without extra package for now
    final date = interaction.occurredAt;
    final dateStr =
        '${date.month}/${date.day} ${date.hour}:${date.minute.toString().padLeft(2, '0')}';

    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 20),
      child: Container(
        decoration: const BoxDecoration(
          border: Border(left: BorderSide(color: Color(0xFFF3F4F6), width: 2)),
        ),
        padding: const EdgeInsets.only(left: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              dateStr,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              interaction.summary,
              style: GoogleFonts.inter(
                fontSize: 13,
                color: const Color(0xFF4B5563),
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
