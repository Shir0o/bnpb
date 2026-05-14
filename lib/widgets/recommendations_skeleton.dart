import 'package:flutter/material.dart';
import 'skeleton_loader.dart';

class RecommendationsSkeleton extends StatelessWidget {
  const RecommendationsSkeleton({super.key, this.itemCount = 3});

  final int itemCount;

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
            Row(
              children: const [
                SkeletonBox(width: 20, height: 20, shape: BoxShape.circle),
                SizedBox(width: 8),
                Expanded(child: SkeletonBox(width: 180, height: 18)),
                SizedBox(width: 8),
                SkeletonBox(width: 20, height: 20, shape: BoxShape.circle),
              ],
            ),
            const SizedBox(height: 12),
            for (var i = 0; i < itemCount; i++) ...[
              const _RecommendationRowSkeleton(),
              if (i < itemCount - 1) const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }
}

class _RecommendationRowSkeleton extends StatelessWidget {
  const _RecommendationRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: const [
        SkeletonBox(width: 36, height: 36, shape: BoxShape.circle),
        SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SkeletonBox(width: 140, height: 14),
              SizedBox(height: 6),
              SkeletonBox(width: double.infinity, height: 12),
            ],
          ),
        ),
        SizedBox(width: 12),
        SkeletonBox(width: 20, height: 20, shape: BoxShape.circle),
      ],
    );
  }
}
