import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../application/feed_screen_providers.dart'
    show myFriendsFeedProvider;
import '../../application/friendship_providers.dart'
    show friendshipRepositoryProvider;
import '../../data/friendship_repository.dart' show FriendshipRepository;
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
/// Stream conversion (REQ-FPS-008): `friendshipByPairProvider` and
/// `acceptedFriendsProvider` are now `StreamProvider.family.autoDispose` and
/// self-update on Firestore mutations — manual `ref.invalidate` for those
/// providers is no longer needed and has been removed. The
/// `myFriendsFeedProvider` invalidation is preserved (still a FutureProvider
/// that requires explicit refresh per ADR-FPS-006).
class PublicProfileFollowButton extends ConsumerStatefulWidget {
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
  ConsumerState<PublicProfileFollowButton> createState() =>
      _PublicProfileFollowButtonState();
}

class _PublicProfileFollowButtonState
    extends ConsumerState<PublicProfileFollowButton> {
  /// In-flight guard for the SEGUIR / ACEPTAR writes. Mirrors the `_busy`
  /// pattern on [FriendRequestInboxTile]: while a friendship mutation is
  /// pending the pill is disabled and shows a spinner so the user can't
  /// double-fire and isn't left staring at an unchanged, silent control.
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final repo = ref.watch(friendshipRepositoryProvider);
    final friendship = widget.friendship;

    if (friendship == null) {
      return _FollowPill(
        label: 'SEGUIR',
        style: _FollowPillStyle.mintFilled,
        busy: _busy,
        onTap: _busy ? null : () => _onRequest(repo),
      );
    }
    if (friendship.status == FriendshipStatus.accepted) {
      return _FollowPill(
        label: 'SIGUIENDO',
        style: _FollowPillStyle.outlined,
        leadingIcon: TreinoIcon.check,
        onTap: () => _showUnfriendSheet(friendship),
      );
    }
    if (friendship.requesterId == widget.viewerUid) {
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
      busy: _busy,
      onTap: _busy ? null : () => _onAccept(repo, friendship),
    );
  }

  /// Sends a follow request, surfacing success/failure to the user.
  ///
  /// Previously this was a fire-and-forget `catch (_)` that left the SEGUIR
  /// pill unchanged on failure (the user assumed success). It now reports both
  /// outcomes via the root [ScaffoldMessenger] and gates re-taps with [_busy].
  Future<void> _onRequest(FriendshipRepository repo) async {
    if (_busy) return;
    setState(() => _busy = true);
    // Capture messenger + copy BEFORE the await: the profile route may be
    // popped during the write, after which `context` is unmounted. The root
    // messenger survives disposal, so the SnackBar is always delivered.
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppL10n.of(context);
    final successMessage = l10n.feedRequestSentSuccess;
    final errorMessage = l10n.feedFriendActionError;
    try {
      await repo.request(widget.viewerUid, widget.targetUid);
      // Stream providers (friendshipByPairProvider, acceptedFriendsProvider)
      // self-update via .snapshots() — no manual invalidation needed.
      // SEGUIR only creates a pending request, so myFriendsFeedProvider
      // (accepted friends list) is unaffected — no invalidation required.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (_) {
      // The pill stays as SEGUIR (the stream won't emit on failure); tell the
      // user the request did not go through so they can retry instead of
      // assuming it succeeded.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(errorMessage)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Accepts a received request, surfacing success/failure to the user.
  Future<void> _onAccept(FriendshipRepository repo, Friendship f) async {
    if (_busy) return;
    setState(() => _busy = true);
    // Capture the root container + messenger BEFORE the await: accepting
    // changes the accepted-friends list and the profile route may be popped
    // during the write, after which `ref`/`context` from this widget can
    // silently no-op (ADR-FPS-006). The container and messenger live at the
    // root and survive disposal.
    final container = ProviderScope.containerOf(context, listen: false);
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppL10n.of(context);
    final successMessage = l10n.feedRequestAcceptedSuccess;
    final errorMessage = l10n.feedFriendActionError;
    try {
      await repo.accept(f.id, widget.viewerUid);
      // Stream providers self-update on Firestore mutation — no invalidation
      // needed for friendshipByPairProvider or acceptedFriendsProvider.
      // myFriendsFeedProvider (still a FutureProvider) MUST be invalidated
      // explicitly — Riverpod does NOT auto-cascade to providers with no
      // active listener at the moment (ADR-FPS-006).
      container.invalidate(myFriendsFeedProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (_) {
      // On failure the feed is NOT invalidated and the pill stays as ACEPTAR;
      // surface the error so the user can retry instead of silently swallowing.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(errorMessage)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Opens the unfriend confirmation bottom sheet.
  ///
  /// Resolves the friend's display name from [userPublicProfileProvider] with
  /// a fallback of "Usuario anónimo". On ELIMINAR, calls
  /// [FriendshipRepository.delete]. Stream providers self-update — only
  /// [myFriendsFeedProvider] requires explicit invalidation.
  Future<void> _showUnfriendSheet(Friendship f) async {
    final palette = AppPalette.of(context);
    final profileAsync = ref.read(userPublicProfileProvider(widget.targetUid));
    final friendDisplayName =
        profileAsync.valueOrNull?.displayName ?? 'Usuario anónimo';

    final repo = ref.read(friendshipRepositoryProvider);
    // Capture messenger + copy BEFORE awaiting the sheet: the delete runs from
    // the sheet's onConfirm and the profile route may be gone by then.
    final messenger = ScaffoldMessenger.of(context);
    final errorMessage = AppL10n.of(context).feedFriendActionError;

    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      backgroundColor: palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => UnfriendConfirmationSheet(
        friendDisplayName: friendDisplayName,
        onConfirm: () async {
          try {
            await repo.delete(f.id, widget.viewerUid);
            // Stream providers self-update on Firestore mutation.
            // myFriendsFeedProvider (FutureProvider) MUST be invalidated
            // explicitly — accepted friends list changed, Feed AMIGOS must
            // refresh.
            ref.invalidate(myFriendsFeedProvider);
          } catch (_) {
            // The friendship is still present (the delete did not commit);
            // surface the failure so the user can retry instead of swallowing.
            messenger
              ..hideCurrentSnackBar()
              ..showSnackBar(SnackBar(content: Text(errorMessage)));
          }
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
    this.busy = false,
  });

  final String label;
  final _FollowPillStyle style;
  final VoidCallback? onTap;
  final IconData? leadingIcon;

  /// When true the pill shows an inline spinner in place of the leading icon,
  /// signalling the friendship write is in flight (the caller also nulls
  /// [onTap] to block re-taps).
  final bool busy;

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
            if (busy) ...[
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(textColor),
                ),
              ),
              const SizedBox(width: 8),
            ] else if (leadingIcon != null) ...[
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
