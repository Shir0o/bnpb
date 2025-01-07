import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart'; // For date formatting
import 'package:shared_preferences/shared_preferences.dart';
import '../models/contact.dart'; // Assuming you have `HistoryEntry` and `Contact` models defined

class ContactDetailsPage extends StatefulWidget {
  final Map<String, dynamic> contact;
  final String Function(String id) getFullNameById;
  final VoidCallback onDelete;

  const ContactDetailsPage({
    super.key,
    required this.contact,
    required this.getFullNameById,
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

  // Grade options
  final List<String> _allGradeOptions = [
    'None',
    '1', '2', '3', '4', '5', '6',
    '7', '8',
    '9', '10', '11', '12',
    'Freshman', 'Sophomore', 'Junior', 'Senior',
    'Graduate School', 'PhD', 'Postdoctoral',
  ];

  String? _selectedGrade;

  @override
  void initState() {
    super.initState();
    // Initialize the history list from the contact data
    history = widget.contact['history'] != null
        ? (widget.contact['history'] as List<dynamic>)
        .map((entry) => HistoryEntry.fromMap(entry as Map<String, dynamic>))
        .toList()
        : [];

    // Initialize grade and occupation controllers
    _selectedGrade = _allGradeOptions.contains(widget.contact['grade'])
        ? widget.contact['grade']
        : _allGradeOptions.first; // Default to the first grade option if null or invalid
    _occupationController.text = widget.contact['occupation'] ?? '';

    _firstNameController.text = widget.contact['firstName'] ?? '';
    _middleNameController.text = widget.contact['middleName'] ?? '';
    _lastNameController.text = widget.contact['lastName'] ?? '';
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

  String _capitalize(String input) {
    if (input.isEmpty) return input;
    return input[0].toUpperCase() + input.substring(1);
  }

  Future<void> _updateContact() async {
    setState(() {
      widget.contact['firstName'] = _capitalize(_firstNameController.text.trim());
      widget.contact['middleName'] = _capitalize(_middleNameController.text.trim());
      widget.contact['lastName'] = _capitalize(_lastNameController.text.trim());
      widget.contact['grade'] = _selectedGrade ?? _allGradeOptions.first; // Ensure non-null value
      widget.contact['occupation'] = _capitalize(_occupationController.text.trim());
    });

    // Persist changes to SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final contactsJson = prefs.getString('contacts');
    final List<Map<String, dynamic>> contacts = contactsJson != null
        ? List<Map<String, dynamic>>.from(
      jsonDecode(contactsJson) as List<dynamic>,
    )
        : [];

    final updatedContacts = contacts.map((contact) {
      if (contact['id'] == widget.contact['id']) {
        return widget.contact;
      }
      return contact;
    }).toList();

    await prefs.setString('contacts', jsonEncode(updatedContacts));

    // Show success Snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contact updated successfully!')),
    );
  }

  Widget _buildGradeDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8.0),
          child: Text(
            'Grade',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
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
              onPressed: () {
                Navigator.pop(context);
                widget.onDelete();
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

  void _deleteHistoryEntry(int index) async {
    setState(() {
      final removedEntry = history.removeAt(index);
      if (widget.contact['history'] != null) {
        widget.contact['history'].removeWhere((entry) {
          return entry['date'] == removedEntry.date.toIso8601String() &&
              entry['detail'] == removedEntry.detail;
        });
      }
    });

    final prefs = await SharedPreferences.getInstance();
    final contactsJson = prefs.getString('contacts');
    final List<Map<String, dynamic>> contacts = contactsJson != null
        ? List<Map<String, dynamic>>.from(
      jsonDecode(contactsJson) as List<dynamic>,
    )
        : [];

    final updatedContacts = contacts.map((contact) {
      if (contact['id'] == widget.contact['id']) {
        return widget.contact;
      }
      return contact;
    }).toList();

    await prefs.setString('contacts', jsonEncode(updatedContacts));
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
                      setState(() {
                        final newEntry = HistoryEntry(
                          date: _selectedDate!,
                          detail: detail,
                        );
                        history.add(newEntry);

                        if (widget.contact['history'] != null) {
                          widget.contact['history'].add(newEntry.toMap());
                        } else {
                          widget.contact['history'] = [newEntry.toMap()];
                        }
                      });

                      final prefs = await SharedPreferences.getInstance();
                      final contactsJson = prefs.getString('contacts');
                      final List<Map<String, dynamic>> contacts = contactsJson != null
                          ? List<Map<String, dynamic>>.from(
                        jsonDecode(contactsJson) as List<dynamic>,
                      )
                          : [];

                      final updatedContacts = contacts.map((contact) {
                        if (contact['id'] == widget.contact['id']) {
                          return widget.contact;
                        }
                        return contact;
                      }).toList();

                      await prefs.setString('contacts', jsonEncode(updatedContacts));

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
      widget.contact['firstName'],
      if (widget.contact['middleName'] != null) widget.contact['middleName'],
      widget.contact['lastName'],
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
            _buildSection(
              title: 'History',
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: history.isNotEmpty
                    ? history.asMap().entries.map((entry) {
                  final index = entry.key;
                  final historyEntry = entry.value;
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          '- ${historyEntry.detail} (${DateFormat.yMMMd().format(historyEntry.date)})',
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          _deleteHistoryEntry(index);
                        },
                      ),
                    ],
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
        const Divider(),
      ],
    );
  }
}