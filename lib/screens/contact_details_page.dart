import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // Add this for date formatting
import 'package:shared_preferences/shared_preferences.dart';
import '../models/contact.dart'; // Assuming you have the `HistoryEntry` and `Contact` models defined

class ContactDetailsPage extends StatefulWidget {
  final Map<String, dynamic> contact;
  final String Function(String id) getFullNameById;
  final VoidCallback onDelete;

  const ContactDetailsPage({
    Key? key,
    required this.contact,
    required this.getFullNameById,
    required this.onDelete,
  }) : super(key: key);

  @override
  State<ContactDetailsPage> createState() => _ContactDetailsPageState();
}

class _ContactDetailsPageState extends State<ContactDetailsPage> {
  late List<HistoryEntry> history;
  final TextEditingController _historyDetailController = TextEditingController();
  DateTime? _selectedDate;

  @override
  void initState() {
    super.initState();
    // Initialize the history list from the contact data
    history = widget.contact['history'] != null
        ? (widget.contact['history'] as List<dynamic>)
        .map((entry) => HistoryEntry.fromMap(entry as Map<String, dynamic>))
        .toList()
        : [];
  }

  @override
  void dispose() {
    _historyDetailController.dispose();
    super.dispose();
  }

  void _confirmDelete() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Contact'),
          content: const Text('Are you sure you want to delete this contact?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context), // Cancel deletion
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close the dialog
                widget.onDelete(); // Trigger the delete callback
                Navigator.pop(context); // Close the ContactDetailsPage
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
              ),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
  }

  void _addHistoryItem() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: const Text('Add History'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _historyDetailController,
                    decoration: const InputDecoration(
                      hintText: 'Enter history detail',
                      border: OutlineInputBorder(),
                    ),
                    keyboardType: TextInputType.text,
                    textCapitalization: TextCapitalization.sentences,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        _selectedDate != null
                            ? DateFormat.yMMMd().format(_selectedDate!)
                            : 'No date selected',
                        style: TextStyle(
                          color: _selectedDate != null ? Colors.black : Colors.grey,
                        ),
                      ),
                      const SizedBox(width: 16),
                      ElevatedButton(
                        onPressed: () async {
                          final pickedDate = await showDatePicker(
                            context: context,
                            initialDate: DateTime.now(),
                            firstDate: DateTime(2000),
                            lastDate: DateTime(2100),
                          );
                          if (pickedDate != null) {
                            setState(() {
                              _selectedDate = pickedDate;
                            });
                          }
                        },
                        child: const Text('Pick Date'),
                      ),
                    ],
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context), // Cancel addition
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final detail = _historyDetailController.text.trim();
                    if (detail.isNotEmpty && _selectedDate != null) {
                      try {
                        setState(() {
                          final newEntry = HistoryEntry(
                            date: _selectedDate!,
                            detail: detail,
                          );
                          history.add(newEntry); // Update local list

                          if (widget.contact['history'] != null) {
                            widget.contact['history'].add(newEntry.toMap()); // Save as Map
                          } else {
                            widget.contact['history'] = [newEntry.toMap()];
                          }
                        });

                        // Save updated contact list to SharedPreferences
                        final prefs = await SharedPreferences.getInstance();
                        final contactsJson = prefs.getString('contacts');
                        final List<Map<String, dynamic>> contacts = contactsJson != null
                            ? List<Map<String, dynamic>>.from(
                            jsonDecode(contactsJson) as List<dynamic>)
                            : [];

                        final updatedContacts = contacts.map((contact) {
                          if (contact['id'] == widget.contact['id']) {
                            return widget.contact; // Replace with updated contact
                          }
                          return contact;
                        }).toList();

                        await prefs.setString('contacts', jsonEncode(updatedContacts));

                        _historyDetailController.clear();
                        _selectedDate = null;
                        Navigator.pop(context); // Close the dialog
                      } catch (error) {
                        print("Error saving history: $error");
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Failed to save history.')),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Please enter a valid detail and date.')),
                      );
                    }
                  },
                  child: const Text('Add'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final fullName = [
      widget.contact['firstName'],
      if (widget.contact['middleName'] != null) widget.contact['middleName'],
      widget.contact['lastName'],
    ].where((name) => name != null && name.trim().isNotEmpty).join(' ');

    return Scaffold(
      appBar: AppBar(
        title: Text(fullName),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: _confirmDelete,
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: ListView(
          children: [
            _buildSection(
              title: 'Grade',
              content: widget.contact['grade'] != null
                  ? Text('Grade: ${widget.contact['grade']}')
                  : const Text('No grade available.'),
            ),
            _buildSection(
              title: 'Occupation',
              content: widget.contact['occupation'] != null
                  ? Text('Occupation: ${widget.contact['occupation']}')
                  : const Text('No occupation available.'),
            ),
            _buildSection(
              title: 'History',
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: history.isNotEmpty
                    ? history.map((entry) {
                  return Text(
                    '- ${entry.detail} (${DateFormat.yMMMd().format(entry.date)})',
                  );
                }).toList()
                    : [const Text('No history available.')],
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addHistoryItem,
        icon: const Icon(Icons.add),
        label: const Text('Add History'),
      ),
    );
  }

  Widget _buildSection({required String title, required Widget content}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        content,
        const Divider(), // Add a divider between sections
      ],
    );
  }
}