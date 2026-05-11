import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../application/profile_setup_notifier.dart';
import '../../application/profile_setup_providers.dart';
import '../../domain/gym.dart';
import '../widgets/gym_card.dart';

/// Step 2: gym selector con search + lista hardcodeada + opción "OTRO/SIN GYM".
/// Mockup: `profile-setup-2.png`.
class Step2Gym extends ConsumerWidget {
  const Step2Gym({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final selectedGymId = ref.watch(
      profileSetupNotifierProvider.select(
        (ProfileSetupState s) => s.draft.gymId,
      ),
    );
    final gyms = ref.watch(filteredGymsProvider);

    return SingleChildScrollView(
      child: Column(
        children: [
          const SizedBox(height: 20),
          TextField(
            onChanged: (v) =>
                ref.read(gymSearchQueryProvider.notifier).state = v,
            style: GoogleFonts.barlow(color: palette.textPrimary, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Buscar gym',
              prefixIcon: Icon(
                TreinoIcon.search,
                color: palette.textMuted,
                size: 20,
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 48, minHeight: 48),
            ),
          ),
          const SizedBox(height: 14),
          for (final gym in gyms) ...[
            GymCard(
              name: gym.name,
              address: gym.address,
              selected: selectedGymId == gym.id,
              onTap: () => ref
                  .read(profileSetupNotifierProvider.notifier)
                  .updateGymId(gym.id),
            ),
            const SizedBox(height: 12),
          ],
          GymCard(
            name: 'OTRO GYM / SIN GYM',
            address: 'No registramos tu gimnasio',
            selected: selectedGymId == kNoGymId,
            onTap: () => ref
                .read(profileSetupNotifierProvider.notifier)
                .updateGymId(kNoGymId),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}
