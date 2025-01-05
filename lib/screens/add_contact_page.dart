import 'package:flutter/material.dart';

/// Add Contact page with a form for all fields in the Contact class
class AddContactPage extends StatelessWidget {
  AddContactPage({super.key});

  final _formKey = GlobalKey<FormState>();
  final TextEditingController _firstNameController = TextEditingController();
  final TextEditingController _middleNameController = TextEditingController();
  final TextEditingController _lastNameController = TextEditingController();
  final TextEditingController _gradeController = TextEditingController();
  final TextEditingController _occupationController = TextEditingController();
  final TextEditingController _historyController = TextEditingController();
  final TextEditingController _relationshipKeyController = TextEditingController();
  final TextEditingController _relationshipValueController = TextEditingController();

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
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _firstNameController,
                      decoration: const InputDecoration(labelText: 'First Name'),
                      validator: (value) => value == null || value.isEmpty ? 'Enter first name' : null,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _middleNameController,
                      decoration: const InputDecoration(labelText: 'Middle Name (Optional)'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _lastNameController,
                      decoration: const InputDecoration(labelText: 'Last Name'),
                      validator: (value) => value == null || value.isEmpty ? 'Enter last name' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _gradeController,
                decoration: const InputDecoration(labelText: 'Grade (Optional)'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _occupationController,
                decoration: const InputDecoration(labelText: 'Occupation (Optional)'),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _historyController,
                decoration: const InputDecoration(labelText: 'History Entry (Optional)'),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _relationshipKeyController,
                      decoration: const InputDecoration(labelText: 'Related Contact ID'),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextFormField(
                      controller: _relationshipValueController,
                      decoration: const InputDecoration(labelText: 'Relationship Type'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: () {
                  if (_formKey.currentState!.validate()) {
                    final newContact = {
                      'firstName': _firstNameController.text,
                      'middleName': _middleNameController.text,
                      'lastName': _lastNameController.text,
                      'grade': _gradeController.text,
                      'occupation': _occupationController.text,
                      'history': _historyController.text.isNotEmpty ? [_historyController.text] : [],
                      'relationships': _relationshipKeyController.text.isNotEmpty &&
                          _relationshipValueController.text.isNotEmpty
                          ? {_relationshipKeyController.text: _relationshipValueController.text}
                          : {},
                    };
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Contact saved: ${newContact['firstName']} ${newContact['lastName']}')),
                    );
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
