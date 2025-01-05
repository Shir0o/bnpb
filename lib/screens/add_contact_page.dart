import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

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
  final TextEditingController _historyController = TextEditingController();
  final TextEditingController _relationshipValueController = TextEditingController();

  // Data lists and selected values
  List<Map<String, dynamic>> _contacts = [];
  String? _selectedGrade;
  String? _selectedContactId;

  /// Categorized grade options
  final Map<String, List<String>> _categorizedGradeOptions = {
    'Elementary': ['1', '2', '3', '4', '5', '6'],
    'Junior High': ['7', '8'],
    'High School': ['9', '10', '11', '12'],
    'College': ['Freshman', 'Sophomore', 'Junior', 'Senior'],
    'Beyond': ['Graduate School', 'PhD', 'Postdoctoral'],
  };

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

  /// Builds dropdown items with category labels for the grade field
  List<DropdownMenuItem<String>> _buildCategorizedDropdownItems() {
    List<DropdownMenuItem<String>> items = [];

    _categorizedGradeOptions.forEach((category, grades) {
      // Add category label (disabled item)
      items.add(
        DropdownMenuItem<String>(
          enabled: false,
          child: Text(
            category,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );

      // Add grades under the category
      items.addAll(
        grades.map((grade) {
          return DropdownMenuItem<String>(
            value: grade,
            child: Padding(
              padding: const EdgeInsets.only(left: 16.0),
              child: Text(grade),
            ),
          );
        }).toList(),
      );
    });

    return items;
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
                      decoration: const InputDecoration(labelText: 'Middle Name (Optional)'),
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
              // Grade dropdown with clear suffix icon
              DropdownButtonFormField<String>(
                value: _selectedGrade,
                items: _buildCategorizedDropdownItems(),
                onChanged: (value) {
                  setState(() {
                    _selectedGrade = value;
                  });
                },
                decoration: InputDecoration(
                  labelText: 'Grade (Optional)',
                  floatingLabelBehavior: FloatingLabelBehavior.auto,
                  suffixIcon: _selectedGrade != null
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() {
                        _selectedGrade = null;
                      });
                    },
                  ) : null,
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
              // History field
              TextFormField(
                controller: _historyController,
                decoration: const InputDecoration(labelText: 'History Entry (Optional)'),
              ),
              const SizedBox(height: 16),
              // Related Contact dropdown with clear suffix icon
              DropdownButtonFormField<String>(
                value: _selectedContactId,
                items: _contacts.map((contact) {
                  final fullName = _constructFullName(
                    contact['firstName'],
                    contact['middleName'],
                    contact['lastName'],
                  );
                  return DropdownMenuItem<String>(
                    value: contact['id'],
                    child: Text(fullName),
                  );
                }).toList(),
                onChanged: (value) {
                  setState(() {
                    _selectedContactId = value;
                  });
                },
                decoration: InputDecoration(
                  labelText: 'Related Contact',
                  suffixIcon: _selectedContactId != null
                      ? IconButton(
                    icon: const Icon(Icons.clear),
                    onPressed: () {
                      setState(() {
                        _selectedContactId = null;
                      });
                    },
                  ) : null,
                ),
              ),
              const SizedBox(height: 16),

              // Relationship Type field
              TextFormField(
                controller: _relationshipValueController,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Relationship Type'),
              ),
              const SizedBox(height: 32),

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
                      'history': _historyController.text.isNotEmpty
                          ? [_historyController.text.trim()]
                          : [],
                      'relationships': _selectedContactId != null &&
                          _relationshipValueController.text.isNotEmpty
                          ? {
                        _selectedContactId!:
                        _relationshipValueController.text.trim()
                      }
                          : {},
                    };

                    // Save the contact
                    await _saveContact(newContact);

                    // Clear form fields
                    _formKey.currentState?.reset();
                    _firstNameController.clear();
                    _middleNameController.clear();
                    _lastNameController.clear();
                    _occupationController.clear();
                    _historyController.clear();
                    _relationshipValueController.clear();
                    setState(() {
                      _selectedGrade = null;
                      _selectedContactId = null;
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
