import 'package:flutter/material.dart';
import 'skeleton_loader.dart';
import 'prayer_insights_skeleton.dart';

class HomePageSkeleton extends StatelessWidget {
  const HomePageSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
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
        _buildContactItemSkeleton(),
        const SizedBox(height: 12),
        _buildContactItemSkeleton(),
      ],
    );
  }

  Widget _buildContactItemSkeleton() {
    return Row(
      children: [
        // Avatar
        const SkeletonBox(width: 48, height: 48, shape: BoxShape.circle),
        const SizedBox(height: 16),
        // Name and details
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SkeletonBox(width: 180, height: 16),
              const SizedBox(height: 8),
              const SkeletonBox(width: 120, height: 14),
            ],
          ),
        ),
      ],
    );
  }
}
