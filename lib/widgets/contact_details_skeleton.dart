import 'package:flutter/material.dart';
import 'skeleton_loader.dart';

class ContactDetailsSkeleton extends StatelessWidget {
  const ContactDetailsSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return SkeletonLoader(
      child: CustomScrollView(
        physics: const NeverScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.all(16.0),
            sliver: SliverList(
              delegate: SliverChildListDelegate([
                // PeopleCard Skeleton / Header
                const SkeletonBox(
                  width: double.infinity,
                  height: 140, // Height of PeopleCard
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                const SizedBox(height: 16),

                // Detail Section (e.g. Meeting Context)
                const SkeletonBox(
                  width: double.infinity,
                  height: 100,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                const SizedBox(height: 16),

                // Detail Section (e.g. Recognition)
                const SkeletonBox(
                  width: double.infinity,
                  height: 120,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                const SizedBox(height: 16),

                // Relationships Card
                const SkeletonBox(
                  width: double.infinity,
                  height: 150,
                  borderRadius: BorderRadius.all(Radius.circular(12)),
                ),
                const SizedBox(height: 16),
              ]),
            ),
          ),
          // Interactions Header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const SkeletonBox(
                width: double.infinity,
                height: 120,
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
            ),
          ),
          // Interactions List Items
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                return Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Timeline line/dot
                      const Column(
                        children: [
                          SkeletonBox(
                            width: 24,
                            height: 24,
                            shape: BoxShape.circle,
                          ),
                          SizedBox(height: 8),
                          SkeletonBox(width: 2, height: 40),
                        ],
                      ),
                      const SizedBox(width: 12),
                      // Card
                      Expanded(
                        child: const SkeletonBox(
                          width: double.infinity,
                          height: 100,
                          borderRadius: BorderRadius.all(Radius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                );
              }, childCount: 3),
            ),
          ),
        ],
      ),
    );
  }
}
