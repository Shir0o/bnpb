import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/contact.dart';
import '../services/ai/ai_services.dart';
import '../services/ai/semantic_search_service.dart';
import '../services/contact_service.dart';
import 'contact_details_page.dart';

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
    _loadContactsLookup();
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
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _busy = false;
      });
    }
  }

  void _runHistoryQuery(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _submit();
  }

  void _openContact(Contact contact) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ContactDetailsPage(
          contact: contact,
          onDelete: () async {},
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final embedderReady = AiServices().embedding.isReady;
    return Scaffold(
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
                        color: theme.colorScheme.tertiaryContainer
                            .withValues(alpha: 0.5),
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
            Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
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
        return Card(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
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
    final color = Theme.of(context)
        .colorScheme
        .surfaceContainerHighest
        .withValues(alpha: 0.6);
    Widget bar({required double width, required double height}) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(4),
          ),
        );
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
