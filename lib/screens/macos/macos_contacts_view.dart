import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../db/db_helper.dart';
import '../../models/contact.dart';
import '../../services/sync_service.dart';
import 'contact_card.dart';
import 'macos_contact_details_page.dart';

class MacOSContactsView extends StatefulWidget {
  const MacOSContactsView({super.key});

  @override
  State<MacOSContactsView> createState() => _MacOSContactsViewState();
}

class _MacOSContactsViewState extends State<MacOSContactsView> {
  final DBHelper _dbHelper = DBHelper();
  List<Contact> _contacts = [];
  bool _isLoading = true;
  String _searchQuery = '';
  StreamSubscription<void>? _syncSubscription;
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _syncSubscription = SyncService().onSyncComplete.listen((_) {
      if (mounted) {
        _loadContacts(refresh: true);
      }
    });
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadContacts({bool refresh = false}) async {
    if (!refresh) {
      setState(() => _isLoading = true);
    }
    try {
      // Fetch all contacts
      final contacts = await _dbHelper.getContacts();

      // Sort by name
      contacts.sort((a, b) => a.displayName.compareTo(b.displayName));

      if (mounted) {
        setState(() {
          _contacts = contacts;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error loading contacts: $e');
      if (mounted) {
        setState(() {
          _contacts = [];
          _isLoading = false;
        });
      }
    }
  }

  List<Contact> get _filteredContacts {
    if (_searchQuery.isEmpty) return _contacts;
    final query = _searchQuery.toLowerCase();
    return _contacts.where((c) {
      return c.displayName.toLowerCase().contains(query) ||
          c.tags.any((t) => t.toLowerCase().contains(query));
    }).toList();
  }

  Future<void> _onAddContact() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MacOSContactDetailsPage()),
    );
    _loadContacts();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final filtered = _filteredContacts;

    return Column(
      children: [
        // Header
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerLowest,
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              Text(
                'All Contacts',
                style: GoogleFonts.googleSans(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${_contacts.length} people',
                style: GoogleFonts.googleSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const Spacer(),
              // Search Field
              Container(
                width: 200,
                height: 32,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: TextField(
                  controller: _searchController,
                  decoration: InputDecoration(
                    hintText: 'Search',
                    prefixIcon: Icon(
                      Icons.search,
                      size: 18,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(
                      vertical: 8,
                    ), // Adjusted for alignment
                  ),
                  style: GoogleFonts.googleSans(fontSize: 13),
                  textAlignVertical: TextAlignVertical.center,
                ),
              ),
              const SizedBox(width: 12),
              // Add Button
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colorScheme.outlineVariant),
                  boxShadow: [
                    BoxShadow(
                      color: colorScheme.shadow.withValues(alpha: 0.05),
                      offset: const Offset(0, 1),
                      blurRadius: 2,
                    ),
                  ],
                ),
                child: IconButton(
                  onPressed: _onAddContact,
                  icon: const Icon(Icons.add),
                  iconSize: 18,
                  color: colorScheme.onSurfaceVariant,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Add Contact',
                ),
              ),
              const SizedBox(width: 12),
              // View Toggle
              Container(
                height: 32,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                padding: const EdgeInsets.all(2),
                child: Row(
                  children: [
                    _buildViewToggleButton(Icons.grid_view, true),
                    _buildViewToggleButton(Icons.view_list, false),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Content
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ColoredBox(
                  color: colorScheme.surfaceContainerLowest,
                  child: GridView.builder(
                    padding: const EdgeInsets.all(24),
                    gridDelegate:
                        const SliverGridDelegateWithMaxCrossAxisExtent(
                      maxCrossAxisExtent: 180,
                      mainAxisSpacing: 24,
                      crossAxisSpacing: 16,
                      childAspectRatio: 0.85, // Adjust based on card content
                    ),
                    itemCount: filtered.length + 1,
                    itemBuilder: (context, index) {
                      if (index == filtered.length) {
                        return AddContactCard(onTap: _onAddContact);
                      }
                      final contact = filtered[index];
                      return ContactCard(
                        contact: contact,
                        onTap: () async {
                          await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  MacOSContactDetailsPage(contact: contact),
                            ),
                          );
                          _loadContacts(refresh: true);
                        },
                      );
                    },
                  ),
                ),
        ),
      ],
    );
  }

  Widget _buildViewToggleButton(IconData icon, bool isActive) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color:
            isActive ? colorScheme.surfaceContainerLowest : Colors.transparent,
        borderRadius: BorderRadius.circular(6),
        boxShadow: isActive
            ? [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.1),
                  blurRadius: 2,
                  offset: const Offset(0, 1),
                ),
              ]
            : null,
      ),
      child: Icon(
        icon,
        size: 16,
        color: isActive ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
      ),
    );
  }
}
