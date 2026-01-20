import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/contact.dart';
import '../services/export_service.dart';

/// Bottom sheet that lets users choose fields and format when exporting data.
class ExportOptionsSheet extends StatefulWidget {
  const ExportOptionsSheet({
    required this.contacts,
    super.key,
  });

  final List<Contact> contacts;

  @override
  State<ExportOptionsSheet> createState() => _ExportOptionsSheetState();
}

class _ExportOptionsSheetState extends State<ExportOptionsSheet> {
  final ExportService _exportService = ExportService();
  final TextEditingController _passphraseController = TextEditingController();
  final Set<String> _selectedFields =
      ExportService.availableFields.map((field) => field.id).toSet();

  bool _isExporting = false;
  String? _error;

  @override
  void dispose() {
    _passphraseController.dispose();
    super.dispose();
  }

  void _toggleField(String id, bool value) {
    setState(() {
      if (value) {
        _selectedFields.add(id);
      } else if (_selectedFields.length > 1) {
        _selectedFields.remove(id);
      }
    });
  }

  Future<void> _shareFile(File file, String description) async {
    // ignore: deprecated_member_use
    await Share.shareXFiles([XFile(file.path)], text: description);
  }

  Future<void> _exportCsv() async {
    await _performExport(
      generator: (fields) => _exportService.exportCsv(widget.contacts, fields),
      description: 'BNPB CSV export ready to review.',
      successMessage: 'CSV export shared securely.',
    );
  }

  Future<void> _exportPdf() async {
    await _performExport(
      generator: (fields) => _exportService.exportPdf(widget.contacts, fields),
      description: 'BNPB PDF export ready to review.',
      successMessage: 'PDF export shared securely.',
    );
  }

  Future<void> _exportJson() async {
    await _performExport(
      generator: (fields) => _exportService.exportJson(widget.contacts, fields),
      description: 'BNPB JSON export ready to review.',
      successMessage: 'JSON export shared securely.',
    );
  }

  Future<void> _exportEncryptedArchive() async {
    final passphrase = _passphraseController.text.trim();
    if (passphrase.isEmpty) {
      setState(() {
        _error = 'Add a passphrase for the encrypted archive.';
      });
      return;
    }

    await _performExport(
      generator: (fields) => _exportService.exportEncryptedArchive(
          widget.contacts, fields, passphrase),
      description:
          'BNPB encrypted archive. Keep the passphrase safe to decrypt later.',
      successMessage: 'Encrypted archive created and shared.',
    );
  }

  Future<void> _performExport({
    required Future<File> Function(List<String> fields) generator,
    required String description,
    required String successMessage,
  }) async {
    if (_selectedFields.isEmpty) {
      setState(() {
        _error = 'Select at least one field to export.';
      });
      return;
    }

    setState(() {
      _isExporting = true;
      _error = null;
    });

    try {
      final file = await generator(_selectedFields.toList());
      await _shareFile(file, description);
      if (mounted) {
        Navigator.of(context).pop(successMessage);
      }
    } catch (error) {
      setState(() {
        _isExporting = false;
        _error = 'Failed to export: $error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return SafeArea(
          child: Padding(
            padding: EdgeInsets.only(bottom: bottomInset),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 48, 24, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Export contacts',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(context).pop(),
                          icon: const Icon(Icons.close),
                          tooltip: 'Cancel export',
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: ListView(
                        padding: EdgeInsets.zero,
                        children: [
                          Text(
                            'Choose which details to include. CSV/PDF/JSON exports remain '
                            'on device until you share them. Encrypted archives require a '
                            'passphrase and bundle the selected fields inside AES-secured '
                            'ZIP data.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 12),
                          ...ExportService.availableFields.map((field) {
                            final selected = _selectedFields.contains(field.id);
                            return CheckboxListTile(
                              value: selected,
                              onChanged: (value) {
                                if (value == null) return;
                                _toggleField(field.id, value);
                              },
                              dense: true,
                              title: Text(field.label),
                              subtitle: Text(field.description),
                              controlAffinity: ListTileControlAffinity.leading,
                            );
                          }),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _passphraseController,
                            enabled: !_isExporting,
                            decoration: const InputDecoration(
                              labelText: 'Encrypted archive passphrase',
                              hintText: 'Use a phrase you can remember',
                            ),
                          ),
                          if (_error != null) ...[
                            const SizedBox(height: 8),
                            Text(
                              _error!,
                              style: TextStyle(
                                color: theme.colorScheme.error,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24, 16, 24, 24),
                      child: _isExporting
                          ? const LinearProgressIndicator()
                          : Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _exportCsv,
                                        icon: const Icon(
                                            Icons.table_chart_outlined),
                                        label: const Text('Export CSV'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: OutlinedButton.icon(
                                        onPressed: _exportPdf,
                                        icon: const Icon(
                                            Icons.picture_as_pdf_outlined),
                                        label: const Text('Export PDF'),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                OutlinedButton.icon(
                                  onPressed: _exportJson,
                                  icon: const Icon(Icons.data_object_outlined),
                                  label: const Text('Export JSON'),
                                ),
                                const SizedBox(height: 12),
                                FilledButton.icon(
                                  onPressed: _exportEncryptedArchive,
                                  icon: const Icon(Icons.lock_outline),
                                  label: const Text('Create encrypted archive'),
                                ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
