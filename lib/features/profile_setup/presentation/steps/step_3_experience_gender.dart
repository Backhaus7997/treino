import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../profile/domain/experience_level.dart';
import '../../../profile/domain/gender.dart';
import '../../application/profile_setup_notifier.dart';
import '../../application/profile_setup_providers.dart';
import '../widgets/experience_card.dart';
import '../widgets/gender_chip.dart';

/// Step 3: nivel de experiencia (3 cards) + género (3 chips).
/// Mockup: `profile-setup-3.png`.
class Step3ExperienceGender extends ConsumerWidget {
  const Step3ExperienceGender({super.key});

  // Labels y descripciones de los niveles de experiencia. Viven acá porque
  // el enum canónico (lib/features/profile/domain/experience_level.dart) no
  // los expone — el enum sólo describe los valores wire, no la copy de UI.
  static const Map<ExperienceLevel, ({String label, String description})>
      _experienceCopy = {
    ExperienceLevel.beginner: (
      label: 'PRINCIPIANTE',
      description: 'Recién empiezo o vuelvo después de mucho.',
    ),
    ExperienceLevel.intermediate: (
      label: 'INTERMEDIO',
      description: 'Entreno hace 6+ meses, conozco la mayoría de ejercicios.',
    ),
    ExperienceLevel.advanced: (
      label: 'AVANZADO',
      description: '2+ años entrenando con periodización.',
    ),
  };

  // Mockup muestra 3 chips: FEMENINO, MASCULINO, OTRO. El enum canónico de
  // Dev A tiene 4 valores (male, female, nonBinary, undisclosed); mapeamos
  // "OTRO" a undisclosed y dejamos nonBinary fuera de la UI por ahora.
  static const List<({Gender value, String label})> _genderChoices = [
    (value: Gender.female, label: 'FEMENINO'),
    (value: Gender.male, label: 'MASCULINO'),
    (value: Gender.undisclosed, label: 'OTRO'),
  ];

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
              label: _experienceCopy[level]!.label,
              description: _experienceCopy[level]!.description,
              selected: draft.experienceLevel == level,
              onTap: () => notifier.updateExperienceLevel(level),
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
              for (final choice in _genderChoices)
                GenderChip(
                  label: choice.label,
                  selected: draft.gender == choice.value,
                  onTap: () => notifier.updateGender(choice.value),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
