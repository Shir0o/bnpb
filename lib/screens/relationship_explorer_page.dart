import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/relationship.dart';

/// Visualizes how contacts are connected to each other.
class RelationshipExplorerPage extends StatefulWidget {
  const RelationshipExplorerPage({super.key});

  @override
  State<RelationshipExplorerPage> createState() =>
      _RelationshipExplorerPageState();
}

class _RelationshipExplorerPageState extends State<RelationshipExplorerPage> {
  final DBHelper _dbHelper = DBHelper();
  List<Contact> _contacts = [];
  List<Relationship> _relationships = [];
  Map<String, Contact> _contactLookup = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() {
      _isLoading = true;
    });

    final contacts = await _dbHelper.getContacts();
    final relationships = await _dbHelper.getAllRelationships();

    if (!mounted) return;
    setState(() {
      _contacts = contacts;
      _relationships = relationships;
      _contactLookup = {for (final contact in contacts) contact.id: contact};
      _isLoading = false;
    });
  }

  String _displayName(String contactId) {
    final contact = _contactLookup[contactId];
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

  List<Widget> _buildSharedConnectionCards(BuildContext context) {
    final groupedByTarget = <String, List<Relationship>>{};
    for (final relationship in _relationships) {
      groupedByTarget.putIfAbsent(relationship.targetContactId, () => []);
      groupedByTarget[relationship.targetContactId]!.add(relationship);
    }

    final entries = groupedByTarget.entries
        .where((entry) => entry.value.length > 1)
        .toList()
      ..sort(
        (a, b) => _displayName(a.key)
            .toLowerCase()
            .compareTo(_displayName(b.key).toLowerCase()),
      );

    return entries.map((entry) {
      final hubName = _displayName(entry.key);
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                hubName,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              ...entry.value.map((relationship) {
                final sourceName = _displayName(relationship.sourceContactId);
                final hasNotes = relationship.notes?.isNotEmpty == true;
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.group_outlined),
                  title: Text(sourceName),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Type: ${relationship.type}'),
                      if (hasNotes)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(relationship.notes!),
                        ),
                    ],
                  ),
                );
              }).toList(),
            ],
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildMetThroughTiles(BuildContext context) {
    final contactsWithIntroducer = _contacts
        .where((contact) => contact.metThroughId != null)
        .toList()
      ..sort(
        (a, b) => _displayName(a.id)
            .toLowerCase()
            .compareTo(_displayName(b.id).toLowerCase()),
      );

    return contactsWithIntroducer.map((contact) {
      final path = _buildMetThroughPath(contact);
      return Card(
        child: ListTile(
          leading: const Icon(Icons.route_outlined),
          title: Text(_displayName(contact.id)),
          subtitle: Text(path),
        ),
      );
    }).toList();
  }

  String _buildMetThroughPath(Contact contact) {
    final visited = <String>{contact.id};
    final segments = <String>[_displayName(contact.id)];

    var current = contact;
    while (current.metThroughId != null) {
      final nextId = current.metThroughId!;
      if (!visited.add(nextId)) {
        segments.add('…');
        break;
      }

      segments.add(_displayName(nextId));
      final next = _contactLookup[nextId];
      if (next == null) {
        break;
      }
      current = next;
    }

    return segments.join(' ← ');
  }

  @override
  Widget build(BuildContext context) {
    final sharedCards = _buildSharedConnectionCards(context);
    final metThroughTiles = _buildMetThroughTiles(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Relationship Explorer'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.all(16),
                children: [
                  Text(
                    'Shared connections',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (sharedCards.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No shared connections yet. Add relationships to discover clusters.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    )
                  else
                    ...sharedCards,
                  const SizedBox(height: 24),
                  Text(
                    'Met through paths',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 12),
                  if (metThroughTiles.isEmpty)
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Text(
                          'No "met through" data recorded yet.',
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ),
                    )
                  else
                    ...metThroughTiles,
                ],
              ),
            ),
    );
  }
}
