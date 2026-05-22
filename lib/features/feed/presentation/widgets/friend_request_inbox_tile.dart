import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../application/friendship_providers.dart';
import '../../domain/friendship.dart';
import '../../domain/gym_name.dart';
import 'post_avatar.dart';

/// A single row in the friend requests inbox.
///
/// Renders: [PostAvatar] + display name (UPPERCASE Barlow Condensed) +
/// gym name subtitle + RECHAZAR / ACEPTAR action pills.
///
/// Actions are fire-and-forget — the stream re-emission removes the row.
/// No `ref.invalidate`, no optimistic UI (ADR-FRI-009).
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
                variant: _PillVariant.outlinedMuted,
                palette: palette,
                onTap: _busy ? null : _onRechazar,
              ),
              const SizedBox(width: 8),
              _InboxActionPill(
                label: 'ACEPTAR',
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
    try {
      await ref
          .read(friendshipRepositoryProvider)
          .accept(widget.friendship.id, widget.viewerUid);
    } catch (_) {
      // Swallow — stream will not emit a removal, so row stays.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _onRechazar() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await ref
          .read(friendshipRepositoryProvider)
          .delete(widget.friendship.id, widget.viewerUid);
    } catch (_) {
      // Swallow — stream will not emit a removal, so row stays.
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
    required this.variant,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final _PillVariant variant;
  final AppPalette palette;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final isFilled = variant == _PillVariant.mintFilled;
    final bg = isFilled ? palette.accent : Colors.transparent;
    final borderColor = isFilled ? palette.accent : palette.border;
    final textColor = isFilled ? palette.bg : palette.textMuted;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor),
        ),
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
    );
  }
}
