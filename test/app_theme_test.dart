import 'package:bnpb/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  GoogleFonts.config.allowRuntimeFetching = false;

  test('app themes use Material 3 and Google Sans typography', () {
    final lightTheme = buildAppTheme(Brightness.light);
    final darkTheme = buildAppTheme(Brightness.dark);

    expect(lightTheme.useMaterial3, isTrue);
    expect(darkTheme.useMaterial3, isTrue);
    expect(
        lightTheme.textTheme.bodyMedium?.fontFamily, startsWith('GoogleSans'));
    expect(
        darkTheme.textTheme.bodyMedium?.fontFamily, startsWith('GoogleSans'));
    expect(lightTheme.colorScheme.brightness, Brightness.light);
    expect(darkTheme.colorScheme.brightness, Brightness.dark);
  });

  test('light theme uses the provided Material 3 color palette', () {
    final colorScheme = buildAppTheme(Brightness.light).colorScheme;

    expect(colorScheme.primary, const Color(0xFF6750A4));
    expect(colorScheme.onPrimary, const Color(0xFFFFFFFF));
    expect(colorScheme.primaryContainer, const Color(0xFFEADDFF));
    expect(colorScheme.onPrimaryContainer, const Color(0xFF4F378B));
    expect(colorScheme.inversePrimary, const Color(0xFFD0BCFF));
    expect(colorScheme.secondary, const Color(0xFF625B71));
    expect(colorScheme.secondaryContainer, const Color(0xFFE8DEF8));
    expect(colorScheme.tertiary, const Color(0xFF7D5260));
    expect(colorScheme.tertiaryContainer, const Color(0xFFFFD8E4));
    expect(colorScheme.error, const Color(0xFFB3261E));
    expect(colorScheme.errorContainer, const Color(0xFFF9DEDC));
    expect(colorScheme.surface, const Color(0xFFFEF7FF));
    expect(colorScheme.onSurface, const Color(0xFF1D1B20));
    expect(colorScheme.surfaceContainerHighest, const Color(0xFFE6E0E9));
    expect(colorScheme.surfaceContainerHigh, const Color(0xFFECE6F0));
    expect(colorScheme.surfaceContainer, const Color(0xFFF3EDF7));
    expect(colorScheme.surfaceContainerLow, const Color(0xFFF7F2FA));
    expect(colorScheme.surfaceContainerLowest, const Color(0xFFFFFFFF));
    expect(colorScheme.outline, const Color(0xFF79747E));
    expect(colorScheme.outlineVariant, const Color(0xFFCAC4D0));
    expect(colorScheme.primaryFixed, const Color(0xFFEADDFF));
    expect(colorScheme.onPrimaryFixed, const Color(0xFF21005D));
    expect(colorScheme.primaryFixedDim, const Color(0xFFD0BCFF));
    expect(colorScheme.onPrimaryFixedVariant, const Color(0xFF4F378B));
  });

  test('dark theme uses the provided Material 3 color palette', () {
    final colorScheme = buildAppTheme(Brightness.dark).colorScheme;

    expect(colorScheme.primary, const Color(0xFFD0BCFF));
    expect(colorScheme.onPrimary, const Color(0xFF381E72));
    expect(colorScheme.primaryContainer, const Color(0xFF4F378B));
    expect(colorScheme.onPrimaryContainer, const Color(0xFFEADDFF));
    expect(colorScheme.secondary, const Color(0xFFCCC2DC));
    expect(colorScheme.onSecondary, const Color(0xFF332D41));
    expect(colorScheme.secondaryContainer, const Color(0xFF4A4458));
    expect(colorScheme.onSecondaryContainer, const Color(0xFFE8DEF8));
    expect(colorScheme.tertiary, const Color(0xFFEFB8C8));
    expect(colorScheme.onTertiary, const Color(0xFF492532));
    expect(colorScheme.tertiaryContainer, const Color(0xFF633B48));
    expect(colorScheme.onTertiaryContainer, const Color(0xFFFFD8E4));
    expect(colorScheme.error, const Color(0xFFF2B8B5));
    expect(colorScheme.onError, const Color(0xFF601410));
    expect(colorScheme.errorContainer, const Color(0xFF8C1D18));
    expect(colorScheme.onErrorContainer, const Color(0xFFF9DEDC));
    expect(colorScheme.surface, const Color(0xFF141218));
    expect(colorScheme.onSurface, const Color(0xFFE6E0E9));
    expect(colorScheme.onSurfaceVariant, const Color(0xFFCAC4D0));
    expect(colorScheme.surfaceContainerHighest, const Color(0xFF36343B));
    expect(colorScheme.surfaceContainerHigh, const Color(0xFF2B2930));
    expect(colorScheme.surfaceContainer, const Color(0xFF211F26));
    expect(colorScheme.surfaceContainerLow, const Color(0xFF1D1B20));
    expect(colorScheme.surfaceContainerLowest, const Color(0xFF0F0D13));
    expect(colorScheme.inverseSurface, const Color(0xFFE6E0E9));
    expect(colorScheme.onInverseSurface, const Color(0xFF322F35));
    expect(colorScheme.surfaceTint, const Color(0xFFD0BCFF));
    expect(colorScheme.outline, const Color(0xFF938F99));
    expect(colorScheme.outlineVariant, const Color(0xFF49454F));
    expect(colorScheme.primaryFixed, const Color(0xFFEADDFF));
    expect(colorScheme.onPrimaryFixed, const Color(0xFF21005D));
    expect(colorScheme.primaryFixedDim, const Color(0xFFD0BCFF));
    expect(colorScheme.onPrimaryFixedVariant, const Color(0xFF4F378B));
    expect(colorScheme.inversePrimary, const Color(0xFF6750A4));
    expect(colorScheme.secondaryFixed, const Color(0xFFE8DEF8));
    expect(colorScheme.onSecondaryFixed, const Color(0xFF1D192B));
    expect(colorScheme.secondaryFixedDim, const Color(0xFFCCC2DC));
    expect(colorScheme.onSecondaryFixedVariant, const Color(0xFF4A4458));
    expect(colorScheme.tertiaryFixed, const Color(0xFFFFD8E4));
    expect(colorScheme.onTertiaryFixed, const Color(0xFF31111D));
    expect(colorScheme.tertiaryFixedDim, const Color(0xFFEFB8C8));
    expect(colorScheme.onTertiaryFixedVariant, const Color(0xFF633B48));
    expect(colorScheme.surfaceBright, const Color(0xFF3B383E));
    expect(colorScheme.surfaceDim, const Color(0xFF141218));
    expect(colorScheme.scrim, const Color(0xFF000000));
    expect(colorScheme.shadow, const Color(0xFF000000));
  });
}
