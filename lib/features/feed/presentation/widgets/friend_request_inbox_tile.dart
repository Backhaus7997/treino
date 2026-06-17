import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../application/feed_screen_providers.dart'
    show myFriendsFeedProvider;
import '../../application/friendship_providers.dart'
    show friendshipRepositoryProvider;
import '../../domain/friendship.dart';
import '../../domain/gym_name.dart';
import 'post_avatar.dart';

/// A single row in the friend requests inbox.
///
/// Renders: [PostAvatar] + display name (UPPERCASE Barlow Condensed) +
/// gym name subtitle + RECHAZAR / ACEPTAR action pills.
///
/// Actions are fire-and-forget — the inbox stream re-emission removes the
/// row. `acceptedFriendsProvider` and `friendshipByPairProvider` are now
/// `StreamProvider.family.autoDispose` and self-update on Firestore mutations
/// — no manual `invalidate` needed for them (REQ-FPS-008, ADR-FPS-006).
/// `myFriendsFeedProvider` (still a FutureProvider) MUST be explicitly
/// invalidated after ACEPTAR because Riverpod does not auto-cascade
/// invalidation to providers with no active listener at the moment.
class FriendRequestInboxTile extends ConsumerStatefulWidget {
  const FriendRequestInboxTile({
    super.key,
    required this.friendship,
    required this.viewerUid,
  });

  final Friendship friendship;
  final String viewerUid;

  @override
  ConsumerState<FriendRequestInboxTile> createState() =>
      _FriendRequestInboxTileState();
}

class _FriendRequestInboxTileState
    extends ConsumerState<FriendRequestInboxTile> {
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final profileAsync =
        ref.watch(userPublicProfileProvider(widget.friendship.requesterId));

    final profile = profileAsync.valueOrNull;
    final displayName = profile?.displayName ?? 'Usuario anónimo';
    final avatarUrl = profile?.avatarUrl;
    final gymName = gymNameFromId(profile?.gymId);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.textMuted.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          // Tappable requester zone: avatar + name + gym (ADR-FRI-012).
          // InkWell is kept inside an Expanded so it fills the available
          // space and provides a large hit target while the action pills
          // remain as independent tap regions to its right.
          Expanded(
            child: InkWell(
              onTap: () => context
                  .push('/feed/profile/${widget.friendship.requesterId}'),
              borderRadius: BorderRadius.circular(8),
              child: Row(
                children: [
                  PostAvatar(
                    authorDisplayName: displayName,
                    authorAvatarUrl: avatarUrl,
                    size: 40,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          displayName.toUpperCase(),
                          style: GoogleFonts.barlowCondensed(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                            color: palette.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (gymName.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(
                            gymName,
                            style: GoogleFonts.barlow(
                              fontSize: 12,
                              color: palette.textMuted,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _InboxActionPill(
                label: 'RECHAZAR',
                semanticsLabel: l10n.dashboardRechazarLabel,
                variant: _PillVariant.outlinedMuted,
                palette: palette,
                onTap: _busy ? null : _onRechazar,
              ),
              const SizedBox(width: 8),
              _InboxActionPill(
                label: 'ACEPTAR',
                semanticsLabel: l10n.dashboardAceptarLabel,
                variant: _PillVariant.mintFilled,
                palette: palette,
                onTap: _busy ? null : _onAceptar,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onAceptar() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Capture the ProviderContainer + repo BEFORE the await. After the
    // accept commits, `pendingRequestsStreamProvider` re-emits without this
    // row and the ListView disposes the tile — `ref` from a disposed
    // ConsumerStatefulWidget can silently no-op on `invalidate`, leaving
    // sibling consumers (Feed AMIGOS) stale. The container lives at the
    // root and survives the tile's disposal, so its invalidate always runs.
    // ADR-FPS-006: This dispose-safe capture pattern MUST be kept for the
    // surviving `myFriendsFeedProvider` invalidation.
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = container.read(friendshipRepositoryProvider);
    final viewerUid = widget.viewerUid;
    // Capture the messenger BEFORE the await for the same reason as the
    // container: a successful accept removes this row and disposes the tile,
    // so `context` may be unmounted by the time we want to report a failure.
    // The messenger is rooted above the list and survives the disposal, so
    // the error SnackBar is always shown (visibility of system status).
    final messenger = ScaffoldMessenger.of(context);
    final errorMessage = AppL10n.of(context).feedFriendActionError;
    try {
      await repo.accept(widget.friendship.id, viewerUid);
      // Stream providers (`acceptedFriendsProvider`, `friendshipByPairProvider`)
      // self-update via .snapshots() — no manual invalidation needed.
      // `myFriendsFeedProvider` (still a FutureProvider) MUST be invalidated
      // explicitly — Riverpod does NOT auto-cascade invalidation to downstream
      // providers with no active listener at the moment (ADR-FPS-006).
      container.invalidate(myFriendsFeedProvider);
    } catch (_) {
      // The stream will not emit a removal, so the row stays — tell the user
      // the action failed so they can retry instead of silently swallowing it.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(errorMessage)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onRechazar() async {
    if (_busy) return;
    setState(() => _busy = true);
    // Same dispose-safe container capture as `_onAceptar` — not needed for
    // invalidation here (rejection never affects AMIGOS feed), but kept
    // for consistency and in case future calls need it.
    final container = ProviderScope.containerOf(context, listen: false);
    final repo = container.read(friendshipRepositoryProvider);
    // Dispose-safe capture (see `_onAceptar`): a successful reject removes the
    // row and disposes the tile, so the messenger must be resolved before the
    // await to guarantee the failure SnackBar survives the tile's disposal.
    final messenger = ScaffoldMessenger.of(context);
    final errorMessage = AppL10n.of(context).feedFriendActionError;
    try {
      await repo.delete(widget.friendship.id, widget.viewerUid);
      // Stream providers self-update on Firestore mutation — no manual
      // invalidation required. Rejection never created a friendship, so
      // myFriendsFeedProvider is unaffected.
    } catch (_) {
      // The stream will not emit a removal, so the row stays — surface the
      // failure instead of swallowing it so the user can retry.
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(errorMessage)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Pill widget
// ---------------------------------------------------------------------------

enum _PillVariant { mintFilled, outlinedMuted }

class _InboxActionPill extends StatelessWidget {
  const _InboxActionPill({
    required this.label,
    required this.semanticsLabel,
    required this.variant,
    required this.palette,
    required this.onTap,
  });

  final String label;

  /// Localized action name announced to TalkBack/VoiceOver. The visible
  /// [label] stays a styled literal, so the semantics node carries the
  /// l10n string and the [Text] is wrapped in [ExcludeSemantics].
  final String semanticsLabel;
  final _PillVariant variant;
  final AppPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isFilled = variant == _PillVariant.mintFilled;
    final bg = isFilled ? palette.accent : Colors.transparent;
    final borderColor = isFilled ? palette.accent : palette.border;
    final textColor = isFilled ? palette.bg : palette.textMuted;

    // a11y: expose the pill as a button with its localized action label and
    // enabled/disabled state (onTap is null while a request is in flight), so
    // TalkBack/VoiceOver announce it as an actionable, stateful control
    // instead of static text — matching the sibling pill pattern.
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: semanticsLabel,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        // Guarantee a >=44pt tap target (iOS HIG minimum) without enlarging
        // the visual pill — the opaque hit test covers the full constrained
        // box while the decorated Container keeps its size.
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
          child: Center(
            widthFactor: 1,
            heightFactor: 1,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: borderColor),
              ),
              // Decorative once the Semantics node carries the action label.
              child: ExcludeSemantics(
                child: Text(
                  label,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.0,
                    color: textColor,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
