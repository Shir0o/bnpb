import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../models/contact.dart';

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
  }

  Future<void> _saveContact() async {
    if (_formKey.currentState!.validate()) {
      // Unfocus the keyboard
      FocusScope.of(context).unfocus();

      final newContact = Contact(
        id: DateTime.now().toIso8601String(),
        firstName: _firstNameController.text.trim(),
        middleName: _middleNameController.text.trim(),
        lastName: _lastNameController.text.trim(),
        grade: _selectedGrade,
        occupation: _occupationController.text.trim().isEmpty
            ? null
            : _occupationController.text.trim(),
        history: [], // History field is empty since functionality is removed
      );

      final dbHelper = DBHelper();
      await dbHelper.insertContact(newContact);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Contact saved: ${newContact.fullName}'),
          backgroundColor: Colors.green,
        ),
      );

      // Clear form
      _formKey.currentState?.reset();
      _firstNameController.clear();
      _middleNameController.clear();
      _lastNameController.clear();
      _occupationController.clear();
      setState(() {
        _selectedGrade = null;
      });
    }
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

              // Save Contact button
              ElevatedButton(
                onPressed: () async {
                  await _saveContact();
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