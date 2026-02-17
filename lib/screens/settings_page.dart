import '../services/sync_service.dart';
import 'package:intl/intl.dart';
import 'package:flutter/material.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/notification_preference.dart';
import '../repositories/notification_preferences_repository.dart';
import '../services/reminder_coordinator.dart';
import '../services/reminder_service.dart';
import '../services/security_service.dart';
import '../widgets/export_options_sheet.dart';
import 'privacy_policy_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final DBHelper _dbHelper = DBHelper();
  final NotificationPreferencesRepository _preferencesRepository =
      NotificationPreferencesRepository();
  final ReminderCoordinator _reminderCoordinator = ReminderCoordinator();
  final SecurityService _securityService = SecurityService();

  bool _isLoading = true;
  bool _isUpdating = false;
  bool _isPurging = false;
  bool _supportsExactAlarmPermission = false;
  bool _requestingExactAlarmPermission = false;
  bool _exactAlarmOptIn = false;

  List<Contact> _contacts = const <Contact>[];
  Map<String, Set<ReminderChannel>> _categoryChannels =
      const <String, Set<ReminderChannel>>{};
  Map<_PreferenceKey, NotificationPreference> _preferences =
      const <_PreferenceKey, NotificationPreference>{};
  Map<ReminderChannel, NotificationPreference> _globalDefaults =
      const <ReminderChannel, NotificationPreference>{};
  bool _hasPasscode = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  String? _syncPath;
  DateTime? _lastBackupTime;

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
    _syncPath = await SyncService().getSyncDirectory();
    _lastBackupTime = await SyncService().getLastBackupTime();

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

    final hasPasscode = await _securityService.hasPasscode();
    final biometricEnabled = await _securityService.isBiometricEnabled();
    final biometricAvailable = await _securityService.canUseBiometrics();
    final reminderService = ReminderService();
    final supportsExactAlarmPermission =
        await reminderService.isExactAlarmPermissionRelevant();
    final exactAlarmOptIn = await reminderService.isExactAlarmOptInEnabled();

    if (!mounted) {
      return;
    }
    setState(() {
      _contacts = contacts;
      _categoryChannels = categoryChannels;
      _preferences = preferenceMap;
      _globalDefaults = globalDefaults;
      _isLoading = false;
      _hasPasscode = hasPasscode;
      _biometricAvailable = biometricAvailable;
      _biometricEnabled = biometricEnabled && biometricAvailable;
      _supportsExactAlarmPermission = supportsExactAlarmPermission;
      _exactAlarmOptIn = exactAlarmOptIn;
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
        title: const Text('Notification settings'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            if (_isUpdating || _isPurging)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16),
                child: LinearProgressIndicator(minHeight: 2),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Configure reminders per contact or category. Global defaults '
                'apply when no override is set.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            _buildGlobalSection(context),
            if (_supportsExactAlarmPermission) ...[
              const SizedBox(height: 16),
              _buildExactAlarmSection(context),
            ],
            const SizedBox(height: 16),
            _buildContactSection(context),
            const SizedBox(height: 16),
            _buildCategorySection(context),
            const SizedBox(height: 16),
            _buildSecuritySection(context),
            const SizedBox(height: 16),
            _buildSyncSection(context),
            const SizedBox(height: 16),
            _buildDataSection(context),
            const SizedBox(height: 16),
            _buildAboutSection(context),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Global defaults',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Changes here affect every reminder unless a contact or '
                'category override is configured.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              ...ReminderChannel.values.map((channel) {
                final preference = _globalDefaults[channel];
                final enabled = preference?.enabled ?? true;
                final leadTime = preference?.leadTime ??
                    _fallbackLeadTimeFor(channel: channel);
                return _PreferenceControl(
                  title: channel.label,
                  subtitle: channel.description,
                  enabled: enabled,
                  leadTime: leadTime,
                  channel: channel,
                  onToggle: (value) {
                    _setPreference(
                      scopeType: NotificationScopeType.global,
                      scopeId: NotificationPreference.globalScopeId,
                      channel: channel,
                      enabled: value,
                      leadTime: leadTime,
                    );
                  },
                  onLeadTimeChanged: (value) {
                    _setPreference(
                      scopeType: NotificationScopeType.global,
                      scopeId: NotificationPreference.globalScopeId,
                      channel: channel,
                      enabled: enabled,
                      leadTime: value,
                    );
                  },
                  leadTimeOptions: _leadTimeOptions(channel, leadTime),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSecuritySection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Security & access',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Protect your address book with a local passcode and optionally '
                'require biometrics when reopening the app.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _isPurging ? null : _promptForPasscode,
                icon: Icon(
                    _hasPasscode ? Icons.password : Icons.enhanced_encryption),
                label:
                    Text(_hasPasscode ? 'Update passcode' : 'Create passcode'),
              ),
              if (_hasPasscode)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: OutlinedButton.icon(
                    onPressed: _isPurging ? null : _removePasscode,
                    icon:
                        const Icon(Icons.no_encryption_gmailerrorred_outlined),
                    label: const Text('Remove passcode'),
                  ),
                ),
              const SizedBox(height: 8),
              SwitchListTile(
                value: _biometricEnabled,
                onChanged: !_biometricAvailable || _isPurging
                    ? null
                    : (value) => _toggleBiometrics(value),
                title: const Text('Require biometrics'),
                subtitle: Text(
                  _biometricAvailable
                      ? 'Use Face ID/Touch ID or the system biometric prompt when unlocking.'
                      : 'Biometric unlock is unavailable on this device.',
                ),
              ),
              const Divider(height: 24),
              Text(
                'Secure deletion removes the encrypted database, backups, and keys '
                'after overwriting the files, then clears scheduled reminders.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _isPurging ? null : _confirmSecurePurge,
                icon: const Icon(Icons.delete_forever_outlined),
                style: FilledButton.styleFrom(
                  backgroundColor: Theme.of(context).colorScheme.errorContainer,
                  foregroundColor:
                      Theme.of(context).colorScheme.onErrorContainer,
                ),
                label: const Text('Securely purge all data'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildExactAlarmSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Precise scheduling',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Exact alarms keep reminders firing at the exact minute on '
                    'Android 12 and newer. Opt in before we ask Android for '
                    'this additional permission.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            SwitchListTile(
              value: _exactAlarmOptIn,
              onChanged: _requestingExactAlarmPermission
                  ? null
                  : (value) => _toggleExactAlarmOptIn(context, value),
              title: const Text('Allow exact alarm scheduling'),
              subtitle: const Text(
                "You'll review a short explanation before Android opens its "
                "permission screen.",
              ),
            ),
            if (_requestingExactAlarmPermission)
              const Padding(
                padding: EdgeInsets.only(bottom: 16),
                child: LinearProgressIndicator(minHeight: 2),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _toggleExactAlarmOptIn(
    BuildContext context,
    bool value,
  ) async {
    final reminderService = ReminderService();
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Stay on schedule'),
            content: const Text(
              'Android only grants exact alarm access when you confirm it '
              'from the system dialog. Granting access keeps prayer updates, '
              'follow-ups, and other reminders firing right on time. '
              'You can change your mind later from this screen.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Not now'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Continue'),
              ),
            ],
          );
        },
      );

      if (confirmed != true) {
        setState(() {
          _exactAlarmOptIn = false;
        });
        return;
      }

      setState(() {
        _requestingExactAlarmPermission = true;
      });

      try {
        await reminderService.updateExactAlarmOptIn(true);
        final granted = await reminderService.requestExactAlarmPermission();
        if (!mounted) {
          return;
        }
        if (!granted) {
          await reminderService.updateExactAlarmOptIn(false);
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Exact alarm permission was not granted.'),
            ),
          );
        }
        setState(() {
          _exactAlarmOptIn = granted;
        });
      } catch (error) {
        if (!context.mounted) {
          return;
        }
        await reminderService.updateExactAlarmOptIn(false);
        setState(() {
          _exactAlarmOptIn = false;
        });
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to request exact alarm access: $error'),
          ),
        );
      } finally {
        if (mounted) {
          setState(() {
            _requestingExactAlarmPermission = false;
          });
        }
      }
    } else {
      setState(() {
        _requestingExactAlarmPermission = true;
      });
      try {
        await reminderService.updateExactAlarmOptIn(false);
      } finally {
        if (mounted) {
          setState(() {
            _exactAlarmOptIn = false;
            _requestingExactAlarmPermission = false;
          });
        }
      }
    }
  }

  Widget _buildSyncSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                "Sync & Backup",
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                "Automatically backup your encrypted database to a shared folder.",
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _syncPath ?? "Sync folder not set",
                      style: Theme.of(context).textTheme.bodyMedium,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  TextButton(
                    onPressed: () async {
                      await SyncService().setSyncDirectory();
                      _load();
                    },
                    child: const Text("Set Location"),
                  ),
                ],
              ),
              if (_syncPath != null) ...[
                const Divider(),
                Text(
                  _lastBackupTime != null
                      ? "Last backup: ${DateFormat.yMMMd().add_jm().format(_lastBackupTime!)}"
                      : "No backups found",
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilledButton.icon(
                      onPressed: () async {
                        await SyncService().performBackup();
                        _load();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text("Backup complete")),
                          );
                        }
                      },
                      icon: const Icon(Icons.backup),
                      label: const Text("Backup Now"),
                    ),
                    const SizedBox(width: 8),
                    OutlinedButton.icon(
                      onPressed: () async {
                        await SyncService().restoreFromLatestBackup();
                        _load();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                                content: Text("Restored from backup")),
                          );
                        }
                      },
                      icon: const Icon(Icons.restore),
                      label: const Text("Restore"),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDataSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Exports & backups',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Generate CSV, PDF, JSON, or encrypted archives with selected fields. '
                'Encrypted SQLCipher backups continue to live in the app documents '
                'folder and rotate automatically when contacts change.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _isPurging ? null : _openExportOptions,
                icon: const Icon(Icons.ios_share_outlined),
                label: const Text('Open export options'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Privacy & usage',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                'Review the privacy policy, personal usage guidelines, and '
                'supporting documentation for the project.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const PrivacyPolicyPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.privacy_tip_outlined),
                label: const Text('View privacy policy'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _promptForPasscode() async {
    final passcodeController = TextEditingController();
    final confirmController = TextEditingController();
    String? error;
    String? passcode;

    final result = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(_hasPasscode ? 'Update passcode' : 'Create passcode'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: passcodeController,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'New passcode'),
                  ),
                  TextField(
                    controller: confirmController,
                    obscureText: true,
                    decoration:
                        const InputDecoration(labelText: 'Confirm passcode'),
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () {
                    final candidate = passcodeController.text.trim();
                    final confirmation = confirmController.text.trim();
                    if (candidate.length < 4) {
                      setState(() {
                        error = 'Use at least 4 characters for your passcode.';
                      });
                      return;
                    }
                    if (candidate != confirmation) {
                      setState(() {
                        error = 'Passcodes do not match.';
                      });
                      return;
                    }
                    passcode = candidate;
                    Navigator.of(context).pop(true);
                  },
                  child: const Text('Save passcode'),
                ),
              ],
            );
          },
        );
      },
    );

    if (result == true && passcode != null) {
      final hadExistingLock = _hasPasscode;
      await _securityService.setPasscode(passcode);
      await _refreshSecurityState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              hadExistingLock
                  ? 'Passcode updated. Biometrics stay enabled if supported.'
                  : 'Passcode created. Enable biometrics for quicker unlocks.',
            ),
          ),
        );
      }
    }
  }

  Future<void> _removePasscode() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Remove passcode'),
          content: const Text(
            'Removing the passcode disables biometric unlock and leaves the app '
            'accessible without authentication. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await _securityService.setPasscode(null);
      await _refreshSecurityState();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Passcode removed.')),
        );
      }
    }
  }

  Future<void> _toggleBiometrics(bool value) async {
    if (!_hasPasscode && value) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add a passcode before enabling biometrics.'),
        ),
      );
      return;
    }

    final success = await _securityService.setBiometricEnabled(value);
    if (!success) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Biometric authentication is unavailable on this device.'),
          ),
        );
      }
      await _refreshSecurityState();
      return;
    }

    await _refreshSecurityState();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            value ? 'Biometric unlock enabled.' : 'Biometric unlock disabled.',
          ),
        ),
      );
    }
  }

  Future<void> _refreshSecurityState() async {
    final hasPasscode = await _securityService.hasPasscode();
    final biometricEnabled = await _securityService.isBiometricEnabled();
    final biometricAvailable = await _securityService.canUseBiometrics();
    if (!mounted) {
      return;
    }
    setState(() {
      _hasPasscode = hasPasscode;
      _biometricAvailable = biometricAvailable;
      _biometricEnabled = biometricEnabled && biometricAvailable;
    });
  }

  Future<void> _confirmSecurePurge() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Securely purge all data'),
          content: const Text(
            'This action overwrites and deletes the encrypted database, removes '
            'rolling backups, resets your encryption keys, and cancels all '
            'scheduled reminders. This cannot be undone. Continue?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Purge data'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) {
      return;
    }

    setState(() {
      _isPurging = true;
    });

    try {
      await ReminderService().cancelAll();
      final removed = await _securityService.secureDeleteAllData();
      await _load();
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            removed
                ? 'All saved data was securely deleted.'
                : 'No stored data was found to delete.',
          ),
        ),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to purge data: $error')),
      );
    } finally {
      if (mounted) {
        setState(() {
          _isPurging = false;
        });
      }
    }
  }

  Future<void> _openExportOptions() async {
    if (_contacts.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add contacts before exporting.')),
      );
      return;
    }

    final message = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (context) => ExportOptionsSheet(contacts: _contacts),
    );

    if (!mounted || message == null) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
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
                    Text(
                      subtitle,
                      style: theme.textTheme.bodySmall,
                    ),
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
