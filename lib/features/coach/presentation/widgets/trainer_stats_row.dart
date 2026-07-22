import 'package:flutter/material.dart';

import '../../../../features/workout/presentation/widgets/stat_tile.dart';
import '../../../../l10n/app_l10n.dart';
import '../../../coach/domain/trainer_public_profile.dart';

/// Three-column stats row for the trainer public profile screen.
///
/// The RESEÑAS slot is wired to [TrainerPublicProfile.averageRating],
/// formatted to 1 decimal place (ADR-RV-011). Null averageRating OR
/// reviewCount == 0 → shows placeholder "—".
///
/// AÑOS EXP shows [TrainerPublicProfile.trainerExperienceYears] (self-attested
/// from the trainer profile form, dual-write) and ALUMNOS shows
/// [TrainerPublicProfile.athleteCount] (active trainer_links count, written by
/// the linkAggregate Cloud Function). Null → "—" placeholder — only for
/// trainers without the data loaded/computed yet (#388).
///
/// REQ-COACH-DISC-UI-015, REQ-RV-DISPLAY-004. Fase 6 Etapa 7.
class TrainerStatsRow extends StatelessWidget {
  const TrainerStatsRow({super.key, required this.profile});

  final TrainerPublicProfile profile;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    // ADR-RV-011: formatted to 1 decimal. Null or 0 reviews → "—" placeholder.
    final ratingValue = profile.reviewCount > 0 && profile.averageRating != null
        ? profile.averageRating!.toStringAsFixed(1)
        : l10n.coachStatsPlaceholder;
    final experienceValue = profile.trainerExperienceYears?.toString() ??
        l10n.coachStatsPlaceholder;
    final studentsValue =
        profile.athleteCount?.toString() ?? l10n.coachStatsPlaceholder;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        StatTile(
          label: l10n.coachStatsReviewsLabel,
          value: ratingValue,
        ),
        StatTile(
          label: l10n.coachStatsExperienceLabel,
          value: experienceValue,
        ),
        StatTile(
          label: l10n.coachStatsStudentsLabel,
          value: studentsValue,
        ),
      ],
    );
  }
}
