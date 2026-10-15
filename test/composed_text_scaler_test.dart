import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/main.dart';

void main() {
  group('ComposedTextScaler', () {
    test('scales font size by composing parent scaler with factor', () {
      const parent = TextScaler.linear(1.5);
      const composed = ComposedTextScaler(parent, 16.0 / 14.0);

      // 14.0 font size -> 14.0 * 1.5 * (16.0 / 14.0) = 24.0
      expect(composed.scale(14.0), closeTo(24.0, 0.0001));
      // textScaleFactor estimated property
      // ignore: deprecated_member_use
      expect(composed.textScaleFactor, closeTo(1.5 * (16.0 / 14.0), 0.0001));
    });

    test('preserves equality and hashCode', () {
      const parent = TextScaler.linear(1.2);
      const scaler1 = ComposedTextScaler(parent, 1.1);
      const scaler2 = ComposedTextScaler(parent, 1.1);
      const scaler3 = ComposedTextScaler(parent, 1.2);

      expect(scaler1, equals(scaler2));
      expect(scaler1.hashCode, equals(scaler2.hashCode));
      expect(scaler1, isNot(equals(scaler3)));
    });

    test('supports clamp method', () {
      const parent = TextScaler.linear(2.0);
      const composed = ComposedTextScaler(parent, 1.5);
      // unclamped would be 3.0x -> 10.0 * 3.0 = 30.0
      final clamped = composed.clamp(maxScaleFactor: 2.5);
      expect(clamped.scale(10.0), closeTo(25.0, 0.0001));
    });
  });
}
