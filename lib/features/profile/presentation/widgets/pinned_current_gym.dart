import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../gyms/application/gym_providers.dart';
import '../../../gyms/domain/gym.dart' show kNoGymId;
import '../../../gyms/domain/gym_display_name.dart';

/// Pinned card showing the athlete's current gym at the top of
/// `ProfileGymScreen` — design gym-selection-v2 AD-11.
///
/// Reuses `gymByIdProvider` + `gymDisplayNameFromGym`, the exact pattern
/// `profile_cuenta_section.dart` already uses for the "Gimnasio" tile
/// subtitle. Display-only — it does NOT re-trigger selection (it IS the
/// current selection); tapping a different gym elsewhere on the screen
/// replaces it.
///
/// Hidden entirely (renders nothing) when [currentGymId] is `null` or
/// [kNoGymId] — spec gym-selection-screen "No pinned card when the athlete
/// has no gym".
class PinnedCurrentGym extends ConsumerWidget {
  const PinnedCurrentGym({super.key, required this.currentGymId});

  /// The athlete's current `gymId`, or `null`/[kNoGymId] when they have no
  /// gym assigned.
  final String? currentGymId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final gymId = currentGymId;
    if (gymId == null || gymId == kNoGymId) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final gymAsync = ref.watch(gymByIdProvider(gymId));

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.accent, width: 1.5),
        ),
        child: gymAsync.when(
          loading: () => const Center(
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
          error: (_, __) => const SizedBox.shrink(),
          data: (gym) => Row(
            children: [
              Icon(TreinoIcon.mapPin, color: palette.accent, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  gymDisplayNameFromGym(gym),
                  style: GoogleFonts.barlowCondensed(
                    color: palette.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
              Icon(TreinoIcon.check, color: palette.accent, size: 20),
            ],
          ),
        ),
      ),
    );
  }
}
