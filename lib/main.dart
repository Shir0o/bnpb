import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
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
import 'services/ai/ai_services.dart';
import 'services/ai/background_downloader.dart';
import 'services/onboarding_service.dart';
import 'services/reminder_coordinator.dart';
import 'services/reminder_service.dart';
import 'widgets/security_gate.dart';
import 'widgets/onboarding_wizard.dart';

const Color _lightPrimary = Color(0xFF6750A4);

const ColorScheme _lightColorScheme = ColorScheme(
  brightness: Brightness.light,
  primary: _lightPrimary,
  onPrimary: Color(0xFFFFFFFF),
  primaryContainer: Color(0xFFEADDFF),
  onPrimaryContainer: Color(0xFF4F378B),
  primaryFixed: Color(0xFFEADDFF),
  primaryFixedDim: Color(0xFFD0BCFF),
  onPrimaryFixed: Color(0xFF21005D),
  onPrimaryFixedVariant: Color(0xFF4F378B),
  secondary: Color(0xFF625B71),
  onSecondary: Color(0xFFFFFFFF),
  secondaryContainer: Color(0xFFE8DEF8),
  onSecondaryContainer: Color(0xFF4A4458),
  secondaryFixed: Color(0xFFE8DEF8),
  secondaryFixedDim: Color(0xFFCCC2DC),
  onSecondaryFixed: Color(0xFF1D192B),
  onSecondaryFixedVariant: Color(0xFF4A4458),
  tertiary: Color(0xFF7D5260),
  onTertiary: Color(0xFFFFFFFF),
  tertiaryContainer: Color(0xFFFFD8E4),
  onTertiaryContainer: Color(0xFF633B48),
  tertiaryFixed: Color(0xFFFFD8E4),
  tertiaryFixedDim: Color(0xFFEFB8C8),
  onTertiaryFixed: Color(0xFF31111D),
  onTertiaryFixedVariant: Color(0xFF633B48),
  error: Color(0xFFB3261E),
  onError: Color(0xFFFFFFFF),
  errorContainer: Color(0xFFF9DEDC),
  onErrorContainer: Color(0xFF8C1D18),
  surface: Color(0xFFFEF7FF),
  onSurface: Color(0xFF1D1B20),
  surfaceDim: Color(0xFFDED8E1),
  surfaceBright: Color(0xFFFEF7FF),
  surfaceContainerLowest: Color(0xFFFFFFFF),
  surfaceContainerLow: Color(0xFFF7F2FA),
  surfaceContainer: Color(0xFFF3EDF7),
  surfaceContainerHigh: Color(0xFFECE6F0),
  surfaceContainerHighest: Color(0xFFE6E0E9),
  onSurfaceVariant: Color(0xFF49454F),
  outline: Color(0xFF79747E),
  outlineVariant: Color(0xFFCAC4D0),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFF322F35),
  onInverseSurface: Color(0xFFF5EFF7),
  inversePrimary: Color(0xFFD0BCFF),
  surfaceTint: _lightPrimary,
);

const ColorScheme _darkColorScheme = ColorScheme(
  brightness: Brightness.dark,
  primary: Color(0xFFD0BCFF),
  onPrimary: Color(0xFF381E72),
  primaryContainer: Color(0xFF4F378B),
  onPrimaryContainer: Color(0xFFEADDFF),
  primaryFixed: Color(0xFFEADDFF),
  primaryFixedDim: Color(0xFFD0BCFF),
  onPrimaryFixed: Color(0xFF21005D),
  onPrimaryFixedVariant: Color(0xFF4F378B),
  secondary: Color(0xFFCCC2DC),
  onSecondary: Color(0xFF332D41),
  secondaryContainer: Color(0xFF4A4458),
  onSecondaryContainer: Color(0xFFE8DEF8),
  secondaryFixed: Color(0xFFE8DEF8),
  secondaryFixedDim: Color(0xFFCCC2DC),
  onSecondaryFixed: Color(0xFF1D192B),
  onSecondaryFixedVariant: Color(0xFF4A4458),
  tertiary: Color(0xFFEFB8C8),
  onTertiary: Color(0xFF492532),
  tertiaryContainer: Color(0xFF633B48),
  onTertiaryContainer: Color(0xFFFFD8E4),
  tertiaryFixed: Color(0xFFFFD8E4),
  tertiaryFixedDim: Color(0xFFEFB8C8),
  onTertiaryFixed: Color(0xFF31111D),
  onTertiaryFixedVariant: Color(0xFF633B48),
  error: Color(0xFFF2B8B5),
  onError: Color(0xFF601410),
  errorContainer: Color(0xFF8C1D18),
  onErrorContainer: Color(0xFFF9DEDC),
  surface: Color(0xFF141218),
  onSurface: Color(0xFFE6E0E9),
  surfaceDim: Color(0xFF141218),
  surfaceBright: Color(0xFF3B383E),
  surfaceContainerLowest: Color(0xFF0F0D13),
  surfaceContainerLow: Color(0xFF1D1B20),
  surfaceContainer: Color(0xFF211F26),
  surfaceContainerHigh: Color(0xFF2B2930),
  surfaceContainerHighest: Color(0xFF36343B),
  onSurfaceVariant: Color(0xFFCAC4D0),
  outline: Color(0xFF938F99),
  outlineVariant: Color(0xFF49454F),
  shadow: Color(0xFF000000),
  scrim: Color(0xFF000000),
  inverseSurface: Color(0xFFE6E0E9),
  onInverseSurface: Color(0xFF322F35),
  inversePrimary: Color(0xFF6750A4),
  surfaceTint: Color(0xFFD0BCFF),
);

/// Builds the app-wide Material 3 theme with Google Sans typography.
ThemeData buildAppTheme(Brightness brightness) {
  final colorScheme =
      brightness == Brightness.light ? _lightColorScheme : _darkColorScheme;
  final baseTheme = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    visualDensity: VisualDensity.standard,
  );
  final textTheme = GoogleFonts.googleSansTextTheme(baseTheme.textTheme).apply(
    bodyColor: colorScheme.onSurface,
    displayColor: colorScheme.onSurface,
  );

  return baseTheme.copyWith(
    textTheme: textTheme,
    primaryTextTheme: GoogleFonts.googleSansTextTheme(
      baseTheme.primaryTextTheme,
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      titleTextStyle: textTheme.titleLarge?.copyWith(
        color: colorScheme.onSurface,
        fontWeight: FontWeight.w600,
      ),
    ),
    cardTheme: CardThemeData(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.outlineVariant, width: 0.5),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
    ),
    navigationBarTheme: NavigationBarThemeData(
      labelTextStyle: WidgetStateProperty.resolveWith((states) {
        final color = states.contains(WidgetState.selected)
            ? colorScheme.onSecondaryContainer
            : colorScheme.onSurfaceVariant;
        return textTheme.labelMedium?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        );
      }),
    ),
  );
}

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
    // `flutter_downloader` powers the background-safe AI model download on
    // mobile. Initialize it eagerly so it's ready by the time the user
    // opens AI settings; harmless no-op on desktop/web.
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      unawaited(FlutterBackgroundDownloader.ensureInitialized());
    }
    unawaited(AiServices().maybeInitialize());
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
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
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
    } else if (state == AppLifecycleState.detached) {
      // Release the vector-store DB handle so Android's CloseGuard doesn't
      // log `flutter_gemma_vectors.db was leaked` at process teardown.
      unawaited(AiServices().shutdown());
    }
  }
}
