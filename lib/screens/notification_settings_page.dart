import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/notification_preference.dart';
import '../repositories/notification_preferences_repository.dart';
import '../services/reminder_coordinator.dart';
import '../widgets/hide_on_scroll_scaffold.dart';

class NotificationSettingsPage extends StatefulWidget {
  const NotificationSettingsPage({super.key});

  @override
  State<NotificationSettingsPage> createState() =>
      _NotificationSettingsPageState();
}

class _NotificationSettingsPageState extends State<NotificationSettingsPage> {
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

    await _preferencesRepository.ensureDefaults();

    final contacts = await _dbHelper.getContacts();
    contacts.sort(
      (a, b) => a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()),
    );

    final prayerCategories = await _dbHelper.getPrayerCategories();
    final categoryChannels = <String, Set<ReminderChannel>>{};
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
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    return HideOnScrollScaffold(
      appBar: AppBar(title: const Text('Contact & category overrides')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
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
                'Configure reminders per contact or category. Global defaults '
                'set in Settings apply when no override is configured here.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            _buildContactSection(context),
            const SizedBox(height: 16),
            _buildCategorySection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildContactSection(BuildContext context) {
    if (_contacts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Add contacts to configure per-person reminder preferences.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          title: const Text('Contact overrides'),
          subtitle: const Text('Override reminders for a specific person.'),
          children: _contacts.map((contact) {
            final displayName =
                contact.fullName.isEmpty ? 'Unnamed contact' : contact.fullName;
            return ExpansionTile(
              title: Text(displayName),
              childrenPadding: const EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 12,
              ),
              children: ReminderChannel.values.map((channel) {
                final key = _PreferenceKey(
                  NotificationScopeType.contact,
                  contact.id,
                  channel,
                );
                final override = _preferences[key];
                final fallbackLeadTime = _fallbackLeadTimeFor(channel: channel);
                final enabled = override?.enabled ?? true;
                final leadTime = override?.leadTime ?? fallbackLeadTime;
                return _PreferenceControl(
                  title: channel.label,
                  subtitle: channel.description,
                  enabled: enabled,
                  leadTime: leadTime,
                  channel: channel,
                  onToggle: (value) {
                    _setPreference(
                      scopeType: NotificationScopeType.contact,
                      scopeId: contact.id,
                      channel: channel,
                      enabled: value,
                      leadTime: leadTime,
                    );
                  },
                  onLeadTimeChanged: (value) {
                    _setPreference(
                      scopeType: NotificationScopeType.contact,
                      scopeId: contact.id,
                      channel: channel,
                      enabled: enabled,
                      leadTime: value,
                    );
                  },
                  leadTimeOptions: _leadTimeOptions(channel, leadTime),
                  onReset: override != null
                      ? () {
                          _clearPreference(
                            scopeType: NotificationScopeType.contact,
                            scopeId: contact.id,
                            channel: channel,
                          );
                        }
                      : null,
                );
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }

  Widget _buildCategorySection(BuildContext context) {
    if (_categoryChannels.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              'Log interactions and prayer requests to enable category '
              'specific reminders.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      );
    }

    final categories = _categoryChannels.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          title: const Text('Category overrides'),
          subtitle: const Text('Tune reminders by interaction or prayer type.'),
          children: categories.map((category) {
            final channels = _categoryChannels[category]!;
            return ExpansionTile(
              title: Text(category),
              childrenPadding: const EdgeInsets.only(
                left: 16,
                right: 16,
                bottom: 12,
              ),
              children: channels.map((channel) {
                final key = _PreferenceKey(
                  NotificationScopeType.category,
                  category,
                  channel,
                );
                final override = _preferences[key];
                final fallbackLeadTime = _fallbackLeadTimeFor(channel: channel);
                final enabled = override?.enabled ?? true;
                final leadTime = override?.leadTime ?? fallbackLeadTime;
                return _PreferenceControl(
                  title: channel.label,
                  subtitle: channel.description,
                  enabled: enabled,
                  leadTime: leadTime,
                  channel: channel,
                  onToggle: (value) {
                    _setPreference(
                      scopeType: NotificationScopeType.category,
                      scopeId: category,
                      channel: channel,
                      enabled: value,
                      leadTime: leadTime,
                    );
                  },
                  onLeadTimeChanged: (value) {
                    _setPreference(
                      scopeType: NotificationScopeType.category,
                      scopeId: category,
                      channel: channel,
                      enabled: enabled,
                      leadTime: value,
                    );
                  },
                  leadTimeOptions: _leadTimeOptions(channel, leadTime),
                  onReset: override != null
                      ? () {
                          _clearPreference(
                            scopeType: NotificationScopeType.category,
                            scopeId: category,
                            channel: channel,
                          );
                        }
                      : null,
                );
              }).toList(),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _setPreference({
    required NotificationScopeType scopeType,
    required String scopeId,
    required ReminderChannel channel,
    required bool enabled,
    required Duration leadTime,
  }) async {
    final key = _PreferenceKey(scopeType, scopeId, channel);
    final existing = _preferences[key];
    if (existing != null &&
        existing.enabled == enabled &&
        existing.leadTime == leadTime) {
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
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
      if (!mounted) {
        return;
      }
      setState(() {
        final mutable = Map<_PreferenceKey, NotificationPreference>.from(
          _preferences,
        );
        mutable[key] = saved;
        _preferences = mutable;
        if (scopeType == NotificationScopeType.global) {
          final globalMutable =
              Map<ReminderChannel, NotificationPreference>.from(
            _globalDefaults,
          );
          globalMutable[channel] = saved;
          _globalDefaults = globalMutable;
        }
      });
      await _triggerResync(scopeType, scopeId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to update preference: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _clearPreference({
    required NotificationScopeType scopeType,
    required String scopeId,
    required ReminderChannel channel,
  }) async {
    final key = _PreferenceKey(scopeType, scopeId, channel);
    if (!_preferences.containsKey(key)) {
      return;
    }

    setState(() {
      _isUpdating = true;
    });

    try {
      await _preferencesRepository.deletePreference(
        scopeType: scopeType,
        scopeId: scopeId,
        channel: channel,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        final mutable = Map<_PreferenceKey, NotificationPreference>.from(
          _preferences,
        );
        mutable.remove(key);
        _preferences = mutable;
      });
      await _triggerResync(scopeType, scopeId);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to reset preference: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isUpdating = false;
        });
      }
    }
  }

  Future<void> _triggerResync(
    NotificationScopeType scopeType,
    String scopeId,
  ) async {
    switch (scopeType) {
      case NotificationScopeType.global:
        await _reminderCoordinator.refreshAllContacts();
        break;
      case NotificationScopeType.contact:
        await _reminderCoordinator.refreshContact(scopeId);
        break;
      case NotificationScopeType.category:
        await _reminderCoordinator.refreshAllContacts();
        break;
    }
  }

  Duration _fallbackLeadTimeFor({required ReminderChannel channel}) {
    return _globalDefaults[channel]?.leadTime ?? channel.defaultLeadTime;
  }

  List<Duration> _leadTimeOptions(ReminderChannel channel, Duration current) {
    List<Duration> options;
    switch (channel) {
      case ReminderChannel.followUp:
        options = [
          const Duration(minutes: 0),
          const Duration(minutes: 10),
          const Duration(minutes: 30),
          const Duration(hours: 1),
          const Duration(hours: 2),
          const Duration(hours: 6),
          const Duration(days: 1),
          const Duration(days: 2),
          const Duration(days: 3),
        ];
        break;
      case ReminderChannel.prayerUpdate:
        options = [
          const Duration(minutes: 0),
          const Duration(hours: 6),
          const Duration(hours: 12),
          const Duration(days: 1),
          const Duration(days: 2),
          const Duration(days: 3),
          const Duration(days: 5),
          const Duration(days: 7),
          const Duration(days: 14),
        ];
        break;
      case ReminderChannel.significantDate:
        options = [
          const Duration(minutes: 0),
          const Duration(days: 1),
          const Duration(days: 2),
          const Duration(days: 3),
          const Duration(days: 5),
          const Duration(days: 7),
          const Duration(days: 14),
          const Duration(days: 30),
        ];
        break;
      case ReminderChannel.weeklyReview:
        options = [
          const Duration(minutes: 0),
          const Duration(hours: 3),
          const Duration(hours: 6),
          const Duration(hours: 12),
          const Duration(days: 1),
          const Duration(days: 2),
          const Duration(days: 3),
        ];
        break;
      case ReminderChannel.monthlyReview:
        options = [
          const Duration(minutes: 0),
          const Duration(hours: 6),
          const Duration(hours: 12),
          const Duration(days: 1),
          const Duration(days: 2),
          const Duration(days: 3),
          const Duration(days: 7),
        ];
        break;
    }
    if (!options.contains(current)) {
      options = [...options, current];
    }
    options.sort((a, b) => a.inMinutes.compareTo(b.inMinutes));
    return options;
  }
}

class _PreferenceControl extends StatelessWidget {
  const _PreferenceControl({
    required this.title,
    required this.subtitle,
    required this.enabled,
    required this.leadTime,
    required this.channel,
    required this.onToggle,
    required this.onLeadTimeChanged,
    required this.leadTimeOptions,
    this.onReset,
  });

  final String title;
  final String subtitle;
  final bool enabled;
  final Duration leadTime;
  final ReminderChannel channel;
  final ValueChanged<bool> onToggle;
  final ValueChanged<Duration> onLeadTimeChanged;
  final List<Duration> leadTimeOptions;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.titleSmall),
                    const SizedBox(height: 4),
                    Text(subtitle, style: theme.textTheme.bodySmall),
                  ],
                ),
              ),
              Switch.adaptive(value: enabled, onChanged: onToggle),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text('Lead time', style: theme.textTheme.bodyMedium),
              const SizedBox(width: 16),
              DropdownButton<Duration>(
                value: leadTime,
                onChanged: enabled
                    ? (value) {
                        if (value != null) {
                          onLeadTimeChanged(value);
                        }
                      }
                    : null,
                items: leadTimeOptions
                    .map(
                      (option) => DropdownMenuItem<Duration>(
                        value: option,
                        child: Text(_formatLeadTime(channel, option)),
                      ),
                    )
                    .toList(),
              ),
              const Spacer(),
              if (onReset != null)
                TextButton(
                  onPressed: onReset,
                  child: const Text('Use default'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreferenceKey {
  const _PreferenceKey(this.scopeType, this.scopeId, this.channel);

  final NotificationScopeType scopeType;
  final String scopeId;
  final ReminderChannel channel;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    if (other is! _PreferenceKey) return false;
    return other.scopeType == scopeType &&
        other.scopeId == scopeId &&
        other.channel == channel;
  }

  @override
  int get hashCode => Object.hash(scopeType, scopeId, channel);
}

String _formatLeadTime(ReminderChannel channel, Duration duration) {
  final minutes = duration.inMinutes;
  if (minutes == 0) {
    switch (channel) {
      case ReminderChannel.followUp:
        return 'At follow-up time';
      case ReminderChannel.prayerUpdate:
        return 'Immediately';
      case ReminderChannel.significantDate:
        return 'Same day';
      case ReminderChannel.weeklyReview:
        return 'Monday morning';
      case ReminderChannel.monthlyReview:
        return 'First of the month';
    }
  }

  final isAfter = channel == ReminderChannel.prayerUpdate ||
      channel == ReminderChannel.weeklyReview ||
      channel == ReminderChannel.monthlyReview;
  final qualifier = isAfter ? 'after' : 'before';

  if (minutes % 1440 == 0) {
    final days = duration.inDays;
    final unit = days == 1 ? 'day' : 'days';
    return '$days $unit $qualifier';
  }

  if (minutes % 60 == 0) {
    final hours = duration.inHours;
    final unit = hours == 1 ? 'hour' : 'hours';
    return '$hours $unit $qualifier';
  }

  final unit = minutes == 1 ? 'minute' : 'minutes';
  return '$minutes $unit $qualifier';
}
