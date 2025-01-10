import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/attendance.dart';
import '../models/contact.dart';

class AddAttendancePage extends StatefulWidget {
  const AddAttendancePage({super.key});

  @override
  _AddAttendancePageState createState() => _AddAttendancePageState();
}

class _AddAttendancePageState extends State<AddAttendancePage> {
  final DBHelper _dbHelper = DBHelper();
  List<Contact> _contacts = [];
  Map<String, bool> _attendance = {}; // Maps contact ID to attendance status
  DateTime _selectedDate = DateTime.now(); // Default to today's date
  final String _eventTitle = 'Event Title'; // Default title for the event
  final TextEditingController _titleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _titleController.text = _eventTitle; // Initialize the title controller
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

  Future<void> _pickDate(BuildContext context) async {
    final DateTime? pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (pickedDate != null && pickedDate != _selectedDate) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  Future<void> _saveEvent() async {
    final attendance = Attendance(
      eventId: 'event_${_selectedDate.toIso8601String()}', // Generate a unique ID for the event
      eventTitle: _titleController.text, // Use the edited title
      eventDate: _selectedDate, // Use the selected date
      contacts: _attendance, // Pass the contact attendance map
    );

    await _dbHelper.insertAttendance(attendance);
    await _submitAttendance();

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Event saved: ${_titleController.text}')),
    );
  }

  Future<void> _submitAttendance() async {
    for (var contact in _contacts) {
      final bool isPresent = _attendance[contact.id] ?? false;

      if (isPresent) {
        final newHistory = HistoryEntry(
          date: _selectedDate,
          detail: _titleController.text,
        );

        final updatedContact = contact.copyWith(
          history: [...contact.history, newHistory],
        );

        await _dbHelper.updateContact(updatedContact);
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Attendance submitted for ${_titleController.text}')),
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: TextField(
          controller: _titleController,
          style: const TextStyle(color: Colors.white, fontSize: 20),
          decoration: const InputDecoration(
            hintText: 'Edit Event Title',
            border: InputBorder.none,
          ),
        ),
        actions: [
          IconButton(
            onPressed: _saveEvent,
            icon: const Icon(Icons.save),
            tooltip: 'Save Event',
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Selected Date Section
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
              child: ListTile(
                title: const Text(
                  'Selected Date',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  DateFormat('yyyy-MM-dd').format(_selectedDate),
                  style: const TextStyle(fontSize: 16),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.calendar_today),
                  tooltip: 'Pick Date',
                  onPressed: () => _pickDate(context),
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Attendance List
            Expanded(
              child: _contacts.isEmpty
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                itemCount: _contacts.length,
                itemBuilder: (context, index) {
                  final contact = _contacts[index];
                  final isPresent = _attendance[contact.id] ?? false;
                  return Card(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    elevation: 2,
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: ListTile(
                      title: Text(contact.fullName),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.check,
                              color: isPresent ? Colors.green : Colors.grey,
                            ),
                            tooltip: 'Mark Present',
                            onPressed: () => _toggleAttendance(contact.id),
                          ),
                          IconButton(
                            icon: Icon(
                              Icons.clear,
                              color: !isPresent ? Colors.red : Colors.grey,
                            ),
                            tooltip: 'Mark Absent',
                            onPressed: () => _toggleAttendance(contact.id),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}