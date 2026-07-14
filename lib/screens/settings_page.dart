import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:intl/intl.dart';

import '../main.dart'
    show
        fontSizeNotifier,
        updateFontSize,
        themeModeNotifier,
        updateThemeMode,
        CrispColorScheme;
import '../widgets/crisp_switch.dart';
import '../widgets/crisp_toast.dart';
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
import 'notification_settings_page.dart';
import 'privacy_policy_page.dart';
import '../widgets/hide_on_scroll_scaffold.dart';

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
    final colorScheme = Theme.of(context).colorScheme;
    final double screenWidth = MediaQuery.of(context).size.width;
    final bool isSmallScreen = screenWidth < 390;
    final double titleSize = isSmallScreen ? 26.0 : 34.0;

    return HideOnScrollScaffold(
      appBar: AppBar(
        title: Text(
          'Settings',
          style: TextStyle(
            fontSize: titleSize,
            fontWeight: FontWeight.w800,
            color: colorScheme.onSurface,
            letterSpacing: -0.6,
          ),
        ),
        titleSpacing: 22,
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        toolbarHeight: 64,
      ),
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

    final colorScheme = Theme.of(context).colorScheme;
    return RefreshIndicator(
      key: const ValueKey('content'),
      onRefresh: _load,
      child: ListTileTheme.merge(
        titleTextStyle: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w700,
          color: colorScheme.onSurface,
        ),
        subtitleTextStyle: TextStyle(
          fontSize: 12.5,
          color: colorScheme.outline,
        ),
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
                const Divider(height: 1, indent: 16, endIndent: 16),
                ListTile(
                  leading: const Icon(Icons.person_pin_circle_outlined),
                  title: const Text('Contact & category overrides'),
                  subtitle: const Text(
                    'Customize reminders for a specific person or category',
                  ),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const NotificationSettingsPage(),
                    ),
                  ),
                ),
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
            _buildSectionHeader('Display'),
            _buildCardGroup(
              children: [
                _buildDarkModeTile(context),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _buildFontSizeTile(context),
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
                    subtitle:
                        const Text('On-device suggestions, off by default'),
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
                    MaterialPageRoute(
                        builder: (_) => const PrivacyPolicyPage()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
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
      padding: const EdgeInsets.fromLTRB(22, 16, 22, 10),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: Theme.of(context).colorScheme.outline,
        ),
      ),
    );
  }

  Widget _buildDarkModeTile(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, themeMode, child) {
        final isDark = themeMode == ThemeMode.dark;
        return ListTile(
          leading: const Icon(Icons.dark_mode_outlined),
          title: const Text('Dark mode'),
          subtitle: Text(
            isDark
                ? 'On · easier on the eyes at night'
                : 'Off · matches light theme',
          ),
          trailing: CrispSwitch(
            value: isDark,
            onChanged: (value) {
              updateThemeMode(value ? ThemeMode.dark : ThemeMode.light);
            },
          ),
        );
      },
    );
  }

  Widget _buildFontSizeTile(BuildContext context) {
    return ValueListenableBuilder<double>(
      valueListenable: fontSizeNotifier,
      builder: (context, currentSize, child) {
        final colorScheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              leading: const Icon(Icons.format_size_outlined),
              title: const Text('Font size'),
              trailing: Text(
                '${currentSize.toStringAsFixed(0)} px',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  color: colorScheme.primary,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Text('A', style: TextStyle(fontSize: 12)),
                  Expanded(
                    child: Slider(
                      value: currentSize,
                      min: 11.0,
                      max: 18.0,
                      divisions: 7,
                      activeColor: colorScheme.primary,
                      inactiveColor: colorScheme.hairline,
                      onChanged: (newSize) {
                        updateFontSize(newSize);
                      },
                    ),
                  ),
                  const Text('A',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                ],
              ),
            ),
          ],
        );
      },
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
          trailing: CrispSwitch(
            value: enabled,
            onChanged: (v) => _setGlobalPreference(channel, v, leadTime),
          ),
          onTap: () => _showLeadTimePicker(context, channel, enabled, leadTime),
        );
      }).toList(),
    );
  }

  Widget _buildExactAlarmTile(BuildContext context) {
    return ListTile(
      leading: const Icon(Icons.timer_outlined),
      title: const Text('Precise scheduling'),
      subtitle: const Text('Ensure reminders fire at the exact minute'),
      trailing: CrispSwitch(
        value: _exactAlarmOptIn,
        onChanged: (v) => _toggleExactAlarmOptIn(context, v),
      ),
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
                  final overlay = Overlay.of(context);
                  final user = await GoogleDriveService().signIn();
                  if (user == null && mounted) {
                    final error = GoogleDriveService().lastSignInError;
                    if (error != null) {
                      CrispToast.showOnOverlay(overlay, error);
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
          ListTile(
            leading: const Icon(Icons.fingerprint),
            title: const Text('Biometric unlock'),
            trailing: CrispSwitch(
              value: _biometricEnabled,
              onChanged: _biometricAvailable ? _toggleBiometrics : null,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildCardGroup({required List<Widget> children}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 4),
      child: Material(
        color: colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(
            color: colorScheme.cardBorder,
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
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceTint,
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
              return colorScheme.surface;
            }
            return Colors.transparent;
          }),
          foregroundColor: WidgetStateProperty.resolveWith<Color>((states) {
            if (states.contains(WidgetState.selected)) {
              return colorScheme.onSurface;
            }
            return colorScheme.secondaryText;
          }),
          elevation: WidgetStateProperty.resolveWith<double>((states) {
            if (states.contains(WidgetState.selected)) {
              return 1.0;
            }
            return 0.0;
          }),
          shadowColor: WidgetStateProperty.all(
              colorScheme.shadow.withValues(alpha: 0.1)),
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
        CrispToast.show(context, 'Sync complete');
      }
    } catch (e) {
      if (mounted) {
        CrispToast.show(context, 'Sync failed: $e');
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

  List<String> _getProposedChanges(
      InteractionDuplicateGroup group, Map<String, String> contactNames) {
    final primary = group.primary;
    final duplicates = group.duplicates;
    final changes = <String>[];

    // 1. Participant IDs
    final primaryParticipants = primary.participantIds.toSet();
    final addedParticipants = <String>{};
    for (final dup in duplicates) {
      for (final pid in dup.participantIds) {
        if (!primaryParticipants.contains(pid)) {
          final name = contactNames[pid] ?? pid;
          addedParticipants.add(name);
        }
      }
    }
    if (addedParticipants.isNotEmpty) {
      changes.add('Add participants: ${addedParticipants.join(", ")}');
    }

    // 2. Location
    String? mergedLocation = primary.location;
    for (final dup in duplicates) {
      if ((mergedLocation == null || mergedLocation.isEmpty) &&
          dup.location != null &&
          dup.location!.isNotEmpty) {
        mergedLocation = dup.location;
      }
    }
    if (mergedLocation != primary.location && mergedLocation != null) {
      changes.add('Location: [None] → "$mergedLocation"');
    }

    // 3. Mark for prayer
    bool mergedMarkForPrayer = primary.markForPrayer;
    for (final dup in duplicates) {
      if (dup.markForPrayer) {
        mergedMarkForPrayer = true;
      }
    }
    if (mergedMarkForPrayer != primary.markForPrayer) {
      changes.add('Mark for prayer: false → true');
    }

    // 4. Duration
    int? mergedDuration = primary.durationMinutes;
    for (final dup in duplicates) {
      if (dup.durationMinutes != null) {
        if (mergedDuration == null || dup.durationMinutes! > mergedDuration) {
          mergedDuration = dup.durationMinutes;
        }
      }
    }
    if (mergedDuration != primary.durationMinutes) {
      changes.add(
          'Duration: ${primary.durationMinutes != null ? "${primary.durationMinutes} mins" : "[None]"} → $mergedDuration mins');
    }

    // 5. Follow up
    DateTime? mergedFollowUp = primary.followUpAt;
    for (final dup in duplicates) {
      if (mergedFollowUp == null && dup.followUpAt != null) {
        mergedFollowUp = dup.followUpAt;
      }
    }
    if (mergedFollowUp != primary.followUpAt && mergedFollowUp != null) {
      changes.add(
          'Follow up: [None] → ${DateFormat.yMMMd().format(mergedFollowUp.toLocal())}');
    }

    // 6. Notes
    var mergedNotes = primary.notes;
    bool notesAppended = false;
    for (final dup in duplicates) {
      if (dup.notes != null && dup.notes!.isNotEmpty) {
        if (mergedNotes == null || mergedNotes.isEmpty) {
          mergedNotes = dup.notes;
          notesAppended = true;
        } else if (mergedNotes != dup.notes &&
            !mergedNotes.contains(dup.notes!)) {
          mergedNotes = '$mergedNotes\n${dup.notes}';
          notesAppended = true;
        }
      }
    }
    if (notesAppended) {
      changes.add('Notes: Appended additional notes');
    }

    // 7. Attachments
    final primaryAttachments = primary.attachments.map((a) => a.uri).toSet();
    int newAttachmentsCount = 0;
    for (final dup in duplicates) {
      for (final att in dup.attachments) {
        if (!primaryAttachments.contains(att.uri)) {
          newAttachmentsCount++;
          primaryAttachments.add(att.uri);
        }
      }
    }
    if (newAttachmentsCount > 0) {
      changes.add('Attachments: Added $newAttachmentsCount new attachment(s)');
    }

    return changes;
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
        CrispToast.show(context, 'Failed to scan for duplicates: $e');
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

    Map<String, String> contactNames = {};
    try {
      final contactsList = await ContactService().getContacts();
      for (final c in contactsList) {
        contactNames[c.id] = c.displayName;
      }
    } catch (e) {
      debugPrint('Failed to load contacts for dry run: $e');
    }

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
                            subtitle: Builder(
                              builder: (context) {
                                final groupChanges =
                                    _getProposedChanges(group, contactNames);
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${DateFormat.yMMMd().format(group.primary.occurredAt.toLocal())} • '
                                      '${group.duplicates.length} duplicate${group.duplicates.length > 1 ? 's' : ''} to merge',
                                    ),
                                    if (groupChanges.isNotEmpty) ...[
                                      const SizedBox(height: 4),
                                      const Text(
                                        'Changes to apply:',
                                        style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 11),
                                      ),
                                      for (final change in groupChanges)
                                        Padding(
                                          padding: const EdgeInsets.only(
                                              left: 8.0, top: 2.0),
                                          child: Text(
                                            '• $change',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: Theme.of(context)
                                                  .colorScheme
                                                  .primary,
                                            ),
                                          ),
                                        ),
                                    ] else ...[
                                      const SizedBox(height: 2),
                                      Text(
                                        '• No field changes (duplicate rows will be soft-deleted)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ],
                                );
                              },
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
          CrispToast.show(
            context,
            mergedCount > 0
                ? 'Successfully merged $mergedCount duplicate interactions.'
                : 'No duplicate interactions found.',
          );
        }
      } catch (e) {
        if (mounted) {
          CrispToast.show(context, 'Failed to de-duplicate: $e');
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
