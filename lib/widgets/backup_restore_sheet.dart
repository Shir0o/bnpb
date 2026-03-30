import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/backup_service.dart';

/// Result options returned from the [BackupRestoreSheet].
enum BackupRestoreSheetResult { restored, legacyImport }

/// Bottom sheet that surfaces rolling backups and allows restoring snapshots.
class BackupRestoreSheet extends StatefulWidget {
  const BackupRestoreSheet({super.key});

  @override
  State<BackupRestoreSheet> createState() => _BackupRestoreSheetState();
}

class _BackupRestoreSheetState extends State<BackupRestoreSheet> {
  late Future<List<BackupSnapshot>> _backupsFuture;

  @override
  void initState() {
    super.initState();
    _backupsFuture = BackupService().listBackups();
  }

  Future<void> _handleRestore(BackupSnapshot snapshot) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Restore backup'),
        content: Text(
          'Replace your current database with the backup from '
          '${DateFormat.yMMMd().add_jm().format(snapshot.modified)}?\n\n'
          'This will overwrite recent changes made after that time.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Restore'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) {
      return;
    }

    final messenger = ScaffoldMessenger.of(context);

    try {
      await _showLoading(
        () => BackupService().restoreBackup(snapshot, messenger: messenger),
        'Restoring backup...\nThis may take a while...',
      );
      if (!mounted) {
        return;
      }
      Navigator.of(context).pop(BackupRestoreSheetResult.restored);
    } on BackupRestoreException {
      // Error snackbar already displayed by the service. Keep the sheet open.
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

  String _formatFileSize(int bytes) {
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    var size = bytes.toDouble();
    var unitIndex = 0;

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    final precision = unitIndex == 0 ? 0 : 1;
    return '${size.toStringAsFixed(precision)} ${units[unitIndex]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final maxHeight = MediaQuery.of(context).size.height * 0.55;

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 24,
          right: 24,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 48,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Restore from backup',
              style: theme.textTheme.titleLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Rolling backups capture the encrypted database after each change. '
              'Choose a snapshot to restore or import a legacy export instead.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: FutureBuilder<List<BackupSnapshot>>(
                future: _backupsFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.waiting) {
                    return const Center(child: CircularProgressIndicator());
                  }

                  if (snapshot.hasError) {
                    return Center(
                      child: Text(
                        'Unable to load backups. Please try again later.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  final backups = snapshot.data ?? [];
                  if (backups.isEmpty) {
                    return Center(
                      child: Text(
                        'No backups found yet. Add or update a contact to create one.',
                        style: theme.textTheme.bodyMedium,
                        textAlign: TextAlign.center,
                      ),
                    );
                  }

                  return ListView.separated(
                    itemCount: backups.length,
                    shrinkWrap: true,
                    itemBuilder: (context, index) {
                      final backup = backups[index];
                      final timestamp = DateFormat.yMMMd().add_jm().format(
                            backup.modified,
                          );
                      final sizeLabel = _formatFileSize(backup.bytes);

                      return ListTile(
                        leading: const Icon(Icons.storage_outlined),
                        title: Text(timestamp),
                        subtitle: Text(sizeLabel),
                        trailing: const Icon(Icons.restore),
                        onTap: () => _handleRestore(backup),
                      );
                    },
                    separatorBuilder: (context, index) =>
                        const Divider(height: 1),
                  );
                },
              ),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () => Navigator.of(
                context,
              ).pop(BackupRestoreSheetResult.legacyImport),
              icon: const Icon(Icons.upload_file_outlined),
              label: const Text('Import JSON export'),
            ),
          ],
        ),
      ),
    );
  }
}
