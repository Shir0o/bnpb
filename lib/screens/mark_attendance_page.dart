import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/attendance_entry.dart';
import '../models/attendance_session.dart';
import '../models/contact.dart';
import '../widgets/people_card.dart';

/// Displays contacts for a session with quick present/absent toggles.
class MarkAttendancePage extends StatefulWidget {
  const MarkAttendancePage({super.key, required this.session});

  final AttendanceSession session;

  @override
  State<MarkAttendancePage> createState() => _MarkAttendancePageState();
}

class _MarkAttendancePageState extends State<MarkAttendancePage> {
  final DBHelper _dbHelper = DBHelper();
  final DateFormat _dateFormat = DateFormat.yMMMMd();

  List<Contact> _contacts = [];
  Map<String, AttendanceStatus> _statuses = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final contacts = await _dbHelper.getContacts()
      ..sort(
        (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
      );
    final sessionId = widget.session.id;
    final entries = sessionId != null
        ? await _dbHelper.getAttendanceEntries(sessionId)
        : <AttendanceEntry>[];

    if (!mounted) return;

    setState(() {
      _contacts = contacts;
      _statuses = {
        for (final entry in entries) entry.contactId: entry.status,
      };
      _isLoading = false;
    });
  }

  Future<void> _updateStatus(Contact contact, bool isPresent) async {
    final status = isPresent ? AttendanceStatus.present : AttendanceStatus.absent;
    setState(() {
      _statuses[contact.id] = status;
    });

    final sessionId = widget.session.id;
    if (sessionId == null) {
      return;
    }

    await _dbHelper.upsertAttendanceEntry(
      AttendanceEntry(
        sessionId: sessionId,
        contactId: contact.id,
        status: status,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final subtitleParts = <String>[_dateFormat.format(session.sessionDate)];
    if (session.location != null && session.location!.isNotEmpty) {
      subtitleParts.add(session.location!);
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(session.title),
            Text(
              subtitleParts.join(' • '),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_contacts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.people_outline, size: 56),
              const SizedBox(height: 12),
              Text(
                'No contacts available yet.',
                style: Theme.of(context).textTheme.titleMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Add people to your directory first, then return to mark attendance.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadData,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _contacts.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final contact = _contacts[index];
          final isPresent =
              _statuses[contact.id] == AttendanceStatus.present;
          return PeopleCard(
            contact: contact,
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Switch.adaptive(
                  value: isPresent,
                  onChanged: (value) => _updateStatus(contact, value),
                ),
                Text(
                  isPresent ? 'Present' : 'Absent',
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
