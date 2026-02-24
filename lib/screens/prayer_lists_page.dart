import 'dart:async';
import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/prayer_list.dart';
import '../services/contact_service.dart';
import '../services/reminder_coordinator.dart';
import '../widgets/contact_selection_sheet.dart';
import 'contact_details_page.dart';

class PrayerListPage extends StatefulWidget {
  const PrayerListPage({super.key});

  @override
  State<PrayerListPage> createState() => _PrayerListPageState();
}

class _PrayerListPageState extends State<PrayerListPage> {
  final DBHelper _dbHelper = DBHelper();
  PrayerList? _list;
  List<Contact> _contacts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _ensureDefaultList();
  }

  Future<void> _ensureDefaultList() async {
    setState(() => _isLoading = true);

    // Check for existing lists
    final lists = await _dbHelper.getPrayerLists();
    PrayerList targetList;

    if (lists.isEmpty) {
      // Create default list if none exists
      targetList = PrayerList.create(
        name: 'My Prayer List',
        description: 'People I am praying for',
      );
      await _dbHelper.insertPrayerList(targetList);
    } else {
      // Use the first available list
      targetList = lists.first;
    }

    // Load contacts for this list
    await _loadListContacts(targetList);
  }

  Future<void> _loadListContacts(PrayerList list) async {
    // Re-fetch list to get up-to-date member IDs if we just grabbed it from a list query
    // (though getPrayerLists actually returns populates IDs, refreshing specific list is safer)
    final freshList = await _dbHelper.getPrayerList(list.id);
    if (freshList == null) return; // Should not happen

    if (freshList.contactIds.isEmpty) {
      if (mounted) {
        setState(() {
          _list = freshList;
          _contacts = [];
          _isLoading = false;
        });
      }
      return;
    }

    final loadedContacts =
        await _dbHelper.getContacts(contactIds: freshList.contactIds);

    // Optimization: Batch fetch all contacts at once instead of N+1 queries.
    // Re-assemble in the correct order based on the list definition.
    final contactMap = {for (final c in loadedContacts) c.id: c};
    final contacts = <Contact>[];
    for (final id in freshList.contactIds) {
      final contact = contactMap[id];
      if (contact != null) {
        contacts.add(contact);
      }
    }

    if (mounted) {
      setState(() {
        _list = freshList;
        _contacts = contacts;
        _isLoading = false;
      });
    }
  }

  Future<void> _addContacts() async {
    if (_list == null) return;

    final currentIds = _list?.contactIds.toSet() ?? {};

    final selectedIds = await showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ContactSelectionSheet(
        disabledIds: currentIds,
      ),
    );

    if (selectedIds != null && selectedIds.isNotEmpty) {
      for (final id in selectedIds) {
        await _dbHelper.addContactToPrayerList(_list!.id, id);
      }
      await _loadListContacts(_list!);
    }
  }

  Future<void> _removeContact(String contactId) async {
    if (_list == null) return;
    await _dbHelper.removeContactFromPrayerList(_list!.id, contactId);
    await _loadListContacts(_list!);
  }

  Future<void> _deleteContact(String contactId) async {
    try {
      await _dbHelper.deleteContact(contactId);
      await ReminderCoordinator().cancelAllForContact(contactId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact deleted successfully.')),
        );
      }
      ContactService().invalidateContacts();
      if (_list != null) {
        await _loadListContacts(_list!);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete contact: $e')),
        );
      }
    }
  }

  void _navigateToContactDetails(Contact contact) {
    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => ContactDetailsPage(
          contact: contact,
          onDelete: () => _deleteContact(contact.id),
        ),
      ),
    )
        .then((_) {
      // Refresh list in case contact was deleted or changed
      if (_list != null) {
        _loadListContacts(_list!);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // Should be guaranteed by _ensureDefaultList, but handle safely
    if (_list == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Prayer List')),
        body: const Center(child: Text('Unable to load prayer list')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_list!.name),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addContacts,
        icon: const Icon(Icons.person_add),
        label: const Text('Add People'),
      ),
      body: _contacts.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.playlist_add,
                    size: 64,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'No contacts in your prayer list yet.',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Tap "Add People" to get started.',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.outline,
                        ),
                  ),
                ],
              ),
            )
          : ListView.builder(
              itemCount: _contacts.length,
              itemBuilder: (context, index) {
                final contact = _contacts[index];
                return ListTile(
                  leading: CircleAvatar(
                    backgroundColor:
                        Theme.of(context).colorScheme.primaryContainer,
                    child: Text(
                      contact.firstName.isNotEmpty ? contact.firstName[0] : '?',
                      style: TextStyle(
                          color:
                              Theme.of(context).colorScheme.onPrimaryContainer),
                    ),
                  ),
                  title: Text(contact.fullName),
                  subtitle:
                      contact.location != null ? Text(contact.location!) : null,
                  onTap: () => _navigateToContactDetails(contact),
                  trailing: IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => _removeContact(contact.id),
                    tooltip: 'Remove from list',
                  ),
                );
              },
            ),
    );
  }
}
