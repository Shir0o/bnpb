import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import 'contact_details_page.dart';
import 'relationship_explorer_page.dart';

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
  final Map<String, Contact> _contactLookup = {};
  List<String> _availableTags = [];
  List<String> _availableMetThroughIds = [];
  String? _selectedTagFilter;
  String? _selectedMetThroughFilterId;
  bool _hasUnintroducedContacts = false;

  static const String _noIntroducerFilter = '__no_introducer__';

  @override
  void initState() {
    super.initState();
    _fetchContacts();
    _searchController.addListener(_filterContacts);
  }

  Future<void> _fetchContacts() async {
    final contacts = await _dbHelper.getContacts();
    final sortedContacts = List<Contact>.from(contacts)
      ..sort((a, b) {
        final lastNameA = a.lastName?.toLowerCase() ?? '';
        final lastNameB = b.lastName?.toLowerCase() ?? '';
        final lastNameComparison = lastNameA.compareTo(lastNameB);
        if (lastNameComparison != 0) {
          return lastNameComparison;
        }
        final firstA = a.firstName.toLowerCase();
        final firstB = b.firstName.toLowerCase();
        if (firstA != firstB) {
          return firstA.compareTo(firstB);
        }
        final nicknameA = a.nickname?.toLowerCase() ?? '';
        final nicknameB = b.nickname?.toLowerCase() ?? '';
        return nicknameA.compareTo(nicknameB);
      });

    final lookup = {for (final contact in sortedContacts) contact.id: contact};
    final tags = sortedContacts
        .expand((contact) => contact.tags)
        .toSet()
        .toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    final metThroughIds = sortedContacts
        .map((contact) => contact.metThroughId)
        .whereType<String>()
        .toSet()
        .toList();
    metThroughIds.sort((a, b) =>
        _displayNameForContactId(lookup, a).toLowerCase().compareTo(
              _displayNameForContactId(lookup, b).toLowerCase(),
            ));
    final hasUnintroduced =
        sortedContacts.any((contact) => contact.metThroughId == null);

    setState(() {
      _contacts = sortedContacts;
      _contactLookup
        ..clear()
        ..addAll(lookup);
      if (_selectedTagFilter != null && !tags.contains(_selectedTagFilter)) {
        _selectedTagFilter = null;
      }
      if (_selectedMetThroughFilterId != null &&
          _selectedMetThroughFilterId != _noIntroducerFilter &&
          !metThroughIds.contains(_selectedMetThroughFilterId)) {
        _selectedMetThroughFilterId = null;
      }
      _availableTags = tags;
      _availableMetThroughIds = metThroughIds;
      _hasUnintroducedContacts = hasUnintroduced;
      _filteredContacts = _applyFilters(sortedContacts);
    });
  }

  List<Contact> _applyFilters(List<Contact> source) {
    final query = _searchController.text.toLowerCase();

    return source.where((contact) {
      final matchesQuery = query.isEmpty ||
          contact.fullName.toLowerCase().contains(query) ||
          (contact.nickname?.toLowerCase().contains(query) ?? false) ||
          contact.tags.any((tag) => tag.toLowerCase().contains(query));

      final matchesTag =
          _selectedTagFilter == null || contact.tags.contains(_selectedTagFilter);

      final matchesMetThrough = () {
        if (_selectedMetThroughFilterId == null) {
          return true;
        }
        if (_selectedMetThroughFilterId == _noIntroducerFilter) {
          return contact.metThroughId == null;
        }
        return contact.metThroughId == _selectedMetThroughFilterId;
      }();

      return matchesQuery && matchesTag && matchesMetThrough;
    }).toList();
  }

  void _filterContacts() {
    setState(() {
      _filteredContacts = _applyFilters(_contacts);
    });
  }

  void _toggleTagFilter(String tag) {
    setState(() {
      if (_selectedTagFilter == tag) {
        _selectedTagFilter = null;
      } else {
        _selectedTagFilter = tag;
      }
      _filteredContacts = _applyFilters(_contacts);
    });
  }

  void _toggleMetThroughFilter(String key) {
    setState(() {
      if (_selectedMetThroughFilterId == key) {
        _selectedMetThroughFilterId = null;
      } else {
        _selectedMetThroughFilterId = key;
      }
      _filteredContacts = _applyFilters(_contacts);
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
      grouped.putIfAbsent(location, () => []);
      grouped[location]!.add(contact);
    }

    return grouped;
  }

  Widget _buildGroupedContactsList() {
    final groupedContacts = _groupContactsByLocation(_filteredContacts);

    return ListView(
      children: groupedContacts.entries.map((entry) {
        final location = entry.key;
        final contactsInLocation = entry.value;

        return ExpansionTile(
          title: Text(location),
          children: contactsInLocation.map((contact) {
            final displayName = contact.fullName.isNotEmpty
                ? contact.fullName
                : (contact.nickname ?? 'Unnamed Contact');
            final subtitle = _buildContactSubtitle(contact);

            return ListTile(
              leading: CircleAvatar(
                child: Text(
                  displayName.isNotEmpty
                      ? displayName[0].toUpperCase()
                      : '?',
                ),
              ),
              title: Text(displayName),
              subtitle: subtitle,
              onTap: () => _navigateToContactDetails(contact),
            );
          }).toList(),
        );
      }).toList(),
    );
  }

  Widget? _buildContactSubtitle(Contact contact) {
    final subtitleWidgets = <Widget>[];

    if ((contact.nickname ?? '').isNotEmpty &&
        contact.fullName.toLowerCase() != contact.nickname!.toLowerCase()) {
      subtitleWidgets.add(Text('Nickname: ${contact.nickname}'));
    }

    final metThroughName = contact.metThroughId != null
        ? _displayNameForContactId(_contactLookup, contact.metThroughId!)
        : null;
    if (metThroughName != null && metThroughName.isNotEmpty) {
      subtitleWidgets.add(Text('Met through: $metThroughName'));
    }

    if (contact.tags.isNotEmpty) {
      subtitleWidgets.add(
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: contact.tags
              .map((tag) => Chip(
                    label: Text(tag),
                    visualDensity: VisualDensity.compact,
                  ))
              .toList(),
        ),
      );
    }

    if (subtitleWidgets.isEmpty) {
      return null;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: subtitleWidgets
          .map((widget) => Padding(
                padding: const EdgeInsets.only(top: 4.0),
                child: widget,
              ))
          .toList(),
    );
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
            icon: const Icon(Icons.account_tree_outlined),
            tooltip: 'Relationship explorer',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => const RelationshipExplorerPage(),
                ),
              );
            },
          ),
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
          if (_availableTags.isNotEmpty ||
              _availableMetThroughIds.isNotEmpty ||
              _hasUnintroducedContacts)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: _buildFilterSection(),
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

  Widget _buildFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_availableTags.isNotEmpty) ...[
          const Text(
            'Filter by tags',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _availableTags
                .map(
                  (tag) => FilterChip(
                    label: Text(tag),
                    selected: _selectedTagFilter == tag,
                    onSelected: (_) => _toggleTagFilter(tag),
                  ),
                )
                .toList(),
          ),
        ],
        if (_availableMetThroughIds.isNotEmpty || _hasUnintroducedContacts) ...[
          if (_availableTags.isNotEmpty) const SizedBox(height: 12),
          const Text(
            'Filter by introducer',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (_hasUnintroducedContacts)
                FilterChip(
                  label: const Text('No introducer'),
                  selected: _selectedMetThroughFilterId == _noIntroducerFilter,
                  onSelected: (_) => _toggleMetThroughFilter(_noIntroducerFilter),
                ),
              ..._availableMetThroughIds.map(
                (id) => FilterChip(
                  label: Text(_displayNameForContactId(_contactLookup, id)),
                  selected: _selectedMetThroughFilterId == id,
                  onSelected: (_) => _toggleMetThroughFilter(id),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  String _displayNameForContactId(
      Map<String, Contact> lookup, String contactId) {
    final contact = lookup[contactId];
    if (contact == null) {
      return 'Unknown contact';
    }
    final fullName = contact.fullName;
    if (fullName.isNotEmpty) {
      return fullName;
    }
    final nickname = contact.nickname ?? '';
    return nickname.isNotEmpty ? nickname : 'Unknown contact';
  }
}
