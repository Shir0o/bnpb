import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/attendance.dart';
import '../models/contact.dart';

class AddAttendancePage extends StatefulWidget {
  const AddAttendancePage({Key? key}) : super(key: key);

  @override
  _AddAttendancePageState createState() => _AddAttendancePageState();
}

class _AddAttendancePageState extends State<AddAttendancePage> {
  final DBHelper _dbHelper = DBHelper();
  List<Contact> _contacts = [];
  Map<String, bool> _attendance = {}; // Maps contact ID to attendance status
  DateTime _selectedDate = DateTime.now(); // Default to today's date
  String _eventTitle = 'Event Title'; // Default title for the event
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
    // Create an Attendance object with the current data
    final attendance = Attendance(
      eventId: 'event_${_selectedDate.toIso8601String()}', // Generate a unique ID for the event
      eventTitle: _titleController.text, // Use the edited title
      eventDate: _selectedDate, // Use the selected date
      contacts: _attendance, // Pass the contact attendance map
    );

    // Save the attendance to the database
    await _dbHelper.insertAttendance(attendance);

    await _submitAttendance();

    // Feedback to the user
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Event saved: ${_titleController.text}')),
    );
  }

  Future<void> _submitAttendance() async {
    for (var contact in _contacts) {
      final bool isPresent = _attendance[contact.id] ?? false;

      if (isPresent) {
        // Create a new history entry for the present contact
        final newHistory = HistoryEntry(
          date: _selectedDate, // Use the selected date
          detail: _titleController.text, // Use the event title as the detail
        );

        // Update the contact's history
        final updatedContact = contact.copyWith(
          history: [...contact.history, newHistory],
        );

        // Save the updated contact to the database
        await _dbHelper.updateContact(updatedContact);
      }
    }

    // Provide feedback to the user and navigate back
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
            tooltip: 'Save Event Title',
          ),
          IconButton(
            onPressed: () => _pickDate(context),
            icon: const Icon(Icons.calendar_today),
            tooltip: 'Pick Date',
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              'Selected Date: ${DateFormat('yyyy-MM-dd').format(_selectedDate)}',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          Expanded(
            child: _contacts.isEmpty
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
          ),
        ],
      ),
    );
  }
}