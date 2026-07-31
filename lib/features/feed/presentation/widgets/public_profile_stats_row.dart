import 'package:flutter/material.dart';

import '../../../../core/utils/k_formatter.dart';
import '../../../workout/presentation/widgets/session_stats_card.dart';
import '../../../workout/presentation/widgets/stat_tile.dart';

/// 2×2 stats card for the public profile. Accepts nullable counter values;
/// null renders as '0'. kFormat is applied to WORKOUTS, SEGUIDORES, SIGUIENDO
/// (compact Xk display). RACHA is rendered as raw integer (design spec).
///
/// RACHA is rendered in accent color to match the mockup; the others use
/// `textPrimary`. Backward-compatible: all params default to null → '0'.
class PublicProfileStatsRow extends StatelessWidget {
  const PublicProfileStatsRow({
    super.key,
    this.workoutsCount,
    this.racha,
    this.followersCount,
    this.followingCount,
  });

  final int? workoutsCount;
  final int? racha;
  final int? followersCount;
  final int? followingCount;

  @override
  Widget build(BuildContext context) {
    return SessionStatsCard(
      tiles: [
        StatTile(
          label: 'WORKOUTS',
          value: kFormat(workoutsCount ?? 0),
        ),
        StatTile(
          label: 'RACHA',
          value: '${racha ?? 0}',
          isAccent: true,
        ),
        StatTile(
          label: 'SEGUIDORES',
          value: kFormat(followersCount ?? 0),
        ),
        StatTile(
          label: 'SIGUIENDO',
          value: kFormat(followingCount ?? 0),
        ),
      ],
    );
  }
}
