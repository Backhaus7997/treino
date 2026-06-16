import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../application/review_providers.dart';
import 'review_tile.dart';

/// Displays a trainer's review section on their public profile.
///
/// Shows a "RESEÑAS" header followed by either an empty-state message
/// or up to 10 [ReviewTile] widgets (capped by [trainerReviewsProvider]).
///
/// REQ-RV-DISPLAY-002, ADR-RV-010, ADR-RV-013. Fase 6 Etapa 7.
class TrainerReviewsSection extends ConsumerWidget {
  const TrainerReviewsSection({super.key, required this.trainerId});

  final String trainerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final reviewsAsync = ref.watch(trainerReviewsProvider(trainerId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          // i18n: Fase 6 Etapa 7
          'RESEÑAS',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 1.5,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 12),
        reviewsAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (reviews) {
            if (reviews.isEmpty) {
              return Text(
                // i18n: Fase 6 Etapa 7
                'Sin reseñas todavía',
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  color: palette.textMuted,
                ),
              );
            }
            // Resolve all review authors in a single batched read instead of
            // one live listener per tile (avoids the per-tile N+1 listen
            // pattern). Sort + dedupe so equal author sets share one provider
            // instance. While the batch is loading, render tiles with no
            // resolved profile (each falls back to its own author stream),
            // preserving the previous behaviour during the brief load window.
            final athleteIds = (reviews.map((r) => r.athleteId).toSet().toList()
                  ..sort())
                .join(',');
            final profilesAsync =
                ref.watch(userPublicProfilesBatchProvider(athleteIds));
            final profiles = profilesAsync.valueOrNull;
            final resolved = profiles != null;

            return Column(
              children: reviews
                  .map(
                    (review) => ReviewTile(
                      review: review,
                      resolvedProfile: profiles?[review.athleteId],
                      profileResolved: resolved,
                    ),
                  )
                  .toList(),
            );
          },
        ),
      ],
    );
  }
}
