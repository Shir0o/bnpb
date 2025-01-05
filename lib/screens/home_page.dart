import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

/// Home page with a list of saved contacts and a refresh button
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Page'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Contacts',
            onPressed: _refreshContacts, // Refresh contacts when pressed
          ),
        ],
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
            return ListTile(
              title: Text(contact['firstName'] +
                  ' ' +
                  (contact['middleName'] ?? '') +
                  ' ' +
                  contact['lastName']),
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

  /// Refresh contacts
  Future<void> _refreshContacts() async {
    await _loadContacts(); // Reload contacts
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Contacts refreshed')),
    );
  }

  /// Show detailed information about a contact
  void _showContactDetails(
      BuildContext context, Map<String, dynamic> contact) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(
              '${contact['firstName']} ${contact['middleName'] ?? ''} ${contact['lastName']}'),
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
                Text(
                  'Relationships: ${contact['relationships'].entries.map((e) => '${e.key}: ${e.value}').join(', ')}',
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
}
