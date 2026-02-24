import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/notification_preference.dart';
import '../repositories/notification_preferences_repository.dart';
import '../services/reminder_coordinator.dart';

class ReminderOverridesPage extends StatefulWidget {
  const ReminderOverridesPage({super.key});

  @override
  State<ReminderOverridesPage> createState() => _ReminderOverridesPageState();
}

class _ReminderOverridesPageState extends State<ReminderOverridesPage> {
  final DBHelper _dbHelper = DBHelper();
  final NotificationPreferencesRepository _preferencesRepository =
      NotificationPreferencesRepository();
  final ReminderCoordinator _reminderCoordinator = ReminderCoordinator();

  bool _isLoading = true;
  bool _isUpdating = false;

  List<Contact> _contacts = const <Contact>[];
  Map<String, Set<ReminderChannel>> _categoryChannels =
      const <String, Set<ReminderChannel>>{};
  Map<_PreferenceKey, NotificationPreference> _preferences =
      const <_PreferenceKey, NotificationPreference>{};
  Map<ReminderChannel, NotificationPreference> _globalDefaults =
      const <ReminderChannel, NotificationPreference>{};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _isLoading = true;
    });

    final contacts = await _dbHelper.getContacts();
    contacts.sort(
      (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
    );

    final interactionCategories = await _dbHelper.getInteractionCategories();
    final prayerCategories = await _dbHelper.getPrayerCategories();
    final categoryChannels = <String, Set<ReminderChannel>>{};
    for (final category in interactionCategories) {
      categoryChannels
          .putIfAbsent(category, () => <ReminderChannel>{})
          .add(ReminderChannel.followUp);
    }
    for (final category in prayerCategories) {
      categoryChannels
          .putIfAbsent(category, () => <ReminderChannel>{})
          .add(ReminderChannel.prayerUpdate);
    }

    final storedPreferences = await _preferencesRepository.loadPreferences();
    final preferenceMap = <_PreferenceKey, NotificationPreference>{};
    final globalDefaults = <ReminderChannel, NotificationPreference>{};
    for (final preference in storedPreferences) {
      final key = _PreferenceKey(
        preference.scopeType,
        preference.scopeId,
        preference.channel,
      );
      preferenceMap[key] = preference;
      if (preference.scopeType == NotificationScopeType.global) {
        globalDefaults[preference.channel] = preference;
      }
    }

    if (!mounted) {
      return;
    }
    setState(() {
      _contacts = contacts;
      _categoryChannels = categoryChannels;
      _preferences = preferenceMap;
      _globalDefaults = globalDefaults;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Reminder overrides'),
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          if (_isUpdating)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: LinearProgressIndicator(minHeight: 2),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Set specific reminder rules for individual contacts or '
              'interaction categories.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
          _buildContactSection(context),
          const SizedBox(height: 16),
          _buildCategorySection(context),
        ],
      ),
    );
  }

  Widget _buildContactSection(BuildContext context) {
    if (_contacts.isEmpty) {
      return const SizedBox.shrink();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'CONTACT OVERRIDES',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        ..._contacts.map((contact) {
          final displayName =
              contact.fullName.isEmpty ? 'Unnamed contact' : contact.fullName;
          
          final hasOverrides = ReminderChannel.values.any((channel) {
            final key = _PreferenceKey(
              NotificationScopeType.contact,
              contact.id,
              channel,
            );
            return _preferences.containsKey(key);
          });

          return ExpansionTile(
            title: Text(displayName),
            subtitle: hasOverrides 
              ? Text('Has active overrides', style: TextStyle(color: Theme.of(context).colorScheme.primary))
              : const Text('Using global defaults'),
            childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: ReminderChannel.values.map((channel) {
              final key = _PreferenceKey(
                NotificationScopeType.contact,
                contact.id,
                channel,
              );
              final override = _preferences[key];
              final fallbackLeadTime = _globalDefaults[channel]?.leadTime ?? channel.defaultLeadTime;
              final enabled = override?.enabled ?? true;
              final leadTime = override?.leadTime ?? fallbackLeadTime;

              return _PreferenceControl(
                title: channel.label,
                enabled: enabled,
                leadTime: leadTime,
                channel: channel,
                onToggle: (value) => _setPreference(
                  scopeType: NotificationScopeType.contact,
                  scopeId: contact.id,
                  channel: channel,
                  enabled: value,
                  leadTime: leadTime,
                ),
                onLeadTimeChanged: (value) => _setPreference(
                  scopeType: NotificationScopeType.contact,
                  scopeId: contact.id,
                  channel: channel,
                  enabled: enabled,
                  leadTime: value,
                ),
                leadTimeOptions: _leadTimeOptions(channel, leadTime),
                onReset: override != null ? () => _clearPreference(
                  scopeType: NotificationScopeType.contact,
                  scopeId: contact.id,
                  channel: channel,
                ) : null,
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  Widget _buildCategorySection(BuildContext context) {
    if (_categoryChannels.isEmpty) {
      return const SizedBox.shrink();
    }

    final categories = _categoryChannels.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Text(
            'CATEGORY OVERRIDES',
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
        ),
        ...categories.map((category) {
          final channels = _categoryChannels[category]!;
          
          final hasOverrides = channels.any((channel) {
            final key = _PreferenceKey(
              NotificationScopeType.category,
              category,
              channel,
            );
            return _preferences.containsKey(key);
          });

          return ExpansionTile(
            title: Text(category),
            subtitle: hasOverrides 
              ? Text('Has active overrides', style: TextStyle(color: Theme.of(context).colorScheme.primary))
              : const Text('Using global defaults'),
            childrenPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            children: channels.map((channel) {
              final key = _PreferenceKey(
                NotificationScopeType.category,
                category,
                channel,
              );
              final override = _preferences[key];
              final fallbackLeadTime = _globalDefaults[channel]?.leadTime ?? channel.defaultLeadTime;
              final enabled = override?.enabled ?? true;
              final leadTime = override?.leadTime ?? fallbackLeadTime;

              return _PreferenceControl(
                title: channel.label,
                enabled: enabled,
                leadTime: leadTime,
                channel: channel,
                onToggle: (value) => _setPreference(
                  scopeType: NotificationScopeType.category,
                  scopeId: category,
                  channel: channel,
                  enabled: value,
                  leadTime: leadTime,
                ),
                onLeadTimeChanged: (value) => _setPreference(
                  scopeType: NotificationScopeType.category,
                  scopeId: category,
                  channel: channel,
                  enabled: enabled,
                  leadTime: value,
                ),
                leadTimeOptions: _leadTimeOptions(channel, leadTime),
                onReset: override != null ? () => _clearPreference(
                  scopeType: NotificationScopeType.category,
                  scopeId: category,
                  channel: channel,
                ) : null,
              );
            }).toList(),
          );
        }),
      ],
    );
  }

  Future<void> _setPreference({
    required NotificationScopeType scopeType,
    required String scopeId,
    required ReminderChannel channel,
    required bool enabled,
    required Duration leadTime,
  }) async {
    setState(() => _isUpdating = true);
    try {
      final key = _PreferenceKey(scopeType, scopeId, channel);
      final existing = _preferences[key];
      final preference = (existing ??
              NotificationPreference(
                scopeType: scopeType,
                scopeId: scopeId,
                channel: channel,
                enabled: enabled,
                leadTime: leadTime,
              ))
          .copyWith(enabled: enabled, leadTime: leadTime);
      
      final saved = await _preferencesRepository.savePreference(preference);
      if (mounted) {
        setState(() {
          final mutable = Map<_PreferenceKey, NotificationPreference>.from(_preferences);
          mutable[key] = saved;
          _preferences = mutable;
        });
        await _triggerResync(scopeType, scopeId);
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _clearPreference({
    required NotificationScopeType scopeType,
    required String scopeId,
    required ReminderChannel channel,
  }) async {
    setState(() => _isUpdating = true);
    try {
      await _preferencesRepository.deletePreference(
        scopeType: scopeType,
        scopeId: scopeId,
        channel: channel,
      );
      if (mounted) {
        setState(() {
          final mutable = Map<_PreferenceKey, NotificationPreference>.from(_preferences);
          mutable.remove(_PreferenceKey(scopeType, scopeId, channel));
          _preferences = mutable;
        });
        await _triggerResync(scopeType, scopeId);
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _triggerResync(NotificationScopeType scopeType, String scopeId) async {
    if (scopeType == NotificationScopeType.contact) {
      await _reminderCoordinator.refreshContact(scopeId);
    } else {
      await _reminderCoordinator.refreshAllContacts();
    }
  }

  List<Duration> _leadTimeOptions(ReminderChannel channel, Duration current) {
    List<Duration> options;
    switch (channel) {
      case ReminderChannel.followUp:
        options = [const Duration(minutes: 0), const Duration(minutes: 10), const Duration(minutes: 30), const Duration(hours: 1), const Duration(hours: 6), const Duration(days: 1)];
        break;
      case ReminderChannel.prayerUpdate:
        options = [const Duration(minutes: 0), const Duration(hours: 6), const Duration(days: 1), const Duration(days: 3), const Duration(days: 7)];
        break;
      default:
        options = [const Duration(minutes: 0), const Duration(days: 1), const Duration(days: 7)];
    }
    if (!options.contains(current)) options.add(current);
    options.sort();
    return options;
  }
}

class _PreferenceControl extends StatelessWidget {
  const _PreferenceControl({
    required this.title,
    required this.enabled,
    required this.leadTime,
    required this.channel,
    required this.onToggle,
    required this.onLeadTimeChanged,
    required this.leadTimeOptions,
    this.onReset,
  });

  final String title;
  final bool enabled;
  final Duration leadTime;
  final ReminderChannel channel;
  final ValueChanged<bool> onToggle;
  final ValueChanged<Duration> onLeadTimeChanged;
  final List<Duration> leadTimeOptions;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SwitchListTile(
          title: Text(title),
          value: enabled,
          onChanged: onToggle,
          contentPadding: EdgeInsets.zero,
        ),
        Row(
          children: [
            const Text('Lead time: '),
            DropdownButton<Duration>(
              value: leadTime,
              onChanged: enabled ? (v) => v != null ? onLeadTimeChanged(v) : null : null,
              items: leadTimeOptions.map((opt) => DropdownMenuItem(
                value: opt,
                child: Text(_formatLeadTime(channel, opt)),
              )).toList(),
            ),
            const Spacer(),
            if (onReset != null)
              TextButton(onPressed: onReset, child: const Text('Reset')),
          ],
        ),
        const Divider(),
      ],
    );
  }
}

class _PreferenceKey {
  const _PreferenceKey(this.scopeType, this.scopeId, this.channel);
  final NotificationScopeType scopeType;
  final String scopeId;
  final ReminderChannel channel;
  @override
  bool operator ==(Object other) => other is _PreferenceKey && other.scopeType == scopeType && other.scopeId == scopeId && other.channel == channel;
  @override
  int get hashCode => Object.hash(scopeType, scopeId, channel);
}

String _formatLeadTime(ReminderChannel channel, Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes == 0) return 'Same time';
  if (minutes % 1440 == 0) return '${duration.inDays} days before';
  if (minutes % 60 == 0) return '${duration.inHours} hours before';
  return '$minutes mins before';
}
