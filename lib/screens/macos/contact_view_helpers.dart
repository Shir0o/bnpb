import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Returns a deterministic color based on the input text.
Color getAvatarColor(String text, [ColorScheme? colorScheme]) {
  if (colorScheme != null) {
    final colors = [
      colorScheme.primary,
      colorScheme.secondary,
      colorScheme.tertiary,
      colorScheme.primaryFixedDim,
      colorScheme.secondaryFixedDim,
      colorScheme.tertiaryFixedDim,
      colorScheme.inversePrimary,
      colorScheme.error,
    ];
    return colors[text.isEmpty ? 0 : text.codeUnitAt(0) % colors.length];
  }

  if (text.isEmpty) return Colors.blue;
  final colors = [
    Colors.blue,
    Colors.red,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.teal,
    Colors.indigo,
    Colors.brown,
  ];
  return colors[text.codeUnitAt(0) % colors.length];
}

// Optimization: Cache DateFormat instances to avoid expensive initialization on every call
final _monthDayFormat = DateFormat('MMM d');
final _timeFormat = DateFormat('h:mm a');

/// Formats a date into a human-readable string (Today, Yesterday, MMM d).
String formatDate(DateTime date) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final input = DateTime(date.year, date.month, date.day);

  if (input == today) {
    return 'Today';
  } else if (input == today.subtract(const Duration(days: 1))) {
    return 'Yesterday';
  } else {
    return _monthDayFormat.format(date);
  }
}

/// Formats a time into a human-readable string (h:mm a).
String formatTime(DateTime date) {
  return _timeFormat.format(date);
}

/// Returns an icon representing the communication medium.
IconData getMediumIcon(String medium) {
  final normalized = medium.toLowerCase().trim();
  switch (normalized) {
    case 'call':
    case 'phone':
      return Icons.call;
    case 'text':
    case 'sms':
    case 'message':
      return Icons.message;
    case 'email':
    case 'mail':
      return Icons.email;
    case 'video':
    case 'meet':
    case 'zoom':
      return Icons.videocam;
    case 'person':
    case 'face':
    case 'meeting':
      return Icons.face;
    case 'group':
    case 'community':
      return Icons.groups;
    default:
      return Icons.chat_bubble_outline;
  }
}
