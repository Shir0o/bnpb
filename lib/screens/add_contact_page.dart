import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// Define HistoryEntry structure
class HistoryEntry {
  final DateTime date;
  final String detail;

  HistoryEntry({required this.date, required this.detail});

  Map<String, dynamic> toMap() {
    return {'date': date.toIso8601String(), 'detail': detail};
  }

  static HistoryEntry fromMap(Map<String, dynamic> map) {
    return HistoryEntry(
      date: DateTime.parse(map['date']),
      detail: map['detail'],
    );
  }
}

class AddContactPage extends StatefulWidget {
  const AddContactPage({super.key});

  @override
  State<AddContactPage> createState() => _AddContactPageState();
}

class _AddContactPageState extends State<AddContactPage> {
  final _formKey = GlobalKey<FormState>();

  // Controllers for text fields
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _occupationController = TextEditingController();
  final TextEditingController _historyDetailController = TextEditingController();

  // Data lists and selected values
  List<Map<String, dynamic>> _contacts = [];
  final List<HistoryEntry> _history = [];
  String? _selectedGrade;

  // Flat list of grades
  final List<String> _allGradeOptions = [
    '1', '2', '3', '4', '5', '6',
    '7', '8',
    '9', '10', '11', '12',
    'Freshman', 'Sophomore', 'Junior', 'Senior',
    'Graduate School', 'PhD', 'Postdoctoral',
  ];

  @override
  void initState() {
    super.initState();
    _loadContacts();
  }

  /// Loads existing contacts from SharedPreferences
  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedContacts = prefs.getString('contacts');

    if (storedContacts != null) {
      setState(() {
        _contacts = List<Map<String, dynamic>>.from(json.decode(storedContacts));
      });
    }
  }

  void _deleteHistoryEntry(int index) {
    setState(() {
      _history.removeAt(index); // Remove the entry from the list
    });
  }

  /// Saves a new or updated contact to SharedPreferences
  Future<void> _saveContact(Map<String, dynamic> contact) async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedContacts = prefs.getString('contacts');
    List<Map<String, dynamic>> contacts = [];

    if (storedContacts != null) {
      contacts = List<Map<String, dynamic>>.from(json.decode(storedContacts));
    }

    // Add the new contact
    contacts.add(contact);

    // Save updated list to SharedPreferences
    await prefs.setString('contacts', json.encode(contacts));

    // Show success message
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Contact saved successfully: ${contact['firstName']} ${contact['lastName']}',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  /// Constructs the full name, omitting middle if empty
  String _constructFullName(String firstName, String? middleName, String lastName) {
    return [
      firstName.trim(),
      if (middleName != null && middleName.trim().isNotEmpty) middleName.trim(),
      lastName.trim(),
    ].join(' ');
  }

  /// Builds dropdown items with real grade options
  List<DropdownMenuItem<String>> _buildGradeDropdownItems() {
    return _allGradeOptions.map((grade) {
      return DropdownMenuItem<String>(
        value: grade,
        child: Text(grade),
      );
    }).toList();
  }

  void _addHistoryEntry() {
    DateTime? selectedDate;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add History Entry'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _historyDetailController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                  labelText: 'History Detail',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text('Select Date:'),
                  TextButton(
                    onPressed: () async {
                      final pickedDate = await showDatePicker(
                        context: context,
                        initialDate: DateTime.now(),
                        firstDate: DateTime(2000),
                        lastDate: DateTime(2100),
                      );
                      if (pickedDate != null) {
                        setState(() {
                          selectedDate = pickedDate;
                        });
                      }
                    },
                    child: const Text('Choose Date'),
                  ),
                ],
              ),
              if (selectedDate != null)
                Text(
                  'Selected Date: ${selectedDate!.toLocal().toString().split(' ')[0]}',
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(context); // Cancel and close the dialog
              },
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final detail = _historyDetailController.text.trim();
                if (detail.isNotEmpty && selectedDate != null) {
                  setState(() {
                    _history.add(HistoryEntry(date: selectedDate!, detail: detail));
                    _historyDetailController.clear();
                  });
                  Navigator.pop(context); // Close the dialog after adding
                } else {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Please provide both detail and date.'),
                      backgroundColor: Colors.red,
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
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Contact'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: ListView(
            children: [
              // Row for First, Middle, Last name
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'First Name'),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Enter first name'
                          : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _middleNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration:
                      const InputDecoration(labelText: 'Middle Name (Optional)'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameController,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(labelText: 'Last Name'),
                      validator: (value) => value == null || value.isEmpty
                          ? 'Enter last name'
                          : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // Grade dropdown
              DropdownButtonFormField<String>(
                value: _selectedGrade,
                items: _buildGradeDropdownItems(),
                onChanged: (value) {
                  setState(() {
                    _selectedGrade = value;
                  });
                },
                decoration: InputDecoration(
                  labelText: 'Grade (Optional)',
                  suffixIcon: _selectedGrade != null
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() {
                        _selectedGrade = null;
                      });
                    },
                  )
                      : null,
                ),
              ),
              const SizedBox(height: 16),

              // Occupation field
              TextFormField(
                controller: _occupationController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Occupation (Optional)'),
              ),
              const SizedBox(height: 16),

              // History section
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'History Entries',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      ElevatedButton(
                        onPressed: _addHistoryEntry,
                        child: const Text('Add History Entry'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ..._history.asMap().entries.map((entry) {
                    final index = entry.key;
                    final historyEntry = entry.value;
                    return ListTile(
                      title: Text(historyEntry.detail),
                      subtitle: Text(
                        historyEntry.date.toLocal().toString().split(' ')[0],
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete, color: Colors.red),
                        onPressed: () {
                          _deleteHistoryEntry(index);
                        },
                      ),
                    );
                  }),
                ],
              ),
              const SizedBox(height: 16),

              // Save Contact button
              ElevatedButton(
                onPressed: () async {
                  if (_formKey.currentState!.validate()) {
                    // Build contact map
                    final newContact = {
                      'id': DateTime.now().toIso8601String(),
                      'firstName': _firstNameController.text.trim(),
                      'middleName': _middleNameController.text.trim(),
                      'lastName': _lastNameController.text.trim(),
                      'grade': _selectedGrade,
                      'occupation': _occupationController.text.isNotEmpty
                          ? _occupationController.text.trim()
                          : null,
                      'history': _history.map((entry) => entry.toMap()).toList(),
                    };

                    // Save the contact
                    await _saveContact(newContact);

                    // Clear form fields
                    _formKey.currentState?.reset();
                    _firstNameController.clear();
                    _middleNameController.clear();
                    _lastNameController.clear();
                    _occupationController.clear();
                    _historyDetailController.clear();
                    setState(() {
                      _selectedGrade = null;
                      _history.clear();
                    });
                  }
                },
                child: const Text('Save Contact'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}