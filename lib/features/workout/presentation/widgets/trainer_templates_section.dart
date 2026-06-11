import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../coach/application/trainer_link_providers.dart';
import '../../../profile/application/user_public_profile_providers.dart';
import '../../../profile/domain/experience_level.dart' show ExperienceLevelEs;
import '../../application/routine_providers.dart';
import '../../domain/routine.dart';

/// Section the athlete sees in their Workout tab when (a) they have an
/// active trainer link AND (b) the linked trainer has flipped
/// `sharedTemplatesWithAthletes` to true on their public profile.
///
/// Renders the trainer's `trainer-template` routines as compact full-width
/// row cards — same visual language as MisRutinasSection/_UserRoutineCard —
/// so that 1–2 shared templates don't leave a large vertical gap the way a
/// 2-column grid with tall cells would.
///
/// Design decision (2026-06-11): grid replaced with row list because the
/// typical case is 1–3 templates and the grid (childAspectRatio 0.95,
/// crossAxisCount 2) reserved a nearly square cell that left ~half the screen
/// empty below a single card. Row cards adapt naturally to any count.
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
        // Row-list layout: each template occupies a full-width compact card
        // identical in structure to _UserRoutineCard (MisRutinasSection).
        // This avoids the tall empty space produced by a 2-column grid when
        // only 1–2 templates are shared.
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final routine in templates)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _TrainerTemplateCard(routine: routine),
              ),
          ],
        ),
      ],
    );
  }
}

// ── Compact row card ──────────────────────────────────────────────────────────

class _TrainerTemplateCard extends StatelessWidget {
  const _TrainerTemplateCard({required this.routine});

  final Routine routine;

  int get _totalExercises =>
      routine.days.fold(0, (sum, day) => sum + day.slots.length);

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return InkWell(
      key: Key('trainer_template_card_${routine.id}'),
      borderRadius: BorderRadius.circular(16),
      onTap: () => context.push('/workout/routine/${routine.id}'),
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            // Tinted icon square matching RoutineCard's visual language.
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: palette.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: palette.accent.withValues(alpha: 0.3),
                ),
              ),
              child: Icon(
                TreinoIcon.tabWorkout,
                color: palette.accent,
                size: 18,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    routine.name,
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: palette.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${routine.level.displayNameEs.toUpperCase()} · $_totalExercises ej.',
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      color: palette.textMuted,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
