import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../db/db_helper.dart';
import '../../main.dart';
import '../../models/prayer_request.dart';
import '../../services/follow_up_recommendation_service.dart';
import '../../services/sync_service.dart';
import '../../widgets/contact_avatar.dart';
import '../../widgets/crisp_switch.dart';
import '../../widgets/crisp_toast.dart';
import 'macos_add_view.dart';
import 'macos_analytics_view.dart';
import 'macos_ask_view.dart';
import 'macos_contacts_view.dart';
import 'macos_prayer_diary_view.dart';
import 'macos_settings_view.dart';

/// Root shell for the macOS build: a custom title bar (real traffic lights,
/// transparent native chrome — see MainFlutterWindow.swift), a 242px
/// sidebar, and a content area holding the app's 6 top-level sections.
class MacOSShell extends StatefulWidget {
  const MacOSShell({super.key});

  @override
  State<MacOSShell> createState() => _MacOSShellState();
}

class _MacOSShellState extends State<MacOSShell> {
  static const int _sectionCount = 6;

  int _selectedIndex = 0;
  late final PageController _pageController;
  final DBHelper _dbHelper = DBHelper();
  final List<GlobalKey<NavigatorState>> _navigatorKeys = List.generate(
    _sectionCount,
    (_) => GlobalKey<NavigatorState>(),
  );

  int _needsPrayerCount = 0;
  List<FollowUpRecommendation> _followUps = [];
  StreamSubscription<void>? _syncSubscription;

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: _selectedIndex);
    _loadSidebarData();
    _syncSubscription = SyncService().onSyncComplete.listen((_) {
      if (mounted) _loadSidebarData();
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  Future<void> _loadSidebarData() async {
    try {
      final counts = await _dbHelper.getPrayerRequestCounts();
      final recommendations =
          await FollowUpRecommendationService().getRecommendations();
      if (!mounted) return;
      setState(() {
        _needsPrayerCount = counts[PrayerRequestStatus.pending] ?? 0;
        _followUps = recommendations.take(3).toList();
      });
    } catch (e) {
      debugPrint('Error loading macOS sidebar data: $e');
    }
  }

  void _selectSection(int index) {
    if (_selectedIndex == index) return;
    setState(() => _selectedIndex = index);
    _pageController.jumpToPage(index);
  }

  Future<void> _handleSyncShortcut() async {
    CrispToast.show(context, 'Syncing…');
    await SyncService().performSync();
    if (!mounted) return;
    CrispToast.show(context, 'Sync complete');
    _loadSidebarData();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyR, meta: true):
            _handleSyncShortcut,
      },
      child: Scaffold(
        body: Column(
          children: [
            _buildTitleBar(colorScheme),
            Expanded(
              child: Row(
                children: [
                  _buildSidebar(colorScheme),
                  Expanded(
                    child: PageView(
                      controller: _pageController,
                      physics: const NeverScrollableScrollPhysics(),
                      children: [
                        _KeepAlivePage(
                          child: _buildNavigator(
                            0,
                            MacOSContactsView(
                              onAddContact: () => _selectSection(4),
                            ),
                          ),
                        ),
                        _KeepAlivePage(
                          child: _buildNavigator(
                            1,
                            const MacOSAnalyticsView(),
                          ),
                        ),
                        _KeepAlivePage(
                          child: _buildNavigator(
                            2,
                            const MacOSPrayerDiaryView(),
                          ),
                        ),
                        _KeepAlivePage(
                          child: _buildNavigator(3, const MacOSAskView()),
                        ),
                        _KeepAlivePage(
                          child: _buildNavigator(
                            4,
                            MacOSAddView(
                              onSaved: () => _selectSection(0),
                            ),
                          ),
                        ),
                        _KeepAlivePage(
                          child: _buildNavigator(
                            5,
                            const MacOSSettingsView(),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleBar(ColorScheme colorScheme) {
    // 46px strip matching the Crisp Utility desktop design. The real,
    // functional traffic-light buttons are drawn natively above this (see
    // MainFlutterWindow.swift's transparent/full-size-content-view titlebar)
    // so no space needs to be reserved for them here.
    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: colorScheme.surfaceTint,
        border: Border(bottom: BorderSide(color: colorScheme.hairline)),
      ),
      alignment: Alignment.center,
      child: Text(
        'BNPB · Ministry CRM',
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: colorScheme.secondaryText,
          letterSpacing: -0.1,
        ),
      ),
    );
  }

  Widget _buildSidebar(ColorScheme colorScheme) {
    return Container(
      width: 242,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(right: BorderSide(color: colorScheme.cardBorder)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 16),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(11),
                  ),
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.favorite_border,
                    color: colorScheme.onPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 11),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'BNPB',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 18,
                          color: colorScheme.onSurface,
                          letterSpacing: -0.2,
                        ),
                      ),
                      Text(
                        'Local-first CRM',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.secondaryText,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _navItem(colorScheme, 0, Icons.people_outline, 'Contacts'),
          _navItem(colorScheme, 1, Icons.insights_outlined, 'Analytics'),
          _navItem(
            colorScheme,
            2,
            Icons.volunteer_activism_outlined,
            'Prayer',
            badge: _needsPrayerCount > 0 ? '$_needsPrayerCount' : null,
          ),
          _navItem(
            colorScheme,
            3,
            Icons.search_outlined,
            'Ask',
            trailingPill: 'on-device',
          ),
          _navItem(
            colorScheme,
            4,
            Icons.person_add_alt_outlined,
            'Add contact',
          ),
          _navItem(colorScheme, 5, Icons.settings_outlined, 'Settings'),
          const Spacer(),
          if (_followUps.isNotEmpty) _buildFollowUpCard(colorScheme),
          _buildThemeToggle(colorScheme),
        ],
      ),
    );
  }

  Widget _navItem(
    ColorScheme colorScheme,
    int index,
    IconData icon,
    String label, {
    String? badge,
    String? trailingPill,
  }) {
    final isSelected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 3),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () => _selectSection(index),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? colorScheme.greenTint : Colors.transparent,
              borderRadius: BorderRadius.circular(11),
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 19,
                  color:
                      isSelected ? colorScheme.primary : colorScheme.iconColor,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 14.5,
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w600,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                ),
                if (badge != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.dangerTint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      badge,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.error,
                      ),
                    ),
                  ),
                if (trailingPill != null)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceTint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      trailingPill,
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.secondaryText,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFollowUpCard(ColorScheme colorScheme) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      decoration: BoxDecoration(
        color: colorScheme.aiCardBg,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome,
                  size: 15, color: Color(0xFF5FE0A0)),
              const SizedBox(width: 7),
              const Text(
                'Follow-ups',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                  color: Colors.white,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF3A1F1F),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '${_followUps.length}',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFF8C7A),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ..._followUps.map(
            (f) => InkWell(
              onTap: () => _selectSection(0),
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  children: [
                    ContactAvatar(contact: f.contact, radius: 14),
                    const SizedBox(width: 9),
                    Expanded(
                      child: Text(
                        f.contact.displayName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                          color: Color(0xFFE8EDE9),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildThemeToggle(ColorScheme colorScheme) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeNotifier,
      builder: (context, mode, _) {
        final isDark = mode == ThemeMode.dark;
        return InkWell(
          borderRadius: BorderRadius.circular(11),
          onTap: () =>
              updateThemeMode(isDark ? ThemeMode.light : ThemeMode.dark),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: colorScheme.cardBorder),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.dark_mode_outlined,
                  size: 17,
                  color: colorScheme.iconColor,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Dark mode',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                CrispSwitch(
                  value: isDark,
                  onChanged: (v) =>
                      updateThemeMode(v ? ThemeMode.dark : ThemeMode.light),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNavigator(int index, Widget child) {
    return Navigator(
      key: _navigatorKeys[index],
      onGenerateRoute: (settings) {
        return MaterialPageRoute(settings: settings, builder: (_) => child);
      },
    );
  }
}

class _KeepAlivePage extends StatefulWidget {
  final Widget child;

  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
