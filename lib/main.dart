import 'dart:async';
import 'dart:ui';
import 'dart:io';
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:sqlite3/open.dart';
import 'package:shared_preferences/shared_preferences.dart';
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

final ValueNotifier<double> fontSizeNotifier = ValueNotifier<double>(13.0);
bool _hasUserCustomFontSize = false;

Future<void> updateFontSize(double newSize) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble('app_font_size', newSize);
  _hasUserCustomFontSize = true;
  fontSizeNotifier.value = newSize;
}

final ValueNotifier<ThemeMode> themeModeNotifier =
    ValueNotifier<ThemeMode>(ThemeMode.light);

Future<void> updateThemeMode(ThemeMode mode) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setInt('app_theme_mode', mode.index);
  themeModeNotifier.value = mode;
}

const ColorScheme _lightColorScheme = ColorScheme.light(
  primary: Color(0xFF0D7A4F),
  onPrimary: Colors.white,
  primaryContainer: Color(0xFFEAF6EF),
  onPrimaryContainer: Color(0xFF0D7A4F),
  secondary: Color(0xFF127A6B),
  onSecondary: Colors.white,
  surface: Colors.white,
  onSurface: Color(0xFF0F1512),
  surfaceContainerLow: Color(0xFFF1F5F2), // Surface tint
  surfaceContainerHighest: Color(0xFFE6EBE7), // Card border
  outline: Color(0xFF8A988F), // Muted
  outlineVariant: Color(0xFFEEF2EF), // Hairline
  error: Color(0xFFC25A3F),
  errorContainer: Color(0xFFFBEEE9),
  onErrorContainer: Color(0xFFC25A3F),
  onSurfaceVariant: Color(0xFF57635C), // secondaryText
  tertiary: Color(0xFF3D4C44), // iconColor
  secondaryContainer: Color(0xFFC3CCC6), // faint
  tertiaryContainer: Color(0xFFFDF5F2), // danger-tint2
  inverseSurface: Color(0xFFF0D9D0), // danger-border
);

const ColorScheme _darkColorScheme = ColorScheme.dark(
  primary: Color(0xFF22A36D),
  onPrimary: Color(0xFF151A17),
  primaryContainer: Color(0xFF12301F),
  onPrimaryContainer: Color(0xFF22A36D),
  secondary: Color(0xFF9AA79F),
  onSecondary: Color(0xFF151A17),
  surface: Color(0xFF151A17),
  onSurface: Color(0xFFE9EFEB),
  surfaceContainerLow: Color(0xFF1F2621), // Surface tint
  surfaceContainerHighest: Color(0xFF2B332D), // Card border
  outline: Color(0xFF8B988F), // Muted
  outlineVariant: Color(0xFF242C26), // Hairline
  error: Color(0xFFE07A5F),
  errorContainer: Color(0xFF331813),
  onErrorContainer: Color(0xFFE07A5F),
  onSurfaceVariant: Color(0xFF9AA79F), // secondaryText
  tertiary: Color(0xFFB6C2BA), // iconColor
  secondaryContainer: Color(0xFF4B564F), // faint
  tertiaryContainer: Color(0xFF2A1611), // danger-tint2
  inverseSurface: Color(0xFF4A2B21), // danger-border
);

extension CrispColorScheme on ColorScheme {
  Color get surfaceTint => surfaceContainerLow; // --tint
  Color get cardBorder => surfaceContainerHighest; // --border
  Color get hairline => outlineVariant; // --hairline
  Color get secondaryText => onSurfaceVariant; // --secondary
  Color get iconColor => tertiary; // --icon
  Color get faint => secondaryContainer; // --faint
  Color get greenTint => primaryContainer; // --green-tint
  Color get dangerTint => errorContainer; // --danger-tint
  Color get dangerTint2 => tertiaryContainer; // --danger-tint2
  Color get dangerBorder => inverseSurface; // --danger-border
  Color get aiCardBg => brightness == Brightness.light
      ? const Color(0xFF0F1512)
      : const Color(0xFF0C1712);
  Color get switchOff => brightness == Brightness.light
      ? const Color(0xFFD5DBD7)
      : const Color(0xFF37413B);
  Color get knobColor =>
      brightness == Brightness.light ? Colors.white : const Color(0xFFF2F5F3);
}

ThemeData buildAppTheme(Brightness brightness, double baseFontSize) {
  final colorScheme =
      brightness == Brightness.dark ? _darkColorScheme : _lightColorScheme;
  final baseTheme = ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    visualDensity: VisualDensity.standard,
  );

  final textTheme =
      GoogleFonts.plusJakartaSansTextTheme(baseTheme.textTheme).apply(
    bodyColor: colorScheme.onSurface,
    displayColor: colorScheme.onSurface,
  );

  return baseTheme.copyWith(
    textTheme: textTheme,
    primaryTextTheme: GoogleFonts.plusJakartaSansTextTheme(
      baseTheme.primaryTextTheme,
    ),
    scaffoldBackgroundColor: colorScheme.surface,
    appBarTheme: AppBarTheme(
      backgroundColor: colorScheme.surface,
      foregroundColor: colorScheme.onSurface,
      elevation: 0,
      centerTitle: true,
      scrolledUnderElevation: 0.0,
      titleTextStyle: TextStyle(
        fontSize: 24,
        fontWeight: FontWeight.w800,
        color: colorScheme.onSurface,
        letterSpacing: -0.48,
      ),
    ),
    cardTheme: CardThemeData(
      color: colorScheme.surface,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colorScheme.surfaceContainerHighest),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
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

    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey('app_font_size')) {
      _hasUserCustomFontSize = true;
      fontSizeNotifier.value = prefs.getDouble('app_font_size') ?? 13.0;
    }
    if (prefs.containsKey('app_theme_mode')) {
      final themeIndex =
          prefs.getInt('app_theme_mode') ?? ThemeMode.light.index;
      themeModeNotifier.value = ThemeMode.values[themeIndex];
    }

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
    if (!_hasUserCustomFontSize) {
      final double physicalWidth = View.of(context).physicalSize.width;
      final double devicePixelRatio = View.of(context).devicePixelRatio;
      final double logicalWidth =
          devicePixelRatio > 0 ? physicalWidth / devicePixelRatio : 360.0;
      final bool isSmallPhone = logicalWidth < 360;
      final double defaultBase = isSmallPhone ? 12.0 : 13.0;

      if (fontSizeNotifier.value != defaultBase) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_hasUserCustomFontSize) {
            fontSizeNotifier.value = defaultBase;
          }
        });
      }
    }

    return ValueListenableBuilder<double>(
      valueListenable: fontSizeNotifier,
      builder: (context, baseFontSize, child) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeNotifier,
          builder: (context, themeMode, child) {
            final lightTheme = buildAppTheme(Brightness.light, baseFontSize);
            final darkTheme = buildAppTheme(Brightness.dark, baseFontSize);
            return MaterialApp(
              title: 'BNPB',
              theme: lightTheme,
              darkTheme: darkTheme,
              themeMode: themeMode,
              builder: (context, child) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    textScaler: TextScaler.linear(baseFontSize / 14.0),
                  ),
                  child: child!,
                );
              },
              home: SecurityGate(
                child: Platform.isMacOS
                    ? const MacOSShell(child: MacOSActiveContactsView())
                    : const MainPage(),
              ),
            );
          },
        );
      },
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
      body: PageView(
        controller: _pageController,
        physics: const NeverScrollableScrollPhysics(),
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
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
