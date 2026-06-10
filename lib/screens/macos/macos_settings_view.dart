import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path/path.dart' as p;

import '../../db/db_helper.dart';
import '../../models/contact.dart';
import '../../services/ai/ai_services.dart';
import '../../services/backup_service.dart';
import '../../services/google_drive_service.dart';
import '../../services/import_duplicate_detector.dart';
import '../../services/sync_service.dart';
import '../../services/import_service.dart';
import '../../widgets/export_options_sheet.dart';
import '../import_duplicate_review_page.dart';

enum _LogTone { normal, info, success, error }

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

  late final StreamSubscription<GoogleSignInAccount?> _userSubscription;

  String? _syncPath;
  bool _isLoading = true;
  SyncType _syncType = SyncType.local;
  SyncConfigurationStatus? _configurationStatus;
  GoogleSignInAccount? _googleUser;
  bool _isSyncing = false;
  String? _syncError;
  final List<Map<String, dynamic>> _logs = [
    {'time': '10:45:02', 'msg': 'Initializing sync service...'},
    {'time': '10:45:03', 'msg': 'Ready.'},
  ];

  void _addLog(String message, {_LogTone tone = _LogTone.normal}) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _logs.add({'time': timeStr, 'msg': message, 'tone': tone});
      if (_logs.length > 10) _logs.removeAt(0);
    });
  }

  Future<void> _performManualSync() async {
    if (_isSyncing) return;

    setState(() {
      _isSyncing = true;
      _syncError = null;
    });
    _addLog('Starting manual sync...', tone: _LogTone.info);

    try {
      await _syncService.performSync(force: true, rethrowErrors: true);
      await _loadSettings();
      _addLog('Sync completed successfully.', tone: _LogTone.success);
    } catch (e) {
      final message = e.toString().replaceAll('Exception: ', '');
      _addLog('Sync failed: $message', tone: _LogTone.error);
      setState(() {
        _syncError = message;
      });
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _userSubscription = _googleDriveService.onUserChanged.listen((user) {
      if (mounted) {
        setState(() => _googleUser = user);
      }
    });
    _loadSettings();
  }

  @override
  void dispose() {
    _userSubscription.cancel();
    super.dispose();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    final syncPath = await _syncService.getSyncDirectory();
    final syncType = await _syncService.getSyncType();
    final configurationStatus = await _syncService.getConfigurationStatus();
    final googleUser = await _googleDriveService.currentUser;

    if (mounted) {
      setState(() {
        _syncPath = syncPath;
        _syncType = syncType;
        _configurationStatus = configurationStatus;
        _googleUser = googleUser;
        _isLoading = false;
      });
    }
  }

  Future<void> _setSyncType(SyncType type) async {
    await _syncService.setSyncType(type);
    setState(() {
      _syncError = null;
    });
    await _loadSettings();
  }

  Future<void> _signInWithGoogle() async {
    final user = await _googleDriveService.signIn();
    if (user != null) {
      await _loadSettings();
      await _performManualSync();
    } else {
      final error = _googleDriveService.lastSignInError;
      if (error != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error)));
      }
    }
  }

  Future<void> _signOutGoogle() async {
    await _googleDriveService.signOut();
    await _loadSettings();
  }

  Future<void> _setSyncLocation() async {
    await _syncService.setSyncDirectory();
    setState(() {
      _syncError = null;
    });
    await _loadSettings();
  }

  Future<void> _exportData() async {
    final contacts = await _dbHelper.getContacts(); // Simplistic fetch for now
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => ExportOptionsSheet(contacts: contacts),
    );
  }

  Future<void> _importData() async {
    final result = await FilePicker.platform.pickFiles(
      dialogTitle: 'Select Backup File',
      type: FileType.any, // .db files
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
          'Importing contacts...\nThis may take a while...',
        );
        if (!mounted) return;
        if (count < 0) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('Import cancelled.')));
          return;
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$count contacts imported successfully')),
        );
        return;
      }

      // Create a snapshot wrapper for the selected file
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
          title: const Text('Restore Backup?'),
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
          () => _backupService.restoreBackup(
            snapshot,
            messenger: ScaffoldMessenger.of(context),
          ),
          'Restoring backup...\nThis may take a while...',
        );
        await _loadSettings();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Backup restored successfully')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error restoring backup: $e')));
      }
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
      if (mounted) {
        Navigator.of(context).pop();
      }
    }
  }

  Widget _buildSyncStatusBadge() {
    final colorScheme = Theme.of(context).colorScheme;
    final configurationStatus = _configurationStatus;

    if (_isSyncing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer,
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Syncing...',
              style: GoogleFonts.googleSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.onPrimaryContainer,
              ),
            ),
          ],
        ),
      );
    }

    if (_syncError != null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.24)),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              Icons.sync_problem,
              size: 16,
              color: colorScheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Text(
              'Sync Failed',
              style: GoogleFonts.googleSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.onErrorContainer,
              ),
            ),
          ],
        ),
      );
    }

    if (configurationStatus != null && !configurationStatus.canSync) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.tertiaryContainer,
          border: Border.all(
            color: colorScheme.tertiary.withValues(alpha: 0.24),
          ),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            Icon(
              Icons.sync_problem,
              size: 16,
              color: colorScheme.onTertiaryContainer,
            ),
            const SizedBox(width: 8),
            Text(
              'Setup Needed',
              style: GoogleFonts.googleSans(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.onTertiaryContainer,
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.secondaryContainer,
        border: Border.all(
          color: colorScheme.secondary.withValues(alpha: 0.24),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          Icon(
            Icons.cloud_done,
            size: 16,
            color: colorScheme.onSecondaryContainer,
          ),
          const SizedBox(width: 8),
          Text(
            'Synced',
            style: GoogleFonts.googleSans(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSecondaryContainer,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Toolbar
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(color: colorScheme.outlineVariant),
            ),
            color: colorScheme.surfaceContainerLowest.withValues(alpha: 0.8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sync & Settings',
                style: GoogleFonts.googleSans(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              _buildSyncStatusBadge(),
            ],
          ),
        ),
        // Scrollable Content
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(48),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 672), // max-w-2xl
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Storage Configuration Section
                    _buildSectionHeader('Storage Configuration'),
                    const SizedBox(height: 12),
                    if (_syncType == SyncType.local)
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.outlineVariant),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withValues(alpha: 0.05),
                              offset: const Offset(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Column(
                          children: [
                            // Sync Type Switch
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Sync Method',
                                    style: GoogleFonts.googleSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  SegmentedButton<SyncType>(
                                    segments: const [
                                      ButtonSegment(
                                        value: SyncType.local,
                                        label: Text('Local'),
                                        icon: Icon(
                                          Icons.folder_outlined,
                                          size: 14,
                                        ),
                                      ),
                                      ButtonSegment(
                                        value: SyncType.googleDrive,
                                        label: Text('Drive'),
                                        icon: Icon(
                                          Icons.cloud_outlined,
                                          size: 14,
                                        ),
                                      ),
                                    ],
                                    selected: {_syncType},
                                    onSelectionChanged:
                                        (Set<SyncType> newSelection) {
                                      _setSyncType(newSelection.first);
                                    },
                                    style: ButtonStyle(
                                      textStyle: WidgetStateProperty.all(
                                        GoogleFonts.googleSans(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(
                              height: 1,
                              color: colorScheme.outlineVariant,
                            ),
                            // Backup Location with Error State Support
                            Container(
                              color: _configurationStatus?.canSync == false
                                  ? colorScheme.errorContainer
                                  : colorScheme.surfaceContainerLowest,
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Text(
                                              'Sync Folder',
                                              style: GoogleFonts.googleSans(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: _configurationStatus
                                                            ?.canSync ==
                                                        false
                                                    ? colorScheme
                                                        .onErrorContainer
                                                    : colorScheme.onSurface,
                                              ),
                                            ),
                                            if (_configurationStatus?.canSync ==
                                                false) ...[
                                              const SizedBox(width: 8),
                                              Icon(
                                                Icons.error,
                                                size: 18,
                                                color: colorScheme.error,
                                              ),
                                            ],
                                          ],
                                        ),
                                        if (_configurationStatus?.canSync ==
                                            false) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            _configurationStatus?.detail ??
                                                'Choose a folder shared with your mobile device.',
                                            style: GoogleFonts.googleSans(
                                              fontSize: 12,
                                              color:
                                                  colorScheme.onErrorContainer,
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            _syncPath ?? 'Not Configured',
                                            style: GoogleFonts.ibmPlexMono(
                                              fontSize: 12,
                                              color:
                                                  colorScheme.onErrorContainer,
                                            ),
                                          ),
                                        ] else ...[
                                          const SizedBox(height: 8),
                                          _buildPathBadge(
                                            _syncPath!,
                                            Icons.folder,
                                          ),
                                        ],
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  _buildActionButton(
                                    _configurationStatus?.canSync == false
                                        ? 'Fix Path...'
                                        : 'Change...',
                                    isDestructive:
                                        _configurationStatus?.canSync == false,
                                    onTap: _setSyncLocation,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.outlineVariant),
                          boxShadow: [
                            BoxShadow(
                              color: colorScheme.shadow.withValues(alpha: 0.05),
                              offset: const Offset(0, 1),
                              blurRadius: 2,
                            ),
                          ],
                        ),
                        child: Column(
                          children: [
                            Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'Sync Method',
                                    style: GoogleFonts.googleSans(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  SegmentedButton<SyncType>(
                                    segments: const [
                                      ButtonSegment(
                                        value: SyncType.local,
                                        label: Text('Local'),
                                        icon: Icon(
                                          Icons.folder_outlined,
                                          size: 14,
                                        ),
                                      ),
                                      ButtonSegment(
                                        value: SyncType.googleDrive,
                                        label: Text('Drive'),
                                        icon: Icon(
                                          Icons.cloud_outlined,
                                          size: 14,
                                        ),
                                      ),
                                    ],
                                    selected: {_syncType},
                                    onSelectionChanged:
                                        (Set<SyncType> newSelection) {
                                      _setSyncType(newSelection.first);
                                    },
                                    style: ButtonStyle(
                                      textStyle: WidgetStateProperty.all(
                                        GoogleFonts.googleSans(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(
                              height: 1,
                              color: colorScheme.outlineVariant,
                            ),
                            _buildGoogleSignInRow(),
                          ],
                        ),
                      ),

                    const SizedBox(height: 40),

                    // Data Management Section
                    _buildSectionHeader('Data Management'),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerLowest,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withValues(alpha: 0.05),
                            offset: const Offset(0, 1),
                            blurRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          _buildSettingRow(
                            title: 'Export Data',
                            description:
                                'Generate a portable JSON dump of all contacts, prayer requests, and session logs.',
                            action: _buildActionButton(
                              'Export JSON...',
                              icon: Icons.download,
                              isPrimary:
                                  false, // Changed to match design (white button)
                              onTap: _exportData,
                            ),
                            isLast: false,
                          ),
                          _buildSettingRow(
                            title: 'Import Data',
                            description:
                                'Restore from a previous backup or migrate from another device.',
                            action: _buildActionButton(
                              'Import...',
                              onTap: _importData,
                            ),
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),

                    // Sync Status Section
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _buildSectionHeader('Sync Status'),
                        _buildStatusBadge(),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.inverseSurface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant),
                        boxShadow: [
                          BoxShadow(
                            color: colorScheme.shadow.withValues(alpha: 0.2),
                            offset: const Offset(0, 2),
                            blurRadius: 4,
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.inverseSurface,
                              border: Border(
                                bottom: BorderSide(
                                  color: colorScheme.onInverseSurface
                                      .withValues(alpha: 0.24),
                                ),
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.terminal,
                                  size: 14,
                                  color: colorScheme.onInverseSurface,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Activity Log',
                                  style: GoogleFonts.ibmPlexMono(
                                    fontSize: 12,
                                    color: colorScheme.onInverseSurface,
                                  ),
                                ),
                                const Spacer(),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap:
                                        _isSyncing ? null : _performManualSync,
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          if (_isSyncing)
                                            SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color:
                                                    colorScheme.inversePrimary,
                                              ),
                                            )
                                          else
                                            Icon(
                                              Icons.refresh,
                                              size: 14,
                                              color: colorScheme.inversePrimary,
                                            ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _isSyncing
                                                ? 'Syncing...'
                                                : 'Sync Now',
                                            style: GoogleFonts.googleSans(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: colorScheme.inversePrimary,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            height: 192, // h-48
                            padding: const EdgeInsets.all(16),
                            child: ListView.builder(
                              itemCount: _logs.length,
                              itemBuilder: (context, index) {
                                final log = _logs[index];
                                return _buildLogEntry(
                                  '[${log['time']}]',
                                  log['msg'],
                                  tone: log['tone'] as _LogTone? ??
                                      _LogTone.normal,
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        _buildIndicator('File System', _LogTone.success),
                        const SizedBox(width: 24),
                        _buildIndicator(
                          _syncType == SyncType.googleDrive
                              ? 'Google Drive'
                              : 'Shared Folder',
                          _configurationStatus?.canSync == true
                              ? _LogTone.success
                              : _LogTone.info,
                          isDimmed: _configurationStatus?.canSync != true,
                        ),
                        const SizedBox(width: 24),
                        _buildIndicator(
                          'Mobile Ready',
                          _configurationStatus?.canSync == true
                              ? _LogTone.success
                              : _LogTone.error,
                          isDimmed: _configurationStatus?.canSync != true,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.googleSans(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildSettingRow({
    required String title,
    String? description,
    Widget? content,
    required Widget action,
    required bool isLast,
    Color? backgroundColor,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    // If we have an error state (red background), display that style
    final bool isError = backgroundColor != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: isLast
            ? null
            : Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isError)
                  Row(
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.googleSans(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onErrorContainer,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Icon(Icons.error, size: 18, color: colorScheme.error),
                    ],
                  )
                else
                  Text(
                    title,
                    style: GoogleFonts.googleSans(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: GoogleFonts.googleSans(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (content != null) ...[
                  if (description == null && !isError)
                    const SizedBox(height: 4),
                  content,
                ],
              ],
            ),
          ),
          const SizedBox(width: 16),
          action,
        ],
      ),
    );
  }

  Widget _buildPathBadge(String path, IconData icon) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border.all(color: colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              path,
              style: GoogleFonts.ibmPlexMono(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton(
    String label, {
    bool isDestructive = false,
    bool isPrimary = false,
    IconData? icon,
    VoidCallback? onTap,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    Color textColor;
    Color borderColor;
    Color backgroundColor = colorScheme.surfaceContainerLowest;

    if (isDestructive) {
      textColor = colorScheme.error;
      borderColor = colorScheme.error.withValues(alpha: 0.24);
    } else if (isPrimary) {
      textColor = colorScheme.primary;
      borderColor = colorScheme.outlineVariant;
    } else {
      textColor = colorScheme.primary;
      borderColor = colorScheme.outlineVariant;
    }

    if (label == 'Export JSON...') {
      textColor = colorScheme.primary;
      borderColor = colorScheme.outlineVariant;
    } else if (label == 'Import...') {
      textColor = colorScheme.onSurface;
      borderColor = colorScheme.outlineVariant;
    } else if (label == 'Fix Path...') {
      textColor = colorScheme.error;
      borderColor = colorScheme.error.withValues(alpha: 0.24);
    }

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            offset: const Offset(0, 1),
            blurRadius: 2,
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: textColor),
                  const SizedBox(width: 8),
                ],
                Text(
                  label,
                  style: GoogleFonts.googleSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStatusBadge() {
    final colorScheme = Theme.of(context).colorScheme;
    final isReady = _configurationStatus?.canSync == true;
    final statusColor = isReady ? colorScheme.primary : colorScheme.tertiary;
    return Row(
      children: [
        SizedBox(
          width: 10,
          height: 10,
          child: Stack(
            children: [
              // Ping animation would go here
              Container(
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
              ),
              Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: statusColor,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          isReady ? 'Operational' : 'Setup Needed',
          style: GoogleFonts.googleSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: statusColor,
          ),
        ),
      ],
    );
  }

  Color _logToneColor(_LogTone tone, ColorScheme colorScheme) {
    return switch (tone) {
      _LogTone.info => colorScheme.inversePrimary,
      _LogTone.success => colorScheme.primaryFixedDim,
      _LogTone.error => colorScheme.error,
      _LogTone.normal => colorScheme.onInverseSurface,
    };
  }

  Widget _buildLogEntry(
    String timestamp,
    String message, {
    _LogTone tone = _LogTone.normal,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            timestamp,
            style: GoogleFonts.ibmPlexMono(
              fontSize: 12,
              color: colorScheme.onInverseSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.ibmPlexMono(
                fontSize: 12,
                color: _logToneColor(tone, colorScheme),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicator(String label, _LogTone tone, {bool isDimmed = false}) {
    final colorScheme = Theme.of(context).colorScheme;
    final finalColor = _logToneColor(tone, colorScheme);

    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: finalColor,
            shape: BoxShape.circle,
            boxShadow: label == 'File System'
                ? [
                    BoxShadow(
                      color: finalColor.withValues(alpha: 0.6),
                      blurRadius: 8,
                      spreadRadius: 0,
                    ),
                  ]
                : null,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.googleSans(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant.withValues(
              alpha: isDimmed ? 0.7 : 1,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleSignInRow() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Google Account',
                  style: GoogleFonts.googleSans(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                if (_googleUser != null)
                  Text(
                    _configurationStatus?.detail ?? _googleUser!.email,
                    style: GoogleFonts.googleSans(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  )
                else
                  Text(
                    _configurationStatus?.detail ??
                        'Sign in to sync your data across devices.',
                    style: GoogleFonts.googleSans(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          if (_googleUser != null)
            _buildActionButton(
              'Sign Out',
              isDestructive: true,
              onTap: _signOutGoogle,
            )
          else
            _buildActionButton(
              'Sign In',
              isPrimary: true,
              onTap: _signInWithGoogle,
            ),
        ],
      ),
    );
  }
}
