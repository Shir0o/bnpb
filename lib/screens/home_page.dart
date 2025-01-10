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
      // Open the file picker for JSON files
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );

      // If no file is picked, return early
      if (result == null || result.files.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No file selected.')),
        );
        return;
      }

      // Get the file path
      final filePath = result.files.single.path;
      if (filePath == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Invalid file.')),
        );
        return;
      }

      // Read and decode the file contents
      final file = File(filePath);
      final fileContent = await file.readAsString();
      final List<dynamic> jsonData = jsonDecode(fileContent);

      // Convert the JSON data back into a list of contacts
      final restoredContacts = jsonData
          .map((contactMap) => Contact.fromMap(contactMap as Map<String, dynamic>))
          .toList();

      // Insert contacts into the database
      for (final contact in restoredContacts) {
        await _dbHelper.insertContact(contact);
      }

      // Refresh the contact list
      await _fetchContacts();

      // Show success message
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Contacts restored successfully!')),
      );
    } catch (e) {
      // Handle any errors
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
      // Refresh contacts when returning to the page
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
            DrawerHeader(
              margin: EdgeInsets.zero,
              padding: EdgeInsets.all(16),
              decoration: const BoxDecoration(
                color: Colors.blue,
              ),
              child: const Text(
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
                Navigator.of(context).pop(); // Close the drawer
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
            padding: const EdgeInsets.all(8.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8.0),
                ),
                prefixIcon: const Icon(Icons.search),
              ),
              autofocus: false,
            ),
          ),
          Expanded(
            child: _filteredContacts.isEmpty
                ? const Center(child: Text('No contacts available.'))
                : ListView.builder(
              itemCount: _filteredContacts.length,
              itemBuilder: (context, index) {
                final contact = _filteredContacts[index];
                return ListTile(
                  title: Text(contact.fullName),
                  onTap: () => _navigateToContactDetails(contact),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}