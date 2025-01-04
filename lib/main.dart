import 'package:flutter/material.dart';

void main() {
  runApp(const MyApp());
}

/// Root of the application
class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'BNPB - Demo', // Updated app title
      theme: ThemeData(
        // Set up a theme with Material 3 and a seed color
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      home: const MyHomePage(title: 'BNPB Demo Home Page'), // Updated home page
    );
  }
}

/// Home page widget, receives a title as input
class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key, required this.title});

  final String title; // Title for the AppBar

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

/// State class for MyHomePage
class _MyHomePageState extends State<MyHomePage> {
  int _counter = 0; // Counter to track button presses

  /// Increment the counter and trigger a UI rebuild
  void _incrementCounter() {
    setState(() {
      _counter++;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        // The AppBar title is set dynamically based on the widget's title
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        title: Text(widget.title),
      ),
      body: Center(
        // Center widget to align children in the middle of the screen
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center, // Vertically center content
          children: <Widget>[
            const Text(
              'You have pressed the button this many times:',
            ),
            Text(
              '$_counter', // Display the counter value
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter, // Increment counter when pressed
        tooltip: 'Increment', // Tooltip for accessibility
        child: const Icon(Icons.add),
      ),
    );
  }
}
