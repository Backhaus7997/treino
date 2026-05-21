import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../app/theme/app_palette.dart';
import '../../core/widgets/treino_icon.dart';
import '../check_in/application/check_in_providers.dart';
import '../check_in/presentation/check_in_dialog.dart';
import 'domain/gym_name.dart';
import '../profile/application/user_providers.dart';
import '../workout/application/session_providers.dart' show currentUidProvider;
import 'application/feed_screen_providers.dart';
import 'application/post_providers.dart';
import 'domain/feed_segment.dart';
import 'presentation/widgets/feed_empty_state.dart';
import 'presentation/widgets/feed_segment_pills.dart';
import 'presentation/widgets/post_card.dart';

/// Session-scoped flag — once the dialog fires during this process lifetime,
/// it should not reappear even on tab switches (ADR-WRS-16).
///
/// Defined at top level (process-lifetime provider) so it persists across
/// multiple `FeedScreen` instances in the same session.
final _checkInDialogShownThisSessionProvider =
    StateProvider<bool>((_) => false);

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  @override
  void initState() {
    super.initState();
    // Defer to after first frame so we have a valid BuildContext for showDialog.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowCheckIn());
  }

  Future<void> _maybeShowCheckIn() async {
    if (!mounted) return;

    // Session guard: do not show more than once per process lifetime.
    if (ref.read(_checkInDialogShownThisSessionProvider)) return;

    // Auth guard: no uid → skip (unauthenticated users do not get the dialog).
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;

    // Fetch today's check-in; provider is already auth-gated.
    final today = await ref.read(todayCheckInProvider.future);

    if (!mounted) return;

    // Check-in guard: already checked in today → do not show.
    if (today != null) return;

    // Mark shown BEFORE awaiting showDialog to prevent race on rapid remounts.
    ref.read(_checkInDialogShownThisSessionProvider.notifier).state = true;

    // Resolve gym info from the user's profile for the dialog copy.
    final profile = ref.read(userProfileProvider).valueOrNull;
    final gymId = profile?.gymId;
    final gymName = gymId != null ? gymNameFromId(gymId) : null;

    await showDialog<void>(
      context: context,
      builder: (_) => CheckInDialog(
        gymId: gymId,
        gymName: gymName?.isNotEmpty == true ? gymName : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          GestureDetector(
            onTap: () => context.push('/feed/search'),
            behavior: HitTestBehavior.opaque,
            child: Icon(TreinoIcon.search, size: 20, color: palette.textMuted),
          ),
          const SizedBox(width: 18),
          GestureDetector(
            onTap: () => context.push('/feed/create'),
            behavior: HitTestBehavior.opaque,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: palette.accent,
                shape: BoxShape.circle,
              ),
              child: Icon(TreinoIcon.plus, size: 20, color: palette.bg),
            ),
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
          physics: const ClampingScrollPhysics(),
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
          physics: const ClampingScrollPhysics(),
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
          physics: const ClampingScrollPhysics(),
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
