import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/services.dart';

import 'macos_prayer_diary_view.dart';
import 'macos_settings_view.dart';
import 'macos_active_contacts_view.dart';
import 'macos_contacts_view.dart';
import '../../services/sync_service.dart';

class MacOSShell extends StatefulWidget {
  final Widget child;

  const MacOSShell({super.key, required this.child});

  @override
  State<MacOSShell> createState() => _MacOSShellState();
}

class _MacOSShellState extends State<MacOSShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true): () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Syncing...')),
          );
          SyncService().performSync();
        },
      },
      child: Scaffold(
        body: Row(
          children: [
            // Sidebar
            Container(
              width: 260,
              decoration: BoxDecoration(
                color: const Color(0xFFF5F5F7).withValues(alpha: 0.85),
                border: const Border(
                  right: BorderSide(color: Color(0xFFE5E5E5)),
                ),
              ),
              child: Column(
                children: [
                  // Traffic Lights Area
                  Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.centerLeft,
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _buildTrafficLight(
                              const Color(0xFFFF5F57), const Color(0xFFE0443E)),
                        ),
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _buildTrafficLight(
                              const Color(0xFFFEBC2E), const Color(0xFFD89E24)),
                        ),
                        _buildTrafficLight(
                            const Color(0xFF28C840), const Color(0xFF1AAB29)),
                      ],
                    ),
                  ),
                  // Navigation
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      children: [
                        _buildSectionHeader('Library'),
                        _buildNavItem(0, Icons.format_list_bulleted,
                            'Prayer List', _selectedIndex == 0),
                        _buildNavItem(
                            1, Icons.book, 'Prayer Diary', _selectedIndex == 1),
                        _buildNavItem(
                            2, Icons.group, 'Contacts', _selectedIndex == 2),
                        const SizedBox(height: 24),
                        _buildSectionHeader('System'),
                        _buildNavItem(3, Icons.settings, 'Sync & Settings',
                            _selectedIndex == 3),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // Main Content Area
            Expanded(
              child: _buildMainContent(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMainContent() {
    switch (_selectedIndex) {
      case 0:
        return const MacOSActiveContactsView();
      case 1:
        return const MacOSPrayerDiaryView();
      case 2:
        return const MacOSContactsView();
      case 3:
        return const MacOSSettingsView();
      default:
        return const Center(child: Text('Not implemented'));
    }
  }

  Widget _buildShellHeader() {
    return Container(
      height: 52,
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Color(0xFFE5E5E5)),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconButton(
            onPressed: () {},
            icon: const Icon(Icons.menu, color: Colors.grey),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
          const Spacer(),
          // Search and Sync
          Container(
            width: 200,
            height: 32,
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: BorderRadius.circular(6),
            ),
            child: const TextField(
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: Icon(Icons.search, size: 18),
                border: InputBorder.none,
                alignLabelWithHint: true,
                isDense: true,
                contentPadding: EdgeInsets.only(top: 6, bottom: 6),
              ),
              style: TextStyle(
                fontSize: 13,
                height: 1.0,
                color: Colors.black,
              ),
              textAlignVertical: TextAlignVertical.center,
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 1,
            height: 16,
            color: Colors.grey[300],
          ),
          const SizedBox(width: 12),
          const Icon(Icons.cloud_done, color: Colors.green, size: 20),
        ],
      ),
    );
  }

  Widget _buildTrafficLight(Color color, Color borderColor) {
    return Container(
      width: 12,
      height: 12,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Colors.grey[500],
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label, bool isActive) {
    // We override isActive with our internal state for now, or we could remove the parameter.
    // For now, let's just use the parameter as it is passed correctly in build().
    final isSelected = isActive;
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            setState(() {
              _selectedIndex = index;
            });
          },
          borderRadius: BorderRadius.circular(6),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            decoration: BoxDecoration(
              color: isSelected
                  ? const Color(0xFF0D7CF2)
                  : Colors.transparent, // bg-primary
              borderRadius: BorderRadius.circular(6),
              boxShadow: isSelected
                  ? [
                      const BoxShadow(
                        color: Color.fromRGBO(0, 0, 0, 0.05), // shadow-sm
                        offset: Offset(0, 1),
                        blurRadius: 2,
                      )
                    ]
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 20,
                  color: isSelected ? Colors.white : Colors.grey[600],
                ),
                const SizedBox(width: 12),
                Text(
                  label,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: isSelected ? Colors.white : Colors.grey[700],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
