import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../domain/post.dart';
import '../../domain/routine_tag.dart';
import 'post_avatar.dart';

class PostCard extends StatelessWidget {
  const PostCard({
    super.key,
    required this.post,
    this.onAuthorTap,
  });

  final Post post;
  final VoidCallback? onAuthorTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: palette.border, width: 1),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── HEADER ROW ──────────────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: onAuthorTap,
                  behavior: HitTestBehavior.opaque,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PostAvatar(
                        authorDisplayName: post.authorDisplayName,
                        authorAvatarUrl: post.authorAvatarUrl,
                        size: 40,
                      ),
                      const SizedBox(width: 12),
                      Flexible(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              post.authorDisplayName,
                              style: GoogleFonts.barlowCondensed(
                                fontWeight: FontWeight.w600,
                                fontSize: 14,
                                letterSpacing: 0.5,
                                color: palette.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                            const SizedBox(height: 8),
                            Text(
                              _formatMeta(post.authorGymId, post.createdAt),
                              style: GoogleFonts.barlow(
                                fontWeight: FontWeight.w400,
                                fontSize: 12,
                                color: palette.textMuted,
                              ),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              // Overflow icon stub — REQ-FEED-POSTCARD-006
              IconButton(
                icon: Icon(
                  TreinoIcon.dotsThree,
                  color: palette.textMuted,
                  size: 20,
                ),
                onPressed: null,
                tooltip: null,
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
              ),
            ],
          ),

          const SizedBox(height: 12),

          // ── BODY TEXT ───────────────────────────────────────────────
          Text(
            post.text,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 14,
              color: palette.textPrimary,
            ),
          ),

          if (post.routineTag != null) ...[
            const SizedBox(height: 12),
            _RoutineTagChip(tag: post.routineTag!),
          ],

          const SizedBox(height: 12),

          // ── STATS STUB ROW ──────────────────────────────────────────
          Row(
            children: [
              Text(
                '— kg',
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(width: 18),
              Text(
                '— min',
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  color: palette.textMuted,
                ),
              ),
              const SizedBox(width: 18),
              Text(
                '— ej.',
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 12,
                  color: palette.textMuted,
                ),
              ),
              // Stub: real stats wired in Fase 4.
            ],
          ),
        ],
      ),
    );
  }
}

// ── Private helpers ────────────────────────────────────────────────────────

String _relativeTime(DateTime createdAt) {
  final delta = DateTime.now().difference(createdAt);
  if (delta.inMinutes < 1) return 'recién';
  if (delta.inHours < 1) return 'hace ${delta.inMinutes}m';
  if (delta.inDays < 1) return 'hace ${delta.inHours}h';
  if (delta.inDays < 7) return 'hace ${delta.inDays}d';
  final d = createdAt.day.toString().padLeft(2, '0');
  final m = createdAt.month.toString().padLeft(2, '0');
  return '$d/$m';
}

String _formatMeta(String? gymId, DateTime createdAt) {
  final gym =
      (gymId == null || gymId.isEmpty) ? null : gymId.toUpperCase();
  final time = _relativeTime(createdAt);
  return gym == null ? time : '$gym · $time';
}

// ── Private widgets ────────────────────────────────────────────────────────

class _RoutineTagChip extends StatelessWidget {
  const _RoutineTagChip({required this.tag});

  final RoutineTag tag;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return GestureDetector(
      onTap: () => context.push('/workout/routine/${tag.routineId}'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: palette.accent.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: palette.accent.withValues(alpha: 0.35),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(TreinoIcon.tabWorkout, color: palette.accent, size: 14),
            const SizedBox(width: 8),
            Text(
              tag.routineName,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w600,
                fontSize: 12,
                letterSpacing: 0.8,
                color: palette.accent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
