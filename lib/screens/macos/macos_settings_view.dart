import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path/path.dart' as p;

import '../../db/db_helper.dart';
import '../../main.dart'
    show
        CrispColorScheme,
        fontSizeNotifier,
        themeModeNotifier,
        updateFontSize,
        updateThemeMode;
import '../../models/contact.dart';
import '../../models/notification_preference.dart';
import '../../repositories/notification_preferences_repository.dart';
import '../../content/privacy_policy.dart';
import '../../services/ai/ai_feature_gate.dart';
import '../../services/ai/ai_services.dart';
import '../../services/backup_service.dart';
import '../../services/contact_service.dart';
import '../../services/google_drive_service.dart';
import '../../services/import_duplicate_detector.dart';
import '../../services/import_service.dart';
import '../../services/reminder_coordinator.dart';
import '../../services/reminder_service.dart';
import '../../services/security_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/crisp_switch.dart';
import '../../widgets/crisp_toast.dart';
import '../../widgets/export_options_sheet.dart';
import '../../widgets/macos_modal.dart';
import '../import_duplicate_review_page.dart';

enum _SettingsTab { appearance, reminders, sync, security, ai, privacy, data }

extension on _SettingsTab {
  String get label {
    switch (this) {
      case _SettingsTab.appearance:
        return 'Appearance';
      case _SettingsTab.reminders:
        return 'Reminders';
      case _SettingsTab.sync:
        return 'Sync & backup';
      case _SettingsTab.security:
        return 'Security';
      case _SettingsTab.ai:
        return 'AI';
      case _SettingsTab.privacy:
        return 'Privacy';
      case _SettingsTab.data:
        return 'Data';
    }
  }

  IconData get icon {
    switch (this) {
      case _SettingsTab.appearance:
        return Icons.dark_mode_outlined;
      case _SettingsTab.reminders:
        return Icons.notifications_none_outlined;
      case _SettingsTab.sync:
        return Icons.cloud_sync_outlined;
      case _SettingsTab.security:
        return Icons.lock_outline;
      case _SettingsTab.ai:
        return Icons.auto_awesome_outlined;
      case _SettingsTab.privacy:
        return Icons.privacy_tip_outlined;
      case _SettingsTab.data:
        return Icons.storage_outlined;
    }
  }
}

/// Desktop "Settings" section: a macOS System-Settings-style sub-nav (236px)
/// + detail pane, restructured from the previous single-column layout.
/// Reuses the same sync/backup/security/AI services as mobile.
class MacOSSettingsView extends StatefulWidget {
  const MacOSSettingsView({super.key});

  @override
  State<MacOSSettingsView> createState() => _MacOSSettingsViewState();
}

class _MacOSSettingsViewState extends State<MacOSSettingsView> {
  final _dbHelper = DBHelper();
  final _syncService = SyncService();
  final _backupService = BackupService();
  final _googleDriveService = GoogleDriveService();
  final _securityService = SecurityService();
  final _preferencesRepository = NotificationPreferencesRepository();
  final _reminderCoordinator = ReminderCoordinator();

  late final StreamSubscription<GoogleSignInAccount?> _userSubscription;

  _SettingsTab _tab = _SettingsTab.appearance;
  bool _isLoading = true;

  // Sync & backup
  String? _syncPath;
  SyncType _syncType = SyncType.local;
  SyncConfigurationStatus? _configurationStatus;
  GoogleSignInAccount? _googleUser;
  bool _isSyncing = false;
  String? _syncError;

  // Reminders
  Map<ReminderChannel, NotificationPreference> _globalDefaults = {};

  // Security
  bool _hasPasscode = false;
  bool _biometricEnabled = false;
  bool _biometricAvailable = false;

  // AI
  bool _aiEnabled = false;
  bool _hasGeminiKey = false;
  bool _aiBusy = false;

  // Data
  bool _isPurging = false;
  bool _isDeduping = false;

  @override
  void initState() {
    super.initState();
    _userSubscription = _googleDriveService.onUserChanged.listen((user) {
      if (mounted) setState(() => _googleUser = user);
    });
    _loadAll();
  }

  @override
  void dispose() {
    _userSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadAll() async {
    setState(() => _isLoading = true);

    final syncPath = await _syncService.getSyncDirectory();
    final syncType = await _syncService.getSyncType();
    final configurationStatus = await _syncService.getConfigurationStatus();
    final googleUser = await _googleDriveService.currentUser;

    await _preferencesRepository.ensureDefaults();
    final storedPreferences = await _preferencesRepository.loadPreferences();
    final globalDefaults = <ReminderChannel, NotificationPreference>{};
    for (final preference in storedPreferences) {
      if (preference.scopeType == NotificationScopeType.global) {
        globalDefaults[preference.channel] = preference;
      }
    }

    final hasPasscode = await _securityService.hasPasscode();
    final biometricAvailable = await _securityService.canUseBiometrics();
    final biometricEnabled =
        await _securityService.isBiometricEnabled() && biometricAvailable;

    final aiEnabled = await AiServices().gate.isEnabled();
    final hasGeminiKey = await _securityService.hasGeminiApiKey();

    if (!mounted) return;
    setState(() {
      _syncPath = syncPath;
      _syncType = syncType;
      _configurationStatus = configurationStatus;
      _googleUser = googleUser;
      _globalDefaults = globalDefaults;
      _hasPasscode = hasPasscode;
      _biometricAvailable = biometricAvailable;
      _biometricEnabled = biometricEnabled;
      _aiEnabled = aiEnabled;
      _hasGeminiKey = hasGeminiKey;
      _isLoading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Row(
      children: [
        _buildSubNav(colorScheme),
        Expanded(
          child: Container(
            color: colorScheme.surface,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(36, 28, 36, 40),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: _buildTabContent(colorScheme),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSubNav(ColorScheme colorScheme) {
    return Container(
      width: 236,
      decoration: BoxDecoration(
        border: Border(right: BorderSide(color: colorScheme.cardBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 8, bottom: 16),
            child: Text(
              'Settings',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 22,
                color: colorScheme.onSurface,
                letterSpacing: -0.2,
              ),
            ),
          ),
          ..._SettingsTab.values.map((t) => _subNavItem(colorScheme, t)),
        ],
      ),
    );
  }

  Widget _subNavItem(ColorScheme colorScheme, _SettingsTab t) {
    final isSelected = _tab == t;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: () => setState(() => _tab = t),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected ? colorScheme.greenTint : Colors.transparent,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Icon(
                  t.icon,
                  size: 18,
                  color:
                      isSelected ? colorScheme.primary : colorScheme.iconColor,
                ),
                const SizedBox(width: 11),
                Text(
                  t.label,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabContent(ColorScheme colorScheme) {
    switch (_tab) {
      case _SettingsTab.appearance:
        return _buildAppearanceTab(colorScheme);
      case _SettingsTab.reminders:
        return _buildRemindersTab(colorScheme);
      case _SettingsTab.sync:
        return _buildSyncTab(colorScheme);
      case _SettingsTab.security:
        return _buildSecurityTab(colorScheme);
      case _SettingsTab.ai:
        return _buildAiTab(colorScheme);
      case _SettingsTab.privacy:
        return _buildPrivacyTab(colorScheme);
      case _SettingsTab.data:
        return _buildDataTab(colorScheme);
    }
  }

  // ---------- Shared row/card helpers ----------

  Widget _tabTitle(ColorScheme colorScheme, String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 20,
          color: colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _card(ColorScheme colorScheme, {required List<Widget> rows}) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: colorScheme.cardBorder),
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: rows),
    );
  }

  Widget _cardDivider(ColorScheme colorScheme) =>
      Divider(height: 1, color: colorScheme.hairline);

  Widget _row(
    ColorScheme colorScheme, {
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget trailing,
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 20, color: colorScheme.iconColor),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14.5,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        subtitle,
                        style:
                            TextStyle(fontSize: 12, color: colorScheme.outline),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            trailing,
          ],
        ),
      ),
    );
  }

  Widget _pillButton(
    ColorScheme colorScheme,
    String label, {
    bool destructive = false,
    bool filled = false,
    VoidCallback? onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: filled
                ? (destructive ? colorScheme.error : colorScheme.primary)
                : colorScheme.surfaceTint,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: filled
                  ? colorScheme.onPrimary
                  : (destructive ? colorScheme.error : colorScheme.onSurface),
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Appearance ----------

  Widget _buildAppearanceTab(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tabTitle(colorScheme, 'Appearance'),
        _card(colorScheme, rows: [
          ValueListenableBuilder<ThemeMode>(
            valueListenable: themeModeNotifier,
            builder: (context, mode, _) {
              final isDark = mode == ThemeMode.dark;
              return _row(
                colorScheme,
                icon: Icons.dark_mode_outlined,
                title: 'Dark mode',
                subtitle: isDark ? 'On' : 'Off',
                trailing: CrispSwitch(
                  value: isDark,
                  onChanged: (v) =>
                      updateThemeMode(v ? ThemeMode.dark : ThemeMode.light),
                ),
              );
            },
          ),
          _cardDivider(colorScheme),
          ValueListenableBuilder<double>(
            valueListenable: fontSizeNotifier,
            builder: (context, size, _) {
              return Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.format_size_outlined,
                        size: 20, color: colorScheme.iconColor),
                    const SizedBox(width: 14),
                    Text(
                      'Font size',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Expanded(
                      child: Slider(
                        value: size,
                        min: 11,
                        max: 18,
                        divisions: 7,
                        activeColor: colorScheme.primary,
                        inactiveColor: colorScheme.hairline,
                        onChanged: updateFontSize,
                      ),
                    ),
                    Text(
                      '${size.toStringAsFixed(0)} px',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: colorScheme.primary),
                    ),
                  ],
                ),
              );
            },
          ),
        ]),
      ],
    );
  }

  // ---------- Reminders ----------

  Widget _buildRemindersTab(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tabTitle(colorScheme, 'Reminders'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Base settings applied to every follow-up, prayer, and review notification.',
            style: TextStyle(fontSize: 13.5, color: colorScheme.outline),
          ),
        ),
        _card(
          colorScheme,
          rows: [
            for (var i = 0; i < ReminderChannel.values.length; i++) ...[
              if (i > 0) _cardDivider(colorScheme),
              _buildReminderRow(colorScheme, ReminderChannel.values[i]),
            ],
          ],
        ),
      ],
    );
  }

  Widget _buildReminderRow(ColorScheme colorScheme, ReminderChannel channel) {
    final pref = _globalDefaults[channel];
    final enabled = pref?.enabled ?? true;
    final leadTime = pref?.leadTime ?? channel.defaultLeadTime;
    return _row(
      colorScheme,
      icon: Icons.notifications_none_outlined,
      title: channel.label,
      subtitle: _formatLeadTime(leadTime),
      onTap: () => _showLeadTimePicker(channel, enabled, leadTime),
      trailing: CrispSwitch(
        value: enabled,
        onChanged: (v) => _setGlobalPreference(channel, v, leadTime),
      ),
    );
  }

  String _formatLeadTime(Duration d) {
    if (d.inMinutes == 0) return 'At scheduled time';
    if (d.inDays > 0) return '${d.inDays} day(s) before';
    if (d.inHours > 0) return '${d.inHours} hour(s) before';
    return '${d.inMinutes} mins before';
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
    if (mounted) setState(() => _globalDefaults = globalDefaults);
  }

  Future<void> _showLeadTimePicker(
    ReminderChannel channel,
    bool enabled,
    Duration current,
  ) async {
    final options = <Duration>{
      const Duration(minutes: 0),
      const Duration(minutes: 30),
      const Duration(hours: 1),
      const Duration(days: 1),
      current,
    }.toList()
      ..sort();

    await showMacModal<void>(
      context,
      width: 340,
      builder: (context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map(
                (opt) => ListTile(
                  title: Text(_formatLeadTime(opt)),
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

  // ---------- Security ----------

  Widget _buildSecurityTab(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tabTitle(colorScheme, 'Security'),
        _card(colorScheme, rows: [
          _row(
            colorScheme,
            icon: Icons.lock_outline,
            title: _hasPasscode ? 'Change passcode' : 'Enable passcode',
            onTap: _promptForPasscode,
            trailing: Icon(Icons.chevron_right, color: colorScheme.outline),
          ),
          if (_hasPasscode) ...[
            _cardDivider(colorScheme),
            _row(
              colorScheme,
              icon: Icons.fingerprint,
              title: 'Biometric unlock',
              trailing: CrispSwitch(
                value: _biometricEnabled,
                onChanged: _biometricAvailable ? _toggleBiometrics : null,
              ),
            ),
          ],
        ]),
      ],
    );
  }

  Future<void> _promptForPasscode() async {
    final controller = TextEditingController();
    final result = await showMacModal<String>(
      context,
      width: 360,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Set passcode',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 18,
                    color: Theme.of(context).colorScheme.onSurface)),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              obscureText: true,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(hintText: '4+ digits'),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel')),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => Navigator.pop(context, controller.text),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (result != null && result.length >= 4) {
      await _securityService.setPasscode(result);
      await _loadAll();
    }
  }

  Future<void> _toggleBiometrics(bool value) async {
    await _securityService.setBiometricEnabled(value);
    await _loadAll();
  }

  // ---------- AI ----------

  Widget _buildAiTab(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tabTitle(colorScheme, 'AI'),
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Opt-in AI suggestions and semantic search. The on-device model '
            'used on mobile isn\'t available on macOS, so this uses your own '
            'Google Gemini API key instead.',
            style: TextStyle(fontSize: 13.5, color: colorScheme.outline),
          ),
        ),
        _card(colorScheme, rows: [
          _row(
            colorScheme,
            icon: Icons.auto_awesome_outlined,
            title: 'AI features',
            subtitle: _aiEnabled
                ? (_hasGeminiKey
                    ? 'On — using Google Gemini (cloud)'
                    : 'On — add an API key below')
                : 'Off',
            trailing: CrispSwitch(
              value: _aiEnabled,
              onChanged: _aiBusy ? null : _setAiEnabled,
            ),
          ),
          if (_aiEnabled) ...[
            _cardDivider(colorScheme),
            _row(
              colorScheme,
              icon: Icons.vpn_key_outlined,
              title: 'Gemini API key',
              subtitle: _hasGeminiKey ? 'Configured' : 'Not set',
              onTap: _aiBusy ? null : _promptForGeminiApiKey,
              trailing: Icon(Icons.chevron_right, color: colorScheme.outline),
            ),
          ],
        ]),
        const SizedBox(height: 20),
        Text(
          'Ask (semantic search) uses an on-device embedder that downloads the '
          'first time it\'s needed, separate from the toggle above.',
          style: TextStyle(fontSize: 12.5, color: colorScheme.outline),
        ),
      ],
    );
  }

  Future<void> _setAiEnabled(bool value) async {
    setState(() => _aiBusy = true);
    try {
      await AiServices().gate.setEnabled(value);
      if (value) {
        await AiServices().gate.setBackend(AiBackend.cloud);
        await AiServices().refreshBackend();
        if (!await _securityService.hasGeminiApiKey()) {
          if (mounted) await _promptForGeminiApiKey();
        }
      }
    } finally {
      if (mounted) {
        setState(() => _aiBusy = false);
        await _loadAll();
      }
    }
  }

  Future<void> _promptForGeminiApiKey() async {
    final existing = await _securityService.getGeminiApiKey();
    final controller = TextEditingController(text: existing ?? '');
    if (!mounted) return;
    final result = await showMacModal<String>(
      context,
      width: 420,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Google Gemini API key',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
            const SizedBox(height: 8),
            Text(
              'Stored securely on this device and sent only to Google\'s API.',
              style: TextStyle(
                  fontSize: 12.5, color: Theme.of(context).colorScheme.outline),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              autofocus: true,
              decoration: const InputDecoration(hintText: 'AIza…'),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, ''),
                  child: const Text('Clear'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () =>
                      Navigator.pop(context, controller.text.trim()),
                  child: const Text('Save'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _securityService.setGeminiApiKey(result.isEmpty ? null : result);
    await AiServices().refreshBackend();
    if (!mounted) return;
    CrispToast.show(
      context,
      result.isEmpty ? 'Gemini API key cleared' : 'Gemini API key saved',
    );
    await _loadAll();
  }

  // ---------- Privacy ----------

  Widget _buildPrivacyTab(ColorScheme colorScheme) {
    final sections = kPrivacyPolicyText.trim().split('\n\n');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < sections.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              sections[i],
              style: i == 0
                  ? TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 20,
                      color: colorScheme.onSurface,
                    )
                  : TextStyle(
                      fontSize: 14,
                      height: 1.5,
                      color: colorScheme.secondaryText),
            ),
          ),
      ],
    );
  }

  // ---------- Data ----------

  Widget _buildDataTab(ColorScheme colorScheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _tabTitle(colorScheme, 'Data'),
        _card(colorScheme, rows: [
          _row(
            colorScheme,
            icon: Icons.ios_share_outlined,
            title: 'Export data',
            subtitle: 'CSV, PDF, JSON, or encrypted archive',
            onTap: _exportData,
            trailing: Icon(Icons.chevron_right, color: colorScheme.outline),
          ),
          _cardDivider(colorScheme),
          _row(
            colorScheme,
            icon: Icons.file_upload_outlined,
            title: 'Import data',
            subtitle: 'Restore from a backup or migrate from another device',
            onTap: _importData,
            trailing: Icon(Icons.chevron_right, color: colorScheme.outline),
          ),
          _cardDivider(colorScheme),
          _row(
            colorScheme,
            icon: Icons.cleaning_services_outlined,
            title: 'De-duplicate interactions',
            subtitle: 'Find and merge duplicate interaction entries',
            onTap: _isDeduping ? null : _confirmDeDuplicate,
            trailing: _isDeduping
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.chevron_right, color: colorScheme.outline),
          ),
        ]),
        const SizedBox(height: 24),
        Text(
          'DANGER ZONE',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
            color: colorScheme.error,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: colorScheme.dangerBorder),
            color: colorScheme.dangerTint2,
            borderRadius: BorderRadius.circular(14),
          ),
          child: _row(
            colorScheme,
            icon: Icons.delete_forever_outlined,
            title: 'Securely purge all data',
            subtitle:
                'Deletes all contacts, interactions, and settings. Cannot be undone.',
            onTap: _isPurging ? null : _confirmSecurePurge,
            trailing: _isPurging
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : Icon(Icons.chevron_right, color: colorScheme.error),
          ),
        ),
      ],
    );
  }

  Future<void> _confirmDeDuplicate() async {
    setState(() => _isDeduping = true);
    try {
      final duplicates = await _dbHelper.findDuplicateInteractions();
      if (!mounted) return;
      if (duplicates.isEmpty) {
        CrispToast.show(context, 'No duplicate interactions found.');
        return;
      }
      final totalDuplicatesCount =
          duplicates.fold<int>(0, (sum, g) => sum + g.duplicates.length);

      final confirmed = await showMacModal<bool>(
        context,
        width: 420,
        builder: (context) => Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Merge duplicate interactions?',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18)),
              const SizedBox(height: 10),
              Text(
                'Found ${duplicates.length} duplicate groups containing '
                '$totalDuplicatesCount entries to merge. This cannot be undone.',
                style: TextStyle(
                    fontSize: 13.5,
                    color: Theme.of(context).colorScheme.secondaryText),
              ),
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('De-duplicate'),
                  ),
                ],
              ),
            ],
          ),
        ),
      );

      if (confirmed == true) {
        final mergedCount = await _dbHelper.deDuplicateInteractions();
        ContactService().notifyContactsChanged();
        if (!mounted) return;
        CrispToast.show(
          context,
          mergedCount > 0
              ? 'Successfully merged $mergedCount duplicate interactions.'
              : 'No duplicate interactions found.',
        );
      }
    } catch (e) {
      if (mounted) CrispToast.show(context, 'Failed to de-duplicate: $e');
    } finally {
      if (mounted) setState(() => _isDeduping = false);
    }
  }

  Future<void> _confirmSecurePurge() async {
    final confirmed = await showMacModal<bool>(
      context,
      width: 420,
      builder: (context) => Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Purge all data?',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 18,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'This will delete all contacts, interactions, and settings. '
              'This cannot be undone.',
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.pop(context, false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.error,
                  ),
                  onPressed: () => Navigator.pop(context, true),
                  child: const Text('Purge'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      setState(() => _isPurging = true);
      await ReminderService().cancelAll();
      await _securityService.secureDeleteAllData();
      await _loadAll();
      if (mounted) setState(() => _isPurging = false);
    }
  }

  Future<void> _exportData() async {
    final contacts = await _dbHelper.getContacts();
    if (!mounted) return;
    await showMacModal(
      context,
      builder: (_) => ExportOptionsSheet(contacts: contacts),
    );
  }

  Future<void> _importData() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Backup File',
      type: FileType.any,
      allowMultiple: false,
    );

    if (result == null || result.files.isEmpty) return;
    final path = result.files.single.path;
    if (path == null) return;

    final file = File(path);
    if (!await file.exists()) return;

    try {
      final extension = p.extension(path).toLowerCase();
      if (extension == '.json') {
        if (!mounted) return;
        final confirmed = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Overwrite existing data?'),
            content: const Text(
              'Importing this backup will delete all your current contacts, '
              'interactions, and prayer requests. This cannot be undone.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Overwrite and Import'),
              ),
            ],
          ),
        );
        if (confirmed != true) return;

        final aiEnabled = await AiServices().gate.isEnabled();
        final count = await _showLoading(
          () => ImportService().importJsonExport(
            file,
            onDuplicatesFound: aiEnabled ? _reviewDuplicates : null,
          ),
          'Importing contacts…',
        );
        if (!mounted) return;
        if (count < 0) {
          CrispToast.show(context, 'Import cancelled.');
          return;
        }
        CrispToast.show(context, '$count contacts imported successfully');
        return;
      }

      final stat = await file.stat();
      final snapshot = BackupSnapshot(
        path: path,
        modified: stat.modified,
        bytes: stat.size,
      );
      if (!mounted) return;

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Restore backup?'),
          content: Text(
            'This will overwrite your current data with the selected backup:\n\n${p.basename(path)}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Restore'),
            ),
          ],
        ),
      );

      if (confirmed == true) {
        if (!mounted) return;
        await _showLoading(
          () => _backupService.restoreBackup(snapshot,
              overlay: Overlay.of(context)),
          'Restoring backup…',
        );
        await _loadAll();
        if (mounted) CrispToast.show(context, 'Backup restored successfully');
      }
    } catch (e) {
      if (mounted) CrispToast.show(context, 'Error restoring backup: $e');
    }
  }

  Future<List<Contact>?> _reviewDuplicates(
    List<Contact> incoming,
    List<DuplicateGroup> groups,
  ) async {
    if (!mounted) return null;
    Navigator.of(context, rootNavigator: true).pop();
    final resolved = await Navigator.of(context).push<List<Contact>>(
      MaterialPageRoute(
        builder: (_) =>
            ImportDuplicateReviewPage(incoming: incoming, groups: groups),
      ),
    );
    if (!mounted) return resolved;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(),
            SizedBox(width: 24),
            Expanded(child: Text('Importing contacts...')),
          ],
        ),
      ),
    );
    return resolved;
  }

  Future<T> _showLoading<T>(Future<T> Function() action, String message) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        content: Row(
          children: [
            const CircularProgressIndicator(),
            const SizedBox(width: 24),
            Expanded(child: Text(message)),
          ],
        ),
      ),
    );
    try {
      return await action();
    } finally {
      if (mounted) Navigator.of(context).pop();
    }
  }

  // ---------- Sync & backup ----------

  Future<void> _performManualSync() async {
    if (_isSyncing) return;
    setState(() {
      _isSyncing = true;
      _syncError = null;
    });
    try {
      await _syncService.performSync(force: true, rethrowErrors: true);
      await _loadAll();
      if (mounted) CrispToast.show(context, 'Sync complete');
    } catch (e) {
      final message = e.toString().replaceAll('Exception: ', '');
      setState(() => _syncError = message);
      if (mounted) CrispToast.show(context, 'Sync failed: $message');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _setSyncType(SyncType type) async {
    await _syncService.setSyncType(type);
    setState(() => _syncError = null);
    await _loadAll();
  }

  Future<void> _signInWithGoogle() async {
    final user = await _googleDriveService.signIn();
    if (user != null) {
      await _loadAll();
      await _performManualSync();
    } else {
      final error = _googleDriveService.lastSignInError;
      if (error != null && mounted) CrispToast.show(context, error);
    }
  }

  Future<void> _signOutGoogle() async {
    await _googleDriveService.signOut();
    await _loadAll();
  }

  Future<void> _setSyncLocation() async {
    await _syncService.setSyncDirectory();
    setState(() => _syncError = null);
    await _loadAll();
  }

  Widget _buildSyncTab(ColorScheme colorScheme) {
    final needsSetup =
        _configurationStatus != null && !_configurationStatus!.canSync;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _tabTitle(colorScheme, 'Sync & backup'),
            _buildSyncStatusBadge(colorScheme),
          ],
        ),
        Container(
          padding: const EdgeInsets.all(4),
          margin: const EdgeInsets.only(bottom: 14),
          decoration: BoxDecoration(
            color: colorScheme.surfaceTint,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Expanded(
                child: _syncTypeTab(colorScheme, SyncType.local,
                    Icons.folder_outlined, 'Local'),
              ),
              Expanded(
                child: _syncTypeTab(colorScheme, SyncType.googleDrive,
                    Icons.cloud_outlined, 'Google Drive'),
              ),
            ],
          ),
        ),
        _card(colorScheme, rows: [
          if (_syncType == SyncType.local)
            _row(
              colorScheme,
              icon: Icons.folder_outlined,
              title: 'Sync folder',
              subtitle: needsSetup
                  ? (_configurationStatus?.detail ??
                      'Choose a folder shared with your mobile device.')
                  : (_syncPath ?? 'Not configured'),
              onTap: _setSyncLocation,
              trailing: _pillButton(
                  colorScheme, needsSetup ? 'Fix path' : 'Change',
                  destructive: needsSetup, onTap: _setSyncLocation),
            )
          else
            _row(
              colorScheme,
              icon: Icons.account_circle_outlined,
              title: 'Google account',
              subtitle: _googleUser?.email ??
                  'Sign in to sync your data across devices.',
              trailing: _googleUser != null
                  ? _pillButton(colorScheme, 'Sign out',
                      destructive: true, onTap: _signOutGoogle)
                  : _pillButton(colorScheme, 'Sign in',
                      filled: true, onTap: _signInWithGoogle),
            ),
        ]),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text('Activity',
                style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                    color: colorScheme.onSurface)),
            _pillButton(
              colorScheme,
              _isSyncing ? 'Syncing…' : 'Sync now',
              filled: true,
              onTap: _isSyncing ? null : _performManualSync,
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (_syncError != null)
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(
              color: colorScheme.dangerTint2,
              border: Border.all(color: colorScheme.dangerBorder),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(_syncError!,
                style: TextStyle(color: colorScheme.error, fontSize: 13)),
          ),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: colorScheme.aiCardBg,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Row(
            children: [
              const Icon(Icons.terminal, size: 16, color: Color(0xFF94A49B)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  _isSyncing
                      ? 'Sync in progress…'
                      : 'Ready. Last check complete.',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12.5,
                    color: Color(0xFFE8EDE9),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _syncTypeTab(
      ColorScheme colorScheme, SyncType type, IconData icon, String label) {
    final selected = _syncType == type;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () => _setSyncType(type),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 9),
          decoration: BoxDecoration(
            color: selected ? colorScheme.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon,
                  size: 15,
                  color: selected
                      ? colorScheme.onSurface
                      : colorScheme.secondaryText),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: selected
                      ? colorScheme.onSurface
                      : colorScheme.secondaryText,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSyncStatusBadge(ColorScheme colorScheme) {
    String label;
    Color color;
    if (_isSyncing) {
      label = 'Syncing…';
      color = colorScheme.primary;
    } else if (_syncError != null) {
      label = 'Sync failed';
      color = colorScheme.error;
    } else if (_configurationStatus != null && !_configurationStatus!.canSync) {
      label = 'Setup needed';
      color = colorScheme.error;
    } else {
      label = 'Synced';
      color = colorScheme.primary;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11.5, fontWeight: FontWeight.w700, color: color)),
    );
  }
}
