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
  Map<String, Contact> _contactLookup = {};
  List<MapEntry<String, List<Relationship>>> _groupedEntries = [];
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

    // Create lookup first for sorting
    final contactLookup = {for (final contact in contacts) contact.id: contact};

    // Group and sort relationships
    final groupedByTarget = <String, List<Relationship>>{};
    for (final relationship in relationships) {
      groupedByTarget.putIfAbsent(relationship.targetContactId, () => []);
      groupedByTarget[relationship.targetContactId]!.add(relationship);
    }

    // Helper to get display name from the local lookup
    String getDisplayName(String id) {
      final contact = contactLookup[id];
      if (contact == null) return 'Unknown contact';
      if (contact.fullName.isNotEmpty) return contact.fullName;
      final nickname = contact.nickname ?? '';
      return nickname.isNotEmpty ? nickname : 'Unknown contact';
    }

    final groupedEntries = groupedByTarget.entries
        .where((entry) => entry.value.length > 1)
        .toList()
      ..sort(
        (a, b) => getDisplayName(
          a.key,
        ).toLowerCase().compareTo(getDisplayName(b.key).toLowerCase()),
      );

    if (!mounted) return;
    setState(() {
      _contactLookup = contactLookup;
      _groupedEntries = groupedEntries;
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

  Widget _buildGroupCard(MapEntry<String, List<Relationship>> entry) {
    final hubName = _displayName(entry.key);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(hubName, style: Theme.of(context).textTheme.titleMedium),
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
            }),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Relationship Explorer')),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadData,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    sliver: SliverList(
                      delegate: SliverChildListDelegate([
                        Text(
                          'Shared connections',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                      ]),
                    ),
                  ),
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: _groupedEntries.isEmpty
                        ? SliverToBoxAdapter(
                            child: Card(
                              child: Padding(
                                padding: const EdgeInsets.all(16),
                                child: Text(
                                  'No shared connections yet. Add relationships to discover clusters.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ),
                          )
                        : SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final entry = _groupedEntries[index];
                              return _buildGroupCard(entry);
                            }, childCount: _groupedEntries.length),
                          ),
                  ),
                  const SliverToBoxAdapter(child: SizedBox(height: 16)),
                ],
              ),
            ),
    );
  }
}
