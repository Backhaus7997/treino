import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/kg_format.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../auth/application/auth_providers.dart';
import '../../application/post_actions_notifier.dart';
import '../../domain/post.dart';
import '../../domain/routine_tag.dart';
import 'post_avatar.dart';

class PostCard extends ConsumerWidget {
  const PostCard({
    super.key,
    required this.post,
    this.onAuthorTap,
  });

  final Post post;
  final VoidCallback? onAuthorTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final viewerUid = ref.watch(authStateChangesProvider).valueOrNull?.uid;
    final isOwner = viewerUid != null && viewerUid == post.authorUid;

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: palette.accent.withValues(alpha: 0.25),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: palette.accent.withValues(alpha: 0.10),
            blurRadius: 10,
            spreadRadius: 0,
            offset: Offset.zero,
          ),
        ],
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
              // Overflow menu — Editar/Eliminar, own posts only
              // (REQ-FEED-POSTCARD-006).
              if (isOwner)
                Semantics(
                  button: true,
                  label: AppL10n.of(context).postCardMenuA11y,
                  child: IconButton(
                    icon: Icon(
                      TreinoIcon.dotsThree,
                      color: palette.textMuted,
                      size: 20,
                    ),
                    onPressed: () => _showPostMenu(context, ref),
                    tooltip: null,
                    constraints: const BoxConstraints(),
                    padding: EdgeInsets.zero,
                  ),
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

          // QA-FEED-364/389: real workout stats when the post came from sharing
          // a workout; otherwise the row is hidden entirely (manual + legacy
          // posts) instead of the old permanent "— kg / — min / — ej." stub.
          if (post.workoutStats != null) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Text(
                  '${formatVolumeKg(post.workoutStats!.volumeKg)} kg',
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(width: 18),
                Text(
                  '${post.workoutStats!.durationMin} min',
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
                const SizedBox(width: 18),
                Text(
                  '${post.workoutStats!.exerciseCount} ej.',
                  style: GoogleFonts.barlow(
                    fontWeight: FontWeight.w400,
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Overflow menu (owner only) ────────────────────────────────────────

  void _showPostMenu(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(TreinoIcon.edit, color: palette.textPrimary),
              title: Text(
                l10n.postCardMenuEdit,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                  color: palette.textPrimary,
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                context.push('/feed/create', extra: post);
              },
            ),
            ListTile(
              leading: Icon(TreinoIcon.trash, color: palette.danger),
              title: Text(
                l10n.postCardMenuDelete,
                style: GoogleFonts.barlow(
                  fontWeight: FontWeight.w400,
                  fontSize: 14,
                  color: palette.danger,
                ),
              ),
              onTap: () {
                Navigator.of(sheetContext).pop();
                _confirmDelete(context, ref);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final l10n = AppL10n.of(context);
    final messenger = ScaffoldMessenger.of(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.postCardDeleteConfirmTitle),
        content: Text(l10n.postCardDeleteConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.commonCancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.postCardMenuDelete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    try {
      await ref.read(postActionsProvider).deletePost(post.id);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.postCardDeleteSuccess)));
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(l10n.postCardDeleteError)));
    }
  }
}

// ── Private helpers ────────────────────────────────────────────────────────

String _relativeTime(DateTime createdAt) {
  final delta = DateTime.now().difference(createdAt);
  if (delta.inMinutes < 1) return 'recién';
  if (delta.inHours < 1) return 'hace ${delta.inMinutes}m';
  if (delta.inDays < 1) return 'hace ${delta.inHours}h';
  if (delta.inDays < 7) return 'hace ${delta.inDays}d';
  // createdAt viaja en UTC (Post.createdAt -> toUtc()); la fecha absoluta se
  // formatea en la zona del usuario para que las zonas de offset negativo
  // (Argentina, UTC-3) no muestren el día siguiente en los posts nocturnos.
  // Mismo criterio que el gemelo de chat_list_screen.
  final local = createdAt.toLocal();
  final d = local.day.toString().padLeft(2, '0');
  final m = local.month.toString().padLeft(2, '0');
  return '$d/$m';
}

String _formatMeta(String? gymId, DateTime createdAt) {
  final gym = (gymId == null || gymId.isEmpty) ? null : gymId.toUpperCase();
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
