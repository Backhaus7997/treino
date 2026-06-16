import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../feed/presentation/widgets/post_avatar.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../../profile/domain/user_public_profile.dart';
import '../../domain/review.dart';
import 'star_rating_display.dart';

/// A tile displaying a single trainer review.
///
/// Renders athlete avatar, name, star rating, optional comment, and a
/// relative date. Falls back to "Usuario eliminado" with neutral avatar
/// when the author profile is null (deleted account).
///
/// The author profile is resolved once for the whole section and passed in via
/// [resolvedProfile] (see [TrainerReviewsSection]) so the section opens a single
/// batched read instead of one live listener per tile. When [profileResolved]
/// is false (e.g. standalone usage, or while the batch is still loading) the
/// tile falls back to watching [userPublicProfileProvider] for its single
/// author.
///
/// REQ-RV-DISPLAY-003, ADR-RV-009. Fase 6 Etapa 7.
class ReviewTile extends ConsumerWidget {
  const ReviewTile({
    super.key,
    required this.review,
    this.resolvedProfile,
    this.profileResolved = false,
  });

  final Review review;

  /// Author profile resolved by the parent section's batch lookup. Only
  /// meaningful when [profileResolved] is true; a null value then means a
  /// genuinely missing (deleted) account rather than "not loaded yet".
  final UserPublicProfile? resolvedProfile;

  /// Whether [resolvedProfile] reflects a completed batch lookup. When false the
  /// tile resolves its own author via [userPublicProfileProvider].
  final bool profileResolved;

  /// Returns a human-readable relative date string.
  /// Format: "hace X días" / "hace X meses" / "DD/MM/YYYY" (>1 year).
  static String _formatRelativeDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);
    final days = diff.inDays;
    if (days < 1) {
      // i18n: Fase 6 Etapa 7
      return 'hoy';
    } else if (days < 30) {
      // i18n: Fase 6 Etapa 7
      return 'hace $days ${days == 1 ? 'día' : 'días'}';
    } else if (days < 365) {
      final months = (days / 30).floor();
      // i18n: Fase 6 Etapa 7
      return 'hace $months ${months == 1 ? 'mes' : 'meses'}';
    } else {
      // DD/MM/YYYY for > 1 year
      return '${date.day.toString().padLeft(2, '0')}/'
          '${date.month.toString().padLeft(2, '0')}/'
          '${date.year}';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // When the section already resolved the author via its batch lookup, render
    // directly — no per-tile listener, even if the resolved profile is null
    // (deleted account). Otherwise fall back to the single-author stream so the
    // tile still works standalone and during the batch's brief load window.
    if (profileResolved) {
      return _content(context, resolvedProfile);
    }

    final profileAsync = ref.watch(userPublicProfileProvider(review.athleteId));
    return profileAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (profile) => _content(context, profile),
    );
  }

  Widget _content(BuildContext context, UserPublicProfile? profile) {
    final palette = AppPalette.of(context);

    // ADR-RV-009: the deleted-account signal is a null profile, NOT a null
    // displayName. A live profile with an avatar but no name still shows its
    // avatar; only a missing profile falls back to "Usuario eliminado".
    // i18n: Fase 6 Etapa 7
    final name = profile?.displayName ?? 'Usuario eliminado';
    final avatarUrl = profile?.avatarUrl;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              PostAvatar(
                authorDisplayName: name,
                authorAvatarUrl: avatarUrl,
                size: 36,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: GoogleFonts.barlowCondensed(
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                        color: palette.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    StarRatingDisplay(rating: review.rating.toDouble()),
                  ],
                ),
              ),
              Text(
                _formatRelativeDate(review.createdAt),
                style: GoogleFonts.barlow(
                  fontSize: 11,
                  color: palette.textMuted,
                ),
              ),
            ],
          ),
          if (review.comment != null && review.comment!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.comment!,
              style: GoogleFonts.barlow(
                fontSize: 13,
                color: palette.textPrimary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
