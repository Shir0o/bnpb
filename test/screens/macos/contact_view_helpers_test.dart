import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:bnpb/screens/macos/contact_view_helpers.dart';

void main() {
  group('getAvatarColor', () {
    test('returns consistent color for same input', () {
      expect(getAvatarColor('John'), getAvatarColor('John'));
      expect(getAvatarColor('Alice'), isNot(getAvatarColor('John')));
    });

    test('returns default for empty input', () {
      expect(getAvatarColor(''), Colors.blue);
    });
  });

  group('formatDate', () {
    test('returns Today', () {
      expect(formatDate(DateTime.now()), 'Today');
    });

    test('returns Yesterday', () {
      expect(
        formatDate(DateTime.now().subtract(const Duration(days: 1))),
        'Yesterday',
      );
    });

    test('returns formatted date for older dates', () {
      final oldDate = DateTime(2023, 10, 24);
      expect(formatDate(oldDate), 'Oct 24');
    });
  });

  group('formatTime', () {
    test('returns formatted time', () {
      final date = DateTime(2023, 10, 24, 8, 30);
      expect(formatTime(date), '8:30 AM');
    });

    test('returns formatted time (PM)', () {
      final date = DateTime(2023, 10, 24, 20, 30);
      expect(formatTime(date), '8:30 PM');
    });
  });

  group('getMediumIcon', () {
    test('returns call icon', () {
      expect(getMediumIcon('call'), Icons.call);
      expect(getMediumIcon('phone'), Icons.call);
    });

    test('returns message icon', () {
      expect(getMediumIcon('text'), Icons.message);
      expect(getMediumIcon('sms'), Icons.message);
    });

    test('returns email icon', () {
      expect(getMediumIcon('email'), Icons.email);
    });

    test('returns default icon for unknown', () {
      expect(getMediumIcon('unknown'), Icons.chat_bubble_outline);
    });
  });
}
