import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../feed/presentation/widgets/post_avatar.dart';
import '../../domain/trainer_public_profile.dart';
import '../../domain/trainer_specialty.dart';
import '../coach_strings.dart';

/// A list tile for a single trainer in the discovery list.
///
/// Per design D16: distance < 10km shows 1 decimal, >= 10km rounded,
/// null shows "—".
///
/// REQ-COACH-DISC-UI-006. SCENARIO-429.
class TrainerListTile extends StatelessWidget {
  const TrainerListTile({
    super.key,
    required this.profile,
    required this.distanceKm,
    required this.onTap,
  });

  final TrainerPublicProfile profile;
  final double? distanceKm;
  final VoidCallback onTap;

  String _formatDistance() {
    final d = distanceKm;
    if (d == null) return CoachStrings.distanceUnknown;
    if (d < 10) return '${d.toStringAsFixed(1)} km';
    return '${d.round()} km';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final specialty = profile.trainerSpecialty;
    final rate = profile.trainerMonthlyRate;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            PostAvatar(
              authorDisplayName: profile.displayName ?? '',
              authorAvatarUrl: profile.avatarUrl,
              size: 48,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.displayName ?? '',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                      letterSpacing: 0.5,
                      color: palette.textPrimary,
                    ),
                  ),
                  if (specialty != null) ...[
                    const SizedBox(height: 4),
                    _SpecialtyChip(label: TrainerSpecialtyX.toWire(specialty)),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (rate != null)
                  Text(
                    '\$$rate${CoachStrings.monthlyRateUnit}',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: palette.accent,
                    ),
                  ),
                const SizedBox(height: 4),
                Text(
                  _formatDistance(),
                  style: GoogleFonts.barlow(
                    fontSize: 12,
                    color: palette.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SpecialtyChip extends StatelessWidget {
  const _SpecialtyChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: palette.border),
      ),
      child: Text(
        label,
        style: GoogleFonts.barlowCondensed(
          fontSize: 11,
          letterSpacing: 0.3,
          color: palette.textMuted,
        ),
      ),
    );
  }
}
