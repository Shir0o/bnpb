import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/prayer_list.dart';
import 'prayer_list_details_page.dart';

class PrayerListsPage extends StatefulWidget {
  const PrayerListsPage({super.key});

  @override
  State<PrayerListsPage> createState() => _PrayerListsPageState();
}

class _PrayerListsPageState extends State<PrayerListsPage> {
  final DBHelper _dbHelper = DBHelper();
  List<PrayerList> _lists = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadLists();
  }

  Future<void> _loadLists() async {
    setState(() => _isLoading = true);
    final lists = await _dbHelper.getPrayerLists();
    if (mounted) {
      setState(() {
        _lists = lists;
        _isLoading = false;
      });
    }
  }

  Future<void> _createList() async {
    final nameController = TextEditingController();
    final descriptionController = TextEditingController();

    final didCreate = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New Prayer List'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(
                  labelText: 'List Name',
                  hintText: 'e.g. Daily Prayer',
                ),
                textCapitalization: TextCapitalization.sentences,
                autofocus: true,
              ),
              const SizedBox(height: 16),
              TextField(
                controller: descriptionController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  hintText: 'What is this list for?',
                ),
                textCapitalization: TextCapitalization.sentences,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  final newList = PrayerList.create(
                    name: name,
                    description: descriptionController.text.trim(),
                  );
                  await _dbHelper.insertPrayerList(newList);
                  Navigator.pop(context, true);
                }
              },
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    if (didCreate == true) {
      _loadLists();
    }
  }

  Future<void> _openListDetails(PrayerList list) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PrayerListDetailsPage(listId: list.id),
      ),
    );
    _loadLists();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Prayer Lists'),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _createList,
        tooltip: 'Create new list',
        child: const Icon(Icons.add),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _lists.isEmpty
              ? _buildEmptyState()
              : ListView.separated(
                  itemCount: _lists.length,
                  separatorBuilder: (context, index) =>
                      const Divider(height: 1),
                  itemBuilder: (context, index) {
                    final list = _lists[index];
                    return ListTile(
                      title: Text(list.name),
                      subtitle: list.description?.isNotEmpty == true
                          ? Text(list.description!)
                          : Text(
                              '${list.contactIds.length} people',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                      onTap: () => _openListDetails(list),
                      trailing: const Icon(Icons.chevron_right),
                    );
                  },
                ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.list_alt_rounded,
            size: 64,
            color: Theme.of(context).colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            'No prayer lists yet',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Create a list to organize people you want to pray for.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Theme.of(context).colorScheme.outline,
                ),
          ),
        ],
      ),
    );
  }
}
