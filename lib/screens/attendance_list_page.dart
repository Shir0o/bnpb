import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';

class AttendanceListPage extends StatefulWidget {
  const AttendanceListPage({Key? key}) : super(key: key);

  @override
  _AttendanceListPageState createState() => _AttendanceListPageState();
}

class _AttendanceListPageState extends State<AttendanceListPage> {
  final DBHelper _dbHelper = DBHelper();
  List<Contact> _contacts = [];
  Map<String, bool> _attendance = {}; // Maps contact ID to attendance status

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  Future<void> _loadContacts() async {
    final contacts = await _dbHelper.getContacts();
    setState(() {
      _contacts = contacts;
      _attendance = {for (var contact in contacts) contact.id: false};
    });
  }

  void _toggleAttendance(String contactId) {
    setState(() {
      _attendance[contactId] = !(_attendance[contactId] ?? false);
    });
  }

  Future<void> _submitAttendance() async {
    final DateTime now = DateTime.now();
    for (var contact in _contacts) {
      final bool isPresent = _attendance[contact.id] ?? false;
      final newHistory = HistoryEntry(
        date: now,
        detail: isPresent ? "Present" : "Absent",
      );
      final updatedContact = contact.copyWith(
        history: [...contact.history, newHistory],
      );
      await _dbHelper.updateContact(updatedContact);
    }
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Mark Attendance'),
        actions: [
          IconButton(
            onPressed: _submitAttendance,
            icon: const Icon(Icons.check),
            tooltip: 'Submit Attendance',
          ),
        ],
      ),
      body: _contacts.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
        itemCount: _contacts.length,
        itemBuilder: (context, index) {
          final contact = _contacts[index];
          final isPresent = _attendance[contact.id] ?? false;
          return ListTile(
            title: Text(contact.fullName),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.check,
                    color: isPresent ? Colors.green : Colors.grey,
                  ),
                  onPressed: () => _toggleAttendance(contact.id),
                ),
                IconButton(
                  icon: Icon(
                    Icons.clear,
                    color: !isPresent ? Colors.red : Colors.grey,
                  ),
                  onPressed: () => _toggleAttendance(contact.id),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}