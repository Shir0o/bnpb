import 'package:flutter/material.dart';
import 'add_contact_page.dart';
import '../models/contact.dart';

/// Home page displaying the list of contacts
class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final List<Contact> _contacts = []; // List of contacts

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('BNPB - My Contacts'), // Page title
      ),
      body: _contacts.isEmpty
          ? const Center(
        child: Text('No contacts added yet.'),
      )
          : ListView.builder(
        itemCount: _contacts.length,
        itemBuilder: (context, index) {
          final contact = _contacts[index];
          return ListTile(
            title: Text(contact.fullName), // Display full name
            subtitle: Text(contact.grade ?? contact.occupation ?? 'No details'), // Display grade or occupation
            onTap: () {
              // Navigate to contact details page (to be implemented)
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          // Navigate to add contact page and wait for the result
          final newContact = await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AddContactPage()),
          );
          if (newContact != null && newContact is Contact) {
            setState(() {
              _contacts.add(newContact); // Add the new contact to the list
            });
          }
        },
        child: const Icon(Icons.add), // Floating action button icon
      ),
    );
  }
}
