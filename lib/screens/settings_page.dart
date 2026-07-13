import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';

import '../db/db_helper.dart';
import '../models/contact.dart';
import '../models/interaction.dart';
import '../models/notification_preference.dart';
import '../repositories/notification_preferences_repository.dart';
import '../services/contact_service.dart';
import '../services/google_drive_service.dart';
import '../services/reminder_coordinator.dart';
import '../services/reminder_service.dart';
import '../services/security_service.dart';
import '../services/sync_service.dart';
import '../widgets/export_options_sheet.dart';
import '../widgets/skeleton_loader.dart';
import 'ai_settings_page.dart';
import 'privacy_policy_page.dart';

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key});

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage>
    with AutomaticKeepAliveClientMixin {
  final DBHelper _dbHelper = DBHelper();
  final NotificationPreferencesRepository _preferencesRepository =
      NotificationPreferencesRepository();
  final ReminderCoordinator _reminderCoordinator = ReminderCoordinator();
  final SecurityService _securityService = SecurityService();

  late final StreamSubscription<GoogleSignInAccount?> _userSubscription;
  late final StreamSubscription<void> _syncSubscription;

  bool _isLoading = true;
  bool _isUpdating = false;
  bool _isPurging = false;
  bool _supportsExactAlarmPermission = false;
  bool _exactAlarmOptIn = false;
  bool _isGoogleInitializing = true;

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
    final googleService = GoogleDriveService();
    // If it's already done or won't be attempted, we start with false.
    _isGoogleInitializing = googleService.isInitializing;

    _userSubscription = googleService.onUserChanged.listen((user) {
      if (mounted) {
        setState(() {
          _googleUser = user;
          _isGoogleInitializing = googleService.isInitializing;
        });
      }
    });

    _syncSubscription = SyncService().onSyncComplete.listen((_) {
      if (mounted) {
        _loadSyncState();
      }
    });

    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final stopwatch = Stopwatch()..start();

    await _preferencesRepository.ensureDefaults();
    _syncPath = await SyncService().getSyncDirectory();
    _lastBackupTime = await SyncService().getLastBackupTime();
    _syncType = await SyncService().getSyncType();

    // Note: We no longer await GoogleDriveService().currentUser here
    // to prevent blocking page load. The listener in initState handles updates.

    _contacts = await _dbHelper.getContacts();

    // Fetch initial Google user state
    final googleService = GoogleDriveService();
    _googleUser = await googleService.currentUser;
    _isGoogleInitializing = googleService.isInitializing;

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

    final elapsed = stopwatch.elapsedMilliseconds;
    if (elapsed < 300) {
      await Future.delayed(Duration(milliseconds: 300 - elapsed));
    }

    if (mounted) {
      setState(() {
        _globalDefaults = globalDefaults;
        _biometricEnabled = _biometricEnabled && _biometricAvailable;
        _isLoading = false;
      });
    }
  }

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _userSubscription.cancel();
    _syncSubscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const _SettingsSkeleton(key: ValueKey('loading'));
    }

    return RefreshIndicator(
      key: const ValueKey('content'),
      onRefresh: _load,
      child: ListView(
        children: [
          if (_isUpdating || _isPurging)
            const LinearProgressIndicator(minHeight: 2),
          const SizedBox(height: 8),
          _buildSectionHeader('Reminders'),
          _buildCardGroup(
            children: [
              _buildGlobalRemindersTile(context),
              if (_supportsExactAlarmPermission) ...[
                const Divider(height: 1, indent: 16, endIndent: 16),
                _buildExactAlarmTile(context),
              ],
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('Sync & Backup'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 8),
            child: _buildSyncSegmentedButton(),
          ),
          _buildSyncGroup(context),
          const SizedBox(height: 16),
          _buildSectionHeader('Security'),
          _buildCardGroup(
            children: [
              _buildSecurityGroup(context),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('Data'),
          _buildCardGroup(
            children: [
              ListTile(
                leading: const Icon(Icons.ios_share_outlined),
                title: const Text('Export options'),
                subtitle: const Text('CSV, PDF, JSON, or encrypted archive'),
                onTap: _isPurging ? null : _openExportOptions,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.cleaning_services_outlined),
                title: const Text('De-duplicate interactions'),
                subtitle: const Text(
                  'Find and merge duplicate interaction entries',
                ),
                onTap: _isPurging || _isUpdating ? null : _confirmDeDuplicate,
              ),
              const Divider(height: 1, indent: 16, endIndent: 16),
              ListTile(
                leading: const Icon(Icons.delete_forever_outlined),
                title: const Text('Securely purge all data'),
                textColor: Theme.of(context).colorScheme.error,
                iconColor: Theme.of(context).colorScheme.error,
                onTap: _isPurging ? null : _confirmSecurePurge,
              ),
            ],
          ),
          const SizedBox(height: 16),
          _buildSectionHeader('AI & About'),
          _buildCardGroup(
            children: [
              if (_aiSupportedPlatform) ...[
                ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: const Text('AI features'),
                  subtitle: const Text('On-device suggestions, off by default'),
                  onTap: () => Navigator.of(
                    context,
                  ).push(MaterialPageRoute(
                      builder: (_) => const AiSettingsPage())),
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
              ],
              ListTile(
                leading: const Icon(Icons.privacy_tip_outlined),
                title: const Text('Privacy policy'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const PrivacyPolicyPage()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  // flutter_gemma 0.12.6 only ships a viable runtime on Android and iOS.
  // The desktop/web backends either fail at load time or are too rough to
  // expose, so hide the entry rather than letting users hit a runtime error.
  bool get _aiSupportedPlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

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
      shape: const Border(),
      collapsedShape: const Border(),
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
        ? DateFormat.yMMMd().add_jm().format(_lastBackupTime!.toLocal())
        : 'Never';

    final isLocal = _syncType == SyncType.local;

    return _buildCardGroup(
      children: [
        if (isLocal)
          ListTile(
            leading: const Icon(Icons.location_on_outlined),
            title: const Text('Sync Location'),
            subtitle: Text(_syncPath ?? 'Not set'),
            trailing: const Icon(Icons.edit_outlined, size: 20),
            onTap: () async {
              await SyncService().setSyncDirectory();
              await _loadSyncState();
            },
          )
        else if (_isGoogleInitializing && _googleUser == null)
          const SkeletonLoader(
            child: ListTile(
              leading: SkeletonBox(
                width: 24,
                height: 24,
                shape: BoxShape.circle,
              ),
              title: SkeletonBox(width: 120, height: 16),
              subtitle: SkeletonBox(width: 180, height: 12),
              trailing: SkeletonBox(width: 64, height: 32),
            ),
          )
        else
          ListTile(
            leading: _googleUser != null
                ? CircleAvatar(
                    backgroundImage: NetworkImage(_googleUser!.photoUrl ?? ''),
                    radius: 12,
                  )
                : const Icon(Icons.account_circle_outlined),
            title: Text(_googleUser?.displayName ?? 'Sign in to sync'),
            subtitle: Text(_googleUser?.email ?? 'Google Drive integration'),
            trailing: TextButton(
              onPressed: () async {
                if (_googleUser == null) {
                  final messenger = ScaffoldMessenger.of(context);
                  final user = await GoogleDriveService().signIn();
                  if (user == null && mounted) {
                    final error = GoogleDriveService().lastSignInError;
                    if (error != null) {
                      messenger.showSnackBar(SnackBar(content: Text(error)));
                    }
                  }
                } else {
                  await GoogleDriveService().signOut();
                }
                await _loadSyncState();
              },
              child: Text(_googleUser == null ? 'Sign In' : 'Sign Out'),
            ),
          ),
        const Divider(height: 1, indent: 16, endIndent: 16),
        ListTile(
          leading: const Icon(Icons.history),
          title: const Text('Last sync status'),
          subtitle: Text(lastSyncStr),
          trailing: _isUpdating
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  icon: const Icon(Icons.sync),
                  tooltip: 'Sync now',
                  onPressed: _performSync,
                ),
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
        if (_hasPasscode) ...[
          const Divider(height: 1, indent: 16, endIndent: 16),
          SwitchListTile.adaptive(
            secondary: const Icon(Icons.fingerprint),
            title: const Text('Biometric unlock'),
            value: _biometricEnabled,
            onChanged: _biometricAvailable ? _toggleBiometrics : null,
          ),
        ],
      ],
    );
  }

  Widget _buildCardGroup({required List<Widget> children}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      child: Material(
        color: const Color(0xFFFFFFFF),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(
            color: Color(0xFFE6EBE7),
            width: 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }

  Widget _buildSyncSegmentedButton() {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F2), // Surface tint
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: SegmentedButton<SyncType>(
        segments: const [
          ButtonSegment(
            value: SyncType.local,
            label: Text('Local'),
            icon: Icon(Icons.folder_outlined, size: 16),
          ),
          ButtonSegment(
            value: SyncType.googleDrive,
            label: Text('Google Drive'),
            icon: Icon(Icons.cloud_outlined, size: 16),
          ),
        ],
        selected: {_syncType},
        showSelectedIcon: false,
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFFFFFFFF);
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return const Color(0xFF0F1512);
            }
            return const Color(0xFF57635C);
          }),
          elevation: WidgetStateProperty.resolveWith<double>((states) {
            if (states.contains(WidgetState.selected)) {
              return 1.0;
            }
            return 0.0;
          }),
          shadowColor: WidgetStateProperty.all(
              const Color(0xFF000000).withValues(alpha: 0.1)),
          side: WidgetStateProperty.all(BorderSide.none),
          shape: WidgetStateProperty.all(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
          ),
          visualDensity: VisualDensity.compact,
        ),
        onSelectionChanged: (Set<SyncType> newSelection) async {
          final newType = newSelection.first;
          setState(() => _syncType = newType);
          await SyncService().setSyncType(newType);
          await _loadSyncState();
        },
      ),
    );
  }

  // --- Actions & Helpers ---

  Future<void> _loadSyncState() async {
    final syncPath = await SyncService().getSyncDirectory();
    final lastBackupTime = await SyncService().getLastBackupTime();
    final syncType = await SyncService().getSyncType();
    final googleUser = await GoogleDriveService().currentUser;
    if (mounted) {
      setState(() {
        _syncPath = syncPath;
        _lastBackupTime = lastBackupTime;
        _syncType = syncType;
        _googleUser = googleUser;
      });
    }
  }

  Future<void> _performSync() async {
    setState(() => _isUpdating = true);
    try {
      await SyncService().performSync(force: true, rethrowErrors: true);
      await _loadSyncState();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Sync complete')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Sync failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _isUpdating = false);
    }
  }

  Future<void> _setGlobalPreference(
    ReminderChannel channel,
    bool enabled,
    Duration leadTime,
  ) async {
    final pref = NotificationPreference(
      scopeType: NotificationScopeType.global,
      scopeId: NotificationPreference.globalScopeId,
      channel: channel,
      enabled: enabled,
      leadTime: leadTime,
    );
    await _preferencesRepository.savePreference(pref);
    await _reminderCoordinator.refreshAllContacts();
    await _loadRemindersState();
  }

  Future<void> _loadRemindersState() async {
    final storedPreferences = await _preferencesRepository.loadPreferences();
    final globalDefaults = <ReminderChannel, NotificationPreference>{};
    for (final preference in storedPreferences) {
      if (preference.scopeType == NotificationScopeType.global) {
        globalDefaults[preference.channel] = preference;
      }
    }

    final reminderService = ReminderService();
    final supportsExactAlarmPermission =
        await reminderService.isExactAlarmPermissionRelevant();
    final exactAlarmOptIn = await reminderService.isExactAlarmOptInEnabled();

    if (mounted) {
      setState(() {
        _globalDefaults = globalDefaults;
        _supportsExactAlarmPermission = supportsExactAlarmPermission;
        _exactAlarmOptIn = exactAlarmOptIn;
      });
    }
  }

  void _showLeadTimePicker(
    BuildContext context,
    ReminderChannel channel,
    bool enabled,
    Duration current,
  ) {
    final options = _leadTimeOptions(channel, current);
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map(
                (opt) => ListTile(
                  title: Text(_formatLeadTime(channel, opt)),
                  trailing: opt == current ? const Icon(Icons.check) : null,
                  onTap: () async {
                    Navigator.pop(context);
                    await _setGlobalPreference(channel, enabled, opt);
                  },
                ),
              )
              .toList(),
        ),
      ),
    );
  }

  List<Duration> _leadTimeOptions(ReminderChannel channel, Duration current) {
    // Simplified common options
    return {
      const Duration(minutes: 0),
      const Duration(minutes: 30),
      const Duration(hours: 1),
      const Duration(days: 1),
      current,
    }.toList()
      ..sort();
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
          content: const Text(
            'This ensures reminders fire at the precise minute on Android 12+.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Enable'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await reminderService.updateExactAlarmOptIn(true);
      await reminderService.requestExactAlarmPermission();
    } else {
      await reminderService.updateExactAlarmOptIn(false);
    }
    await _loadRemindersState();
  }

  Future<void> _promptForPasscode() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Set Passcode'),
        content: TextField(
          controller: controller,
          obscureText: true,
          keyboardType: TextInputType.number,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result != null && result.length >= 4) {
      await _securityService.setPasscode(result);
      await _loadSecurityState();
    }
  }

  Future<void> _loadSecurityState() async {
    final hasPasscode = await _securityService.hasPasscode();
    final biometricEnabled = await _securityService.isBiometricEnabled();
    final biometricAvailable = await _securityService.canUseBiometrics();
    if (mounted) {
      setState(() {
        _hasPasscode = hasPasscode;
        _biometricEnabled = biometricEnabled && biometricAvailable;
        _biometricAvailable = biometricAvailable;
      });
    }
  }

  Future<void> _toggleBiometrics(bool value) async {
    await _securityService.setBiometricEnabled(value);
    await _loadSecurityState();
  }

  Future<void> _confirmSecurePurge() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Purge All Data?'),
        content: const Text(
          'This will delete all contacts, interactions, and settings. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            child: const Text('Purge'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      setState(() => _isPurging = true);
      await ReminderService().cancelAll();
      await _securityService.secureDeleteAllData();
      _load();
    }
  }

  Future<void> _confirmDeDuplicate() async {
    setState(() => _isUpdating = true);

    // Show a non-dismissible loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 20),
            Text('Scanning for duplicates...'),
          ],
        ),
      ),
    );

    List<InteractionDuplicateGroup> duplicates = [];
    try {
      duplicates = await _dbHelper.findDuplicateInteractions();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to scan for duplicates: $e')),
        );
      }
    } finally {
      if (mounted) {
        Navigator.pop(context); // Dismiss the loading dialog
        setState(() => _isUpdating = false);
      }
    }

    if (duplicates.isEmpty) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('De-duplicate Interactions'),
            content: const Text('No duplicate interactions found.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
      return;
    }

    final totalDuplicatesCount = duplicates.fold<int>(
      0,
      (sum, g) => sum + g.duplicates.length,
    );

    if (!mounted) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Merge Duplicate Interactions?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'We found ${duplicates.length} duplicate groups containing '
              '${totalDuplicatesCount + duplicates.length} total entries. '
              'The primary entries will be updated and $totalDuplicatesCount duplicate '
              'entries will be merged and soft-deleted. This cannot be undone.',
            ),
            const SizedBox(height: 16),
            const Text(
              'Duplicate groups found:',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Material(
              color: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHighest
                  .withValues(alpha: 0.3),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: Theme.of(context)
                      .colorScheme
                      .outline
                      .withValues(alpha: 0.2),
                ),
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.3,
                  ),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final group in duplicates) ...[
                          ListTile(
                            dense: true,
                            contentPadding: EdgeInsets.zero,
                            title: Text(
                              group.primary.summary,
                              style:
                                  const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              '${DateFormat.yMMMd().format(group.primary.occurredAt.toLocal())} • '
                              '${group.duplicates.length} duplicate${group.duplicates.length > 1 ? 's' : ''} to merge',
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('De-duplicate'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      setState(() => _isUpdating = true);
      try {
        final mergedCount = await _dbHelper.deDuplicateInteractions();
        ContactService().notifyContactsChanged();
        await _load();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                mergedCount > 0
                    ? 'Successfully merged $mergedCount duplicate interactions.'
                    : 'No duplicate interactions found.',
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('Failed to de-duplicate: $e')));
        }
      } finally {
        if (mounted) {
          setState(() => _isUpdating = false);
        }
      }
    }
  }

  Future<void> _openExportOptions() async {
    if (_contacts.isEmpty) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ExportOptionsSheet(contacts: _contacts),
    );
  }
}

class _SettingsSkeleton extends StatelessWidget {
  const _SettingsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: ListView(
        padding: const EdgeInsets.symmetric(vertical: 16),
        physics: const NeverScrollableScrollPhysics(),
        children: List.generate(
          10,
          (index) => ListTile(
            leading: const SkeletonBox(
              width: 24,
              height: 24,
              shape: BoxShape.circle,
            ),
            title: SkeletonBox(width: 120 + (index % 4 * 30.0), height: 16),
            subtitle: const SkeletonBox(width: 200, height: 12),
          ),
        ),
      ),
    );
  }
}
