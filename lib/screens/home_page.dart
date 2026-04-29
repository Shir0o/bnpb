import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/interaction.dart';
import '../models/prayer_request.dart';
import '../services/contact_search_service.dart';
import '../services/contact_service.dart';
import '../services/reminder_coordinator.dart';
import '../services/sync_service.dart';
import '../widgets/backup_restore_sheet.dart';
import '../widgets/export_options_sheet.dart';
import '../widgets/home_page_skeleton.dart';
import '../widgets/people_card.dart';
import '../services/follow_up_recommendation_service.dart';
import '../services/import_service.dart';
import 'contact_details_page.dart';
import 'prayer_diary_page.dart';
import 'prayer_request_details_page.dart';
import 'prayer_lists_page.dart';
import '../widgets/smooth_expansion_tile.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
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

class _HomePageState extends State<HomePage>
    with
        WidgetsBindingObserver,
        TickerProviderStateMixin,
        AutomaticKeepAliveClientMixin {
  final DBHelper _dbHelper = DBHelper();
  final FollowUpRecommendationService _recommendationService =
      FollowUpRecommendationService();
  List<Contact> _contacts = [];
  List<Contact> _filteredContacts = [];
  // Optimization: Cache grouped contacts to avoid O(N) grouping in every build.
  List<MapEntry<String, List<Contact>>> _groupedFilteredContacts = [];
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
  List<FollowUpRecommendation> _recommendations = [];
  Map<String, ContactMatch> _activeMatches = {};

  final Set<String> _expandedLocations = <String>{};

  bool _isInitialLoad = true;
  bool _showRefreshSkeleton = false;
  bool _wasKeyboardVisible = false;
  StreamSubscription<void>? _syncSubscription;

  // Optimization: Cached DateFormat to avoid expensive parsing during build loops.
  late DateFormat _dateFormat;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _dateFormat = DateFormat.yMMMd();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _performInitialLoad();
    _searchController.addListener(_filterContacts);
    _searchFocusNode.addListener(() {
      setState(() {});
    });
    _syncSubscription = SyncService().onSyncComplete.listen((_) {
      if (mounted) {
        _fetchContacts(forceRefresh: true);
      }
    });
  }

  Future<void> _performInitialLoad() async {
    // Decision: No longer enforcing a minimum delay for the skeleton.
    // If data is ready instantly (e.g., from cache or fast DB), we transition immediately.
    // This prevents the "flashing" effect where a skeleton is shown for a fixed duration.
    await _fetchContacts();

    if (mounted) {
      setState(() {
        _isInitialLoad = false;
      });
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    final bottomInset = WidgetsBinding
        .instance.platformDispatcher.views.first.viewInsets.bottom;
    final isKeyboardVisible = bottomInset > 0.0;

    // If keyboard was visible and now is not, and we have focus, un-focus to close suggestions.
    if (_wasKeyboardVisible &&
        !isKeyboardVisible &&
        _searchFocusNode.hasFocus) {
      _searchFocusNode.unfocus();
    }
    _wasKeyboardVisible = isKeyboardVisible;
  }

  Future<void> _fetchContacts({
    bool forceRefresh = false,
    bool useSkeleton = false,
  }) async {
    if (useSkeleton) {
      setState(() {
        _showRefreshSkeleton = true;
      });
    }

    // If using skeleton, enforce minimum delay to prevent flashing
    final minDelay =
        useSkeleton ? const Duration(milliseconds: 300) : Duration.zero;

    await Future.wait([
      (() async {
        final contacts = await ContactService().getContacts(
          forceRefresh: forceRefresh,
        );
        _applyContactsSnapshot(contacts);
        await Future.wait([
          _loadPrayerInsights(),
          _loadRecommendations(),
        ]);
      })(),
      if (useSkeleton) Future.delayed(minDelay),
    ]);

    if (mounted && useSkeleton) {
      setState(() {
        _showRefreshSkeleton = false;
      });
    }
  }

  Future<void> _loadRecommendations() async {
    final recommendations = await _recommendationService.getRecommendations();
    if (mounted) {
      setState(() {
        _recommendations = recommendations;
      });
    }
  }

  Future<void> _applyContactsSnapshot(List<Contact> contacts) async {
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

    final filtered = await _applyFilters(sortedContacts);
    if (!mounted) return;

    final grouped = _groupContactsByLocation(filtered).entries.toList();

    setState(() {
      _contacts = sortedContacts;
      _contactLookup
        ..clear()
        ..addAll(lookup);
      if (_selectedTagFilter != null && !tags.contains(_selectedTagFilter)) {
        _selectedTagFilter = null;
      }
      _availableTags = tags;
      _filteredContacts = filtered;
      _groupedFilteredContacts = grouped;
    });
  }

  Future<void> _loadPrayerInsights() async {
    const prayerFocusLimit = 5;

    final results = await Future.wait([
      _dbHelper.getPrayerRequestCounts(),
      _dbHelper.getPrayerRequests(
        status: PrayerRequestStatus.pending,
        limit: 3,
      ),
      _dbHelper.getPrayerRequests(
        status: PrayerRequestStatus.answered,
        limit: 3,
        latestAnsweredFirst: true,
      ),
      _dbHelper.getPrayerFocusInteractions(limit: prayerFocusLimit),
    ]);

    if (!mounted) return;

    final counts = results[0] as Map<PrayerRequestStatus, int>;
    final pending = results[1] as List<PrayerRequest>;
    final answered = results[2] as List<PrayerRequest>;
    final prayerFocusInteractions = results[3] as List<Interaction>;

    setState(() {
      _prayerCounts = {
        for (final status in PrayerRequestStatus.values)
          status: counts[status] ?? 0,
      };
      _pendingPrayerReminders = pending;
      _recentAnsweredPrayers = answered;
      _prayerFocusInteractions = prayerFocusInteractions;
    });
  }

  Future<List<Contact>> _applyFilters(List<Contact> source) async {
    final query = _searchController.text.trim();

    List<Contact> baseList;
    if (query.isEmpty) {
      _activeMatches = {};
      baseList = source;
    } else {
      final matches = await _searchService.search(query);
      if (_searchController.text.trim() != query) {
        return [];
      }
      _activeMatches = {for (final match in matches) match.contact.id: match};
      baseList = matches.map((match) => match.contact).toList();
    }

    return baseList
        .where(
          (contact) =>
              _selectedTagFilter == null ||
              contact.tags.contains(_selectedTagFilter),
        )
        .toList();
  }

  Future<void> _filterContacts() async {
    final queryBefore = _searchController.text.trim();
    final filterBefore = _selectedTagFilter;

    final filtered = await _applyFilters(_contacts);
    if (!mounted) return;
    if (_searchController.text.trim() != queryBefore ||
        _selectedTagFilter != filterBefore) {
      return;
    }

    final grouped = _groupContactsByLocation(filtered).entries.toList();
    setState(() {
      _filteredContacts = filtered;
      _groupedFilteredContacts = grouped;
    });
  }

  Future<void> _toggleTagFilter(String tag) async {
    setState(() {
      if (_selectedTagFilter == tag) {
        _selectedTagFilter = null;
      } else {
        _selectedTagFilter = tag;
      }
    });

    final queryBefore = _searchController.text.trim();
    final filterBefore = _selectedTagFilter;

    final filtered = await _applyFilters(_contacts);
    if (!mounted) return;
    if (_searchController.text.trim() != queryBefore ||
        _selectedTagFilter != filterBefore) {
      return;
    }

    final grouped = _groupContactsByLocation(filtered).entries.toList();
    setState(() {
      _filteredContacts = filtered;
      _groupedFilteredContacts = grouped;
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
      return _buildSuggestionsCard(
        suggestions,
        key: const ValueKey('suggestions'),
      );
    }

    final suggestions = _filteredContacts
        .take(5)
        .map((c) => ContactMatch(contact: c, score: 0))
        .toList();

    if (suggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return _buildSuggestionsCard(
      suggestions,
      key: ValueKey('results_${suggestions.length}'),
    );
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
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
            _SuggestionTile(
              contact: matches[index].contact,
              // If it's a search result, use the active match details.
              // If it's a suggestion (score 1.0 from getSuggestions), use its description.
              match:
                  _activeMatches[matches[index].contact.id] ?? matches[index],
              onTap: () => _navigateToContactDetails(matches[index].contact),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPrayerInsightsCard() {
    final theme = Theme.of(context);
    final hasAnyPrayer = _prayerCounts.values.any((count) => count != 0);

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              ],
            ),
            const SizedBox(height: 12),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: Column(
                key: const ValueKey('insights_content'),
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!hasAnyPrayer) const PrayerInsightsEmptyState(),
                  if (_pendingPrayerReminders.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text('Needs prayer', style: theme.textTheme.titleSmall),
                    const SizedBox(height: 8),
                    ..._pendingPrayerReminders.map((request) {
                      final contactName = _displayNameForContactId(
                        _contactLookup,
                        request.contactId,
                      );
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
                    Text(
                      'Answered recently',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    ..._recentAnsweredPrayers.map((request) {
                      final contactName = _displayNameForContactId(
                        _contactLookup,
                        request.contactId,
                      );
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
                    Text(
                      'Prayer focus interactions',
                      style: theme.textTheme.titleSmall,
                    ),
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

  Widget _buildRecommendationsCard() {
    if (_recommendations.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final topRecommendations = _recommendations.take(5).toList();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  Icons.auto_awesome,
                  size: 20,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Smart follow-up suggestions',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: topRecommendations.map((rec) {
                  Color borderColor;
                  IconData icon;
                  switch (rec.priority) {
                    case RecommendationPriority.critical:
                      borderColor = Colors.red.withValues(alpha: 0.5);
                      icon = Icons.priority_high;
                      break;
                    case RecommendationPriority.high:
                      borderColor = Colors.orange.withValues(alpha: 0.5);
                      icon = Icons.star_outline;
                      break;
                    case RecommendationPriority.medium:
                      borderColor =
                          theme.colorScheme.primary.withValues(alpha: 0.5);
                      icon = Icons.chat_bubble_outline;
                      break;
                    case RecommendationPriority.low:
                      borderColor = theme.colorScheme.outlineVariant;
                      icon = Icons.person_outline;
                      break;
                  }

                  return Container(
                    width: 200,
                    margin: const EdgeInsets.only(right: 12),
                    child: InkWell(
                      onTap: () => _navigateToContactDetails(rec.contact),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          border: Border.all(color: borderColor, width: 2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                CircleAvatar(
                                  radius: 14,
                                  child: Text(
                                    rec.contact.initials,
                                    style: const TextStyle(fontSize: 10),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    rec.contact.displayName,
                                    style: theme.textTheme.titleSmall,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Icon(icon,
                                    size: 14,
                                    color: borderColor.withValues(alpha: 1.0)),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Text(
                              rec.reason,
                              style: theme.textTheme.bodySmall,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    return _dateFormat.format(date);
  }

  Future<void> _openPrayerRequestDetails(PrayerRequest request) async {
    final participants = request.participantIds
        .map((id) => _contactLookup[id])
        .whereType<Contact>()
        .toList();

    final didUpdate = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => PrayerRequestDetailsPage(
          request: request,
          initialContacts: participants,
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

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
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
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('No file selected.')));
        return;
      }

      final filePath = result.files.single.path;
      if (filePath == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Invalid file.')));
        return;
      }

      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Overwrite existing data?'),
          content: const Text(
            'Importing this backup will delete all your current contacts, '
            'interactions, and prayer requests. This cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Overwrite and Import'),
            ),
          ],
        ),
      );

      if (confirmed != true) return;

      final count = await _showLoading(
        () => ImportService().importJsonExport(File(filePath)),
        'Importing contacts...\nThis may take a while...',
      );

      await _fetchContacts();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$count contacts restored successfully!')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to restore contacts: $e')));
    }
  }

  Future<T> _showLoading<T>(Future<T> Function() action, String message) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 24),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );

    try {
      return await action();
    } finally {
      if (mounted) {
        Navigator.of(context).pop();
      }
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
      ContactService().invalidateContacts();
      unawaited(_fetchContacts(forceRefresh: true));
    } catch (error) {
      _applyContactsSnapshot(previousContacts);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to delete contact: $error')),
      );
    }
  }

  void _navigateToContactDetails(Contact contact) {
    setState(() {
      _showRefreshSkeleton = true;
    });

    Navigator.of(context)
        .push(
      MaterialPageRoute(
        builder: (context) => ContactDetailsPage(
          contact: contact,
          onDelete: () => _deleteContact(contact.id),
        ),
      ),
    )
        .then((_) {
      unawaited(_fetchContacts(useSkeleton: true));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _syncSubscription?.cancel();
    super.dispose();
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final groupedEntries = _groupedFilteredContacts;
    final hasFilterOptions = _availableTags.isNotEmpty;
    final searchSuggestions = _buildSearchSuggestions();
    final isShowingSuggestions = searchSuggestions is! SizedBox;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Contacts'),
        actions: [
          IconButton(
            icon: const Icon(Icons.self_improvement_outlined),
            tooltip: 'Prayer diary',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PrayerDiaryPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.list_alt),
            tooltip: 'Prayer Lists',
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const PrayerListPage()),
              );
            },
          ),
          IconButton(
            icon: const Icon(Icons.settings_backup_restore),
            tooltip: 'Backup and Restore',
            onPressed: _openRestoreSheet,
          ),
          IconButton(
            icon: const Icon(Icons.ios_share),
            tooltip: 'Export',
            onPressed: _openExportSheet,
          ),
        ],
      ),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 500),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeOut,
        child: (_isInitialLoad || _showRefreshSkeleton)
            ? const HomePageSkeleton(key: ValueKey('home_skeleton'))
            : RefreshIndicator(
                key: const ValueKey('home_content'),
                onRefresh: () => _fetchContacts(forceRefresh: true),
                child: CustomScrollView(
                  slivers: [
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          decoration: InputDecoration(
                            hintText: 'Search contacts...',
                            prefixIcon: const Icon(Icons.search),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear),
                                    onPressed: () {
                                      _searchController.clear();
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: Theme.of(context)
                                .colorScheme
                                .secondaryContainer
                                .withValues(alpha: 0.3),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 0,
                              horizontal: 16,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (isShowingSuggestions)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverToBoxAdapter(child: searchSuggestions),
                      )
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildRecommendationsCard(),
                              const SizedBox(height: 16),
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
                                          padding: const EdgeInsets.only(
                                            right: 8,
                                          ),
                                          child: FilterChip(
                                            label: Text(tag),
                                            selected: _selectedTagFilter == tag,
                                            onSelected: (_) =>
                                                _toggleTagFilter(tag),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                      if (groupedEntries.isNotEmpty)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final entry = groupedEntries[index];
                              final location = entry.key;
                              final contactsInLocation = entry.value;
                              final isExpanded = _expandedLocations.contains(
                                location,
                              );

                              return Padding(
                                padding: const EdgeInsets.only(bottom: 12),
                                child: SmoothExpansionTile(
                                  key: PageStorageKey<String>(location),
                                  tilePadding: EdgeInsets.zero,
                                  title: Text(location),
                                  childrenPadding: const EdgeInsets.only(
                                    top: 8,
                                  ),
                                  initiallyExpanded: isExpanded,
                                  duration: const Duration(milliseconds: 400),
                                  reverseDuration: const Duration(
                                    milliseconds: 600,
                                  ),
                                  curve: Curves.fastOutSlowIn,
                                  onExpansionChanged: (isExpanded) {
                                    if (isExpanded) {
                                      setState(() {
                                        // Optimization: Expanded locations immediately display contacts since data
                                        // is pre-loaded locally. This removes an artificial 500ms network simulation delay
                                        // and its associated SkeletonLoader, removing a half-second UI bottleneck.
                                        _expandedLocations.add(location);
                                      });
                                    } else {
                                      setState(() {
                                        _expandedLocations.remove(location);
                                      });
                                    }
                                  },
                                  itemCount: isExpanded
                                      ? contactsInLocation.length
                                      : (contactsInLocation.length > 5
                                          ? 5
                                          : contactsInLocation.length),
                                  itemBuilder: (context, index) {
                                    final contact = contactsInLocation[index];
                                    final match = _activeMatches[contact.id];
                                    return Padding(
                                      padding: const EdgeInsets.only(
                                        bottom: 12,
                                      ),
                                      child: PeopleCard(
                                        contact: contact,
                                        onTap: () =>
                                            _navigateToContactDetails(contact),
                                        highlightLabel: match?.matchDescription,
                                        highlightText: match?.snippet,
                                      ),
                                    );
                                  },
                                ),
                              );
                            }, childCount: groupedEntries.length),
                          ),
                        )
                      else
                        SliverFillRemaining(
                          hasScrollBody: false,
                          child: Center(
                            child: Padding(
                              padding: const EdgeInsets.only(bottom: 48),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.person_off_outlined,
                                    size: 48,
                                    color: Theme.of(
                                      context,
                                    ).colorScheme.outline,
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    'No contacts found',
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodyLarge
                                        ?.copyWith(
                                          color: Theme.of(
                                            context,
                                          ).colorScheme.outline,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                    ],
                    const SliverToBoxAdapter(child: SizedBox(height: 80)),
                  ],
                ),
              ),
      ),
    );
  }

  String _displayNameForContactId(
    Map<String, Contact> lookup,
    String contactId,
  ) {
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
