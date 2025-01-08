import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date formatting
import '../models/contact.dart'; // Assuming you have `HistoryEntry` and `Contact` models defined
import '../db/db_helper.dart'; // SQLite DBHelper

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
  late List<HistoryEntry> history;
  final TextEditingController _historyDetailController = TextEditingController();
  final TextEditingController _gradeController = TextEditingController();
  final TextEditingController _occupationController = TextEditingController();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  DateTime? _selectedDate;
  String? _selectedGrade;

  // Grade options
  final List<String> _allGradeOptions = [
    'None',
    '1', '2', '3', '4', '5', '6',
    '7', '8',
    '9', '10', '11', '12',
    'Freshman', 'Sophomore', 'Junior', 'Senior',
    'Graduate School', 'PhD', 'Postdoctoral',
  ];

  @override
  void initState() {
    super.initState();
    history = widget.contact.history ?? [];
    _selectedGrade = _allGradeOptions.contains(widget.contact.grade)
        ? widget.contact.grade
        : _allGradeOptions.first; // Default to the first grade option
    _occupationController.text = widget.contact.occupation ?? '';
    _firstNameController.text = widget.contact.firstName ?? '';
    _middleNameController.text = widget.contact.middleName ?? '';
    _lastNameController.text = widget.contact.lastName ?? '';
  }

  @override
  void dispose() {
    _historyDetailController.dispose();
    _gradeController.dispose();
    _occupationController.dispose();
    _firstNameController.dispose();
    _middleNameController.dispose();
    _lastNameController.dispose();
    super.dispose();
  }

  Future<void> _updateContact() async {
    final updatedContact = widget.contact.copyWith(
      firstName: _firstNameController.text.trim(),
      middleName: _middleNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      grade: _selectedGrade ?? _allGradeOptions.first,
      occupation: _occupationController.text.trim(),
    );

    await DBHelper().updateContact(updatedContact);

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contact updated successfully!')),
    );
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
                Navigator.pop(context);
                Navigator.pop(context);
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
          builder: (context, setStateDialog) {
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
                      final updatedHistory = List<HistoryEntry>.from(history)..add(newEntry);

                      // Create an updated contact
                      final updatedContact = widget.contact.copyWith(history: updatedHistory);

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
                        const SnackBar(content: Text('Please fill in all fields.')),
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
      widget.contact.firstName,
      widget.contact.middleName,
      widget.contact.lastName,
    ].where((name) => name != null && name.trim().isNotEmpty).join(' ');

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
            _buildEditableSection(
              title: 'First Name',
              controller: _firstNameController,
              hintText: 'Enter first name',
            ),
            _buildEditableSection(
              title: 'Middle Name',
              controller: _middleNameController,
              hintText: 'Enter middle name (optional)',
            ),
            _buildEditableSection(
              title: 'Last Name',
              controller: _lastNameController,
              hintText: 'Enter last name',
            ),
            _buildGradeDropdown(),
            _buildEditableSection(
              title: 'Occupation',
              controller: _occupationController,
              hintText: 'Enter occupation',
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

  Widget _buildEditableSection({
    required String title,
    required TextEditingController controller,
    required String hintText,
  }) {
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
        TextField(
          controller: controller,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(
            hintText: hintText,
            border: const OutlineInputBorder(),
          ),
        ),
        const Divider(),
      ],
    );
  }

  Widget _buildGradeDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: const Text(
            'Grade',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
        ),
        DropdownButtonFormField<String>(
          value: _selectedGrade,
          items: _allGradeOptions
              .map((grade) => DropdownMenuItem(
            value: grade,
            child: Text(grade),
          ))
              .toList(),
          onChanged: (value) {
            setState(() {
              _selectedGrade = value;
            });
          },
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            contentPadding: EdgeInsets.symmetric(horizontal: 12),
          ),
        ),
        const Divider(),
      ],
    );
  }
}