import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/prayer_request.dart';
import '../services/contact_search_service.dart';
import '../services/contact_service.dart';
import '../services/reminder_coordinator.dart';
import '../services/sync_service.dart';
import '../widgets/backup_restore_sheet.dart';
import '../widgets/contact_avatar.dart';
import '../widgets/export_options_sheet.dart';
import '../widgets/home_page_skeleton.dart';
import '../widgets/people_card.dart';
import '../widgets/recommendations_skeleton.dart';
import '../widgets/skeleton_loader.dart';
import '../services/ai/ai_services.dart';
import '../services/ai/ai_feature_gate.dart';
import '../services/follow_up_recommendation_service.dart';
import '../services/import_duplicate_detector.dart';
import '../services/import_service.dart';
import 'contact_details_page.dart';
import 'import_duplicate_review_page.dart';
import 'prayer_diary_page.dart';
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
  Map<PrayerRequestStatus, int> _prayerCounts = {
    for (final status in PrayerRequestStatus.values) status: 0,
  };
  List<FollowUpRecommendation> _recommendations = [];
  bool _isRefreshingRecommendations = false;
  Map<String, ContactMatch> _activeMatches = {};
  String _aiLabel = 'on-device';

  final Set<String> _expandedLocations = <String>{};

  bool _isInitialLoad = true;
  bool _showRefreshSkeleton = false;
  bool _wasKeyboardVisible = false;
  StreamSubscription<void>? _syncSubscription;
  StreamSubscription<void>? _contactsChangedSubscription;

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
    _contactsChangedSubscription = ContactService().onContactsChanged.listen((
      _,
    ) {
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
          _checkAiStatus(),
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

  Future<void> _loadRecommendations({bool forceRefresh = false}) async {
    if (forceRefresh) {
      setState(() => _isRefreshingRecommendations = true);
    }
    try {
      final recommendations = await _recommendationService.getRecommendations(
        forceRefresh: forceRefresh,
      );
      if (mounted) {
        setState(() {
          _recommendations = recommendations;
        });
      }
    } finally {
      if (mounted && forceRefresh) {
        setState(() => _isRefreshingRecommendations = false);
      }
    }
  }

  Future<void> _checkAiStatus() async {
    final gate = AiFeatureGate();
    final enabled = await gate.isEnabled();
    if (!enabled) {
      if (mounted) {
        setState(() {
          _aiLabel = 'on-device';
        });
      }
      return;
    }
    final backend = await gate.backend();
    if (mounted) {
      setState(() {
        _aiLabel = backend == AiBackend.cloud ? 'cloud' : 'on-device';
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

    _searchService.index(sortedContacts);

    final filtered = await _applyFilters(sortedContacts);
    if (!mounted) return;

    final grouped = _groupContactsByLocation(filtered).entries.toList();

    setState(() {
      _contacts = sortedContacts;
      _contactLookup
        ..clear()
        ..addAll(lookup);
      _filteredContacts = filtered;
      _groupedFilteredContacts = grouped;
    });
  }

  Future<void> _loadPrayerInsights() async {
    try {
      final counts = await _dbHelper.getPrayerRequestCounts();
      if (!mounted) return;
      setState(() {
        _prayerCounts = {
          for (final status in PrayerRequestStatus.values)
            status: counts[status] ?? 0,
        };
      });
    } catch (e) {
      debugPrint('Failed to load prayer request counts: $e');
    }
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

    return baseList;
  }

  Future<void> _filterContacts() async {
    final queryBefore = _searchController.text.trim();

    final filtered = await _applyFilters(_contacts);
    if (!mounted) return;
    if (_searchController.text.trim() != queryBefore) {
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
    final pendingCount = _prayerCounts[PrayerRequestStatus.pending] ?? 0;
    final answeredCount = _prayerCounts[PrayerRequestStatus.answered] ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Prayer insights',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Color(0xFF0F1512),
            letterSpacing: -0.2,
          ),
        ),
        const SizedBox(height: 12),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: InkWell(
                  onTap: () {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) =>
                                const PrayerDiaryPage(initialFilter: 'Pending'),
                          ),
                        )
                        .then((_) => _fetchContacts(forceRefresh: true));
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFBEEE9),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'NEEDS PRAYER',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.48, // 12 * 0.04em
                            color: Color(0xFFC25A3F),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          pendingCount.toString(),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F1512),
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () {
                    Navigator.of(context)
                        .push(
                          MaterialPageRoute(
                            builder: (_) => const PrayerDiaryPage(
                                initialFilter: 'Answered'),
                          ),
                        )
                        .then((_) => _fetchContacts(forceRefresh: true));
                  },
                  borderRadius: BorderRadius.circular(14),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF6EF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'ANSWERED',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.48, // 12 * 0.04em
                            color: Color(0xFF0D7A4F),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          answeredCount.toString(),
                          style: const TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            color: Color(0xFF0F1512),
                            height: 1.0,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRecommendationsCard() {
    if (_recommendations.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final topRecommendations = _recommendations.take(5).toList();

    return Material(
      color: const Color(0xFF0F1512),
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(
          iconTheme: const IconThemeData(color: Color(0xFFEEF2EF)),
          textTheme: theme.textTheme.apply(
            bodyColor: const Color(0xFFFFFFFF),
            displayColor: const Color(0xFFFFFFFF),
          ),
          listTileTheme: ListTileThemeData(
            titleTextStyle: theme.textTheme.titleSmall?.copyWith(
              color: const Color(0xFFFFFFFF),
              fontWeight: FontWeight.w600,
            ),
            subtitleTextStyle: theme.textTheme.bodySmall?.copyWith(
              color: const Color(0xFF8A988F),
            ),
            iconColor: const Color(0xFFEEF2EF),
          ),
        ),
        child: Builder(
          builder: (cardContext) {
            final cardTheme = Theme.of(cardContext);
            return Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const Icon(
                        Icons.auto_awesome,
                        size: 20,
                        color: Color(0xFF5FE0A0),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Follow-up suggestions',
                          style: cardTheme.textTheme.titleMedium?.copyWith(
                            color: const Color(0xFFFFFFFF),
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                      Text(
                        _aiLabel,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF7D8A82),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (_isRefreshingRecommendations)
                        const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      else
                        IconButton(
                          icon: const Icon(Icons.refresh, size: 20),
                          onPressed: () =>
                              _loadRecommendations(forceRefresh: true),
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                          tooltip: 'Refresh suggestions',
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_isRefreshingRecommendations)
                    SkeletonLoader(
                      child: RecommendationRowsSkeleton(
                        itemCount: topRecommendations.length.clamp(1, 5),
                      ),
                    )
                  else
                    Column(
                      children: topRecommendations.map((rec) {
                        Color iconColor;
                        IconData icon;
                        switch (rec.priority) {
                          case RecommendationPriority.critical:
                            iconColor = const Color(0xFFFF8C7A);
                            icon = Icons.priority_high;
                            break;
                          case RecommendationPriority.high:
                            iconColor = const Color(0xFF5FE0A0);
                            icon = Icons.star_outline;
                            break;
                          case RecommendationPriority.medium:
                            iconColor = const Color(0xFFEEF2EF);
                            icon = Icons.chat_bubble_outline;
                            break;
                          case RecommendationPriority.low:
                            iconColor = const Color(0xFF8A988F);
                            icon = Icons.person_outline;
                            break;
                        }

                        return ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: ContactAvatar(
                            contact: rec.contact,
                            radius: 18,
                          ),
                          title: Text(
                            rec.contact.displayName,
                          ),
                          subtitle: Text(
                            rec.reason,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          trailing: Icon(icon, color: iconColor, size: 20),
                          onTap: () => _navigateToContactDetails(rec.contact),
                        );
                      }).toList(),
                    ),
                ],
              ),
            );
          },
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
      useSafeArea: true,
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
      useSafeArea: true,
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

      final aiEnabled = await AiServices().gate.isEnabled();
      final count = await _showLoading(
        () => ImportService().importJsonExport(
          File(filePath),
          onDuplicatesFound: aiEnabled ? _reviewDuplicates : null,
        ),
        'Importing contacts...\nThis may take a while...',
      );

      await _fetchContacts();

      if (!mounted) return;
      if (count < 0) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Import cancelled.')));
        return;
      }
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

  Future<List<Contact>?> _reviewDuplicates(
    List<Contact> incoming,
    List<DuplicateGroup> groups,
  ) async {
    if (!mounted) return null;
    // _showLoading pushes a dialog; pop it before showing the review page,
    // then re-show after the user decides.
    Navigator.of(context, rootNavigator: true).pop();
    final resolved = await Navigator.of(context).push<List<Contact>>(
      MaterialPageRoute(
        builder: (_) =>
            ImportDuplicateReviewPage(incoming: incoming, groups: groups),
      ),
    );
    if (!mounted) return resolved;
    // Re-show loading dialog so _showLoading's finally-pop still has a target.
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 24),
            Expanded(child: Text('Importing contacts...')),
          ],
        ),
      ),
    );
    return resolved;
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
    _contactsChangedSubscription?.cancel();
    super.dispose();
  }

  Widget _buildHeaderButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color backgroundColor,
    required Color iconColor,
    required String tooltip,
    required double containerSize,
    required double iconSize,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            width: containerSize,
            height: containerSize,
            child: Icon(
              icon,
              size: iconSize,
              color: iconColor,
            ),
          ),
        ),
      ),
    );
  }

  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final groupedEntries = _groupedFilteredContacts;
    final searchSuggestions = _buildSearchSuggestions();
    final isShowingSuggestions = searchSuggestions is! SizedBox;

    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 390;

    final double buttonSize = isSmallScreen ? 36.0 : 42.0;
    final double buttonIconSize = isSmallScreen ? 20.0 : 23.0;
    final double buttonSpacing = isSmallScreen ? 4.0 : 6.0;
    final double titleSize = isSmallScreen ? 26.0 : 34.0;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Contacts',
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            color: const Color(0xFF0F1512),
            letterSpacing: -0.6,
          ),
        ),
        titleSpacing: 22,
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        toolbarHeight: 64,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 18),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildHeaderButton(
                  icon: Icons.people_outline_rounded,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const PrayerListPage(),
                      ),
                    );
                  },
                  backgroundColor: const Color(0xFFF1F5F2),
                  iconColor: const Color(0xFF3D4C44),
                  tooltip: 'Prayer Lists',
                  containerSize: buttonSize,
                  iconSize: buttonIconSize,
                ),
                SizedBox(width: buttonSpacing),
                _buildHeaderButton(
                  icon: Icons.format_list_bulleted_rounded,
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const PrayerDiaryPage(),
                      ),
                    );
                  },
                  backgroundColor: const Color(0xFFF1F5F2),
                  iconColor: const Color(0xFF3D4C44),
                  tooltip: 'Prayer Diary',
                  containerSize: buttonSize,
                  iconSize: buttonIconSize,
                ),
                SizedBox(width: buttonSpacing),
                _buildHeaderButton(
                  icon: Icons.history_rounded,
                  onTap: _openRestoreSheet,
                  backgroundColor: const Color(0xFFF1F5F2),
                  iconColor: const Color(0xFF3D4C44),
                  tooltip: 'Backup and Restore',
                  containerSize: buttonSize,
                  iconSize: buttonIconSize,
                ),
                SizedBox(width: buttonSpacing),
                _buildHeaderButton(
                  icon: Icons.upload_rounded,
                  onTap: _openExportSheet,
                  backgroundColor: const Color(0xFF0D7A4F),
                  iconColor: const Color(0xFFFFFFFF),
                  tooltip: 'Export',
                  containerSize: buttonSize,
                  iconSize: buttonIconSize,
                ),
              ],
            ),
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
                        padding: const EdgeInsets.fromLTRB(22, 0, 22, 18),
                        child: TextField(
                          controller: _searchController,
                          focusNode: _searchFocusNode,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                            color: Color(0xFF0F1512),
                          ),
                          decoration: InputDecoration(
                            hintText: 'Search contacts…',
                            hintStyle: const TextStyle(
                              color: Color(0xFF8A988F),
                              fontSize: 16,
                              fontWeight: FontWeight.w500,
                            ),
                            prefixIcon: const Padding(
                              padding: EdgeInsets.only(left: 15, right: 11),
                              child: Icon(
                                Icons.search,
                                color: Color(0xFF8A988F),
                                size: 19,
                              ),
                            ),
                            prefixIconConstraints: const BoxConstraints(
                              minWidth: 45,
                              minHeight: 19,
                            ),
                            suffixIcon: _searchController.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    color: const Color(0xFF8A988F),
                                    onPressed: () {
                                      _searchController.clear();
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(13),
                              borderSide: BorderSide.none,
                            ),
                            filled: true,
                            fillColor: const Color(0xFFF1F5F2),
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 13,
                              horizontal: 15,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (isShowingSuggestions)
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        sliver: SliverToBoxAdapter(child: searchSuggestions),
                      )
                    else ...[
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 22),
                        sliver: SliverToBoxAdapter(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildRecommendationsCard(),
                              const SizedBox(height: 16),
                              _buildPrayerInsightsCard(),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                      if (groupedEntries.isNotEmpty)
                        SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 22),
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
}
