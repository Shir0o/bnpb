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
  // List to hold all contact data
  List<Map<String, dynamic>> _contacts = [];
  // List to hold filtered (search) results
  List<Map<String, dynamic>> _filteredContacts = [];

  // Controller for the search bar
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadContacts(); // Load contacts when the page initializes

    // Re-filter whenever the user types something
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  /// Callback that runs every time the search text changes
  void _onSearchChanged() {
    final query = _searchController.text.toLowerCase().trim();
    setState(() {
      // Filter the master list of contacts
      _filteredContacts = _contacts.where((contact) {
        final fullName = _constructFullName(
          contact['firstName'],
          contact['middleName'],
          contact['lastName'],
        ).toLowerCase();
        return fullName.contains(query);
      }).toList();
    });
  }

  /// Load contacts from shared preferences
  Future<void> _loadContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final String? storedContacts = prefs.getString('contacts');

    if (storedContacts != null) {
      final List<Map<String, dynamic>> contacts =
      List<Map<String, dynamic>>.from(json.decode(storedContacts));

      setState(() {
        // Sort by full name
        _contacts = contacts
          ..sort((a, b) {
            final nameA = _constructFullName(a['firstName'], a['middleName'], a['lastName']).toLowerCase();
            final nameB = _constructFullName(b['firstName'], b['middleName'], b['lastName']).toLowerCase();
            return nameA.compareTo(nameB);
          });

        // Initially, filteredContacts = all contacts
        _filteredContacts = List.from(_contacts);
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

            // After deleting, also reapply the current search filter
            _onSearchChanged();
          },
        ),
      ),
    ).then((_) async {
      // Reload contacts after navigating back
      await _loadContacts();
      // Reapply the search filter with the updated contact list
      _onSearchChanged();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Page'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(kToolbarHeight),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: const InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: _filteredContacts.isEmpty
            ? const Center(
          child: Text(
            'No contacts available. Add some contacts!',
            style: TextStyle(fontSize: 18),
          ),
        )
            : ListView.builder(
          itemCount: _filteredContacts.length,
          itemBuilder: (context, index) {
            final contact = _filteredContacts[index];
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