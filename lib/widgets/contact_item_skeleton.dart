import 'package:flutter/material.dart';
import 'skeleton_loader.dart';

class ContactItemSkeleton extends StatelessWidget {
  const ContactItemSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0, // Flat look for skeleton
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: Colors
          .transparent, // Let skeleton loader highlighting work or just keep structure
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Avatar (radius 24 = 48x48)
            const SkeletonBox(width: 48, height: 48, shape: BoxShape.circle),
            const SizedBox(width: 12),
            // Name and details
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SkeletonBox(width: 140, height: 18), // Name
                  const SizedBox(height: 8),
                  const SkeletonBox(width: 100, height: 14), // Subtitle
                  const SizedBox(height: 12),
                  const SkeletonBox(
                    width: double.infinity,
                    height: 60,
                  ), // Interaction/Keyword area
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
