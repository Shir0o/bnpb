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
    final activeRequestCount = contact.prayerRequests
        .where((r) => r.status == PrayerRequestStatus.pending)
        .length;

    final borderColor = isSelected
        ? Theme.of(context).primaryColor.withValues(alpha: 0.2)
        : Colors.transparent;
    final backgroundColor = isSelected
        ? Theme.of(context).primaryColor.withValues(alpha: 0.1)
        : Colors.transparent;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: Colors.grey[50],
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
                    color: Colors.grey[200],
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey[100]!),
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
                            color: Colors.grey[500],
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
                    color: Colors.grey[900],
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
                        ? Theme.of(context).primaryColor
                        : Colors.grey[400],
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
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        hoverColor: Colors.grey[50],
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: Colors.grey[300]!,
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
                    color: Colors.grey[300]!,
                    width: 2,
                    style: BorderStyle
                        .solid, // Again, mimicking dashed visually or using simple border
                  ),
                ),
                child: Icon(Icons.add, size: 32, color: Colors.grey[300]),
              ),
              const SizedBox(height: 12),
              Text(
                'Add Contact',
                style: GoogleFonts.googleSans(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[400],
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
