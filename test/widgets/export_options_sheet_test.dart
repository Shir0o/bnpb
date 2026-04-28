import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/widgets/export_options_sheet.dart';
import 'package:bnpb/models/contact.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('ExportOptionsSheet displays all export format buttons',
      (WidgetTester tester) async {
    final contacts = [Contact(id: '1', firstName: 'Alice')];

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ExportOptionsSheet(contacts: contacts),
      ),
    ));

    // Verify format buttons exist
    expect(find.text('Export JSON'), findsOneWidget);
    expect(find.text('Export CSV'), findsOneWidget);
    expect(find.text('Export PDF'), findsOneWidget);
    expect(find.text('Create encrypted archive'), findsOneWidget);

    // Verify field selection exists
    expect(find.text('First name'), findsOneWidget);
    expect(find.text('Nickname'), findsOneWidget);
  });
}
