import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../services/contact_search_service.dart';
import '../widgets/people_card.dart';

class MetAtLookupPage extends StatefulWidget {
  const MetAtLookupPage({super.key, required this.contacts});

  final List<Contact> contacts;

  @override
  State<MetAtLookupPage> createState() => _MetAtLookupPageState();
}

class _MetAtLookupPageState extends State<MetAtLookupPage> {
  late final TextEditingController _controller;
  late final ContactSearchService _searchService;
  List<ContactMatch> _results = [];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController();
    _controller.addListener(_onQueryChanged);
    _searchService = ContactSearchService()..index(widget.contacts);
  }

  @override
  void dispose() {
    _controller.removeListener(_onQueryChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged() {
    final query = _controller.text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = [];
      });
      return;
    }

    final matches = _searchService.searchMeetingContexts(query);
    setState(() {
      _results = matches;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Where did we meet?'),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            TextField(
              controller: _controller,
              decoration: InputDecoration(
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                prefixIcon: const Icon(Icons.search),
                hintText: 'Search by event, venue, or meeting context...',
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _results.isEmpty
                  ? _buildEmptyState()
                  : ListView.separated(
                      itemBuilder: (context, index) {
                        final match = _results[index];
                        return PeopleCard(
                          contact: match.contact,
                          onTap: () {
                            Navigator.of(context).pop(match.contact);
                          },
                          highlightLabel: match.matchDescription,
                          highlightText: match.snippet,
                        );
                      },
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemCount: _results.length,
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    final theme = Theme.of(context);
    if (_controller.text.trim().isEmpty) {
      return Center(
        child: Text(
          'Type a landmark, conference name, or shared activity to find who you met there.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.outline,
          ),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Center(
      child: Text(
        'No contacts matched that meeting context yet. Try a different keyword.',
        style: theme.textTheme.bodyMedium?.copyWith(
          color: theme.colorScheme.outline,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }
}
