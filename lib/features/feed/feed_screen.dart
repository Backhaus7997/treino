import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_palette.dart';
import '../../core/widgets/treino_icon.dart';
import 'application/feed_screen_providers.dart';
import 'application/post_providers.dart';
import 'domain/feed_segment.dart';
import 'presentation/widgets/feed_empty_state.dart';
import 'presentation/widgets/feed_segment_pills.dart';
import 'presentation/widgets/post_card.dart';

class FeedScreen extends ConsumerWidget {
  const FeedScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segment = ref.watch(feedSegmentProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _FeedHeader(),
        const SizedBox(height: 14),
        const FeedSegmentPills(),
        const SizedBox(height: 18),
        Expanded(
          child: switch (segment) {
            FeedSegment.amigos => const _AmigosBody(),
            FeedSegment.gym => const _MiGymBody(),
            FeedSegment.public => const _PublicoBody(),
          },
        ),
      ],
    );
  }
}

class _FeedHeader extends StatelessWidget {
  const _FeedHeader();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          Text(
            'FEED',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 28,
              letterSpacing: 1.2,
              color: palette.textPrimary,
            ),
          ),
          const Spacer(),
          Icon(TreinoIcon.search, size: 20, color: palette.textMuted),
          const SizedBox(width: 18),
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: palette.accent,
              shape: BoxShape.circle,
            ),
            child: Icon(TreinoIcon.plus, size: 20, color: palette.bg),
          ),
        ],
      ),
    );
  }
}

class _AmigosBody extends ConsumerWidget {
  const _AmigosBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final asyncPosts = ref.watch(myFriendsFeedProvider);

    return asyncPosts.when(
      data: (posts) {
        if (posts.isEmpty) {
          return const FeedEmptyState(
            message: 'Aún no hay posts de tus amigos',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: posts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (_, i) => PostCard(
            post: posts[i],
            onAuthorTap: () =>
                context.go('/feed/profile/${posts[i].authorUid}'),
          ),
        );
      },
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'No pudimos cargar tu feed. Intentá de nuevo.',
            style: GoogleFonts.barlow(
              fontSize: 14,
              color: palette.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _MiGymBody extends ConsumerWidget {
  const _MiGymBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final asyncPosts = ref.watch(myGymFeedProvider);

    return asyncPosts.when(
      data: (posts) {
        if (posts == null) {
          return const FeedEmptyState(
            message: 'Todavía no estás en un gym',
          );
        }
        if (posts.isEmpty) {
          return const FeedEmptyState(
            message: 'Tu gym todavía no tiene posts',
          );
        }
        // TODO(pagination): cursor-based pagination deferred (see explore §9)
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: posts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (_, i) => PostCard(
            post: posts[i],
            onAuthorTap: () =>
                context.go('/feed/profile/${posts[i].authorUid}'),
          ),
        );
      },
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'No pudimos cargar tu feed. Intentá de nuevo.',
            style: GoogleFonts.barlow(
              fontSize: 14,
              color: palette.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}

class _PublicoBody extends ConsumerWidget {
  const _PublicoBody();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final asyncPosts = ref.watch(feedPublicProvider);

    return asyncPosts.when(
      data: (posts) {
        if (posts.isEmpty) {
          return const FeedEmptyState(
            message: 'Aún no hay posts públicos',
          );
        }
        // TODO(pagination): cursor-based pagination deferred (see explore §9)
        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          itemCount: posts.length,
          separatorBuilder: (_, __) => const SizedBox(height: 14),
          itemBuilder: (_, i) => PostCard(
            post: posts[i],
            onAuthorTap: () =>
                context.go('/feed/profile/${posts[i].authorUid}'),
          ),
        );
      },
      loading: () => Center(
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'No pudimos cargar tu feed. Intentá de nuevo.',
            style: GoogleFonts.barlow(
              fontSize: 14,
              color: palette.textMuted,
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
