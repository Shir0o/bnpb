import 'package:flutter/material.dart';
import '../models/contact.dart';

/// Page for adding a new contact
class AddContactPage extends StatefulWidget {
  const AddContactPage({Key? key}) : super(key: key);

  @override
  State<AddContactPage> createState() => _AddContactPageState();
}

class _AddContactPageState extends State<AddContactPage> {
  final _formKey = GlobalKey<FormState>(); // Form key for validation

  // Form field controllers
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _gradeController = TextEditingController();
  final TextEditingController _occupationController = TextEditingController();

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
              // Input field for first name
              TextFormField(
                controller: _firstNameController,
                decoration: const InputDecoration(labelText: 'First Name'),
                validator: (value) => value == null || value.isEmpty ? 'Enter a first name' : null,
              ),
              // Input field for middle name
              TextFormField(
                controller: _middleNameController,
                decoration: const InputDecoration(labelText: 'Middle Name (Optional)'),
              ),
              // Input field for last name
              TextFormField(
                controller: _lastNameController,
                decoration: const InputDecoration(labelText: 'Last Name'),
                validator: (value) => value == null || value.isEmpty ? 'Enter a last name' : null,
              ),
              // Input field for grade
              TextFormField(
                controller: _gradeController,
                decoration: const InputDecoration(labelText: 'Grade (Optional)'),
              ),
              // Input field for occupation
              TextFormField(
                controller: _occupationController,
                decoration: const InputDecoration(labelText: 'Occupation (Optional)'),
              ),
              const SizedBox(height: 20),
              // Save button
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    final newContact = Contact(
                      id: DateTime.now().toIso8601String(), // Generate unique ID
                      firstName: _firstNameController.text,
                      middleName: _middleNameController.text,
                      lastName: _lastNameController.text,
                      grade: _gradeController.text.isNotEmpty ? _gradeController.text : null,
                      occupation: _occupationController.text.isNotEmpty ? _occupationController.text : null,
                      history: [], // Default to empty history
                      relationships: {}, // Default to empty relationships
                    );
                    Navigator.pop(context, newContact); // Return the new contact
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
