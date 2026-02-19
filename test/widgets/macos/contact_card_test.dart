import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/screens/macos/contact_card.dart';
import 'package:bnpb/models/contact.dart';

void main() {
  testWidgets('ContactCard has performance optimizations', (WidgetTester tester) async {
    final contact = Contact(
      id: '1',
      firstName: 'John',
      lastName: 'Doe',
      recognitionPhotoUris: ['https://example.com/photo.jpg'],
    );

    // Mock network images to avoid actual network calls (though ResizeImage doesn't fetch until layout/paint, better safe)
    // Actually, NetworkImage in test environment usually throws if not mocked or handled.
    // However, ResizeImage wraps it.
    // We can just inspect the widget tree without triggering the image load fully if we are careful.

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ContactCard(contact: contact),
        ),
      ),
    );

    // Check for RepaintBoundary inside InkWell
    // The structure is Material -> InkWell -> RepaintBoundary -> Container
    final inkWellFinder = find.byType(InkWell);
    expect(inkWellFinder, findsOneWidget);

    final repaintBoundaryFinder = find.descendant(
      of: inkWellFinder,
      matching: find.byType(RepaintBoundary),
    );

    expect(repaintBoundaryFinder, findsOneWidget,
        reason: 'ContactCard content should be wrapped in RepaintBoundary to isolate from hover effects');

    // Check for ResizeImage
    // Find the Container with the decoration
    final containerFinder = find.descendant(
      of: find.byType(Column),
      matching: find.byWidgetPredicate((widget) {
        if (widget is Container && widget.decoration is BoxDecoration) {
          final decoration = widget.decoration as BoxDecoration;
          return decoration.image != null;
        }
        return false;
      }),
    );

    expect(containerFinder, findsOneWidget, reason: 'Should find the avatar container');
    final container = tester.widget<Container>(containerFinder);
    final decoration = container.decoration as BoxDecoration;
    final imageProvider = decoration.image!.image;

    expect(imageProvider, isA<ResizeImage>(),
        reason: 'Contact avatar should use ResizeImage to save memory');

    final resizeImage = imageProvider as ResizeImage;
    // We expect the width to be around 64 * devicePixelRatio.
    // Since we didn't specify a devicePixelRatio, it defaults to 3.0 in tests usually, or 1.0.
    // We just check it is set.
    expect(resizeImage.width, isNotNull);
    // And specifically, it should be at least 64.
    expect(resizeImage.width! >= 64, isTrue);
  });
}
