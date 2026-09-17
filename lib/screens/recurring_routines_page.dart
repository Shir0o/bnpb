import 'package:flutter/material.dart';

import '../models/contact.dart';
import '../models/recurring_log_pattern.dart';
import '../services/contact_service.dart';
import '../services/recurring_log_pattern_service.dart';
import '../services/recurring_log_preferences.dart';

class RecurringRoutinesPage extends StatefulWidget {
  const RecurringRoutinesPage({super.key});

  @override
  State<RecurringRoutinesPage> createState() => _RecurringRoutinesPageState();
}

class _RecurringRoutinesPageState extends State<RecurringRoutinesPage> {
  final RecurringLogPatternService _service =
      const RecurringLogPatternService();
  final RecurringLogPreferenceStore _store = RecurringLogPreferenceStore();

  List<Contact> _contacts = const [];
  RecurringLogPreferences _preferences = RecurringLogPreferences();
  List<RecurringLogPattern> _patterns = const [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (mounted) setState(() => _loading = true);
    final contacts = await ContactService().getContacts(forceRefresh: true);
    final preferences = await _store.load();
    final patterns = _service.resolvePatterns(
      _service.detectPatterns(contacts, now: DateTime.now()),
      preferences,
    );
    if (mounted == false) return;
    setState(() {
      _contacts = contacts;
      _preferences = preferences;
      _patterns = patterns;
      _loading = false;
    });
  }

  Contact? _contactFor(RecurringLogPattern pattern) {
    final participants = _participantsFor(pattern);
    return participants.isEmpty ? null : participants.first;
  }

  List<Contact> _participantsFor(RecurringLogPattern pattern) {
    final byId = {for (final contact in _contacts) contact.id: contact};
    return [
      for (final participantId in pattern.identity.participantIds)
        if (byId[participantId] != null) byId[participantId]!,
    ];
  }

  RecurringLogPreference _preferenceFor(RecurringLogPattern pattern) =>
      _preferences.preferenceFor(pattern.key);

  Future<void> _savePreference(
    String key,
    RecurringLogPreference preference,
  ) async {
    final updated = _preferences.withPreference(key, preference);
    await _store.save(updated);
    await _load();
  }

  Future<void> _saveAll(RecurringLogPreferences preferences) async {
    await _store.save(preferences);
    await _load();
  }

  Future<void> _confirmPattern(RecurringLogPattern pattern) async {
    await _savePreference(
      pattern.key,
      _preferenceFor(pattern).copyWith(confirmed: true),
    );
  }

  Future<void> _snoozePattern(RecurringLogPattern pattern) async {
    final until = dateOnly(DateTime.now()).add(const Duration(days: 1));
    await _savePreference(
      pattern.key,
      _preferenceFor(pattern).copyWith(snoozedUntil: until),
    );
  }

  Future<void> _stopPattern(RecurringLogPattern pattern) async {
    await _savePreference(
      pattern.key,
      _preferenceFor(pattern).copyWith(suppressed: true),
    );
  }

  Future<void> _combinePatterns() async {
    final candidates = _patterns
        .where((pattern) => _preferenceFor(pattern).suppressed == false)
        .toList();
    if (candidates.length < 2) return;

    final selected = <String>{};
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: const Text('Combine routines'),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Select the routines that are really the same '
                      'engagement. They will be merged into one.',
                      style: TextStyle(fontSize: 13),
                    ),
                    const SizedBox(height: 12),
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (final pattern in candidates)
                            CheckboxListTile(
                              dense: true,
                              title: Text(
                                '${_participantNames(pattern)} - '
                                '${pattern.displayActivity}',
                                style: const TextStyle(fontSize: 13.5),
                              ),
                              value: selected.contains(pattern.key),
                              onChanged: (value) {
                                setDialogState(() {
                                  if (value == true) {
                                    selected.add(pattern.key);
                                  } else {
                                    selected.remove(pattern.key);
                                  }
                                });
                              },
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: selected.length >= 2
                      ? () => Navigator.of(context).pop(true)
                      : null,
                  child: const Text('Combine'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || selected.length < 2) return;

    final chosen = candidates
        .where((pattern) => selected.contains(pattern.key))
        .toList()
      ..sort((a, b) => b.occurrenceCount.compareTo(a.occurrenceCount));
    final target = chosen.first;
    final sources = chosen.skip(1).toList();

    final updated = _service.combinePatterns(_preferences, target, sources);
    await _saveAll(updated);
  }

  Future<void> _editPattern(RecurringLogPattern pattern) async {
    final preference = _preferenceFor(pattern);
    final latest = pattern.matchingInteractions.first;
    final nameController = TextEditingController(
      text: preference.displayNameOverride ?? pattern.displayActivity,
    );
    final mediumController = TextEditingController(text: latest.medium);
    final spanController = TextEditingController(
      text: (preference.spanOverride ?? pattern.inferredSpan).toString(),
    );
    final selectedParticipants =
        Set<String>.from(pattern.identity.participantIds);
    var cadenceValue = _cadenceValue(override: preference.cadenceOverride);

    final saved = await showDialog<bool>(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              title: Text(pattern.displayActivity),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(
                        labelText: 'Name',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: mediumController,
                      decoration: const InputDecoration(
                        labelText: 'Medium',
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: spanController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Chapters per session',
                      ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: cadenceValue,
                      decoration: const InputDecoration(labelText: 'Cadence'),
                      items: const [
                        DropdownMenuItem(
                          value: 'detected',
                          child: Text('Use detected cadence'),
                        ),
                        DropdownMenuItem(
                          value: 'daily',
                          child: Text('Every day'),
                        ),
                        DropdownMenuItem(
                          value: 'mon-sat',
                          child: Text('Monday to Saturday'),
                        ),
                        DropdownMenuItem(
                          value: 'every2',
                          child: Text('Every 2 days'),
                        ),
                        DropdownMenuItem(
                          value: 'every7',
                          child: Text('Every 7 days'),
                        ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setDialogState(() => cadenceValue = value);
                      },
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Regular participants',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 8),
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 160),
                      child: SingleChildScrollView(
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: [
                            for (final contact in _contacts)
                              FilterChip(
                                label: Text(contact.displayName),
                                selected: selectedParticipants.contains(
                                  contact.id,
                                ),
                                onSelected: (value) {
                                  setDialogState(() {
                                    if (value) {
                                      selectedParticipants.add(contact.id);
                                    } else {
                                      selectedParticipants.remove(contact.id);
                                    }
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    if (saved == true) {
      final name = nameController.text.trim();
      final medium = mediumController.text.trim();
      final span = int.tryParse(spanController.text.trim());
      final cadenceOverride = _cadenceFromValue(cadenceValue);

      final newIdentity = PatternIdentity(
        activity: pattern.identity.activity,
        medium: medium.isEmpty
            ? pattern.identity.medium
            : PatternIdentity.normalize(medium),
        participantIds: selectedParticipants.isEmpty
            ? pattern.identity.participantIds
            : selectedParticipants.toList(),
      );

      final overrides = preference.copyWith(
        confirmed: true,
        displayNameOverride: name.isEmpty ? null : name,
        clearDisplayName: name.isEmpty,
        spanOverride: span,
        clearSpan: span == null,
        cadenceOverride: cadenceOverride,
        clearCadence: cadenceOverride == null,
        canonicalIdentity: newIdentity,
      );

      final updated = _service.rekeyPattern(
        _preferences,
        pattern.key,
        newIdentity,
        overrides,
      );
      await _saveAll(updated);
    }
    nameController.dispose();
    mediumController.dispose();
    spanController.dispose();
  }

  String _participantNames(RecurringLogPattern pattern) {
    final contacts = _participantsFor(pattern);
    if (contacts.isEmpty) return 'Unknown contact';
    return contacts.map((contact) => contact.displayName).join(', ');
  }

  String _cadenceValue({PatternCadence? override}) {
    if (override == null) return 'detected';
    final days = override.weekdays;
    if (days != null && days.length == 7) return 'daily';
    if (days != null &&
        days.length == 6 &&
        days.contains(DateTime.monday) &&
        days.contains(DateTime.tuesday) &&
        days.contains(DateTime.wednesday) &&
        days.contains(DateTime.thursday) &&
        days.contains(DateTime.friday) &&
        days.contains(DateTime.saturday)) {
      return 'mon-sat';
    }
    if (override.intervalDays == 2) return 'every2';
    if (override.intervalDays == 7) return 'every7';
    return 'detected';
  }

  PatternCadence? _cadenceFromValue(String value) {
    switch (value) {
      case 'daily':
        return PatternCadence.weekdays({
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
          DateTime.friday,
          DateTime.saturday,
          DateTime.sunday,
        });
      case 'mon-sat':
        return PatternCadence.weekdays({
          DateTime.monday,
          DateTime.tuesday,
          DateTime.wednesday,
          DateTime.thursday,
          DateTime.friday,
          DateTime.saturday,
        });
      case 'every2':
        return PatternCadence.interval(2, dateOnly(DateTime.now()));
      case 'every7':
        return PatternCadence.interval(7, dateOnly(DateTime.now()));
      default:
        return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Routines'),
        actions: [
          if (_patterns.length >= 2)
            IconButton(
              tooltip: 'Combine routines',
              icon: const Icon(Icons.merge),
              onPressed: _combinePatterns,
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _buildBody(),
    );
  }

  Widget _buildBody() {
    final visible = _patterns.where((pattern) {
      return _preferenceFor(pattern).suppressed == false;
    }).toList();

    if (visible.isEmpty) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'No recurring routines detected yet. Log the same activity a few '
            'times and it will appear here.',
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    return ListView.separated(
      itemCount: visible.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final pattern = visible[index];
        final contact = _contactFor(pattern);
        final preference = _preferenceFor(pattern);
        final span = preference.spanOverride ?? pattern.inferredSpan;
        final participants = _participantsFor(pattern);
        final contactName = participants.length > 1
            ? participants.map((contact) => contact.displayName).join(', ')
            : contact == null
                ? 'Unknown contact'
                : contact.displayName;
        final subtitle =
            '$contactName - $pattern.cadence.description - $span chapters';
        return ListTile(
          title: Text(pattern.displayActivity),
          subtitle: Text(
            preference.confirmed ? subtitle : '$subtitle - not confirmed',
          ),
          onTap: () => _editPattern(pattern),
          trailing: PopupMenuButton<String>(
            tooltip: 'Routine options',
            onSelected: (value) {
              if (value == 'confirm') _confirmPattern(pattern);
              if (value == 'edit') _editPattern(pattern);
              if (value == 'snooze') _snoozePattern(pattern);
              if (value == 'stop') _stopPattern(pattern);
            },
            itemBuilder: (context) => [
              if (preference.confirmed == false)
                const PopupMenuItem(
                  value: 'confirm',
                  child: Text('Confirm routine'),
                ),
              const PopupMenuItem(value: 'edit', child: Text('Edit')),
              const PopupMenuItem(value: 'snooze', child: Text('Not today')),
              const PopupMenuItem(
                value: 'stop',
                child: Text('Stop suggesting'),
              ),
            ],
          ),
        );
      },
    );
  }
}
