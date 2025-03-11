import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'dart:io';
import 'package:path_provider/path_provider.dart';

import '../db/db_helper.dart'; // SQLite DBHelper
import '../models/contact.dart'; // Using the updated Contact model with location

class ContactDetailsPage extends StatefulWidget {
  final Contact contact;
  final VoidCallback onDelete;

  const ContactDetailsPage({
    super.key,
    required this.contact,
    required this.onDelete,
  });

  @override
  State<ContactDetailsPage> createState() => _ContactDetailsPageState();
}

class _ContactDetailsPageState extends State<ContactDetailsPage> {
  // Controllers
  final TextEditingController _historyDetailController = TextEditingController();

  final TextEditingController _locationController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();

  late List<HistoryEntry> history;
  DateTime? _selectedDate;

  // Grade options

  @override
  void initState() {
    super.initState();

    history = widget.contact.history;

    // Initialize text field controllers

    _locationController.text = widget.contact.location ?? '';
    _firstNameController.text = widget.contact.firstName;
    _middleNameController.text = widget.contact.middleName;
    _lastNameController.text = widget.contact.lastName ?? '';
  }

  @override
  void dispose() {
    _historyDetailController.dispose();

    _locationController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _updateContact() async {
    final lastNameText = _lastNameController.text.trim();
    final updatedContact = widget.contact.copyWith(
      firstName: _firstNameController.text.trim(),
      middleName: _middleNameController.text.trim(),
      lastName: lastNameText.isEmpty ? null : lastNameText,
      location: _locationController.text.trim(),
    );

    await DBHelper().updateContact(updatedContact);

    // Create a backup
    await _exportBackup();

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contact updated successfully!')),
    );

    Navigator.pop(context);
  }

  Future<void> _exportBackup() async {
    final directory = await getApplicationDocumentsDirectory();
    final backupDir = Directory('${directory.path}/backups');

    if (!backupDir.existsSync()) {
      backupDir.createSync(recursive: true);
    }

    final dbFile = File('${directory.path}/contacts.db');
    if (!dbFile.existsSync()) return;

    final timestamp = DateFormat('yyyy-MM-dd_HH-mm-ss').format(DateTime.now());
    final backupFile = File('${backupDir.path}/backup_$timestamp.db');

    await dbFile.copy(backupFile.path);

    // Retain only the latest 5 backups
    final backups = backupDir
        .listSync()
        .whereType<File>()
        .where((file) => file.path.contains('backup_'))
        .toList()
      ..sort((a, b) => b.statSync().modified.compareTo(a.statSync().modified));

    while (backups.length > 5) {
      backups.removeLast().deleteSync();
    }
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
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                await DBHelper().deleteContact(widget.contact.id);
                widget.onDelete();
                Navigator.pop(context); // Close the dialog
                Navigator.pop(context); // Pop back to the previous screen
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

  void _deleteHistoryEntry(int index) async {
    // Sort the history list by date in descending order
    final sortedHistory = List<HistoryEntry>.from(history)
      ..sort((a, b) => b.date.compareTo(a.date));

    // Get the actual entry to delete from the sorted list
    final historyToDelete = sortedHistory[index];

    // Remove the entry from the original history list
    setState(() {
      history.removeWhere((entry) => entry == historyToDelete);
    });

    // Update the contact in the database
    final updatedContact = widget.contact.copyWith(history: history);
    await DBHelper().updateContact(updatedContact);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('History entry deleted')),
    );
  }

  void _addHistoryItem() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: const Text('Add History'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Material-styled TextField for history detail
                  TextField(
                    controller: _historyDetailController,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: 'Enter history detail',
                      border: const OutlineInputBorder(),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                        const BorderSide(color: Colors.blue, width: 2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        _selectedDate != null
                            ? DateFormat.yMMMd().format(_selectedDate!)
                            : 'No date selected',
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
                            setStateDialog(() {
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
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final detail = _historyDetailController.text.trim();
                    if (detail.isNotEmpty && _selectedDate != null) {
                      final newEntry = HistoryEntry(
                        date: _selectedDate!,
                        detail: detail,
                      );

                      // Update the history list
                      final updatedHistory = List<HistoryEntry>.from(history)
                        ..add(newEntry);

                      // Create an updated contact
                      final updatedContact =
                      widget.contact.copyWith(history: updatedHistory);

                      // Update the state
                      setState(() {
                        history = updatedHistory;
                      });

                      // Update the database
                      await DBHelper().updateContact(updatedContact);

                      // Clear inputs and close dialog
                      _historyDetailController.clear();
                      _selectedDate = null;
                      Navigator.pop(context);
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Please fill in all fields.'),
                        ),
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
    // Generate a full name for the AppBar title
    final fullName = widget.contact.fullName;

    return Scaffold(
      appBar: AppBar(
        title: Text(fullName),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _updateContact,
          ),
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
            // First Name
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
              child: Padding(
                padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: _buildEditableSection(
                  title: 'First Name',
                  controller: _firstNameController,
                  hintText: 'Enter first name',
                ),
              ),
            ),

            // Middle Name
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
              child: Padding(
                padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: _buildEditableSection(
                  title: 'Middle Name',
                  controller: _middleNameController,
                  hintText: 'Enter middle name (optional)',
                ),
              ),
            ),

            // Last Name
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
              child: Padding(
                padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: _buildEditableSection(
                  title: 'Last Name',
                  controller: _lastNameController,
                  hintText: 'Enter last name',
                ),
              ),
            ),

            // Removed Grade and Occupation sections

            // Location (New Section)
            Card(
              margin: const EdgeInsets.only(bottom: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
              child: Padding(
                padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: _buildEditableSection(
                  title: 'Location',
                  controller: _locationController,
                  hintText: 'Enter location',
                ),
              ),
            ),

            // History Section
            Card(
              margin: const EdgeInsets.only(bottom: 80), // Extra space for FAB
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: 2,
              child: Padding(
                padding:
                const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                child: _buildHistorySection(),
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

  /// Displays a list of history items in descending order
  Widget _buildHistorySection() {
    final sortedHistory = List<HistoryEntry>.from(history)
      ..sort((a, b) => b.date.compareTo(a.date));

    return _buildSection(
      title: 'History',
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: sortedHistory.isNotEmpty
            ? sortedHistory.asMap().entries.map((entry) {
          final index = entry.key;
          final historyEntry = entry.value;
          return ListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              historyEntry.detail,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: Text(
              DateFormat.yMMMd().format(historyEntry.date),
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.red),
              onPressed: () => _deleteHistoryEntry(index),
            ),
          );
        }).toList()
            : [
          const Text(
            'No history available.',
            style: TextStyle(fontSize: 14, color: Colors.grey),
          ),
        ],
      ),
    );
  }

  /// A reusable method to build a section with a title
  Widget _buildSection({
    required String title,
    required Widget content,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Section Title
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(
            title,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        // Actual content
        content,
      ],
    );
  }

  /// Reusable method to build an editable section with a title and TextField
  Widget _buildEditableSection({
    required String title,
    required TextEditingController controller,
    required String hintText,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Title
        Padding(
          padding: const EdgeInsets.only(bottom: 8.0),
          child: Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        // Material-styled TextField
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: hintText,
            border: const OutlineInputBorder(),
            // Add a more visible focus border for Material emphasis
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide:
              const BorderSide(color: Colors.blue, width: 2),
            ),
          ),
        ),
      ],
    );
  }
}