import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../services/ai/ai_services.dart';
import '../services/ai/semantic_search_service.dart';
import '../services/contact_service.dart';
import '../services/reminder_coordinator.dart';
import 'contact_details_page.dart';
import '../widgets/crisp_toast.dart';
import '../widgets/hide_on_scroll_scaffold.dart';

/// Natural-language semantic search across all interactions and prayer
/// requests. Lives on its own surface (rather than fighting the
/// contacts-search bar for the same input affordance) because the
/// interaction model is fundamentally different: type a question, submit,
/// wait, see ranked matches with snippets.
class AskPage extends StatefulWidget {
  const AskPage({super.key});

  @override
  State<AskPage> createState() => _AskPageState();
}

class _AskPageState extends State<AskPage> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _busy = false;
  String? _error;
  String? _lastQuery;
  List<SemanticMatch> _results = const [];
  Map<String, Contact> _contactsById = const {};
  // Resolves once the initial contacts lookup load has completed. Used by
  // `_submit` so a tap-immediately-after-open doesn't race the load and
  // hand an empty lookup to the semantic search service.
  Future<void>? _contactsLoadFuture;
  // Persisted history of past queries (most-recent-first). Surfaced when
  // the field is empty so the user can re-run prior searches without
  // retyping. We don't cache results — that would risk pointing the user
  // at a contact that's been deleted since the last query.
  static const String _historyPrefKey = 'ask_page.query_history';
  static const int _maxHistory = 20;
  List<String> _history = const [];

  @override
  void initState() {
    super.initState();
    _contactsLoadFuture = _loadContactsLookup();
    _loadHistory();
  }

  Future<void> _loadContactsLookup() async {
    final contacts = await ContactService().getContacts();
    if (!mounted) return;
    setState(() {
      _contactsById = {for (final c in contacts) c.id: c};
    });
  }

  Future<void> _loadHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getStringList(_historyPrefKey) ?? const <String>[];
    if (!mounted) return;
    setState(() => _history = stored);
  }

  Future<void> _recordHistory(String query) async {
    final next = <String>[query, ..._history.where((q) => q != query)];
    while (next.length > _maxHistory) {
      next.removeLast();
    }
    setState(() => _history = next);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_historyPrefKey, next);
  }

  Future<void> _clearHistory() async {
    setState(() => _history = const []);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_historyPrefKey);
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final query = _controller.text.trim();
    if (query.isEmpty) return;
    _focusNode.unfocus();

    setState(() {
      _busy = true;
      _error = null;
      _lastQuery = query;
      _results = const [];
    });
    // Let the IME hide animation start before we kick off the embed —
    // without this yield the keyboard freezes mid-slide because the
    // platform main thread gets pinned by the method-channel chain.
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
      // initState kicks off the contacts load without awaiting it, so a
      // user who taps Submit immediately on page open could race it.
      // Block here until the initial load has resolved so the semantic
      // search call gets a populated lookup map.
      await _contactsLoadFuture;
      final contacts = _contactsById.values.toList();
      await AiServices().ensureSemanticIndex(contacts);
      final results = await AiServices().semanticSearch.query(
            query,
            contactsById: _contactsById,
          );
      if (!mounted) return;
      setState(() {
        _results = results;
        _busy = false;
      });
      unawaited(_recordHistory(query));
    } catch (e, st) {
      // Log the raw exception for debugging; surface a friendly message
      // to the user. Raw error strings from native plugins are noisy and
      // unhelpful out of context.
      debugPrint('Ask query failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = "Something went wrong running that question. Try again.";
        _busy = false;
      });
    }
  }

  void _runHistoryQuery(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _submit();
  }

  Future<void> _openContact(Contact contact) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContactDetailsPage(
          contact: contact,
          onDelete: () => _deleteContactFromDetails(contact.id),
        ),
      ),
    );
    // Refresh on return so an edit on the details page (or a delete the
    // user might have undone elsewhere) is reflected the next time the
    // user re-runs a history query.
    ContactService().invalidateContacts();
    if (mounted) {
      await _loadContactsLookup();
    }
  }

  Future<void> _deleteContactFromDetails(String id) async {
    try {
      await DBHelper().deleteContact(id);
      await ReminderCoordinator().cancelAllForContact(id);
      ContactService().invalidateContacts();
      if (!mounted) return;
      setState(() {
        // Drop the deleted contact from the in-memory lookup so any
        // results currently on screen that reference it disappear via
        // `resultsToMatches`' missing-contact filter.
        _contactsById = Map.of(_contactsById)..remove(id);
        _results = _results.where((r) => r.contact.id != id).toList();
      });
      CrispToast.show(context, 'Contact deleted successfully.');
    } catch (error) {
      if (!mounted) return;
      CrispToast.show(context, 'Failed to delete contact: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final embedderReady = AiServices().embedding.isReady;
    return HideOnScrollScaffold(
      appBar: AppBar(title: const Text('Ask')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (!embedderReady)
                    Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.tertiaryContainer.withValues(
                          alpha: 0.5,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        'Set up the embedder in AI Settings to enable Ask.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  TextField(
                    controller: _controller,
                    focusNode: _focusNode,
                    enabled: embedderReady && !_busy,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      hintText: 'Ask a question…',
                      prefixIcon: const Icon(Icons.psychology_outlined),
                      suffixIcon: _busy
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: Icon(Icons.hourglass_top, size: 20),
                            )
                          : (_controller.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear),
                                  onPressed: () {
                                    setState(() {
                                      _controller.clear();
                                      _results = const [];
                                      _lastQuery = null;
                                      _error = null;
                                    });
                                  },
                                )
                              : null),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: theme.colorScheme.secondaryContainer
                          .withValues(alpha: 0.3),
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_lastQuery != null && !_busy)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        _error != null
                            ? 'Error: $_error'
                            : '${_results.length} result${_results.length == 1 ? '' : 's'} for "$_lastQuery"',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            Expanded(child: _buildResultsList(theme)),
          ],
        ),
      ),
    );
  }

  Card _buildCard({required Widget child}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
      ),
      child: child,
    );
  }

  Widget _buildResultsList(ThemeData theme) {
    if (_busy) {
      return ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: 4,
        separatorBuilder: (_, __) => const SizedBox(height: 8),
        itemBuilder: (_, __) => _SkeletonResultCard(),
      );
    }
    if (_lastQuery == null) {
      if (_history.isEmpty) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'Type a question and tap search.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Text(
                  'Recent questions',
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _clearHistory,
                  child: const Text('Clear'),
                ),
              ],
            ),
          ),
          for (final q in _history)
            _buildCard(
              child: ListTile(
                leading: const Icon(Icons.history, size: 20),
                title: Text(q),
                onTap: () => _runHistoryQuery(q),
              ),
            ),
        ],
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No matches.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: _results.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, i) {
        final r = _results[i];
        return _buildCard(
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openContact(r.contact),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          r.contact.displayName,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      Text(
                        r.type == IndexDocumentType.prayerRequest
                            ? 'Prayer'
                            : 'Interaction',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (r.snippet.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(
                        r.snippet,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SkeletonResultCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final color = colorScheme.surfaceContainerHighest.withValues(alpha: 0.6);
    Widget bar({required double width, required double height}) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        );
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            bar(width: 140, height: 16),
            const SizedBox(height: 8),
            bar(width: double.infinity, height: 12),
            const SizedBox(height: 6),
            bar(width: 220, height: 12),
          ],
        ),
      ),
    );
  }
}
