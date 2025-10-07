import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'screens/add_contact_page.dart';
import 'screens/analytics_page.dart';
import 'screens/home_page.dart';
import 'screens/notification_settings_page.dart';
import 'services/notification_preferences_repository.dart';
import 'services/reminder_coordinator.dart';
import 'services/reminder_service.dart';
import 'widgets/security_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ReminderService().initialize();
  final preferencesRepository = NotificationPreferencesRepository();
  await preferencesRepository.ensureDefaults();
  await ReminderCoordinator().refreshAllContacts();
  runApp(const MyApp());
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
      themeMode: ThemeMode.system, // Uses system light/dark mode
      home: const SecurityGate(
        child: MainPage(),
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

class _MainPageState extends State<MainPage> {
  int _currentIndex = 0;

  final List<Widget> _pages = [
    const HomePage(),
    const AnalyticsPage(),
    const AddContactPage(),
    const NotificationSettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
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
}