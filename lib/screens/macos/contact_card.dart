import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../models/contact.dart';
import '../../models/prayer_request.dart';

class ContactCard extends StatelessWidget {
  final Contact contact;
  final bool isSelected;
  final VoidCallback? onTap;

  const ContactCard({
    super.key,
    required this.contact,
    this.isSelected = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final activeRequestCount = contact.prayerRequests
        .where((r) => r.status == PrayerRequestStatus.pending)
        .length;

    final borderColor = isSelected
        ? colorScheme.primary.withValues(alpha: 0.2)
        : Colors.transparent;
    final backgroundColor = isSelected
        ? colorScheme.primary.withValues(alpha: 0.1)
        : Colors.transparent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: colorScheme.surfaceContainerLow,
        // Optimization: Isolate the content from the InkWell ripple animation.
        child: RepaintBoundary(
          child: Container(
            decoration: BoxDecoration(
              color: backgroundColor,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? borderColor : Colors.transparent,
                width: isSelected ? 2 : 1, // Visual emphasis
              ),
            ),
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Avatar
                Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest,
                    shape: BoxShape.circle,
                    border: Border.all(color: colorScheme.surfaceContainerHigh),
                    image: contact.recognitionPhotoUris.isNotEmpty
                        ? DecorationImage(
                            // Optimization: Resize image to display size to save memory.
                            image: ResizeImage(
                              NetworkImage(contact.recognitionPhotoUris.first),
                              width:
                                  (64 * MediaQuery.of(context).devicePixelRatio)
                                      .toInt(),
                            ),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: contact.recognitionPhotoUris.isEmpty
                      ? Text(
                          contact.initials,
                          style: GoogleFonts.googleSans(
                            fontSize: 24,
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        )
                      : null,
                ),
                const SizedBox(height: 12),
                // Name
                Text(
                  contact.displayName,
                  style: GoogleFonts.googleSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                // Status / Active Requests
                Text(
                  activeRequestCount > 0
                      ? '$activeRequestCount active request${activeRequestCount == 1 ? '' : 's'}'
                      : 'No active requests',
                  style: GoogleFonts.googleSans(
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: activeRequestCount > 0
                        ? colorScheme.primary
                        : colorScheme.outline,
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AddContactCard extends StatelessWidget {
  final VoidCallback? onTap;

  const AddContactCard({super.key, this.onTap});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: colorScheme.surfaceContainerLow,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outlineVariant,
              style: BorderStyle
                  .solid, // Flutter doesn't support dashed easily without package, sticking to solid or using CustomPainter.
              // Design says dashed. For simplicity without extra dependencies, I'll use solid light grey which looks fine,
              // or implement a dashed border painter if critical. Let's start with solid light grey.
            ),
          ),
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.outlineVariant,
                    width: 2,
                    style: BorderStyle
                        .solid, // Again, mimicking dashed visually or using simple border
                  ),
                ),
                child: Icon(
                  Icons.add,
                  size: 32,
                  color: colorScheme.outlineVariant,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Add Contact',
                style: GoogleFonts.googleSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.outline,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              // Spacer to align with contact card text height
              Text('', style: GoogleFonts.googleSans(fontSize: 11)),
            ],
          ),
        ),
      ),
    );
  }
}
