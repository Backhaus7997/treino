import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
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
            return Column(
              children:
                  reviews.map((review) => ReviewTile(review: review)).toList(),
            );
          },
        ),
      ],
    );
  }
}
