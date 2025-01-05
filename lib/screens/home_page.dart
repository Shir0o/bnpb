import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<Map<String, dynamic>> _contacts = []; // List to hold contact data

  @override
  void initState() {
    super.initState();
    _loadContacts(); // Load contacts when the page initializes
  }

  /// Load contacts from shared preferences
  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedContacts = prefs.getString('contacts');

    if (storedContacts != null) {
      final List<Map<String, dynamic>> contacts =
      List<Map<String, dynamic>>.from(json.decode(storedContacts));
      setState(() {
        _contacts = contacts;
      });
    }
  }

  /// Map relationship IDs to contact names
  String _getFullNameById(String id) {
    final contact = _contacts.firstWhere(
          (c) => c['id'] == id,
      orElse: () => {}, // Return an empty map instead of null
    );

    if (contact.isNotEmpty) {
      return _constructFullName(
        contact['firstName'],
        contact['middleName'],
        contact['lastName'],
      );
    }
    return 'Unknown'; // Fallback if the contact is not found
  }

  /// Construct the full name without extra spaces
  String _constructFullName(String firstName, String? middleName, String lastName) {
    return [
      firstName.trim(),
      if (middleName != null && middleName.trim().isNotEmpty) middleName.trim(),
      lastName.trim(),
    ].join(' ');
  }

  /// Show detailed information about a contact
  void _showContactDetails(BuildContext context, Map<String, dynamic> contact) {
    final fullName = _constructFullName(
      contact['firstName'],
      contact['middleName'],
      contact['lastName'],
    );

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(fullName),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (contact['grade'] != null)
                Text('Grade: ${contact['grade']}'),
              if (contact['occupation'] != null)
                Text('Occupation: ${contact['occupation']}'),
              if (contact['history'] != null && contact['history'].isNotEmpty)
                Text('History: ${contact['history'].join(', ')}'),
              if (contact['relationships'] != null &&
                  contact['relationships'].isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Relationships:'),
                    ...contact['relationships'].entries.map((entry) {
                      final relatedContactName = _getFullNameById(entry.key);
                      return Text(
                        '${relatedContactName}: ${entry.value}',
                        style: const TextStyle(fontSize: 14),
                      );
                    }).toList(),
                  ],
                ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
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
        title: const Text('Home Page'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _contacts.isEmpty
            ? const Center(
          child: Text(
            'No contacts available. Add some contacts!',
            style: TextStyle(fontSize: 18),
          ),
        )
            : ListView.builder(
          itemCount: _contacts.length,
          itemBuilder: (context, index) {
            final contact = _contacts[index];
            final fullName = _constructFullName(
              contact['firstName'],
              contact['middleName'],
              contact['lastName'],
            );
            return ListTile(
              title: Text(fullName),
              subtitle: Text(contact['grade'] != null
                  ? 'Grade: ${contact['grade']}'
                  : contact['occupation'] != null
                  ? 'Occupation: ${contact['occupation']}'
                  : 'No additional details'),
              onTap: () {
                // Display detailed info for the contact
                _showContactDetails(context, contact);
              },
            );
          },
        ),
      ),
    );
  }
}
