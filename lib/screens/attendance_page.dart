import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/attendance_session.dart';
import 'mark_attendance_page.dart';

/// Lists attendance sessions and allows creating a new session.
class AttendancePage extends StatefulWidget {
  const AttendancePage({super.key});

  @override
  State<AttendancePage> createState() => _AttendancePageState();
}

class _AttendancePageState extends State<AttendancePage> {
  final DBHelper _dbHelper = DBHelper();
  final DateFormat _dateFormat = DateFormat.yMMMd();

  List<AttendanceSession> _sessions = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSessions();
  }

  Future<void> _loadSessions() async {
    setState(() {
      _isLoading = true;
    });

    final sessions = await _dbHelper.getAttendanceSessions();

    if (!mounted) return;
    setState(() {
      _sessions = sessions;
      _isLoading = false;
    });
  }

  Future<void> _showCreateSessionSheet() async {
    final titleController = TextEditingController();
    final locationController = TextEditingController();
    DateTime selectedDate = DateTime.now();

    AttendanceSession? session;
    try {
      session = await showModalBottomSheet<AttendanceSession>(
        context: context,
        isScrollControlled: true,
        builder: (context) {
          return Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(context).viewInsets.bottom,
            ),
            child: StatefulBuilder(
              builder: (context, setModalState) {
                return Padding(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'New session',
                            style: Theme.of(context).textTheme.titleLarge,
                          ),
                          IconButton(
                            onPressed: Navigator.of(context).pop,
                            icon: const Icon(Icons.close),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: titleController,
                        decoration: const InputDecoration(
                          labelText: 'Title',
                          hintText: 'e.g., Sunday Gathering',
                        ),
                        textCapitalization: TextCapitalization.sentences,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: locationController,
                        decoration: const InputDecoration(
                          labelText: 'Location (optional)',
                        ),
                        textCapitalization: TextCapitalization.words,
                      ),
                      const SizedBox(height: 12),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.event_outlined),
                        title: const Text('Session date'),
                        subtitle: Text(_dateFormat.format(selectedDate)),
                        onTap: () async {
                          final now = DateTime.now();
                          final picked = await showDatePicker(
                            context: context,
                            initialDate: selectedDate,
                            firstDate: now.subtract(const Duration(days: 365 * 3)),
                            lastDate: now.add(const Duration(days: 365 * 3)),
                          );
                          if (picked != null) {
                            setModalState(() {
                              selectedDate = picked;
                            });
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            final title = titleController.text.trim();
                            if (title.isEmpty) {
                              return;
                            }
                            Navigator.of(context).pop(
                              AttendanceSession(
                                title: title,
                                location: locationController.text.trim().isEmpty
                                    ? null
                                    : locationController.text.trim(),
                                sessionDate: selectedDate,
                              ),
                            );
                          },
                          icon: const Icon(Icons.save_outlined),
                          label: const Text('Create session'),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          );
        },
      );
    } finally {
      titleController.dispose();
      locationController.dispose();
    }

    if (session == null) {
      return;
    }

    await _dbHelper.insertAttendanceSession(session);
    await _loadSessions();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Attendance'),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateSessionSheet,
        icon: const Icon(Icons.add),
        label: const Text('New session'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.event_busy_outlined, size: 56),
            const SizedBox(height: 12),
            Text(
              'No attendance sessions yet.',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            const Text('Create a session to start tracking presence.'),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadSessions,
      child: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: _sessions.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, index) {
          final session = _sessions[index];
          final subtitleParts = <String>[_dateFormat.format(session.sessionDate)];
          if (session.location != null && session.location!.isNotEmpty) {
            subtitleParts.add(session.location!);
          }

          return Card(
            child: ListTile(
              title: Text(session.title),
              subtitle: Text(subtitleParts.join(' • ')),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                if (session.id == null) {
                  return;
                }
                await Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => MarkAttendancePage(session: session),
                  ),
                );
                await _loadSessions();
              },
            ),
          );
        },
      ),
    );
  }
}
