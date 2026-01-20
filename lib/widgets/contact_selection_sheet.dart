import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../services/contact_search_service.dart';

class ContactSelectionSheet extends StatefulWidget {
  const ContactSelectionSheet({
    super.key,
    required this.alreadySelectedIds,
    this.title = 'Select Contacts',
  });

  final Set<String> alreadySelectedIds;
  final String title;

  @override
  State<ContactSelectionSheet> createState() => _ContactSelectionSheetState();
}

class _ContactSelectionSheetState extends State<ContactSelectionSheet> {
  final DBHelper _dbHelper = DBHelper();
  final ContactSearchService _searchService = ContactSearchService();
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<ContactMatch> _searchResults = [];
  final Set<String> _selectedIds = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadContacts();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  Future<void> _loadContacts() async {
    setState(() => _isLoading = true);
    final contacts = await _dbHelper.getContacts();
    // Sort by name by default
    contacts.sort((a, b) => a.fullName.compareTo(b.fullName));

    _searchService.index(contacts);

    if (mounted) {
      setState(() {
        // Initial "search" with empty query returns all contacts (handled by service or logic below)
        _searchResults = _searchService.search('');
        _isLoading = false;
      });
    }
  }

  void _onSearchChanged() {
    final query = _searchController.text;
    setState(() {
      _searchResults = _searchService.search(query);
    });
  }

  void _toggleSelection(String contactId) {
    setState(() {
      if (_selectedIds.contains(contactId)) {
        _selectedIds.remove(contactId);
      } else {
        _selectedIds.add(contactId);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSearching = _searchController.text.isNotEmpty;
    // If not searching, show all (except already members if desired? No, user might want to see them disabled or filter them out.
    // The requirement is usually to pick *new* people.
    // The parent passes `alreadySelectedIds`. We can filter them out completely or show them as disabled selected.
    // Let's filter them out from the "available to pick" list to avoid clutter,
    // or keep them but show as checked and disabled?
    // Filtering out is usually cleaner for "Add" flows.

    final displayList = _searchResults
        .where((match) => !widget.alreadySelectedIds.contains(match.contact.id))
        .toList();

    return Container(
      height: MediaQuery.of(context).size.height * 0.9,
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel'),
                ),
                Expanded(
                  child: Text(
                    widget.title,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton(
                  onPressed: _selectedIds.isEmpty
                      ? null
                      : () => Navigator.pop(context, _selectedIds.toList()),
                  child: Text('Add (${_selectedIds.length})'),
                ),
              ],
            ),
          ),

          // Search Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocusNode,
              decoration: InputDecoration(
                hintText: 'Search contacts...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.3),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // List
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : displayList.isEmpty
                    ? Center(
                        child: Text(
                          isSearching
                              ? 'No matching contacts found'
                              : 'No contacts to add',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.outline,
                          ),
                        ),
                      )
                    : ListView.builder(
                        itemCount: displayList.length,
                        itemBuilder: (context, index) {
                          final match = displayList[index];
                          final contact = match.contact;
                          final isSelected = _selectedIds.contains(contact.id);

                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.primaryContainer,
                              foregroundColor:
                                  theme.colorScheme.onPrimaryContainer,
                              child: Text(contact.firstName.isNotEmpty
                                  ? contact.firstName[0].toUpperCase()
                                  : '?'),
                            ),
                            title: Text(contact.fullName),
                            subtitle: match.snippet != null
                                ? Text(match.snippet!)
                                : (contact.location?.isNotEmpty == true
                                    ? Text(contact.location!)
                                    : null),
                            trailing: Checkbox(
                              value: isSelected,
                              onChanged: (_) => _toggleSelection(contact.id),
                            ),
                            onTap: () => _toggleSelection(contact.id),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}
