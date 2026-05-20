import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/utils/k_formatter.dart';

/// 4-column stats row for the public profile. Accepts nullable counter values;
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
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: _StatTile(
            label: 'WORKOUTS',
            value: kFormat(workoutsCount ?? 0),
          ),
        ),
        Expanded(
          child: _StatTile(
            label: 'RACHA',
            value: '${racha ?? 0}',
            isAccent: true,
          ),
        ),
        Expanded(
          child: _StatTile(
            label: 'SEGUIDORES',
            value: kFormat(followersCount ?? 0),
          ),
        ),
        Expanded(
          child: _StatTile(
            label: 'SIGUIENDO',
            value: kFormat(followingCount ?? 0),
          ),
        ),
      ],
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.label,
    required this.value,
    this.isAccent = false,
  });

  final String label;
  final String value;
  final bool isAccent;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          value,
          style: GoogleFonts.barlow(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: isAccent ? palette.accent : palette.textPrimary,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w600,
            fontSize: 11,
            letterSpacing: 1.0,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}
