import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/interaction.dart';
import '../models/prayer_request.dart';
import '../services/contact_search_service.dart';
import '../services/legacy_import_service.dart';
import '../services/reminder_coordinator.dart';
import '../widgets/backup_restore_sheet.dart';
import '../widgets/export_options_sheet.dart';
import '../widgets/people_card.dart';
import 'contact_details_page.dart';
import 'met_at_lookup_page.dart';
import 'prayer_requests_page.dart';
import 'relationship_explorer_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _SuggestionTile extends StatelessWidget {
  const _SuggestionTile({
    required this.contact,
    required this.onTap,
    this.match,
  });

  final Contact contact;
  final VoidCallback onTap;
  final ContactMatch? match;

  @override
  Widget build(BuildContext context) {
    final displayName = contact.fullName.isNotEmpty
        ? contact.fullName
        : (contact.nickname ?? contact.firstName);

    final subtitleParts = <String>[];
    final description = match?.matchDescription;
    final snippet = match?.snippet;
    if (description != null && description.trim().isNotEmpty) {
      subtitleParts.add(description.trim());
    }
    if (snippet != null && snippet.trim().isNotEmpty) {
      subtitleParts.add(snippet.trim());
    }

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      dense: true,
      title: Text(displayName),
      subtitle: subtitleParts.isNotEmpty
          ? Text(
              subtitleParts.join(' • '),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
      onTap: onTap,
    );
  }
}

class _HomePageState extends State<HomePage> {
  final DBHelper _dbHelper = DBHelper();
  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  final TextEditingController _searchController = TextEditingController();
  final Map<String, Contact> _contactLookup = {};
  final ContactSearchService _searchService = ContactSearchService();
  List<String> _availableTags = [];
  String? _selectedTagFilter;
  Map<PrayerRequestStatus, int> _prayerCounts = {
    for (final status in PrayerRequestStatus.values) status: 0,
  };
  List<PrayerRequest> _pendingPrayerReminders = [];
  List<PrayerRequest> _recentAnsweredPrayers = [];
  List<Interaction> _prayerFocusInteractions = [];
  PrayerRequestStatus? _selectedPrayerStatusFilter;
  bool _isLoadingPrayerInsights = false;
  Map<String, ContactMatch> _activeMatches = {};

  @override
  void initState() {
    super.initState();
    _fetchContacts();
    _searchController.addListener(_filterContacts);
  }

  Future<void> _fetchContacts() async {
    final contacts = await _dbHelper.getContacts();
    _applyContactsSnapshot(contacts);

    await _loadPrayerInsights();
  }

  void _applyContactsSnapshot(List<Contact> contacts) {
    if (!mounted) return;

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

    _searchService.index(sortedContacts);

    setState(() {
      _contacts = sortedContacts;
      _contactLookup
        ..clear()
        ..addAll(lookup);
      if (_selectedTagFilter != null && !tags.contains(_selectedTagFilter)) {
        _selectedTagFilter = null;
      }
      _availableTags = tags;
      _filteredContacts = _applyFilters(sortedContacts);
    });
  }

  Future<void> _loadPrayerInsights() async {
    setState(() {
      _isLoadingPrayerInsights = true;
    });

    const prayerFocusLimit = 5;

    final counts = await _dbHelper.getPrayerRequestCounts();
    final pending = await _dbHelper.getPrayerRequests(
      status: PrayerRequestStatus.pending,
      limit: 3,
    );
    final answered = await _dbHelper.getPrayerRequests(
      status: PrayerRequestStatus.answered,
      limit: 3,
      latestAnsweredFirst: true,
    );
    final prayerFocusInteractions =
        await _dbHelper.getPrayerFocusInteractions(limit: prayerFocusLimit);

    if (!mounted) return;
    setState(() {
      _prayerCounts = {
        for (final status in PrayerRequestStatus.values)
          status: counts[status] ?? 0,
      };
      _pendingPrayerReminders = pending;
      _recentAnsweredPrayers = answered;
      _prayerFocusInteractions = prayerFocusInteractions;
      _isLoadingPrayerInsights = false;
    });
  }

  List<Contact> _applyFilters(List<Contact> source) {
    final query = _searchController.text.trim();

    List<Contact> baseList;
    if (query.isEmpty) {
      _activeMatches = {};
      baseList = source;
    } else {
      final matches = _searchService.search(query);
      _activeMatches = {
        for (final match in matches) match.contact.id: match,
      };
      baseList = matches.map((match) => match.contact).toList();
    }

    return baseList.where((contact) {
      final matchesTag = _selectedTagFilter == null ||
          contact.tags.contains(_selectedTagFilter);

      final matchesPrayerStatus = () {
        if (_selectedPrayerStatusFilter == null) {
          return true;
        }
        return contact.prayerRequests
            .any((request) => request.status == _selectedPrayerStatusFilter);
      }();

      return matchesTag && matchesPrayerStatus;
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

  void _togglePrayerStatusFilter(PrayerRequestStatus status) {
    setState(() {
      if (_selectedPrayerStatusFilter == status) {
        _selectedPrayerStatusFilter = null;
      } else {
        _selectedPrayerStatusFilter = status;
      }
      _filteredContacts = _applyFilters(_contacts);
    });
  }

  Widget? _buildSearchSuggestions() {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      return null;
    }

    final suggestions = _filteredContacts.take(5).toList();
    if (suggestions.isEmpty) {
      return null;
    }

    final theme = Theme.of(context);

    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int index = 0; index < suggestions.length; index++) ...[
            if (index != 0)
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            _SuggestionTile(
              contact: suggestions[index],
              match: _activeMatches[suggestions[index].id],
              onTap: () => _navigateToContactDetails(suggestions[index]),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrayerInsightsCard() {
    final theme = Theme.of(context);
    final hasAnyPrayer =
        _prayerCounts.values.any((count) => count != 0);

    final statusChips = PrayerRequestStatus.values.map((status) {
      final count = _prayerCounts[status] ?? 0;
      return FilterChip(
        label: Text('${status.label} ($count)'),
        selected: _selectedPrayerStatusFilter == status,
        onSelected: (_) => _togglePrayerStatusFilter(status),
      );
    }).toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Prayer insights',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                if (_isLoadingPrayerInsights) ...[
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                ],
                TextButton(
                  onPressed: _openPrayerRequestsPage,
                  child: const Text('View all'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: statusChips,
            ),
            if (!hasAnyPrayer && !_isLoadingPrayerInsights) ...[
              const SizedBox(height: 12),
              Text(
                'Log prayer requests from a contact to receive reminders and celebrate answered prayers here.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ],
            if (_pendingPrayerReminders.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Needs prayer', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ..._pendingPrayerReminders.map((request) {
                final contactName =
                    _displayNameForContactId(_contactLookup, request.contactId);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.hourglass_top_outlined),
                  title: Text(request.description),
                  subtitle: Text(
                    '${_formatDate(request.requestedAt)} • $contactName',
                  ),
                  onTap: () {
                    final contact = _contactLookup[request.contactId];
                    if (contact != null) {
                      _navigateToContactDetails(contact);
                    }
                  },
                );
              }),
            ],
            if (_recentAnsweredPrayers.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Answered recently', style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ..._recentAnsweredPrayers.map((request) {
                final contactName =
                    _displayNameForContactId(_contactLookup, request.contactId);
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.secondaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ListTile(
                    dense: true,
                    leading: Icon(
                      Icons.celebration_outlined,
                      color: theme.colorScheme.onSecondaryContainer,
                    ),
                    title: Text(
                      request.description,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    subtitle: Text(
                      '${_formatDate(request.answeredAt ?? request.requestedAt)} • $contactName',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                    onTap: () {
                      final contact = _contactLookup[request.contactId];
                      if (contact != null) {
                        _navigateToContactDetails(contact);
                      }
                    },
                  ),
                );
              }),
            ],
            if (_prayerFocusInteractions.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text('Prayer focus interactions',
                  style: theme.textTheme.titleSmall),
              const SizedBox(height: 8),
              ..._prayerFocusInteractions.map((interaction) {
                final contact = _contactLookup[interaction.contactId];
                final contactName =
                    _displayNameForContactId(_contactLookup, interaction.contactId);
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  leading: const Icon(Icons.self_improvement_outlined),
                  title: Text(interaction.summary),
                  subtitle: Text(
                    '${_formatDate(interaction.occurredAt)} • $contactName',
                  ),
                  onTap: contact != null
                      ? () => _navigateToContactDetails(contact)
                      : null,
                );
              }),
            ],
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat.yMMMd().format(date);
  }

  void _openPrayerRequestsPage() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PrayerRequestsPage(
          initialStatus: _selectedPrayerStatusFilter,
        ),
      ),
    );
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

  List<Widget> _buildGroupedContactsList() {
    final groupedContacts = _groupContactsByLocation(_filteredContacts);

    return groupedContacts.entries.map((entry) {
      final location = entry.key;
      final contactsInLocation = entry.value;

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(location),
          childrenPadding: const EdgeInsets.only(top: 8),
          children: contactsInLocation.map((contact) {
            final match = _activeMatches[contact.id];
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: PeopleCard(
                contact: contact,
                onTap: () => _navigateToContactDetails(contact),
                highlightLabel: match?.matchDescription,
                highlightText: match?.snippet,
              ),
            );
          }).toList(),
        ),
      );
    }).toList();
  }

  Future<void> _openExportSheet() async {
    if (_contacts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add contacts before exporting.')),
      );
      return;
    }

    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ExportOptionsSheet(contacts: _contacts),
    );

    if (!mounted || message == null) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _openRestoreSheet() async {
    final result = await showModalBottomSheet<BackupRestoreSheetResult>(
      context: context,
      isScrollControlled: true,
      builder: (context) => const BackupRestoreSheet(),
    );

    if (!mounted || result == null) {
      return;
    }

    switch (result) {
      case BackupRestoreSheetResult.restored:
        await _fetchContacts();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Backup restored successfully.')),
        );
        break;
      case BackupRestoreSheetResult.legacyImport:
        await _importLegacyJson();
        break;
    }
  }

  Future<void> _importLegacyJson() async {
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
          .map((contactMap) => Contact.fromMap(
                Map<String, dynamic>.from(contactMap as Map),
              ))
          .toList();

      await processLegacyContacts(
        contacts: restoredContacts,
        persistContact: (contact) => _dbHelper.insertContact(contact),
      );

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
    final previousContacts = List<Contact>.from(_contacts);
    final optimisticContacts =
        previousContacts.where((contact) => contact.id != id).toList();

    _applyContactsSnapshot(optimisticContacts);

    try {
      await _dbHelper.deleteContact(id);
      await ReminderCoordinator().cancelAllForContact(id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact deleted successfully.')),
        );
      }
      unawaited(_fetchContacts());
    } catch (error) {
      _applyContactsSnapshot(previousContacts);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete contact: $error')),
      );
    }
  }

  Future<void> _updateContact(Contact contact) async {
    final previousContacts = List<Contact>.from(_contacts);
    final optimisticContacts = previousContacts
        .map((existing) => existing.id == contact.id ? contact : existing)
        .toList();

    _applyContactsSnapshot(optimisticContacts);

    try {
      await _dbHelper.updateContact(contact);
      await ReminderCoordinator().refreshContact(contact.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Contact updated successfully.')),
        );
      }
      unawaited(_fetchContacts());
    } catch (error) {
      _applyContactsSnapshot(previousContacts);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update contact: $error')),
      );
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
        .then((result) {
      if (result is Contact) {
        final previousContacts = List<Contact>.from(_contacts);
        final optimisticContacts = previousContacts
            .map((existing) => existing.id == result.id ? result : existing)
            .toList();
        _applyContactsSnapshot(optimisticContacts);
      }
      unawaited(_fetchContacts());
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupedContactSections = _buildGroupedContactsList();
    final hasPrayerFilters =
        _prayerCounts.values.any((count) => count > 0);
    final hasFilterOptions = hasPrayerFilters || _availableTags.isNotEmpty;
    final searchSuggestions = _buildSearchSuggestions();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.travel_explore_outlined),
            tooltip: 'Reverse lookup (met at...)',
            onPressed: () {
              Navigator.of(context)
                  .push(
                MaterialPageRoute(
                  builder: (context) => MetAtLookupPage(
                    contacts: _contacts,
                  ),
                ),
              )
                  .then((result) {
                if (result is Contact) {
                  _navigateToContactDetails(result);
                }
              });
            },
          ),
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
            onPressed: _openExportSheet,
          ),
          IconButton(
            icon: const Icon(Icons.restore_outlined),
            tooltip: 'Restore backups',
            onPressed: _openRestoreSheet,
          ),
        ],
      ),
      body: CustomScrollView(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            sliver: SliverToBoxAdapter(
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16.0),
                  ),
                  prefixIcon: const Icon(Icons.search),
                  suffixIcon: _searchController.text.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear),
                          tooltip: 'Clear search query',
                          onPressed: () {
                            _searchController.clear();
                            _filterContacts();
                          },
                        )
                      : null,
                  hintText: 'Search contacts...',
                ),
              ),
            ),
          ),
          if (searchSuggestions != null)
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              sliver: SliverToBoxAdapter(
                child: searchSuggestions,
              ),
            ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            sliver: SliverToBoxAdapter(
              child: _buildPrayerInsightsCard(),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 16)),
          if (hasFilterOptions)
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              sliver: SliverToBoxAdapter(
                child: _buildFilterSection(),
              ),
            ),
          if (hasFilterOptions)
            const SliverToBoxAdapter(child: SizedBox(height: 16)),
          if (groupedContactSections.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: Center(child: Text('No contacts available.')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) => groupedContactSections[index],
                  childCount: groupedContactSections.length,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_prayerCounts.values.any((count) => count > 0)) ...[
          const Text(
            'Filter by prayer status',
            style: TextStyle(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: PrayerRequestStatus.values
                .map(
                  (status) => FilterChip(
                    label: Text(
                      '${status.label} (${_prayerCounts[status] ?? 0})',
                    ),
                    selected: _selectedPrayerStatusFilter == status,
                    onSelected: (_) => _togglePrayerStatusFilter(status),
                  ),
                )
                .toList(),
          ),
          if (_availableTags.isNotEmpty)
            const SizedBox(height: 12),
        ],
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
