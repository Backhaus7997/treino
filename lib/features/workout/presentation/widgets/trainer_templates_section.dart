import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../coach/application/trainer_link_providers.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../application/routine_providers.dart';
import 'routine_card.dart';

/// Section the athlete sees in their Workout tab when (a) they have an
/// active trainer link AND (b) the linked trainer has flipped
/// `sharedTemplatesWithAthletes` to true on their public profile.
///
/// Renders the trainer's `trainer-template` routines as `RoutineCard`s so
/// the athlete can browse them, open RoutineDetail, and "EMPEZAR" a
/// session exactly like with the system catalogue.
///
/// When the conditions don't hold (no active link, or trainer hasn't opted
/// in, or zero templates), the whole section is hidden — no empty
/// placeholder, no clutter for athletes without trainers.
class TrainerTemplatesSection extends ConsumerWidget {
  const TrainerTemplatesSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final linkAsync = ref.watch(currentAthleteLinkProvider);
    final link = linkAsync.valueOrNull;
    if (link == null) return const SizedBox.shrink();

    final trainerProfile =
        ref.watch(userPublicProfileProvider(link.trainerId)).valueOrNull;
    if (trainerProfile?.sharedTemplatesWithAthletes != true) {
      return const SizedBox.shrink();
    }

    final templatesAsync =
        ref.watch(trainerTemplatesStreamProvider(link.trainerId));
    final templates = templatesAsync.valueOrNull ?? const [];
    if (templates.isEmpty) return const SizedBox.shrink();

    final palette = AppPalette.of(context);
    final theme = Theme.of(context);

    final trainerName = trainerProfile?.displayName?.trim().isNotEmpty == true
        ? trainerProfile!.displayName!
        : 'tu entrenador';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'PLANTILLAS DE ${trainerName.toUpperCase()}',
          style: theme.textTheme.titleMedium?.copyWith(
            color: palette.textPrimary,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          'Tu entrenador compartió estas plantillas con vos.',
          style: GoogleFonts.barlow(
            fontWeight: FontWeight.w400,
            fontSize: 12,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
            childAspectRatio: 0.95,
          ),
          itemCount: templates.length,
          itemBuilder: (context, i) {
            final routine = templates[i];
            final variant = routine.id.hashCode % 3 == 0
                ? RoutineCardVariant.highlight
                : RoutineCardVariant.accent;
            return RoutineCard(routine: routine, variant: variant);
          },
        ),
      ],
    );
  }
}
