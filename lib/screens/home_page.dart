import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

import 'contact_details_page.dart';

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

  /// Save updated contacts to shared preferences
  Future<void> _saveContacts() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('contacts', json.encode(_contacts));
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

  void _navigateToContactDetails(BuildContext context, Map<String, dynamic> contact) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ContactDetailsPage(
          contact: contact,
          getFullNameById: _getFullNameById,
          onDelete: () async {
            setState(() {
              _contacts.remove(contact); // Remove the contact from the list
            });
            await _saveContacts(); // Save changes to shared preferences
          },
        ),
      ),
    ).then((_) async {
      // Reload contacts after navigating back
      await _loadContacts();
    });
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
              onTap: () {
                // Display detailed info for the contact
                _navigateToContactDetails(context, contact);
              },
            );
          },
        ),
      ),
    );
  }
}