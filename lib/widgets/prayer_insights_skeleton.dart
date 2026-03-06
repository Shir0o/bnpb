import 'package:flutter/material.dart';
import 'skeleton_loader.dart';

class PrayerInsightsSkeleton extends StatelessWidget {
  const PrayerInsightsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title "Prayer insights"
            const Align(
              alignment: Alignment.centerLeft,
              child: SkeletonBox(width: 150, height: 24),
            ),
            const SizedBox(height: 12),

            // --- Section 1: Review/Needs Prayer ---
            const Align(
              alignment: Alignment.centerLeft,
              child: SkeletonBox(width: 100, height: 16),
            ),
            const SizedBox(height: 8),
            _buildInteractionItemSkeleton(),
            const SizedBox(height: 12),
            _buildInteractionItemSkeleton(),

            const SizedBox(height: 20),

            // --- Section 2: Answered ---
            const Align(
              alignment: Alignment.centerLeft,
              child: SkeletonBox(width: 120, height: 16),
            ),
            const SizedBox(height: 8),
            _buildInteractionItemSkeleton(),
            const SizedBox(height: 12),
            _buildInteractionItemSkeleton(),

            const SizedBox(height: 20),

            // --- Section 3: Interactions ---
            const Align(
              alignment: Alignment.centerLeft,
              child: SkeletonBox(width: 140, height: 16),
            ),
            const SizedBox(height: 8),
            _buildInteractionItemSkeleton(),
            const SizedBox(height: 12),
            _buildInteractionItemSkeleton(),
          ],
        ),
      ),
    );
  }

  Widget _buildInteractionItemSkeleton() {
    return Row(
      children: [
        // Icon placeholder
        const SkeletonBox(width: 24, height: 24, shape: BoxShape.circle),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Interaction summary
              const SkeletonBox(width: double.infinity, height: 14),
              const SizedBox(height: 4),
              // Date • Contact Name
              const SkeletonBox(width: 150, height: 12),
            ],
          ),
        ),
      ],
    );
  }
}
