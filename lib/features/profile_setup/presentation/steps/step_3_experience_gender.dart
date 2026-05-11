import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../application/profile_setup_notifier.dart';
import '../../application/profile_setup_providers.dart';
import '../../domain/experience_level.dart';
import '../../domain/gender.dart';
import '../widgets/experience_card.dart';
import '../widgets/gender_chip.dart';

/// Step 3: nivel de experiencia (3 cards) + género (3 chips).
/// Mockup: `profile-setup-3.png`.
class Step3ExperienceGender extends ConsumerWidget {
  const Step3ExperienceGender({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final draft = ref.watch(
      profileSetupNotifierProvider.select(
        (ProfileSetupState s) => s.draft,
      ),
    );
    final notifier = ref.read(profileSetupNotifierProvider.notifier);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          for (final level in ExperienceLevel.values) ...[
            ExperienceCard(
              label: level.label,
              description: level.description,
              selected: draft.experience == level,
              onTap: () => notifier.updateExperience(level),
            ),
            const SizedBox(height: 12),
          ],
          const SizedBox(height: 14),
          Text(
            'GÉNERO',
            style: GoogleFonts.barlowCondensed(
              color: palette.textMuted,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 1.4,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            children: [
              for (final g in Gender.values)
                GenderChip(
                  label: g.label,
                  selected: draft.gender == g,
                  onTap: () => notifier.updateGender(g),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
