import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path/path.dart' as p;

import '../../db/db_helper.dart';
import '../../services/backup_service.dart';
import '../../services/google_drive_service.dart';
import '../../services/sync_service.dart';
import '../../services/import_service.dart';
import '../../widgets/export_options_sheet.dart';

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

  String? _syncPath;
  bool _isLoading = true;
  SyncType _syncType = SyncType.local;
  GoogleSignInAccount? _googleUser;
  bool _isSyncing = false;
  String? _syncError;
  final List<Map<String, dynamic>> _logs = [
    {'time': '10:45:02', 'msg': 'Initializing sync service...'},
    {'time': '10:45:03', 'msg': 'Ready.'},
  ];

  void _addLog(String message, {Color? color}) {
    final now = DateTime.now();
    final timeStr =
        '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}:${now.second.toString().padLeft(2, '0')}';
    setState(() {
      _logs.add({'time': timeStr, 'msg': message, 'color': color});
      if (_logs.length > 10) _logs.removeAt(0);
    });
  }

  Future<void> _performManualSync() async {
    if (_isSyncing) return;

    setState(() {
      _isSyncing = true;
      _syncError = null;
    });
    _addLog('Starting manual sync...', color: const Color(0xFF60A5FA));

    try {
      await _syncService.performSync(force: true);
      _addLog('Sync completed successfully.', color: const Color(0xFF4ADE80));
    } catch (e) {
      _addLog('Sync failed: $e', color: const Color(0xFFEF4444));
      setState(() {
        _syncError = e.toString().replaceAll('Exception: ', '');
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
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    setState(() => _isLoading = true);

    final syncPath = await _syncService.getSyncDirectory();
    final syncType = await _syncService.getSyncType();
    final googleUser = await _googleDriveService.currentUser;

    if (mounted) {
      setState(() {
        _syncPath = syncPath;
        _syncType = syncType;
        _googleUser = googleUser;
        _isLoading = false;
      });
    }
  }

  Future<void> _setSyncType(SyncType type) async {
    await _syncService.setSyncType(type);
    await _loadSettings();
  }

  Future<void> _signInWithGoogle() async {
    final user = await _googleDriveService.signIn();
    if (user != null) {
      await _loadSettings();
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
    await _loadSettings();
  }

  Future<void> _exportData() async {
    final contacts = await _dbHelper.getContacts(); // Simplistic fetch for now
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
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
        final count = await _showLoading(
          () => ImportService().importJsonExport(file),
          'Importing contacts...',
        );
        if (!mounted) return;
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
          'Restoring backup...',
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
    if (_isSyncing) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF), // blue-50
          border: Border.all(color: const Color(0xFFDBEAFE)), // blue-100
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFF3B82F6),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              'Syncing...',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFF1D4ED8), // blue-700
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
          color: const Color(0xFFFEF2F2), // red-50
          border: Border.all(color: const Color(0xFFFECACA)), // red-200
          borderRadius: BorderRadius.circular(4),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.sync_problem,
              size: 16,
              color: Color(0xFFB91C1C),
            ), // red-700
            const SizedBox(width: 8),
            Text(
              'Sync Failed',
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: const Color(0xFFB91C1C),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: const Color(0xFFF0FDF4), // green-50
        border: Border.all(color: const Color(0xFFBBF7D0)), // green-200
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_done,
            size: 16,
            color: Color(0xFF15803D),
          ), // green-700
          const SizedBox(width: 8),
          Text(
            'Synced',
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: const Color(0xFF15803D),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Column(
      children: [
        // Toolbar
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE5E5E5))),
            color: Color(0xCCFFFFFF), // white/80
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Sync & Settings',
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                  color: Colors.black,
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE5E5E5)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color.fromRGBO(0, 0, 0, 0.05),
                              offset: Offset(0, 1),
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
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black,
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
                                        GoogleFonts.inter(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFE5E5E5)),
                            // Backup Location with Error State Support
                            Container(
                              color: _syncPath == null
                                  ? const Color(0xFFFEF2F2) // red-50
                                  : Colors.white,
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
                                              'Backup Location',
                                              style: GoogleFonts.inter(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                                color: _syncPath == null
                                                    ? const Color(
                                                        0xFF7F1D1D,
                                                      ) // red-900
                                                    : Colors.black,
                                              ),
                                            ),
                                            if (_syncPath == null) ...[
                                              const SizedBox(width: 8),
                                              const Icon(
                                                Icons.error,
                                                size: 18,
                                                color: Color(0xFFDC2626),
                                              ), // red-600
                                            ],
                                          ],
                                        ),
                                        if (_syncPath == null) ...[
                                          const SizedBox(height: 4),
                                          Text(
                                            'Path not found or invalid permissions.',
                                            style: GoogleFonts.inter(
                                              fontSize: 12,
                                              color: const Color(0xFFB91C1C),
                                            ), // red-700
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            'Not Configured',
                                            style: GoogleFonts.ibmPlexMono(
                                              fontSize: 12,
                                              color: const Color(0xFF991B1B),
                                            ), // red-800
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
                                    _syncPath == null
                                        ? 'Fix Path...'
                                        : 'Change...',
                                    isDestructive: _syncPath == null,
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
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE5E5E5)),
                          boxShadow: const [
                            BoxShadow(
                              color: Color.fromRGBO(0, 0, 0, 0.05),
                              offset: Offset(0, 1),
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
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: Colors.black,
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
                                        GoogleFonts.inter(fontSize: 12),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Divider(height: 1, color: Color(0xFFE5E5E5)),
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
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFE5E5E5)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromRGBO(0, 0, 0, 0.05),
                            offset: Offset(0, 1),
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
                        color: const Color(0xFF1E1E1E),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFF1F2937)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color.fromRGBO(
                              0,
                              0,
                              0,
                              0.2,
                            ), // shadow-inner approx
                            offset: Offset(0, 2),
                            blurRadius: 4,
                            // inset: true, // Removed as not supported
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
                            decoration: const BoxDecoration(
                              color: Color(0xFF252526),
                              border: Border(
                                bottom: BorderSide(color: Color(0xFF374151)),
                              ),
                            ),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.terminal,
                                  size: 14,
                                  color: Color(0xFF9CA3AF),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  'Activity Log',
                                  style: GoogleFonts.ibmPlexMono(
                                    fontSize: 12,
                                    color: const Color(0xFF9CA3AF),
                                  ),
                                ),
                                const Spacer(),
                                Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: _isSyncing
                                        ? null
                                        : _performManualSync,
                                    borderRadius: BorderRadius.circular(4),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                        vertical: 4,
                                      ),
                                      child: Row(
                                        children: [
                                          if (_isSyncing)
                                            const SizedBox(
                                              width: 12,
                                              height: 12,
                                              child: CircularProgressIndicator(
                                                strokeWidth: 2,
                                                color: Color(0xFF60A5FA),
                                              ),
                                            )
                                          else
                                            const Icon(
                                              Icons.refresh,
                                              size: 14,
                                              color: Color(0xFF60A5FA),
                                            ),
                                          const SizedBox(width: 6),
                                          Text(
                                            _isSyncing
                                                ? 'Syncing...'
                                                : 'Sync Now',
                                            style: GoogleFonts.inter(
                                              fontSize: 11,
                                              fontWeight: FontWeight.w600,
                                              color: const Color(0xFF60A5FA),
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
                                  textColor: log['color'],
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
                        _buildIndicator('File System', Colors.green),
                        const SizedBox(width: 24),
                        _buildIndicator(
                          'Background Task',
                          Colors.yellow,
                          isDimmed: true,
                        ),
                        const SizedBox(width: 24),
                        _buildIndicator('Network', Colors.red, isDimmed: true),
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
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: const Color(0xFF6B7280), // gray-500
          letterSpacing: 0.5, // tracking-wide
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
    // If we have an error state (red background), display that style
    final bool isError = backgroundColor != null;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: isLast
            ? null
            : const Border(bottom: BorderSide(color: Color(0xFFE5E5E5))),
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
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: const Color(0xFF7F1D1D),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const Icon(
                        Icons.error,
                        size: 18,
                        color: Color(0xFFDC2626),
                      ),
                    ],
                  )
                else
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: Colors.black,
                    ),
                  ),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF6B7280),
                    ),
                  ), // gray-500
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
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFB), // gray-50
        border: Border.all(color: const Color(0xFFF3F4F6)), // gray-100
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: const Color(0xFF6B7280)), // gray-500
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              path,
              style: GoogleFonts.ibmPlexMono(
                fontSize: 12,
                color: const Color(0xFF6B7280),
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
    Color textColor;
    Color borderColor;
    Color backgroundColor = Colors.white;

    if (isDestructive) {
      textColor = const Color(0xFFB91C1C); // red-700
      borderColor = const Color(0xFFFECACA); // red-200
      // hover state is handled by InkWell, but we can set bg if needed
    } else if (isPrimary) {
      textColor = const Color(0xFF0D7CF2); // primary blue
      borderColor = const Color(0xFFE5E7EB); // gray-200
    } else {
      textColor = const Color(
        0xFF0D7CF2,
      ); // primary blue for action text usually, or gray-700
      borderColor = const Color(0xFFE5E7EB); // gray-200
      // Stitch design shows "Export JSON..." as text-primary (blue) with white bg
      // "Fix Path..." is red-700
      // "Import..." is gray-700 in HTML (text-gray-700)
    }

    // specific overrides based on label analysis from Stitch HTML
    if (label == 'Export JSON...') {
      textColor = const Color(0xFF0D7CF2); // text-primary
      borderColor = const Color(0xFFE5E5E5); // gray-200
    } else if (label == 'Import...') {
      textColor = const Color(0xFF374151); // text-gray-700
      borderColor = const Color(0xFFE5E5E5);
    } else if (label == 'Fix Path...') {
      textColor = const Color(0xFFB91C1C); // text-red-700
      borderColor = const Color(0xFFFECACA); // border-red-200
    }

    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: borderColor),
        boxShadow: const [
          BoxShadow(
            color: Color.fromRGBO(0, 0, 0, 0.05),
            offset: Offset(0, 1),
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
                  style: GoogleFonts.inter(
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
    return Row(
      children: [
        SizedBox(
          width: 10,
          height: 10,
          child: Stack(
            children: [
              // Ping animation would go here
              Container(
                decoration: const BoxDecoration(
                  color: Color(0xFF4ADE80), // green-400
                  shape: BoxShape.circle,
                ),
              ),
              Center(
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFF22C55E), // green-500
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Operational',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF16A34A), // green-600
          ),
        ),
      ],
    );
  }

  Widget _buildLogEntry(String timestamp, String message, {Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            timestamp,
            style: GoogleFonts.ibmPlexMono(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.ibmPlexMono(
                fontSize: 12,
                color: textColor ?? Colors.grey[400],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildIndicator(String label, Color color, {bool isDimmed = false}) {
    Color finalColor = color;
    // Adjust colors to match Stitch
    if (label == 'File System') {
      finalColor = const Color(0xFF22C55E); // green-500
    }
    if (label == 'Background Task') {
      finalColor = const Color(0xFFEAB308); // yellow-500
    }
    if (label == 'Network') {
      finalColor = const Color(0xFFEF4444); // red-500
    }

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
                    const BoxShadow(
                      color: Color.fromRGBO(34, 197, 94, 0.6),
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
          style: GoogleFonts.inter(
            fontSize: 12,
            color: isDimmed
                ? const Color(0xFF4B5563)
                : const Color(0xFF4B5563), // gray-600
          ),
        ),
      ],
    );
  }

  Widget _buildGoogleSignInRow() {
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
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.black,
                  ),
                ),
                const SizedBox(height: 4),
                if (_googleUser != null)
                  Text(
                    _googleUser!.email,
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF6B7280),
                    ),
                  )
                else
                  Text(
                    'Sign in to sync your data across devices.',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: const Color(0xFF6B7280),
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
