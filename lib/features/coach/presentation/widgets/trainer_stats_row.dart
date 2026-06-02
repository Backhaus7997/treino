import 'package:flutter/material.dart';

import '../../../../features/workout/presentation/widgets/stat_tile.dart';
import '../../../coach/domain/trainer_public_profile.dart';
import '../coach_strings.dart';

/// Three-column stats row for the trainer public profile screen.
///
/// The RESEÑAS slot is wired to [TrainerPublicProfile.averageRating],
/// formatted to 1 decimal place (ADR-RV-011). Null averageRating OR
/// reviewCount == 0 → shows placeholder "—".
///
/// Experience and Students slots remain deferred (placeholder "—").
///
/// REQ-COACH-DISC-UI-015, REQ-RV-DISPLAY-004. Fase 6 Etapa 7.
class TrainerStatsRow extends StatelessWidget {
  const TrainerStatsRow({super.key, required this.profile});

  final TrainerPublicProfile profile;

  @override
  Widget build(BuildContext context) {
    // ADR-RV-011: formatted to 1 decimal. Null or 0 reviews → "—" placeholder.
    final ratingValue = profile.reviewCount > 0 && profile.averageRating != null
        ? profile.averageRating!.toStringAsFixed(1)
        : CoachStrings.statsPlaceholder;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        StatTile(
          label: CoachStrings.statsReviewsLabel,
          value: ratingValue,
        ),
        const StatTile(
          label: CoachStrings.statsExperienceLabel,
          value: CoachStrings.statsPlaceholder,
        ),
        const StatTile(
          label: CoachStrings.statsStudentsLabel,
          value: CoachStrings.statsPlaceholder,
        ),
      ],
    );
  }
}
