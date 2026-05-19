import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../domain/gym_name.dart';
import '../../../profile/domain/user_public_profile.dart';
import 'post_avatar.dart';

/// A single row in the search results list.
///
/// Renders: [PostAvatar] + display name (UPPERCASE Barlow Condensed) +
/// gym name subtitle. Does NOT include a follow/unfollow button
/// (REQ-UPS-010, ADR-UPP-10).
///
/// Navigation is the caller's responsibility via [onTap] — this widget
/// does NOT import go_router so it stays independently testable.
///
/// Uses [UserPublicProfile] — never [UserProfile] (privacy boundary).
class UserSearchResultTile extends StatelessWidget {
  const UserSearchResultTile({
    super.key,
    required this.profile,
    required this.onTap,
  });

  final UserPublicProfile profile;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final gymName = gymNameFromId(profile.gymId);
    final displayName = profile.displayName ?? 'Anónimo';

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.textMuted.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            PostAvatar(
              authorDisplayName: displayName,
              authorAvatarUrl: profile.avatarUrl,
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
            const SizedBox(width: 8),
            Icon(TreinoIcon.chevronRight, size: 16, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}
