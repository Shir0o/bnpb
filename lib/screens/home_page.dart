import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import 'attendance_page.dart';
import 'contact_details_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final DBHelper _dbHelper = DBHelper();
  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fetchContacts();
    _searchController.addListener(_filterContacts);
  }

  Future<void> _fetchContacts() async {
    final contacts = await _dbHelper.getContacts();
    setState(() {
      _contacts = contacts
        ..sort((a, b) {
          final lastNameComparison =
          a.lastName.toLowerCase().compareTo(b.lastName.toLowerCase());
          if (lastNameComparison != 0) {
            return lastNameComparison;
          }
          return a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase());
        });
      _filteredContacts = List.from(_contacts);
    });
  }

  /// Groups the given list of contacts by their location.
  /// If a contact’s location is empty or null, assign "Unknown" as the location.
  Map<String, List<Contact>> _groupContactsByLocation(List<Contact> contacts) {
    final grouped = <String, List<Contact>>{};

    for (var contact in contacts) {
      final location =
      (contact.location != null && contact.location!.isNotEmpty)
          ? contact.location!
          : 'Unknown';
      if (!grouped.containsKey(location)) {
        grouped[location] = [];
      }
      grouped[location]!.add(contact);
    }

    return grouped;
  }

  Widget _buildGroupedContactsList() {
    // Group the filtered contacts by location
    final groupedContacts = _groupContactsByLocation(_filteredContacts);

    // Build an ExpansionTile for each location
    return ListView(
      children: groupedContacts.entries.map((entry) {
        final location = entry.key;
        final contactsInLocation = entry.value;

        return ExpansionTile(
          title: Text(location),
          initiallyExpanded: true,
          children: contactsInLocation.map((contact) {
            return ListTile(
              leading: CircleAvatar(
                child: Text(contact.fullName.isNotEmpty
                    ? contact.fullName[0]
                    : '?'),
              ),
              title: Text(contact.fullName),
              onTap: () => _navigateToContactDetails(contact),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  void _filterContacts() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      _filteredContacts = _contacts
          .where((contact) =>
      contact.fullName.toLowerCase().contains(query) ||
          (contact.occupation?.toLowerCase() ?? '').contains(query) ||
          (contact.grade?.toLowerCase() ?? '').contains(query))
          .toList();
    });
  }

  Future<void> _exportContactsToFile() async {
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/contacts.json');
      final data = _contacts.map((contact) => contact.toMap()).toList();
      await file.writeAsString(jsonEncode(data));

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Here is the exported contacts file.',
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to export contacts: $e')),
      );
    }
  }

  Future<void> _restoreContactsFromFile() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      if (result == null || result.files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No file selected.')),
        );
        return;
      }

      final filePath = result.files.single.path;
      if (filePath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid file.')),
        );
        return;
      }

      final file = File(filePath);
      final fileContent = await file.readAsString();
      final List<dynamic> jsonData = jsonDecode(fileContent);

      final restoredContacts = jsonData
          .map((contactMap) => Contact.fromMap(contactMap as Map<String, dynamic>))
          .toList();

      for (final contact in restoredContacts) {
        await _dbHelper.insertContact(contact);
      }

      await _fetchContacts();

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contacts restored successfully!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to restore contacts: $e')),
      );
    }
  }

  Future<void> _deleteContact(String id) async {
    await _dbHelper.deleteContact(id);
    _fetchContacts();
  }

  Future<void> _updateContact(Contact contact) async {
    await _dbHelper.updateContact(contact);
    _fetchContacts();
  }

  void _navigateToContactDetails(Contact contact) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => ContactDetailsPage(
          contact: contact,
          onDelete: () {
            _deleteContact(contact.id);
          },
        ),
      ),
    )
        .then((_) {
      _fetchContacts();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _exportContactsToFile,
          ),
          IconButton(
            icon: const Icon(Icons.restore),
            onPressed: _restoreContactsFromFile,
          ),
        ],
      ),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            const DrawerHeader(
              margin: EdgeInsets.zero,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.blue, Colors.lightBlueAccent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Text(
                'Menu',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.contacts),
              title: const Text('Contacts'),
              onTap: () {
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.event_note),
              title: const Text('Attendance'),
              onTap: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const AttendancePage(),
                  ),
                );
              },
            ),
          ],
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16.0),
                ),
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search contacts...',
              ),
            ),
          ),
          Expanded(
            child: _filteredContacts.isEmpty
                ? const Center(child: Text('No contacts available.'))
                : _buildGroupedContactsList(),
          ),
        ],
      ),
    );
  }
}