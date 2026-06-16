import 'package:flutter/material.dart';
import '../db/db_helper.dart';
import '../models/contact.dart';
import '../screens/add_contact_page.dart';
import '../services/contact_search_service.dart';
import 'skeleton_loader.dart';

class ContactSelectionSheet extends StatefulWidget {
  const ContactSelectionSheet({
    super.key,
    this.initialSelectedIds = const {},
    this.disabledIds = const {},
    this.title = 'Select Contacts',
    this.searchService,
  });

  final Set<String> initialSelectedIds;
  final Set<String> disabledIds;
  final String title;
  final ContactSearchService? searchService;

  @override
  State<ContactSelectionSheet> createState() => _ContactSelectionSheetState();
}

class _ContactSelectionSheetState extends State<ContactSelectionSheet> {
  final DBHelper _dbHelper = DBHelper();
  late final ContactSearchService _searchService;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  List<ContactMatch> _searchResults = [];
  late final Set<String> _selectedIds;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _searchService = widget.searchService ?? ContactSearchService();
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
    debugPrint(
        'DEBUG: _loadContacts called, query: "${_searchController.text}"');
    setState(() => _isLoading = true);
    final stopwatch = Stopwatch()..start();
    final contacts = await _dbHelper.getContacts();
    debugPrint('DEBUG: _loadContacts fetched ${contacts.length} contacts');
    // Sort by name by default
    contacts.sort((a, b) => a.fullName.compareTo(b.fullName));

    _searchService.index(contacts);

    if (mounted) {
      final currentQuery = _searchController.text;
      debugPrint('DEBUG: _loadContacts searching for "$currentQuery"');
      final results = await _searchService.search(currentQuery);
      debugPrint(
          'DEBUG: _loadContacts search finished, matches: ${results.length}');

      // Ensure at least 400ms passes so the loading indicator doesn't "flash"
      final elapsed = stopwatch.elapsedMilliseconds;
      if (elapsed < 400) {
        debugPrint(
            'DEBUG: _loadContacts waiting for delay: ${400 - elapsed}ms');
        await Future.delayed(Duration(milliseconds: 400 - elapsed));
      }

      if (mounted) {
        debugPrint(
            'DEBUG: _loadContacts after delay check: searchController="${_searchController.text}", currentQuery="$currentQuery"');
        if (_searchController.text != currentQuery) {
          debugPrint(
              'DEBUG: _loadContacts searchController.text changed, returning early');
          return;
        }
        setState(() {
          _searchResults = results;
          _isLoading = false;
        });
        debugPrint('DEBUG: _loadContacts setState completed, isLoading=false');
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

  Future<void> _createNewContact(BuildContext context) async {
    final query = _searchController.text.trim();
    String? initialFirstName;
    String? initialLastName;
    if (query.isNotEmpty) {
      final parts = query.split(RegExp(r'\s+'));
      if (parts.length > 1) {
        initialFirstName = parts.first;
        initialLastName = parts.sublist(1).join(' ');
      } else {
        initialFirstName = query;
      }
    }

    final newContact = await Navigator.push<Contact>(
      context,
      MaterialPageRoute(
        builder: (context) => AddContactPage(
          popOnSave: true,
          initialFirstName: initialFirstName,
          initialLastName: initialLastName,
        ),
      ),
    );

    if (newContact != null && mounted) {
      await _loadContacts();
      setState(() {
        _selectedIds.add(newContact.id);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isSearching = _searchController.text.isNotEmpty;

    final displayList = _searchResults;

    return Material(
      color: theme.scaffoldBackgroundColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.9,
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
                  fillColor:
                      theme.colorScheme.surfaceContainerHighest.withValues(
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
                    : ListView.builder(
                        key: const ValueKey('list'),
                        itemCount:
                            1 + (displayList.isEmpty ? 1 : displayList.length),
                        itemBuilder: (context, index) {
                          if (index == 0) {
                            final query = _searchController.text.trim();
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor:
                                    theme.colorScheme.primaryContainer,
                                foregroundColor:
                                    theme.colorScheme.onPrimaryContainer,
                                child: const Icon(Icons.person_add),
                              ),
                              title: Text(
                                query.isEmpty
                                    ? 'Create New Contact'
                                    : "Create Contact '$query'",
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              subtitle: Text(
                                query.isEmpty
                                    ? 'Add a new person to your contacts'
                                    : "Create and select '$query'",
                                style: TextStyle(
                                  color: theme.colorScheme.outline,
                                ),
                              ),
                              onTap: () => _createNewContact(context),
                            );
                          }

                          if (displayList.isEmpty) {
                            return Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 32.0,
                                horizontal: 16.0,
                              ),
                              child: Center(
                                child: Text(
                                  isSearching
                                      ? 'No matching contacts found'
                                      : 'No contacts found',
                                  style: theme.textTheme.bodyLarge?.copyWith(
                                    color: theme.colorScheme.outline,
                                  ),
                                ),
                              ),
                            );
                          }

                          final match = displayList[index - 1];
                          final contact = match.contact;
                          final isSelected = _selectedIds.contains(contact.id);
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
