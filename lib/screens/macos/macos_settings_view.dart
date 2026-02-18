import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class MacOSSettingsView extends StatelessWidget {
  const MacOSSettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        // Toolbar
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 24),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: Color(0xFFE5E5E5))),
            color: Colors.white,
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
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFF0FDF4), // green-50
                  border:
                      Border.all(color: const Color(0xFFBBF7D0)), // green-200
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.cloud_done,
                        size: 16, color: Color(0xFF15803D)), // green-700
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
              ),
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
                    _buildSectionHeader('Storage Configuration'),
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
                            title: 'Database Location',
                            content: _buildPathBadge(
                                '/Users/alexander/Documents/prayers.db',
                                Icons.storage),
                            action: _buildActionButton('Change...'),
                            isLast: false,
                          ),
                          _buildSettingRow(
                            title: 'Backup Location',
                            content: _buildErrorPath(
                                '/Volumes/ExternalDrive/Backups/PrayerSync/'),
                            action: _buildActionButton('Fix Path...',
                                isDestructive: true),
                            isLast: true,
                            backgroundColor: const Color(0xFFFEF2F2), // red-50
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
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
                            action: _buildActionButton('Export JSON...',
                                icon: Icons.download, isPrimary: true),
                            isLast: false,
                          ),
                          _buildSettingRow(
                            title: 'Import Data',
                            description:
                                'Restore from a previous backup or migrate from another device.',
                            action: _buildActionButton('Import...'),
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 40),
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
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 8),
                            color: const Color(0xFF252526),
                            child: Row(
                              children: [
                                const Icon(Icons.terminal,
                                    size: 14, color: Color(0xFF9CA3AF)),
                                const SizedBox(width: 8),
                                Text(
                                  'Activity Log',
                                  style: GoogleFonts.ibmPlexMono(
                                    fontSize: 12,
                                    color: const Color(0xFF9CA3AF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            height: 192, // h-48
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildLogEntry('[10:45:02]',
                                    'Initializing file watcher service...'),
                                _buildLogEntry('[10:45:03]',
                                    'Database integrity check passed (CRC32: 8A2F90).'),
                                _buildLogEntry('[10:48:12]',
                                    'Detected change in /Users/alexander/Documents/prayers.db',
                                    textColor: const Color(0xFF4ADE80)),
                                _buildLogEntry('[10:48:13]',
                                    'Syncing 2 modifications to local cache...',
                                    textColor: const Color(0xFF60A5FA)),
                                _buildLogEntry(
                                    '[10:48:14]', 'Sync complete. Ready.',
                                    textColor: const Color(0xFFD1D5DB)),
                              ],
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
                        _buildIndicator('Background Task', Colors.yellow,
                            isDimmed: true),
                        const SizedBox(width: 24),
                        _buildIndicator('Network', Colors.red, isDimmed: true),
                      ],
                    ),
                    const SizedBox(height: 24),
                    const Divider(),
                    const SizedBox(height: 24),
                    Text(
                      'Cupertino Native: Prayer Sync v1.0.2 (Build 445)\n© 2023 Local First Software',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: Colors.grey[400],
                        height: 1.5,
                      ),
                    ),
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
          color: Colors.grey[500],
          letterSpacing: 0.5,
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
                if (backgroundColor != null && title == 'Backup Location')
                  Row(children: [
                    Text(title,
                        style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF7F1D1D))),
                    const SizedBox(width: 8),
                    const Icon(Icons.error, size: 18, color: Color(0xFFDC2626)),
                  ])
                else
                  Text(title,
                      style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.black)),
                if (description != null) ...[
                  const SizedBox(height: 4),
                  Text(description,
                      style: GoogleFonts.inter(
                          fontSize: 12, color: Colors.grey[500])),
                ],
                if (content != null) ...[
                  if (description == null && title != 'Backup Location')
                    const SizedBox(height: 4),
                  content,
                ]
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
        color: const Color(0xFFF9FAFB),
        border: Border.all(color: const Color(0xFFF3F4F6)),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              path,
              style: GoogleFonts.ibmPlexMono(
                  fontSize: 12, color: Colors.grey[500]),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorPath(String path) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 4),
        Text(
          'Path not found or invalid permissions.',
          style: GoogleFonts.inter(
              fontSize: 12, color: const Color(0xFFB91C1C)), // red-700
        ),
        const SizedBox(height: 8),
        Text(
          path,
          style: GoogleFonts.ibmPlexMono(
              fontSize: 12, color: const Color(0xFF991B1B)), // red-800
        ),
      ],
    );
  }

  Widget _buildActionButton(String label,
      {bool isDestructive = false, bool isPrimary = false, IconData? icon}) {
    Color textColor;
    Color borderColor;

    if (isDestructive) {
      textColor = const Color(0xFFB91C1C);
      borderColor = const Color(0xFFFECACA);
    } else if (isPrimary) {
      textColor = const Color(0xFF0D7CF2);
      borderColor = const Color(0xFFE5E7EB);
    } else {
      textColor = const Color(0xFF374151);
      borderColor = const Color(0xFFE5E7EB);
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
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
          onTap: () {},
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
        Container(
          width: 10,
          height: 10,
          decoration: const BoxDecoration(
            color: Colors.green, // Animate ping effect later if needed
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Operational',
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: const Color(0xFF16A34A),
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
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            color: isDimmed ? Colors.grey[600] : Colors.grey[800],
          ),
        ),
      ],
    );
  }
}
