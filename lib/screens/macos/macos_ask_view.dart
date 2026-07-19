import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../main.dart' show CrispColorScheme;
import '../../models/contact.dart';
import '../../services/ai/ai_services.dart';
import '../../services/ai/semantic_search_service.dart';
import '../../services/contact_service.dart';
import 'macos_contact_details_page.dart';

/// Desktop "Ask" section: centered semantic search over interactions and
/// prayer requests. Reuses the same on-device search stack as the mobile
/// `AskPage`, laid out to match the Crisp Utility desktop design.
class MacOSAskView extends StatefulWidget {
  const MacOSAskView({super.key});

  @override
  State<MacOSAskView> createState() => _MacOSAskViewState();
}

class _MacOSAskViewState extends State<MacOSAskView> {
  static const String _historyPrefKey = 'ask_page.query_history';
  static const int _maxHistory = 20;

  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  bool _busy = false;
  String? _error;
  String? _lastQuery;
  List<SemanticMatch> _results = const [];
  Map<String, Contact> _contactsById = const {};
  Future<void>? _contactsLoadFuture;
  List<String> _history = const [];

  @override
  void initState() {
    super.initState();
    _contactsLoadFuture = _loadContactsLookup();
    _loadHistory();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _loadContactsLookup() async {
    final contacts = await ContactService().getContacts();
    if (!mounted) return;
    setState(() => _contactsById = {for (final c in contacts) c.id: c});
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
    await SchedulerBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 50));
    try {
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
      debugPrint('Ask query failed: $e\n$st');
      if (!mounted) return;
      setState(() {
        _error = 'Something went wrong running that question. Try again.';
        _busy = false;
      });
    }
  }

  void _runHistoryQuery(String query) {
    _controller.text = query;
    _controller.selection = TextSelection.collapsed(offset: query.length);
    _submit();
  }

  void _clearQuery() {
    setState(() {
      _controller.clear();
      _results = const [];
      _lastQuery = null;
      _error = null;
    });
  }

  Future<void> _openContact(Contact contact) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MacOSContactDetailsPage(contact: contact),
      ),
    );
    ContactService().invalidateContacts();
    if (mounted) await _loadContactsLookup();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final embedderReady = AiServices().embedding.isReady;

    return Container(
      color: colorScheme.surface,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(38),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ask',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 27,
                    color: colorScheme.onSurface,
                    letterSpacing: -0.3,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Semantic search across every interaction and prayer — '
                  'embedded and matched fully on this device.',
                  style: TextStyle(fontSize: 14, color: colorScheme.outline),
                ),
                const SizedBox(height: 18),
                if (!embedderReady)
                  Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: colorScheme.dangerTint2,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: colorScheme.dangerBorder),
                    ),
                    child: Text(
                      'Set up the embedder in Settings → AI to enable Ask.',
                      style: TextStyle(fontSize: 13, color: colorScheme.error),
                    ),
                  ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 15),
                  decoration: BoxDecoration(
                    color: colorScheme.aiCardBg,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.psychology_outlined,
                          size: 20, color: Color(0xFF5FE0A0)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _controller,
                          focusNode: _focusNode,
                          enabled: embedderReady && !_busy,
                          onSubmitted: (_) => _submit(),
                          decoration: const InputDecoration(
                            hintText: 'Ask a question…',
                            hintStyle: TextStyle(color: Color(0xFF94A49B)),
                            border: InputBorder.none,
                            isDense: true,
                          ),
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      if (_busy)
                        const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor:
                                AlwaysStoppedAnimation(Color(0xFF5FE0A0)),
                          ),
                        )
                      else if (_controller.text.isNotEmpty)
                        InkWell(
                          onTap: _clearQuery,
                          child: const Icon(Icons.close,
                              size: 18, color: Color(0xFF94A49B)),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _buildResults(colorScheme),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults(ColorScheme colorScheme) {
    if (_lastQuery == null) {
      if (_history.isEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Text(
            'Type a question and press enter.',
            style: TextStyle(fontSize: 14, color: colorScheme.outline),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Recent questions',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              InkWell(
                onTap: _clearHistory,
                child: Text(
                  'Clear',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.primary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ..._history.map(
            (q) => Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(13),
                onTap: () => _runHistoryQuery(q),
                child: Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 17, vertical: 14),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceTint,
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.history, size: 18, color: colorScheme.outline),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          q,
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          _error!,
          style: TextStyle(fontSize: 14, color: colorScheme.error),
        ),
      );
    }

    if (_results.isEmpty && !_busy) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No matches on this device',
          style: TextStyle(fontSize: 14, color: colorScheme.outline),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${_results.length} result${_results.length == 1 ? '' : 's'} for "$_lastQuery"',
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
            color: colorScheme.outline,
          ),
        ),
        const SizedBox(height: 12),
        ..._results.map(
          (r) => Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () => _openContact(r.contact),
              child: Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding:
                    const EdgeInsets.symmetric(horizontal: 17, vertical: 15),
                decoration: BoxDecoration(
                  border: Border.all(color: colorScheme.cardBorder),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            r.contact.displayName,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 16,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 9, vertical: 3),
                          decoration: BoxDecoration(
                            color: colorScheme.greenTint,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            r.type == IndexDocumentType.prayerRequest
                                ? 'Prayer'
                                : 'Interaction',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: colorScheme.primary,
                            ),
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
                          style: TextStyle(
                            fontSize: 13.5,
                            color: colorScheme.secondaryText,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
