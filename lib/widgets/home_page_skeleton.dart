import 'package:flutter/material.dart';
import 'skeleton_loader.dart';
import 'prayer_insights_skeleton.dart';
import 'contact_item_skeleton.dart';

class HomePageSkeleton extends StatelessWidget {
  const HomePageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      duration: const Duration(seconds: 6),
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        physics: const NeverScrollableScrollPhysics(), // Disable scrolling on skeleton
        children: [
          // Search Bar
          const SkeletonBox(
            height: 48,
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
          const SizedBox(height: 16),

          // Prayer Insights Card
          const PrayerInsightsSkeleton(),
          const SizedBox(height: 16),

          // Filter Chips
          Row(
            children: [
              const SkeletonBox(width: 50, height: 32, borderRadius: BorderRadius.all(Radius.circular(8))),
              const SizedBox(width: 8),
              const SkeletonBox(width: 80, height: 32, borderRadius: BorderRadius.all(Radius.circular(8))),
              const SizedBox(width: 8),
              const SkeletonBox(width: 70, height: 32, borderRadius: BorderRadius.all(Radius.circular(8))),
            ],
          ),
          const SizedBox(height: 24),

          // Contact Groups
          _buildContactGroupSkeleton(),
          const SizedBox(height: 16),
          _buildContactGroupSkeleton(),
          const SizedBox(height: 16),
          _buildContactGroupSkeleton(),
        ],
      ),
    );
  }

  Widget _buildContactGroupSkeleton() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Group Header
        const SkeletonBox(width: 100, height: 18),
        const SizedBox(height: 12),
        // Contact Items
        const ContactItemSkeleton(),
        const SizedBox(height: 12),
        const ContactItemSkeleton(),
      ],
    );
  }


}
