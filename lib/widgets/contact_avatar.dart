import 'package:flutter/material.dart';
import '../models/contact.dart';

/// A reusable avatar widget utilizing the green color palette from Crisp Utility design tokens.
class ContactAvatar extends StatelessWidget {
  const ContactAvatar({
    super.key,
    required this.contact,
    this.radius = 22,
    this.isDisabled = false,
  });

  final Contact contact;
  final double radius;
  final bool isDisabled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (isDisabled) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        child: Text(
          contact.initials,
          style: TextStyle(
            color: theme.colorScheme.outline,
            fontWeight: FontWeight.bold,
            fontSize: radius * 0.8,
          ),
        ),
      );
    }

    // Consistent hashing algorithm for avatar colors:
    const greens = [
      Color(0xFF0D7A4F),
      Color(0xFF127A6B),
      Color(0xFF1A6B4A),
      Color(0xFF0E6F5C),
    ];

    int h = 0;
    final source = contact.id.isNotEmpty
        ? contact.id
        : (contact.firstName.isNotEmpty ? contact.firstName : '');
    for (int i = 0; i < source.length; i++) {
      h = (h * 31 + source.codeUnitAt(i)) % greens.length;
    }
    final avatarColor = greens[h];

    return CircleAvatar(
      radius: radius,
      backgroundColor: avatarColor,
      child: Text(
        contact.initials,
        style: TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );
  }
}
