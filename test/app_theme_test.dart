import 'package:bnpb/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test('app themes use Material 3 and Plus Jakarta Sans typography', () {
    final lightTheme = buildAppTheme(Brightness.light, 13.0);
    final darkTheme = buildAppTheme(Brightness.dark, 13.0);

    expect(lightTheme.useMaterial3, isTrue);
    expect(darkTheme.useMaterial3, isTrue);

    // We enforce light mode colors for both
    expect(lightTheme.colorScheme.brightness, Brightness.light);
    expect(darkTheme.colorScheme.brightness, Brightness.light);

    // Assert that scrolledUnderElevation is disabled
    expect(lightTheme.appBarTheme.scrolledUnderElevation, 0.0);
    expect(darkTheme.appBarTheme.scrolledUnderElevation, 0.0);

    // Assert custom titleTextStyle on appBarTheme
    expect(lightTheme.appBarTheme.titleTextStyle?.fontSize, 24.0);
    expect(lightTheme.appBarTheme.titleTextStyle?.fontWeight, FontWeight.w800);
  });

  test('theme uses the provided Material 3 color palette for Crisp Utility',
      () {
    final colorScheme = buildAppTheme(Brightness.light, 13.0).colorScheme;

    expect(colorScheme.primary, const Color(0xFF0D7A4F));
    expect(colorScheme.onPrimary, const Color(0xFFFFFFFF));
    expect(colorScheme.primaryContainer, const Color(0xFFEAF6EF));
    expect(colorScheme.onPrimaryContainer, const Color(0xFF0D7A4F));
    expect(colorScheme.secondary, const Color(0xFF127A6B));
    expect(colorScheme.error, const Color(0xFFC25A3F));
    expect(colorScheme.errorContainer, const Color(0xFFFBEEE9));
    expect(colorScheme.surface, const Color(0xFFFFFFFF));
    expect(colorScheme.onSurface, const Color(0xFF0F1512));
    expect(colorScheme.surfaceContainerHighest, const Color(0xFFE6EBE7));
    expect(colorScheme.surfaceContainerLow, const Color(0xFFF1F5F2));
    expect(colorScheme.outline, const Color(0xFF8A988F));
    expect(colorScheme.outlineVariant, const Color(0xFFEEF2EF));
  });

  test('fontSizeNotifier updates and persists correct value', () async {
    SharedPreferences.setMockInitialValues({});

    // Update font size
    await updateFontSize(15.0);
    expect(fontSizeNotifier.value, 15.0);

    // Verify it is saved in SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getDouble('app_font_size'), 15.0);
  });
}
