import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../services/contact_search_service.dart';
import 'skeleton_loader.dart';

class ContactSelectionSheet extends StatefulWidget {
  const ContactSelectionSheet({
    super.key,
    this.initialSelectedIds = const {},
    this.disabledIds = const {},
    this.title = 'Select Contacts',
  });

  final Set<String> initialSelectedIds;
  final Set<String> disabledIds;
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
  late final Set<String> _selectedIds;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialSelectedIds);
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
    final stopwatch = Stopwatch()..start();
    final contacts = await _dbHelper.getContacts();
    // Sort by name by default
    contacts.sort((a, b) => a.fullName.compareTo(b.fullName));

    _searchService.index(contacts);

    if (mounted) {
      final results = await _searchService.search('');

      // Ensure at least 400ms passes so the loading indicator doesn't "flash"
      final elapsed = stopwatch.elapsedMilliseconds;
      if (elapsed < 400) {
        await Future.delayed(Duration(milliseconds: 400 - elapsed));
      }

      if (mounted) {
        if (_searchController.text.isNotEmpty) return;
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _onSearchChanged() async {
    final query = _searchController.text;
    final results = await _searchService.search(query);
    if (!mounted) return;
    if (_searchController.text != query) return;
    setState(() {
      _searchResults = results;
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

    final displayList = _searchResults;

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
                  onPressed: () =>
                      Navigator.pop(context, _selectedIds.toList()),
                  child: const Text('Done'),
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
                fillColor: theme.colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 16,
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // List
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: _isLoading
                  ? const _ContactSelectionSkeleton(key: ValueKey('loading'))
                  : displayList.isEmpty
                      ? Center(
                          key: const ValueKey('empty'),
                          child: Text(
                            isSearching
                                ? 'No matching contacts found'
                                : 'No contacts found',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        )
                      : ListView.builder(
                          key: const ValueKey('list'),
                          itemCount: displayList.length,
                          itemBuilder: (context, index) {
                            final match = displayList[index];
                            final contact = match.contact;
                            final isSelected =
                                _selectedIds.contains(contact.id);
                            final isDisabled = widget.disabledIds.contains(
                              contact.id,
                            );

                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: isDisabled
                                    ? theme.colorScheme.surfaceContainerHighest
                                    : theme.colorScheme.primaryContainer,
                                foregroundColor: isDisabled
                                    ? theme.colorScheme.outline
                                    : theme.colorScheme.onPrimaryContainer,
                                child: Text(
                                  contact.firstName.isNotEmpty
                                      ? contact.firstName[0].toUpperCase()
                                      : '?',
                                ),
                              ),
                              title: Text(
                                contact.fullName,
                                style: TextStyle(
                                  color: isDisabled
                                      ? theme.colorScheme.outline
                                      : null,
                                ),
                              ),
                              subtitle: match.snippet != null
                                  ? Text(match.snippet!)
                                  : (contact.location?.isNotEmpty == true
                                      ? Text(contact.location!)
                                      : null),
                              trailing: Checkbox(
                                value: isSelected || isDisabled,
                                onChanged: isDisabled
                                    ? null
                                    : (_) => _toggleSelection(contact.id),
                              ),
                              onTap: isDisabled
                                  ? null
                                  : () => _toggleSelection(contact.id),
                            );
                          },
                        ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ContactSelectionSkeleton extends StatelessWidget {
  const _ContactSelectionSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: ListView.builder(
        itemCount: 10,
        physics: const NeverScrollableScrollPhysics(),
        itemBuilder: (context, index) => ListTile(
          leading: const SkeletonBox(
            width: 40,
            height: 40,
            shape: BoxShape.circle,
          ),
          title: SkeletonBox(width: 120 + (index % 3 * 20.0), height: 16),
          subtitle: const SkeletonBox(width: 80, height: 12),
          trailing: const SkeletonBox(width: 24, height: 24),
        ),
      ),
    );
  }
}
