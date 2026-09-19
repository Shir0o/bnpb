import 'package:flutter/material.dart';
import '../models/contact.dart';
import 'contact_avatar.dart';

/// A fast search-and-token component for selecting contacts.
///
/// Features:
/// - Auto-focused persistent search bar.
/// - Selecting a search match immediately adds the contact to the selected set,
///   clears the search query, and keeps the keyboard open so the user can immediately
///   type the next person.
/// - Selected contacts appear as dismissible chips.
/// - Optional [suggestions] section shown when search query is empty (e.g. Regular Participants
///   or Recent Contacts).
class ContactMultiSelect extends StatefulWidget {
  const ContactMultiSelect({
    super.key,
    required this.contacts,
    this.initialSelectedIds = const {},
    this.suggestions = const [],
    this.title = 'Select Attendees',
    this.suggestionsTitle = 'Suggested',
  });

  final List<Contact> contacts;
  final Set<String> initialSelectedIds;
  final List<Contact> suggestions;
  final String title;
  final String suggestionsTitle;

  static Future<List<String>?> show(
    BuildContext context, {
    required List<Contact> contacts,
    Set<String> initialSelectedIds = const {},
    List<Contact> suggestions = const [],
    String title = 'Select Attendees',
    String suggestionsTitle = 'Suggested',
  }) {
    return showModalBottomSheet<List<String>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ContactMultiSelect(
        contacts: contacts,
        initialSelectedIds: initialSelectedIds,
        suggestions: suggestions,
        title: title,
        suggestionsTitle: suggestionsTitle,
      ),
    );
  }

  @override
  State<ContactMultiSelect> createState() => _ContactMultiSelectState();
}

class _ContactMultiSelectState extends State<ContactMultiSelect> {
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  late final Set<String> _selectedIds;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = Set<String>.from(widget.initialSelectedIds);
    _searchController.addListener(() {
      final newQuery = _searchController.text.trim().toLowerCase();
      if (_query != newQuery) {
        setState(() {
          _query = newQuery;
        });
      }
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggleContact(Contact contact) {
    setState(() {
      if (_selectedIds.contains(contact.id)) {
        _selectedIds.remove(contact.id);
      } else {
        _selectedIds.add(contact.id);
        // Clear text and keep focus for rapid continuous entry!
        _searchController.clear();
        _query = '';
      }
    });
    _focusNode.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mediaQuery = MediaQuery.of(context);

    final contactMap = {for (final c in widget.contacts) c.id: c};
    final selectedContacts =
        _selectedIds.map((id) => contactMap[id]).whereType<Contact>().toList();

    // Filter contacts based on query
    List<Contact> searchResults = [];
    if (_query.isNotEmpty) {
      searchResults = widget.contacts.where((c) {
        final full = c.fullName.toLowerCase();
        final first = c.firstName.toLowerCase();
        final nick = c.nickname?.toLowerCase() ?? '';
        return full.contains(_query) ||
            first.contains(_query) ||
            nick.contains(_query);
      }).toList();
    }

    final unselectedSuggestions =
        widget.suggestions.where((c) => !_selectedIds.contains(c.id)).toList();

    return Material(
      color: theme.scaffoldBackgroundColor,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
        child: SizedBox(
          height: mediaQuery.size.height * 0.85,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16.0, vertical: 12.0),
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
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () =>
                          Navigator.pop(context, _selectedIds.toList()),
                      child: const Text('Done',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                    ),
                  ],
                ),
              ),

              // Selected chips wrap
              if (selectedContacts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16.0, vertical: 4.0),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 110),
                    child: SingleChildScrollView(
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: selectedContacts.map((contact) {
                          return Chip(
                            avatar: ContactAvatar(contact: contact, radius: 10),
                            label: Text(contact.displayName,
                                style: const TextStyle(fontSize: 12)),
                            deleteIcon: const Icon(Icons.close, size: 14),
                            onDeleted: () {
                              setState(() {
                                _selectedIds.remove(contact.id);
                              });
                            },
                          );
                        }).toList(),
                      ),
                    ),
                  ),
                ),

              // Search bar
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                child: TextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  autofocus: true,
                  decoration: InputDecoration(
                    hintText: 'Type contact name...',
                    prefixIcon: const Icon(Icons.search),
                    suffixIcon: _query.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              _query = '';
                            },
                          )
                        : null,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(
                        vertical: 10, horizontal: 14),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),

              // Body: Suggestions or Search Results
              Expanded(
                child: _query.isEmpty
                    ? (unselectedSuggestions.isNotEmpty
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Padding(
                                padding:
                                    const EdgeInsets.fromLTRB(16, 8, 16, 4),
                                child: Text(
                                  widget.suggestionsTitle,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: theme.colorScheme.secondary,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16.0),
                                child: Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: unselectedSuggestions.map((c) {
                                    return ActionChip(
                                      avatar:
                                          ContactAvatar(contact: c, radius: 10),
                                      label: Text(c.displayName),
                                      onPressed: () => _toggleContact(c),
                                    );
                                  }).toList(),
                                ),
                              ),
                              const Divider(height: 24),
                              Expanded(
                                child: ListView.builder(
                                  itemCount: widget.contacts.length,
                                  itemBuilder: (ctx, idx) {
                                    final contact = widget.contacts[idx];
                                    final isSelected =
                                        _selectedIds.contains(contact.id);
                                    return ListTile(
                                      leading: ContactAvatar(
                                          contact: contact, radius: 18),
                                      title: Text(contact.displayName),
                                      subtitle: contact.location != null &&
                                              contact.location!.isNotEmpty
                                          ? Text(contact.location!)
                                          : null,
                                      trailing: isSelected
                                          ? Icon(Icons.check_circle,
                                              color: theme.colorScheme.primary)
                                          : const Icon(Icons.circle_outlined),
                                      onTap: () => _toggleContact(contact),
                                    );
                                  },
                                ),
                              ),
                            ],
                          )
                        : ListView.builder(
                            itemCount: widget.contacts.length,
                            itemBuilder: (ctx, idx) {
                              final contact = widget.contacts[idx];
                              final isSelected =
                                  _selectedIds.contains(contact.id);
                              return ListTile(
                                leading:
                                    ContactAvatar(contact: contact, radius: 18),
                                title: Text(contact.displayName),
                                subtitle: contact.location != null &&
                                        contact.location!.isNotEmpty
                                    ? Text(contact.location!)
                                    : null,
                                trailing: isSelected
                                    ? Icon(Icons.check_circle,
                                        color: theme.colorScheme.primary)
                                    : const Icon(Icons.circle_outlined),
                                onTap: () => _toggleContact(contact),
                              );
                            },
                          ))
                    : (searchResults.isEmpty
                        ? const Center(
                            child: Padding(
                              padding: EdgeInsets.all(24.0),
                              child: Text('No matching contacts found'),
                            ),
                          )
                        : ListView.builder(
                            itemCount: searchResults.length,
                            itemBuilder: (ctx, idx) {
                              final contact = searchResults[idx];
                              final isSelected =
                                  _selectedIds.contains(contact.id);
                              return ListTile(
                                leading:
                                    ContactAvatar(contact: contact, radius: 18),
                                title: Text(contact.displayName),
                                subtitle: contact.location != null &&
                                        contact.location!.isNotEmpty
                                    ? Text(contact.location!)
                                    : null,
                                trailing: isSelected
                                    ? Icon(Icons.check_circle,
                                        color: theme.colorScheme.primary)
                                    : const Icon(Icons.add_circle_outline),
                                onTap: () => _toggleContact(contact),
                              );
                            },
                          )),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
