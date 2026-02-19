import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../db/db_helper.dart';
import '../../models/contact.dart';
import '../../models/prayer_request.dart';
import '../prayer_request_details_page.dart';
import '../../widgets/log_prayer_request_sheet.dart';

class MacOSPrayerDiaryView extends StatefulWidget {
  const MacOSPrayerDiaryView({super.key});

  @override
  State<MacOSPrayerDiaryView> createState() => _MacOSPrayerDiaryViewState();
}

class _MacOSPrayerDiaryViewState extends State<MacOSPrayerDiaryView> {
  final DBHelper _dbHelper = DBHelper();
  final Map<String, Contact> _contactLookup = {};
  List<Contact> _contacts = [];
  List<PrayerRequest> _requests = [];
  bool _isLoading = false;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    try {
      final results = await Future.wait([
        _dbHelper.getPrayerRequests(),
        _dbHelper.getContacts(),
      ]);

      if (!mounted) return;

      final requests = results[0] as List<PrayerRequest>;
      final contacts = List<Contact>.from(results[1] as List<Contact>)
        ..sort(
          (a, b) =>
              a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
        );

      // Sort requests by date descending
      requests.sort((a, b) {
        final aDate = a.answeredAt ?? a.requestedAt;
        final bDate = b.answeredAt ?? b.requestedAt;
        return bDate.compareTo(aDate);
      });

      setState(() {
        _requests = requests;
        _contacts = contacts;
        _contactLookup
          ..clear()
          ..addEntries(
            contacts.map((contact) => MapEntry(contact.id, contact)),
          );
      });
    } catch (e) {
      debugPrint('Error loading prayer diary data: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openLogPrayerRequestSheet() async {
    if (_contacts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a contact before logging a prayer request.'),
        ),
      );
      return;
    }

    bool didSave = false;
    await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) {
        return LogPrayerRequestSheet(
          availableContacts: List<Contact>.from(_contacts),
          onSaved: (_) {
            didSave = true;
          },
        );
      },
    );

    if (mounted && didSave) {
      await _loadData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _buildContent(),
        ),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E5E5)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'Prayer Diary',
            style: GoogleFonts.inter(
              fontSize: 16,
              fontWeight: FontWeight.w600,
              color: Colors.black,
            ),
          ),
          Row(
            children: [
              // Search Bar
              Container(
                width: 200,
                height: 32,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(6),
                ),
                child: TextField(
                  onChanged: (value) {
                    setState(() {
                      _searchQuery = value.toLowerCase();
                    });
                  },
                  decoration: const InputDecoration(
                    hintText: 'Search',
                    prefixIcon: Icon(Icons.search, size: 18),
                    border: InputBorder.none,
                    alignLabelWithHint: true,
                    isDense: true,
                    contentPadding: EdgeInsets.only(top: 6, bottom: 6),
                  ),
                  style: const TextStyle(
                    fontSize: 13,
                    height: 1.0,
                    color: Colors.black,
                  ),
                  textAlignVertical: TextAlignVertical.center,
                ),
              ),
              const SizedBox(width: 12),
              // Add Button
              IconButton(
                onPressed: _openLogPrayerRequestSheet,
                icon: const Icon(Icons.add),
                style: IconButton.styleFrom(
                  foregroundColor: const Color(0xFF0D7CF2),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                  hoverColor: const Color(0xFF0D7CF2).withAlpha(25),
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 32,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    final filteredRequests = _requests.where((req) {
      if (_searchQuery.isEmpty) return true;
      final contactName = _displayNameForContact(req.contactId).toLowerCase();
      return req.description.toLowerCase().contains(_searchQuery) ||
          contactName.contains(_searchQuery);
    }).toList();

    if (filteredRequests.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.book_outlined, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No prayer entries found',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: Colors.grey[600],
              ),
            ),
          ],
        ),
      );
    }

    // Group by date
    final grouped = <String, List<PrayerRequest>>{};
    for (var req in filteredRequests) {
      final date = req.answeredAt ?? req.requestedAt;
      final key = _getDateGroupKey(date);
      grouped.putIfAbsent(key, () => []).add(req);
    }

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: grouped.length,
      itemBuilder: (context, index) {
        final key = grouped.keys.elementAt(index);
        final requests = grouped[key]!;
        // Assuming requests are already sorted by date desc within keys because _requests is sorted
        // and insertions preserve order.

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDateHeader(
                key, requests.first.answeredAt ?? requests.first.requestedAt),
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

    if (checkDate == today) {
      return 'Today';
    } else if (checkDate == yesterday) {
      return 'Yesterday';
    } else {
      return 'Older';
    }
  }

  Widget _buildDateHeader(String title, DateTime date) {
    String dateStr = '';
    if (title == 'Older') {
      // Just show nothing or a generic headers? Design shows "Older" section.
      dateStr = ''; // Or dynamic range? Design implies just a header.
    } else {
      dateStr = DateFormat('MMMM d, y').format(date);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          bottom:
              BorderSide(color: Color(0xFFF5F5F7)), // Optional visual separator
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title.toUpperCase(),
            style: GoogleFonts.inter(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Colors.black,
              letterSpacing: 0.5,
            ),
          ),
          if (dateStr.isNotEmpty)
            Text(
              dateStr,
              style: GoogleFonts.sourceCodePro(
                fontSize: 11,
                color: Colors.grey[400],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEntry(PrayerRequest request) {
    final contactName = _displayNameForContact(request.contactId);
    final timeStr =
        DateFormat('h:mm a').format(request.answeredAt ?? request.requestedAt);
    final isAnswered = request.status == PrayerRequestStatus.answered;
    final isArchived = request.status == PrayerRequestStatus.archived;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Timeline visual
          // This part is a bit tricky with standard widgets.
          // We can use a Stack or CustomPaint, or just simple containers if alignment is fixed.
          // Let's approximate the timeline look:
          // Left side: Time, Contact name, Status
          // Right side: Content with timeline line.

          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 20),
              decoration: const BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Color(0xFFF5F5F7)),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      // Time
                      SizedBox(
                        width: 60,
                        child: Text(
                          timeStr,
                          style: GoogleFonts.inter(
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                            color: Colors.grey[400],
                          ),
                        ),
                      ),
                      Text('•', style: TextStyle(color: Colors.grey[300])),
                      const SizedBox(width: 8),
                      // Contact Chip
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0D7CF2)
                              .withAlpha(25), // Primary/10
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.person,
                                size: 14, color: Color(0xFF0D7CF2)),
                            const SizedBox(width: 4),
                            Text(
                              contactName,
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: const Color(0xFF0D7CF2),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Status Badge
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey[100],
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.grey[200]!),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isAnswered)
                              const Padding(
                                padding: EdgeInsets.only(right: 2),
                                child: Icon(Icons.check_circle,
                                    size: 12, color: Colors.green),
                              ),
                            if (isArchived)
                              const Padding(
                                padding: EdgeInsets.only(right: 2),
                                child: Icon(Icons.inventory_2,
                                    size: 12, color: Colors.grey),
                              ),
                            Text(
                              request.status.label,
                              style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w500,
                                color: Colors.grey[500],
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Edit Button
                      InkWell(
                        onTap: () => _openPrayerRequestDetails(request),
                        borderRadius: BorderRadius.circular(4),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          child: Text(
                            'Edit',
                            style: GoogleFonts.inter(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: const Color(0xFF0D7CF2),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Content with indent using padding
                  Padding(
                    padding:
                        const EdgeInsets.only(left: 72), // 60 width + dot + gap
                    child: Container(
                      decoration: const BoxDecoration(
                        border:
                            Border(left: BorderSide(color: Color(0xFFE5E5E5))),
                      ),
                      padding: const EdgeInsets.only(left: 16),
                      child: Text(
                        request.description,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          height: 1.5,
                          color: Colors.black87,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openPrayerRequestDetails(PrayerRequest request) async {
    final contact = _contactLookup[request.contactId];
    if (contact == null) return;

    final didUpdate = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => PrayerRequestDetailsPage(
          request: request,
          contact: contact,
        ),
      ),
    );

    if (mounted && didUpdate == true) {
      await _loadData();
    }
  }

  String _displayNameForContact(String contactId) {
    final contact = _contactLookup[contactId];
    if (contact == null) {
      return 'Unknown';
    }
    if (contact.fullName.isNotEmpty) {
      return contact.fullName;
    }
    final nickname = contact.nickname ?? '';
    return nickname.isNotEmpty ? nickname : 'Unknown';
  }
}
