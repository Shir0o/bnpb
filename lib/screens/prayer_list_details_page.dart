import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/prayer_list.dart';
import '../services/contact_service.dart';
import '../widgets/contact_selection_sheet.dart';

class PrayerListDetailsPage extends StatefulWidget {
  const PrayerListDetailsPage({super.key, required this.listId});

  final String listId;

  @override
  State<PrayerListDetailsPage> createState() => _PrayerListDetailsPageState();
}

class _PrayerListDetailsPageState extends State<PrayerListDetailsPage> {
  final DBHelper _dbHelper = DBHelper();
  PrayerList? _list;
  List<Contact> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    final list = await _dbHelper.getPrayerList(widget.listId);
    if (list != null) {
      final contacts = <Contact>[];
      for (final id in list.contactIds) {
        final contact = await _dbHelper.getContactById(id);
        if (contact != null) {
          contacts.add(contact);
        }
      }
      if (mounted) {
        setState(() {
          _list = list;
          _contacts = contacts;
          _isLoading = false;
        });
      }
    } else {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _addContacts() async {
    final currentIds = _list?.contactIds.toSet() ?? {};

    final selectedIds = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ContactSelectionSheet(
        alreadySelectedIds: currentIds,
      ),
    );

    if (selectedIds != null && selectedIds.isNotEmpty) {
      for (final id in selectedIds) {
        await _dbHelper.addContactToPrayerList(widget.listId, id);
      }
      _loadData();
    }
  }

  Future<void> _removeContact(String contactId) async {
    await _dbHelper.removeContactFromPrayerList(widget.listId, contactId);
    _loadData();
  }

  Future<void> _deleteList() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete List?'),
        content: const Text(
            'This will delete the list but not the contacts themselves.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await _dbHelper.deletePrayerList(widget.listId);
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_list == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: Text('List not found')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_list!.name),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline),
            onPressed: _deleteList,
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addContacts,
        icon: const Icon(Icons.person_add),
        label: const Text('Add People'),
      ),
      body: _contacts.isEmpty
          ? Center(
              child: Text(
                'No contacts in this list yet.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Theme.of(context).colorScheme.outline,
                    ),
              ),
            )
          : ListView.builder(
              itemCount: _contacts.length,
              itemBuilder: (context, index) {
                final contact = _contacts[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(contact.firstName.isNotEmpty
                        ? contact.firstName[0]
                        : '?'),
                  ),
                  title: Text(contact.fullName),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => _removeContact(contact.id),
                  ),
                );
              },
            ),
    );
  }
}
