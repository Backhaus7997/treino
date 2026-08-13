import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../application/post_providers.dart';
import 'widgets/post_card.dart';

/// Live detail view for a single feed post.
///
/// Firestore rules remain the source of truth for privacy. A missing document
/// and a rejected read intentionally share the same user-facing unavailable
/// state so implementation details are never leaked.
class PostDetailScreen extends ConsumerWidget {
  const PostDetailScreen({
    super.key,
    required this.postId,
  });

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncPost = ref.watch(postByIdProvider(postId));
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const _PostDetailHeader(),
        Expanded(
          child: TreinoStateSwitcher(
            childKey: ValueKey(
              asyncPost.when(
                data: (post) => post == null ? 'unavailable' : 'data',
                loading: () => 'loading',
                error: (_, __) => 'unavailable-error',
              ),
            ),
            child: asyncPost.when(
              loading: () => Center(
                key: const ValueKey('post-detail-loading'),
                child: CircularProgressIndicator(color: palette.accent),
              ),
              data: (post) => post == null
                  ? const _PostUnavailableState()
                  : SingleChildScrollView(
                      key: const ValueKey('post-detail-content'),
                      padding: EdgeInsets.fromLTRB(
                        20,
                        0,
                        20,
                        MediaQuery.paddingOf(context).bottom + 20,
                      ),
                      child: PostCard(
                        key: ValueKey(post.id),
                        post: post,
                        onAuthorTap: () =>
                            context.push('/feed/profile/${post.authorUid}'),
                      ),
                    ),
              error: (_, __) => _PostUnavailableState(
                onRetry: () => ref.invalidate(postByIdProvider(postId)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _PostDetailHeader extends StatelessWidget {
  const _PostDetailHeader();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      child: Row(
        children: [
          Semantics(
            container: true,
            button: true,
            label: l10n.commonBack,
            child: TreinoTappable(
              onTap: () => context.pop(),
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(
                  child: Icon(
                    TreinoIcon.back,
                    size: 20,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 14),
          Text(
            l10n.postDetailTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 20,
              letterSpacing: 1.2,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _PostUnavailableState extends StatelessWidget {
  const _PostUnavailableState({this.onRetry});

  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    return Center(
      key: const ValueKey('post-detail-unavailable'),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.postDetailUnavailable,
              style: GoogleFonts.barlow(
                fontSize: 14,
                color: palette.textMuted,
              ),
              textAlign: TextAlign.center,
            ),
            if (onRetry != null) ...[
              const SizedBox(height: 20),
              Semantics(
                container: true,
                button: true,
                label: l10n.coachRetryLabel,
                child: TextButton(
                  onPressed: onRetry,
                  style: TextButton.styleFrom(foregroundColor: palette.accent),
                  child: Text(l10n.coachRetryLabel),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
