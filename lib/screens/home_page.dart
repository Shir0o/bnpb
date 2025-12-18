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
import '../widgets/home_page_skeleton.dart';
import '../widgets/people_card.dart';
import 'contact_details_page.dart';
import 'met_at_lookup_page.dart';
import 'prayer_diary_page.dart';
import 'prayer_request_details_page.dart';
import 'relationship_explorer_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  _HomePageState createState() => _HomePageState();
}

class _AnimatedIconButton extends StatefulWidget {
  const _AnimatedIconButton({
    required this.icon,
    required this.onPressed,
    this.tooltip,
  });

  final Widget icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  State<_AnimatedIconButton> createState() => _AnimatedIconButtonState();
}

class _AnimatedIconButtonState extends State<_AnimatedIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 150),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.9).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _handleTap() {
    _controller.forward().then((_) => _controller.reverse());
    widget.onPressed();
  }

  @override
  Widget build(BuildContext context) {
    return ScaleTransition(
      scale: _scaleAnimation,
      child: IconButton(
        icon: widget.icon,
        tooltip: widget.tooltip,
        onPressed: _handleTap,
      ),
    );
  }
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

/// Displays the empty prayer insights call-to-action when no requests exist.
class PrayerInsightsEmptyState extends StatelessWidget {
  const PrayerInsightsEmptyState({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Text(
      'Log prayer requests from a contact to receive reminders and celebrate answered prayers here.',
      style: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.outline,
      ),
    );
  }
}

class _HomePageState extends State<HomePage> with WidgetsBindingObserver, TickerProviderStateMixin {
  final DBHelper _dbHelper = DBHelper();
  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
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
  bool _isLoadingPrayerInsights = false;
  Map<String, ContactMatch> _activeMatches = {};
  final Set<String> _expandedLocations = <String>{};

  bool _isInitialLoad = true;
  bool _wasKeyboardVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _performInitialLoad();
    _searchController.addListener(_filterContacts);
    _searchFocusNode.addListener(() {
      setState(() {});
    });
  }

  Future<void> _performInitialLoad() async {
    // Wait for both the data fetch and a minimum delay to ensure the skeleton
    // is visible long enough to not look like a glitch.
    await Future.wait([
      _fetchContacts(),
      Future.delayed(const Duration(milliseconds: 1500)),
    ]);
    
    if (mounted) {
      setState(() {
        _isInitialLoad = false;
      });
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final bottomInset =  WidgetsBinding.instance.platformDispatcher.views.first.viewInsets.bottom;
    final isKeyboardVisible = bottomInset > 0.0;

    // If keyboard was visible and now is not, and we have focus, un-focus to close suggestions.
    if (_wasKeyboardVisible && !isKeyboardVisible && _searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
    }
    _wasKeyboardVisible = isKeyboardVisible;
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

    return baseList
        .where((contact) =>
            _selectedTagFilter == null ||
            contact.tags.contains(_selectedTagFilter))
        .toList();
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

  Widget _buildSearchSuggestions() {
    final query = _searchController.text.trim();
    
    // Show suggestions if query is empty BUT search bar is focused
    // Note: We used to check keyboard visibility here, but it caused issues on initial focus (frame 0).
    // Instead, we handle "unfocus on keyboard close" via WidgetsBindingObserver.
    if (query.isEmpty) {
      if (!_searchFocusNode.hasFocus) {
        return const SizedBox.shrink();
      }
      final suggestions = _searchService.getSuggestions();
      if (suggestions.isEmpty) {
        return const SizedBox.shrink();
      }
      return _buildSuggestionsCard(suggestions, key: const ValueKey('suggestions'));
    }

    final suggestions = _filteredContacts
        .take(5)
        .map((c) => ContactMatch(contact: c, score: 0))
        .toList();

    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }
    
    return _buildSuggestionsCard(suggestions, key: ValueKey('results_${suggestions.length}'));
  }

  Widget _buildSuggestionsCard(List<ContactMatch> matches, {Key? key}) {
    final theme = Theme.of(context);
    
    return Card(
      key: key,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int index = 0; index < matches.length; index++) ...[
            if (index != 0)
              Divider(
                height: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            _SuggestionTile(
              contact: matches[index].contact,
              // If it's a search result, use the active match details.
              // If it's a suggestion (score 1.0 from getSuggestions), use its description.
              match: _activeMatches[matches[index].contact.id] ?? matches[index],
              onTap: () => _navigateToContactDetails(matches[index].contact),
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
                  const SizedBox(width: 8),
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: AnimatedSwitcher(
                        duration: Duration(milliseconds: 200),
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Column(
                key: ValueKey('insights_$_isLoadingPrayerInsights'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!hasAnyPrayer && !_isLoadingPrayerInsights)
                    const PrayerInsightsEmptyState(),
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
                        onTap: () => _openPrayerRequestDetails(request),
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
                          onTap: () => _openPrayerRequestDetails(request),
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
                      final primaryContactId =
                          interaction.participantIds.isNotEmpty
                              ? interaction.participantIds.first
                              : null;
                      final contact = primaryContactId != null
                          ? _contactLookup[primaryContactId]
                          : null;
                      final contactName = primaryContactId != null
                          ? _displayNameForContactId(
                              _contactLookup,
                              primaryContactId,
                            )
                          : 'Unknown contact';
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
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return DateFormat.yMMMd().format(date);
  }

  Future<void> _openPrayerRequestDetails(PrayerRequest request) async {
    final contact = _contactLookup[request.contactId];
    if (contact == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Contact details unavailable for this request.'),
        ),
      );
      return;
    }

    final didUpdate = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => PrayerRequestDetailsPage(
          request: request,
          contact: contact,
        ),
      ),
    );

    if (!mounted) return;

    if (didUpdate == true) {
      await _fetchContacts();
    }
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

      final isExpanded = _expandedLocations.contains(location);

      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: Text(location),
          childrenPadding: const EdgeInsets.only(top: 8),
          initiallyExpanded: isExpanded,
          onExpansionChanged: (isExpanded) {
            setState(() {
              if (isExpanded) {
                _expandedLocations.add(location);
              } else {
                _expandedLocations.remove(location);
              }
            });
          },
          children: isExpanded
              ? contactsInLocation.map((contact) {
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
                }).toList()
              : const <Widget>[],
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

    AnimationController? controller;
    if (mounted) {
      controller = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 400),
        reverseDuration: const Duration(milliseconds: 300),
      );
    }

    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      transitionAnimationController: controller,
      builder: (context) => ExportOptionsSheet(contacts: _contacts),
    );

    // controller?.dispose(); // Do not dispose; BottomSheet takes ownership.

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
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final groupedContactSections = _buildGroupedContactsList();
    final hasFilterOptions = _availableTags.isNotEmpty;
    final searchSuggestions = _buildSearchSuggestions();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.self_improvement_outlined),
            tooltip: 'Prayer diary',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const PrayerDiaryPage(),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.travel_explore_outlined),
            tooltip: 'Reverse lookup (met at...)',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => MetAtLookupPage(
                    contacts: _contacts,
                  ),
                ),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.backup_outlined),
            tooltip: 'Backup and Restore',
            onPressed: _openRestoreSheet,
          ),
          IconButton(
            icon: const Icon(Icons.share_outlined),
            tooltip: 'Export',
            onPressed: _openExportSheet,
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeOut,
        child: _isInitialLoad
            ? const HomePageSkeleton(key: ValueKey('home_skeleton'))
            : RefreshIndicator(
                key: const ValueKey('home_content'),
                onRefresh: _fetchContacts,
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  children: [
                    TextField(
                      controller: _searchController,
                      focusNode: _searchFocusNode,
                      decoration: InputDecoration(
                        hintText: 'Search contacts...',
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        filled: true,
                        fillColor: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.3),
                        contentPadding: const EdgeInsets.symmetric(vertical: 0, horizontal: 16),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (searchSuggestions is! SizedBox) ...[
                      searchSuggestions,
                    ] else ...[
                      _buildPrayerInsightsCard(),
                      if (hasFilterOptions) ...[
                        const SizedBox(height: 16),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              FilterChip(
                                label: const Text('All'),
                                selected: _selectedTagFilter == null,
                                onSelected: (_) => _toggleTagFilter(''),
                              ),
                              const SizedBox(width: 8),
                              ..._availableTags.map((tag) {
                                return Padding(
                                  padding: const EdgeInsets.only(right: 8),
                                  child: FilterChip(
                                    label: Text(tag),
                                    selected: _selectedTagFilter == tag,
                                    onSelected: (_) => _toggleTagFilter(tag),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      ...groupedContactSections,
                      if (groupedContactSections.isEmpty)
                        Center(
                          child: Padding(
                            padding: const EdgeInsets.only(top: 48),
                            child: Column(
                              children: [
                                Icon(
                                  Icons.person_off_outlined,
                                  size: 48,
                                  color: Theme.of(context).colorScheme.outline,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'No contacts found',
                                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                        color: Theme.of(context).colorScheme.outline,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                    const SizedBox(height: 80),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildFilterSection() {
    if (_availableTags.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
