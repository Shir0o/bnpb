import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/contact.dart';
import '../../services/contact_service.dart';

class MacOSActiveContactsView extends StatefulWidget {
  const MacOSActiveContactsView({super.key});

  @override
  State<MacOSActiveContactsView> createState() =>
      _MacOSActiveContactsViewState();
}

class _MacOSActiveContactsViewState extends State<MacOSActiveContactsView> {
  List<Contact> _contacts = [];
  Contact? _selectedContact;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchContacts();
  }

  Future<void> _fetchContacts() async {
    setState(() => _isLoading = true);
    final contacts = await ContactService().getContacts();
    if (mounted) {
      setState(() {
        _contacts = contacts;
        if (_contacts.isNotEmpty && _selectedContact == null) {
          _selectedContact = _contacts.first;
        }
        _isLoading = false;
      });
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
                    Icon(Icons.filter_list,
                        size: 18, color: Theme.of(context).primaryColor),
                  ],
                ),
              ),
              // List Items
              Expanded(
                child: ListView.separated(
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
                              'Last prayed: Today',
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
                  // Placeholders for requests
                  _buildRequestItem(
                    'Surgery scheduled for tomorrow morning. Pray for peace and steady hands for the surgeons.',
                    true,
                  ),
                  _buildRequestItem(
                    'Recovery process in the coming weeks.',
                    false,
                  ),
                  const SizedBox(height: 24),
                  const Divider(),
                  const SizedBox(height: 24),
                  _buildSectionTitle('Recent Sessions'),
                  const SizedBox(height: 16),
                  _buildSessionItem(
                    'Today, 8:30 AM',
                    'Spent 15m in prayer. Felt a strong sense of peace regarding the outcome.',
                  ),
                  _buildSessionItem(
                    'Oct 22, 9:00 PM',
                    'Brief prayer before bed.',
                  ),
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

  Widget _buildRequestItem(String text, bool checked) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 18,
              color: checked
                  ? Theme.of(context).primaryColor
                  : const Color(0xFFD1D5DB),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
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

  Widget _buildSessionItem(String date, String notes) {
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
              date,
              style: GoogleFonts.inter(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF9CA3AF),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              notes,
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
