import 'dart:ui';
import 'dart:io';
import 'dart:ffi';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';

import 'screens/add_contact_page.dart';
import 'screens/analytics_page.dart';
import 'screens/home_page.dart';
import 'screens/macos/macos_active_contacts_view.dart';
import 'screens/macos/macos_shell.dart';
import 'screens/settings_page.dart';
import 'services/sync_service.dart';
import 'services/google_drive_service.dart';
import 'repositories/notification_preferences_repository.dart';
import 'services/onboarding_service.dart';
import 'services/reminder_coordinator.dart';
import 'services/reminder_service.dart';
import 'widgets/security_gate.dart';
import 'widgets/onboarding_wizard.dart';

Future<void> main() async {
  try {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      if (Platform.isMacOS) {
        open.overrideFor(OperatingSystem.macOS, _openOnMacOS);
      }
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
    }
    WidgetsFlutterBinding.ensureInitialized();

    // Pre-warm Google Sign-In silent login
    await GoogleDriveService().initialize();

    await ReminderService().initialize();
    final preferencesRepository = NotificationPreferencesRepository();
    await preferencesRepository.ensureDefaults();
    runApp(const MyApp());
  } catch (error, stackTrace) {
    debugPrint('Initialization error: $error');
    debugPrint(stackTrace.toString());
    runApp(ErrorApp(error: error, stackTrace: stackTrace));
  }
}

DynamicLibrary _openOnMacOS() {
  try {
    return DynamicLibrary.open('SQLCipher.framework/SQLCipher');
  } catch (_) {
    try {
      return DynamicLibrary.open('libsqlcipher.dylib');
    } catch (e) {
      debugPrint('Failed to load SQLCipher: $e');
      rethrow;
    }
  }
}

class ErrorApp extends StatelessWidget {
  const ErrorApp({super.key, required this.error, required this.stackTrace});

  final Object error;
  final StackTrace stackTrace;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        backgroundColor: Colors.white,
        body: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Application Failed to Start',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Error:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                Text(
                  error.toString(),
                  style: const TextStyle(color: Colors.black87),
                ),
                const SizedBox(height: 16),
                Text(
                  'Stack Trace:',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.grey[800],
                  ),
                ),
                Text(
                  stackTrace.toString(),
                  style: const TextStyle(
                    fontFamily: 'Courier',
                    fontSize: 12,
                    color: Colors.black87,
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

/// Root of the application
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BNPB',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue, // Can be adjusted to dynamic colors later.
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        textTheme: GoogleFonts.ibmPlexSansTextTheme().apply(
          bodyColor: Colors.white, // Ensure body text is white
          displayColor: Colors.white, // Ensure display text is white
        ),
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: Platform.isMacOS ? ThemeMode.light : ThemeMode.system,
      home: SecurityGate(
        child: Platform.isMacOS
            ? const MacOSShell(child: MacOSActiveContactsView())
            : const MainPage(),
      ),
    );
  }
}

/// Main page with bottom navigation
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> with WidgetsBindingObserver {
  int _currentIndex = 0;
  final OnboardingService _onboardingService = OnboardingService();
  bool _onboardingEvaluated = false;
  bool _isBottomBarVisible = true;

  final List<Widget> _pages = [
    const HomePage(),
    const AnalyticsPage(),
    const AddContactPage(),
    const SettingsPage(),
  ];

  late final AppLifecycleListener _listener;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Initialize AppLifecycleListener to handle exit requests (MacOS Quit)
    _listener = AppLifecycleListener(onExitRequested: _onExitRequested);

    _pageController = PageController(initialPage: _currentIndex);

    // Run heavy background initialization after the UI has a chance to mount
    _runBackgroundInitialization();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybeShowOnboarding();
    });
  }

  Future<void> _runBackgroundInitialization() async {
    // We don't await these here to keep initState fast,
    // but they will run in sequence in the background.
    try {
      await SyncService().performSync();
      await ReminderCoordinator().refreshAllContacts();
    } catch (e) {
      debugPrint('Background initialization error: $e');
    }
  }

  Future<AppExitResponse> _onExitRequested() async {
    // Perform sync before exiting
    await SyncService().performSync();
    return AppExitResponse.exit;
  }

  Future<void> _maybeShowOnboarding() async {
    if (_onboardingEvaluated) {
      return;
    }
    _onboardingEvaluated = true;

    final shouldShow = await _onboardingService.shouldShowOnboarding();
    if (!mounted || !shouldShow) {
      return;
    }

    final result = await showDialog<OnboardingResult>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const OnboardingWizard(),
    );

    if (!mounted || result == null) {
      return;
    }

    if (result.completed) {
      await _onboardingService.markComplete();
    }

    final followUp = result.followUp;
    if (followUp != null) {
      _handleOnboardingFollowUp(followUp);
    }
  }

  void _handleOnboardingFollowUp(OnboardingFollowUp followUp) {
    late final String message;
    late final int targetIndex;
    switch (followUp) {
      case OnboardingFollowUp.importContacts:
        targetIndex = 0;
        message =
            'Tap the restore icon on the Contacts tab to import people from a backup file.';
        break;
      case OnboardingFollowUp.manageTags:
        targetIndex = 2;
        message =
            'Use the tags section while adding a contact to build and reuse your tag library.';
        break;
      case OnboardingFollowUp.notificationSettings:
        targetIndex = 3;
        message =
            'Adjust follow-ups, prayer nudges, and review prompts from the settings tab.';
        break;
    }

    setState(() {
      _currentIndex = targetIndex;
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(SnackBar(content: Text(message)));
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: NotificationListener<UserScrollNotification>(
        onNotification: (notification) {
          if (notification.direction == ScrollDirection.reverse &&
              !_isBottomBarVisible) {
            setState(() => _isBottomBarVisible = true);
          } else if (notification.direction == ScrollDirection.forward &&
              _isBottomBarVisible) {
            setState(() => _isBottomBarVisible = false);
          }
          return true;
        },
        // Optimization: Replaced IndexedStack with a lazy-loading PageView.
        // IndexedStack instantiates and builds all children immediately, causing a spike
        // in memory and initialization overhead on startup. PageView with AutomaticKeepAliveClientMixin
        // on its children preserves state while only building pages as they are navigated to.
        child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: _pages,
        ),
      ),
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: _isBottomBarVisible ? 80 : 0,
        child: SingleChildScrollView(
          physics: const NeverScrollableScrollPhysics(),
          child: NavigationBar(
            selectedIndex: _currentIndex,
            onDestinationSelected: (index) {
              setState(() {
                _currentIndex = index;
              });
              _pageController.jumpToPage(index);
            },
            destinations: const [
              NavigationDestination(
                icon: Icon(Icons.home_outlined),
                selectedIcon: Icon(Icons.home),
                label: 'Home',
              ),
              NavigationDestination(
                icon: Icon(Icons.insights_outlined),
                selectedIcon: Icon(Icons.insights),
                label: 'Analytics',
              ),
              NavigationDestination(
                icon: Icon(Icons.person_add_outlined),
                selectedIcon: Icon(Icons.person_add),
                label: 'Add Contact',
              ),
              NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _pageController.dispose();
    _listener.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Sync on resume - use cooldown to avoid "Google logging in" flashes.
      SyncService().performSync();
    }
  }
}
