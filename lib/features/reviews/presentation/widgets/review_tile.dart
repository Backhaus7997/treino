import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../feed/presentation/widgets/post_avatar.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../domain/review.dart';
import 'star_rating_display.dart';

/// A tile displaying a single trainer review.
///
/// Renders athlete avatar, name, star rating, optional comment, and a
/// relative date. Falls back to "Usuario eliminado" with neutral avatar
/// when [userPublicProfileProvider] emits null (deleted account).
///
/// REQ-RV-DISPLAY-003, ADR-RV-009. Fase 6 Etapa 7.
class ReviewTile extends ConsumerWidget {
  const ReviewTile({super.key, required this.review});

  final Review review;

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
    final palette = AppPalette.of(context);
    final profileAsync = ref.watch(userPublicProfileProvider(review.athleteId));

    return profileAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (profile) {
        // ADR-RV-009: null profile → deleted account fallback.
        // i18n: Fase 6 Etapa 7
        final name = profile?.displayName ?? 'Usuario eliminado';
        final avatarUrl = profile?.displayName != null ? profile?.avatarUrl : null;

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
      },
    );
  }
}
