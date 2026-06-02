import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../coach/application/trainer_link_providers.dart';
import '../../../coach/domain/trainer_link_status.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../application/review_providers.dart';
import '../../presentation/widgets/review_bottom_sheet.dart';

/// "DEJAR UNA RESEÑA" / "EDITAR MI RESEÑA" CTA shown on the trainer's public
/// profile screen.
///
/// Only rendered when the current athlete has an active link with [trainerId].
/// Branches on whether a review already exists for the link:
///   - null → "DEJAR UNA RESEÑA"
///   - non-null → "EDITAR MI RESEÑA"
///
/// Uses [currentAthleteLinkProvider] to resolve the active link, and
/// [userReviewForLinkProvider] to resolve the existing review.
///
/// REQ-RV-WRITE-006. Fase 6 Etapa 7.
class ReviewCta extends ConsumerWidget {
  const ReviewCta({
    super.key,
    required this.trainerId,
  });

  final String trainerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final linkAsync = ref.watch(currentAthleteLinkProvider);
    final link = linkAsync.valueOrNull;

    // Only show CTA for athletes with an active link to this specific trainer.
    if (link == null ||
        link.status != TrainerLinkStatus.active ||
        link.trainerId != trainerId) {
      return const SizedBox.shrink();
    }

    final reviewKey = '${link.id}:${link.athleteId}';
    final reviewAsync = ref.watch(userReviewForLinkProvider(reviewKey));
    final existingReview = reviewAsync.valueOrNull;

    // Resolve trainer name for the sheet title.
    final trainerPub =
        ref.watch(userPublicProfileProvider(trainerId)).valueOrNull;
    final trainerName = trainerPub?.displayName ??
        'tu Personal Trainer'; // i18n: Fase 6 Etapa 7

    // Determine label based on whether review exists.
    final label = existingReview != null
        ? 'EDITAR MI RESEÑA' // i18n: Fase 6 Etapa 7
        : 'DEJAR UNA RESEÑA'; // i18n: Fase 6 Etapa 7

    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () {
          showModalBottomSheet<void>(
            context: context,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => ReviewBottomSheet(
              linkId: link.id,
              trainerId: trainerId,
              trainerName: trainerName,
              athleteId: link.athleteId,
              existing: existingReview,
              triggerVariant: ReviewTriggerVariant.standard,
            ),
          );
        },
        style: OutlinedButton.styleFrom(
          foregroundColor: palette.accent,
          side: BorderSide(color: palette.accent),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 15,
            letterSpacing: 1.5,
          ),
        ),
      ),
    );
  }
}
