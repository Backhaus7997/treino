import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../app/theme/app_palette.dart';
import '../../application/feed_screen_providers.dart';
import '../../domain/feed_segment.dart';

class FeedSegmentPills extends ConsumerWidget {
  const FeedSegmentPills({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segment = ref.watch(feedSegmentProvider);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const ClampingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _Pill(
            label: 'AMIGOS',
            isActive: segment == FeedSegment.amigos,
            onTap: () => ref.read(feedSegmentProvider.notifier).state =
                FeedSegment.amigos,
          ),
          const SizedBox(width: 12),
          const _Pill(
            label: 'MI GYM',
            isActive: false,
            onTap: null,
          ),
          const SizedBox(width: 12),
          const _Pill(
            label: 'PÚBLICO',
            isActive: false,
            onTap: null,
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  final String label;
  final bool isActive;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
        decoration: BoxDecoration(
          color: isActive ? palette.accent : palette.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isActive ? palette.accent : palette.border,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: isActive ? palette.bg : palette.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
