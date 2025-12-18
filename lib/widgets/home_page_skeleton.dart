import 'package:flutter/material.dart';
import 'skeleton_loader.dart';

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
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white, width: 2), // Simulate card border
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                 // Title
                const SkeletonBox(width: 150, height: 20),
                const SizedBox(height: 12),
                
                // Insights items (simulating "Needs prayer" section)
                const SkeletonBox(width: 100, height: 16),
                const SizedBox(height: 8),
                Row(
                  children: [
                     const SkeletonBox(width: 24, height: 24, shape: BoxShape.circle),
                     const SizedBox(width: 16),
                     Expanded(
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                             const SkeletonBox(width: double.infinity, height: 14),
                             const SizedBox(height: 4),
                             const SkeletonBox(width: 150, height: 12),
                         ],
                       ),
                     ),
                  ],
                ),
                 const SizedBox(height: 12),
                // Another item
                 Row(
                  children: [
                     const SkeletonBox(width: 24, height: 24, shape: BoxShape.circle),
                     const SizedBox(width: 16),
                     Expanded(
                       child: Column(
                         crossAxisAlignment: CrossAxisAlignment.start,
                         children: [
                             const SkeletonBox(width: 200, height: 14),
                             const SizedBox(height: 4),
                             const SkeletonBox(width: 120, height: 12),
                         ],
                       ),
                     ),
                  ],
                ),
              ],
            ),
          ),
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
