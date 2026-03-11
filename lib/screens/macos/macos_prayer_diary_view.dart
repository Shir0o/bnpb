import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../db/db_helper.dart';
import '../../models/contact.dart';
import '../../models/prayer_request.dart';

import '../../widgets/log_prayer_request_sheet.dart';
import 'prayer_diary_entry.dart';

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
  String? _editingRequestId;
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

      // Sort requests
      _sortRequests(requests);

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

  void _sortRequests(List<PrayerRequest> requests) {
    requests.sort((a, b) {
      // Group 1: Pending (comes first)
      // Group 2: Answered and Archived (comes after)
      final aIsPending = a.status == PrayerRequestStatus.pending;
      final bIsPending = b.status == PrayerRequestStatus.pending;

      if (aIsPending && !bIsPending) return -1;
      if (!aIsPending && bIsPending) return 1;

      // Within groups, sort by date descending
      final aDate = a.answeredAt ?? a.requestedAt;
      final bDate = b.answeredAt ?? b.requestedAt;
      return bDate.compareTo(aDate);
    });
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
        border: Border(bottom: BorderSide(color: Color(0xFFE5E5E5))),
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
                constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
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
      final matchDescription = req.description.toLowerCase().contains(
            _searchQuery,
          );
      final matchContacts = req.participantIds.any((id) {
        final name = _displayNameForContact(id).toLowerCase();
        return name.contains(_searchQuery);
      });
      return matchDescription || matchContacts;
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
              style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
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
      dateStr = '';
    } else {
      dateStr = DateFormat('MMMM d, y').format(date);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: Color(0xFFF5F5F7))),
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
    final participants = request.participantIds
        .map((id) => _contactLookup[id])
        .whereType<Contact>()
        .toList();

    return PrayerDiaryEntry(
      request: request,
      contacts: participants,
      isEditing: _editingRequestId == request.syncId,
      onEditStart: () => _onEntryEditStart(request),
      onEditSave: _onEntryEditSave,
      onEditCancel: _onEntryEditCancel,
    );
  }

  void _onEntryEditStart(PrayerRequest request) {
    setState(() {
      _editingRequestId = request.syncId;
    });
  }

  Future<void> _onEntryEditSave(PrayerRequest updatedRequest) async {
    try {
      if (updatedRequest.id != null) {
        await _dbHelper.updatePrayerRequest(updatedRequest);
      } else {
        await _dbHelper.insertPrayerRequest(updatedRequest);
      }
      if (mounted) {
        setState(() {
          _editingRequestId = null;
          final index = _requests.indexWhere(
            (r) => r.syncId == updatedRequest.syncId,
          );
          if (index != -1) {
            _requests[index] = updatedRequest;
            _sortRequests(_requests);
          }
        });
      }
    } catch (e) {
      debugPrint('Error updating prayer request: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Failed to update request: $e')));
      }
    }
  }

  void _onEntryEditCancel() {
    setState(() {
      _editingRequestId = null;
    });
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
