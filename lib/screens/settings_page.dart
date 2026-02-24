import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/notification_preference.dart';
import '../repositories/notification_preferences_repository.dart';
import '../services/google_drive_service.dart';
import '../services/reminder_coordinator.dart';
import '../services/reminder_service.dart';
import '../services/security_service.dart';
import '../services/sync_service.dart';
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
  bool _exactAlarmOptIn = false;

  List<Contact> _contacts = const <Contact>[];
  Map<ReminderChannel, NotificationPreference> _globalDefaults =
      const <ReminderChannel, NotificationPreference>{};
  bool _hasPasscode = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;
  String? _syncPath;
  DateTime? _lastBackupTime;
  SyncType _syncType = SyncType.local;
  GoogleSignInAccount? _googleUser;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);

    await _preferencesRepository.ensureDefaults();
    _syncPath = await SyncService().getSyncDirectory();
    _lastBackupTime = await SyncService().getLastBackupTime();
    _syncType = await SyncService().getSyncType();
    _googleUser = await GoogleDriveService().currentUser;

    _contacts = await _dbHelper.getContacts();

    final storedPreferences = await _preferencesRepository.loadPreferences();
    final globalDefaults = <ReminderChannel, NotificationPreference>{};
    for (final preference in storedPreferences) {
      if (preference.scopeType == NotificationScopeType.global) {
        globalDefaults[preference.channel] = preference;
      }
    }

    _hasPasscode = await _securityService.hasPasscode();
    _biometricEnabled = await _securityService.isBiometricEnabled();
    _biometricAvailable = await _securityService.canUseBiometrics();
    final reminderService = ReminderService();
    _supportsExactAlarmPermission =
        await reminderService.isExactAlarmPermissionRelevant();
    _exactAlarmOptIn = await reminderService.isExactAlarmOptInEnabled();

    if (mounted) {
      setState(() {
        _globalDefaults = globalDefaults;
        _biometricEnabled = _biometricEnabled && _biometricAvailable;
        _isLoading = false;
      });
    }
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
        title: const Text('Settings'),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          children: [
            if (_isUpdating || _isPurging)
              const LinearProgressIndicator(minHeight: 2),
            _buildSectionHeader('Reminders'),
            _buildGlobalRemindersTile(context),
            if (_supportsExactAlarmPermission) _buildExactAlarmTile(context),
            const Divider(),
            _buildSectionHeader('Sync & Backup'),
            _buildSyncGroup(context),
            const Divider(),
            _buildSectionHeader('Security'),
            _buildSecurityGroup(context),
            const Divider(),
            _buildSectionHeader('Data'),
            ListTile(
              leading: const Icon(Icons.ios_share_outlined),
              title: const Text('Export options'),
              subtitle: const Text('CSV, PDF, JSON, or encrypted archive'),
              onTap: _isPurging ? null : _openExportOptions,
            ),
            ListTile(
              leading: const Icon(Icons.delete_forever_outlined),
              title: const Text('Securely purge all data'),
              textColor: Theme.of(context).colorScheme.error,
              iconColor: Theme.of(context).colorScheme.error,
              onTap: _isPurging ? null : _confirmSecurePurge,
            ),
            const Divider(),
            _buildSectionHeader('About'),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const Text('Privacy policy'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
              ),
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        title.toUpperCase(),
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.bold,
            ),
      ),
    );
  }

  Widget _buildGlobalRemindersTile(BuildContext context) {
    return ExpansionTile(
      leading: const Icon(Icons.notifications_none_outlined),
      title: const Text('Global reminder defaults'),
      subtitle: const Text('Base settings for all notifications'),
      children: ReminderChannel.values.map((channel) {
        final pref = _globalDefaults[channel];
        final enabled = pref?.enabled ?? true;
        final leadTime = pref?.leadTime ?? channel.defaultLeadTime;
        return ListTile(
          title: Text(channel.label),
          subtitle: Text(_formatLeadTime(channel, leadTime)),
          trailing: Switch.adaptive(
            value: enabled,
            onChanged: (v) => _setGlobalPreference(channel, v, leadTime),
          ),
          onTap: () => _showLeadTimePicker(context, channel, enabled, leadTime),
        );
      }).toList(),
    );
  }

  Widget _buildExactAlarmTile(BuildContext context) {
    return SwitchListTile.adaptive(
      secondary: const Icon(Icons.timer_outlined),
      title: const Text('Precise scheduling'),
      subtitle: const Text('Ensure reminders fire at the exact minute'),
      value: _exactAlarmOptIn,
      onChanged: (v) => _toggleExactAlarmOptIn(context, v),
    );
  }

  Widget _buildSyncGroup(BuildContext context) {
    final lastSyncStr = _lastBackupTime != null
        ? DateFormat.yMMMd().add_jm().format(_lastBackupTime!)
        : 'Never';

    return Column(
      children: [
        ListTile(
          leading: Icon(_syncType == SyncType.local ? Icons.folder_outlined : Icons.cloud_outlined),
          title: Text(_syncType == SyncType.local ? 'Local Folder Sync' : 'Google Drive Sync'),
          subtitle: Text('Last sync: $lastSyncStr'),
          trailing: IconButton(
            icon: const Icon(Icons.sync),
            onPressed: _isUpdating ? null : _performSync,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SegmentedButton<SyncType>(
            segments: const [
              ButtonSegment(value: SyncType.local, label: Text('Local')),
              ButtonSegment(value: SyncType.googleDrive, label: Text('Google')),
            ],
            selected: {_syncType},
            onSelectionChanged: (Set<SyncType> newSelection) async {
              await SyncService().setSyncType(newSelection.first);
              _load();
            },
          ),
        ),
        if (_syncType == SyncType.local)
          ListTile(
            title: const Text('Sync Location'),
            subtitle: Text(_syncPath ?? 'Not set'),
            onTap: () async {
              await SyncService().setSyncDirectory();
              _load();
            },
          )
        else
          ListTile(
            title: Text(_googleUser?.displayName ?? 'Not signed in'),
            subtitle: Text(_googleUser?.email ?? 'Tap to sign in'),
            leading: _googleUser != null
                ? CircleAvatar(backgroundImage: NetworkImage(_googleUser!.photoUrl ?? ''), radius: 12)
                : null,
            onTap: () async {
              if (_googleUser == null) {
                await GoogleDriveService().signIn();
              } else {
                await GoogleDriveService().signOut();
              }
              _load();
            },
          ),
      ],
    );
  }

  Widget _buildSecurityGroup(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.lock_outline),
          title: Text(_hasPasscode ? 'Change passcode' : 'Enable passcode'),
          onTap: _promptForPasscode,
        ),
        if (_hasPasscode)
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Biometric unlock'),
            value: _biometricEnabled,
            onChanged: _biometricAvailable ? _toggleBiometrics : null,
          ),
      ],
    );
  }

  // --- Actions & Helpers ---

  Future<void> _performSync() async {
    setState(() => _isUpdating = true);
    try {
      await SyncService().performSync();
      await _load();
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Sync complete')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _setGlobalPreference(ReminderChannel channel, bool enabled, Duration leadTime) async {
    final pref = NotificationPreference(
      scopeType: NotificationScopeType.global,
      scopeId: NotificationPreference.globalScopeId,
      channel: channel,
      enabled: enabled,
      leadTime: leadTime,
    );
    await _preferencesRepository.savePreference(pref);
    await _reminderCoordinator.refreshAllContacts();
    _load();
  }

  void _showLeadTimePicker(BuildContext context, ReminderChannel channel, bool enabled, Duration current) {
    final options = _leadTimeOptions(channel, current);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((opt) => ListTile(
            title: Text(_formatLeadTime(channel, opt)),
            trailing: opt == current ? const Icon(Icons.check) : null,
            onTap: () {
              Navigator.pop(context);
              _setGlobalPreference(channel, enabled, opt);
            },
          )).toList(),
        ),
      ),
    );
  }

  List<Duration> _leadTimeOptions(ReminderChannel channel, Duration current) {
    // Simplified common options
    return [const Duration(minutes: 0), const Duration(minutes: 30), const Duration(hours: 1), const Duration(days: 1), current].toSet().toList()..sort();
  }

  String _formatLeadTime(ReminderChannel channel, Duration d) {
    if (d.inMinutes == 0) return 'At scheduled time';
    if (d.inDays > 0) return '${d.inDays} day(s) before';
    if (d.inHours > 0) return '${d.inHours} hour(s) before';
    return '${d.inMinutes} mins before';
  }

  // Re-use logic from previous implementation
  Future<void> _toggleExactAlarmOptIn(BuildContext context, bool value) async {
    final reminderService = ReminderService();
    if (value) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Enable Exact Alarms?'),
          content: const Text('This ensures reminders fire at the precise minute on Android 12+.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Enable')),
          ],
        ),
      );
      if (confirmed != true) return;
      await reminderService.updateExactAlarmOptIn(true);
      await reminderService.requestExactAlarmPermission();
    } else {
      await reminderService.updateExactAlarmOptIn(false);
    }
    _load();
  }

  Future<void> _promptForPasscode() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Passcode'),
        content: TextField(controller: controller, obscureText: true, keyboardType: TextInputType.number),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('Save')),
        ],
      ),
    );
    if (result != null && result.length >= 4) {
      await _securityService.setPasscode(result);
      _load();
    }
  }

  Future<void> _toggleBiometrics(bool value) async {
    await _securityService.setBiometricEnabled(value);
    _load();
  }

  Future<void> _confirmSecurePurge() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Purge All Data?'),
        content: const Text('This will delete all contacts, interactions, and settings. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Purge'), style: TextButton.styleFrom(foregroundColor: Colors.red)),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _isPurging = true);
      await _securityService.secureDeleteAllData();
      await ReminderService().cancelAll();
      _load();
    }
  }

  Future<void> _openExportOptions() async {
    if (_contacts.isEmpty) return;
    showModalBottomSheet(context: context, isScrollControlled: true, builder: (context) => ExportOptionsSheet(contacts: _contacts));
  }
}
