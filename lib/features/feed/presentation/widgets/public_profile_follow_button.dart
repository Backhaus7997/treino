import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../application/friendship_providers.dart'
    show acceptedFriendsProvider, friendshipRepositoryProvider;
import '../../application/public_profile_providers.dart'
    show friendshipByPairProvider;
import '../../domain/friendship.dart';
import '../../domain/friendship_status.dart';
import 'unfriend_confirmation_sheet.dart';

/// 4-state SEGUIR pill for the public profile screen.
///
/// State resolution (per design §7):
/// - `friendship == null`                                → SEGUIR (mint active)
/// - status accepted                                     → SIGUIENDO (outlined + check, no-op)
/// - status pending && requesterId == viewerUid          → SOLICITUD ENVIADA (muted, opacity 0.6, no-op)
/// - status pending && requesterId == targetUid          → ACEPTAR (mint active)
///
/// Tapping SEGUIR or ACEPTAR fires the repo mutation and then invalidates
/// [friendshipByPairProvider] to refetch the state.
class PublicProfileFollowButton extends ConsumerWidget {
  const PublicProfileFollowButton({
    super.key,
    required this.friendship,
    required this.viewerUid,
    required this.targetUid,
  });

  final Friendship? friendship;
  final String viewerUid;
  final String targetUid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repo = ref.watch(friendshipRepositoryProvider);

    Future<void> invalidatePair() async => ref.invalidate(
          friendshipByPairProvider(
            (viewerUid: viewerUid, targetUid: targetUid),
          ),
        );

    if (friendship == null) {
      return _FollowPill(
        label: 'SEGUIR',
        style: _FollowPillStyle.mintFilled,
        onTap: () async {
          await repo.request(viewerUid, targetUid);
          // Pending request — only the pair view changes; the accepted
          // friends list is unaffected.
          await invalidatePair();
        },
      );
    }
    final f = friendship!;
    if (f.status == FriendshipStatus.accepted) {
      return _FollowPill(
        label: 'SIGUIENDO',
        style: _FollowPillStyle.outlined,
        leadingIcon: TreinoIcon.check,
        onTap: () => _showUnfriendSheet(context, ref, f),
      );
    }
    if (f.requesterId == viewerUid) {
      return const _FollowPill(
        label: 'SOLICITUD ENVIADA',
        style: _FollowPillStyle.outlinedMuted,
        onTap: null,
      );
    }
    // pending && requesterId == targetUid → received → ACEPTAR
    return _FollowPill(
      label: 'ACEPTAR',
      style: _FollowPillStyle.mintFilled,
      onTap: () async {
        await repo.accept(f.id, viewerUid);
        // Per ADR-FRI-013: refresh both the pair (button transitions to
        // SIGUIENDO) AND the AMIGOS feed source (the new friend's posts
        // start appearing without an app restart).
        await invalidatePair();
        ref.invalidate(acceptedFriendsProvider(viewerUid));
      },
    );
  }

  /// Opens the unfriend confirmation bottom sheet.
  ///
  /// Resolves the friend's display name from [userPublicProfileProvider] with
  /// a fallback of "Usuario anónimo". On ELIMINAR, calls
  /// [FriendshipRepository.delete] and invalidates [friendshipByPairProvider]
  /// so the pill transitions back to SEGUIR.
  Future<void> _showUnfriendSheet(
    BuildContext context,
    WidgetRef ref,
    Friendship f,
  ) async {
    final palette = AppPalette.of(context);
    final profileAsync = ref.read(userPublicProfileProvider(targetUid));
    final friendDisplayName =
        profileAsync.valueOrNull?.displayName ?? 'Usuario anónimo';

    final repo = ref.read(friendshipRepositoryProvider);

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => UnfriendConfirmationSheet(
        friendDisplayName: friendDisplayName,
        onConfirm: () async {
          try {
            await repo.delete(f.id, viewerUid);
          } catch (_) {
            // Swallow — same fire-and-forget pattern as inbox pills (ADR-FRI-009).
          }
          // Per ADR-FRI-013: refresh both the pair (so the button transitions
          // back to SEGUIR) AND the AMIGOS feed source (so the ex-friend's
          // posts are pruned from the viewer's feed without an app restart).
          ref.invalidate(
            friendshipByPairProvider(
              (viewerUid: viewerUid, targetUid: targetUid),
            ),
          );
          ref.invalidate(acceptedFriendsProvider(viewerUid));
        },
      ),
    );
  }
}

enum _FollowPillStyle { mintFilled, outlined, outlinedMuted }

class _FollowPill extends StatelessWidget {
  const _FollowPill({
    required this.label,
    required this.style,
    required this.onTap,
    this.leadingIcon,
  });

  final String label;
  final _FollowPillStyle style;
  final VoidCallback? onTap;
  final IconData? leadingIcon;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    final Color bg;
    final Color textColor;
    final Color borderColor;
    switch (style) {
      case _FollowPillStyle.mintFilled:
        bg = palette.accent;
        textColor = palette.bg;
        borderColor = palette.accent;
        break;
      case _FollowPillStyle.outlined:
        bg = Colors.transparent;
        textColor = palette.textPrimary;
        borderColor = palette.border;
        break;
      case _FollowPillStyle.outlinedMuted:
        bg = Colors.transparent;
        textColor = palette.textMuted;
        borderColor = palette.border;
        break;
    }

    final pill = GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: borderColor, width: 1),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (leadingIcon != null) ...[
              Icon(leadingIcon, size: 14, color: textColor),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 13,
                letterSpacing: 1.0,
                color: textColor,
              ),
            ),
          ],
        ),
      ),
    );

    if (style == _FollowPillStyle.outlinedMuted) {
      return Opacity(opacity: 0.6, child: pill);
    }
    return pill;
  }
}
