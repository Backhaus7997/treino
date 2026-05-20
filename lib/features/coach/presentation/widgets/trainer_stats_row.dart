import 'package:flutter/material.dart';

import '../../../../features/workout/presentation/widgets/stat_tile.dart';
import '../coach_strings.dart';

/// Three-column stats row for the trainer public profile screen.
///
/// All values are deferred to Etapa 3 (per design D14 — rating/exp/students
/// not part of this PR). Displays placeholder "—" for all three stats.
///
/// Reuses [StatTile] from the workout feature (compatible: takes label + value?).
///
/// REQ-COACH-DISC-UI-015.
class TrainerStatsRow extends StatelessWidget {
  const TrainerStatsRow({super.key});

  @override
  Widget build(BuildContext context) {
    return const Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        StatTile(
          label: CoachStrings.statsReviewsLabel,
          value: CoachStrings.statsPlaceholder,
        ),
        StatTile(
          label: CoachStrings.statsExperienceLabel,
          value: CoachStrings.statsPlaceholder,
        ),
        StatTile(
          label: CoachStrings.statsStudentsLabel,
          value: CoachStrings.statsPlaceholder,
        ),
      ],
    );
  }
}
