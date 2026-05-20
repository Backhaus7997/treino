import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../feed/presentation/widgets/post_avatar.dart';
import '../../domain/trainer_public_profile.dart';
import 'trainer_specialty_chips.dart';

/// Hero block for a trainer profile page.
///
/// Layout: large [PostAvatar] centered, displayName below, specialty label
/// below that (if set). Null avatarUrl is handled by [PostAvatar]'s initials
/// fallback (per design risk note 7: "render placeholder `TreinoIcon.user`"
/// — [PostAvatar] already does this via initial letter).
///
/// REQ-COACH-DISC-UI-015.
class TrainerProfileHero extends StatelessWidget {
  const TrainerProfileHero({super.key, required this.profile});

  final TrainerPublicProfile profile;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final specialty = profile.trainerSpecialty;

    return Column(
      children: [
        const SizedBox(height: 24),
        Center(
          child: PostAvatar(
            authorDisplayName: profile.displayName ?? '',
            authorAvatarUrl: profile.avatarUrl,
            size: 88,
          ),
        ),
        const SizedBox(height: 12),
        if (profile.displayName != null) ...[
          Center(
            child: Text(
              profile.displayName!,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 24,
                letterSpacing: 0.5,
                color: palette.textPrimary,
              ),
            ),
          ),
        ],
        if (specialty != null) ...[
          const SizedBox(height: 6),
          Center(
            child: Text(
              SpecialtyLabels.of(specialty),
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w500,
                fontSize: 14,
                letterSpacing: 0.5,
                color: palette.accent,
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
      ],
    );
  }
}
