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
  final TextEditingController _locationController = TextEditingController();

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
        lastName: _lastNameController.text.trim().isEmpty
            ? null
            : _lastNameController.text.trim(),
        history: [],
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
      _locationController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add Contact'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Form(
          key: _formKey,
          child: Column(
            children: [
              // First Name field (wrapped in a Card)
              Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: TextFormField(
                    controller: _firstNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _buildInputDecoration('First Name'),
                    validator: (value) => value == null || value.isEmpty
                        ? 'Enter first name'
                        : null,
                  ),
                ),
              ),

              // Middle Name field (wrapped in a Card)
              Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: TextFormField(
                    controller: _middleNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _buildInputDecoration('Middle Name (Optional)'),
                  ),
                ),
              ),

              // Last Name field (wrapped in a Card)
              Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: TextFormField(
                    controller: _lastNameController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _buildInputDecoration('Last Name (Optional)'),
                    validator: (value) => null,
                  ),
                ),
              ),

              // Location field (wrapped in a Card)
              Card(
                elevation: 2,
                margin: const EdgeInsets.only(bottom: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                  child: TextFormField(
                    controller: _locationController,
                    textCapitalization: TextCapitalization.words,
                    decoration: _buildInputDecoration('Location (Optional)'), // Updated label
                  ),
                ),
              ),

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

  /// Helper function to apply a consistent OutlineInputBorder style
  InputDecoration _buildInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: Colors.blue, width: 2),
      ),
    );
  }
}