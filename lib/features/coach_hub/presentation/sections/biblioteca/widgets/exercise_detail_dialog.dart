// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../app/theme/tokens/primitives.dart';
import '../../../../../../core/widgets/motion/treino_shimmer.dart';
import '../../../../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../../../workout/application/exercise_providers.dart';
import '../../../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../../../../workout/domain/exercise.dart';
import '../../../../../workout/domain/muscle_group.dart';
import '../../../../../workout/presentation/widgets/exercise_video_player.dart';
import '../../../../../workout/presentation/widgets/technique_instruction_item.dart';
import '../../../widgets/coach_hub_widgets.dart';

/// Abre un [TreinoDialog] del kit con el detalle de un ejercicio.
///
/// Entry point: [showExerciseDetailDialog].
///
/// El body es un [ConsumerWidget] que watchea [slotExerciseProvider] para
/// re-fetch el doc custom completo cuando hace falta (la proyección lossy
/// de la grilla nunca se filtra — ADR-BIBW-02). El `.when` interno se
/// resuelve con [TreinoStateSwitcher]: loading → skeleton [TreinoShimmer],
/// error/no-encontrado → mensaje honesto, data → contenido (video +
/// técnica). Mirrors [AppointmentDetailDialog] from the agenda section.
///
/// Constraints: width 520, maxHeight 560, SingleChildScrollView. No
/// Scaffold, no navigation (ADR-CHW-005, ADR-BIBW-03).
///
/// REQ-BIBW-07, SCENARIO-BIBW-07a, SCENARIO-BIBW-07b.
void showExerciseDetailDialog(
  BuildContext context, {
  required String exerciseId,
  String? ownerId,
  String? exerciseName,
}) {
  showTreinoDialog<void>(
    context,
    builder: (ctx) => _ExerciseDetailDialog(
      exerciseId: exerciseId,
      ownerId: ownerId,
      exerciseName: exerciseName,
    ),
  );
}

class _ExerciseDetailDialog extends ConsumerWidget {
  const _ExerciseDetailDialog({
    required this.exerciseId,
    this.ownerId,
    this.exerciseName,
  });

  final String exerciseId;
  final String? ownerId;
  final String? exerciseName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final exerciseAsync = ref.watch(
      slotExerciseProvider((
        exerciseId: exerciseId,
        ownerId: ownerId,
        exerciseName: exerciseName,
      )),
    );

    return TreinoDialog(
      title: exerciseName ?? 'Ejercicio', // i18n
      primaryLabel: 'Cerrar', // i18n
      onPrimaryTap: () => Navigator.of(context).pop(),
      body: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: SingleChildScrollView(
            child: TreinoStateSwitcher(
              childKey: ValueKey(_stateKey(exerciseAsync)),
              child: exerciseAsync.when(
                loading: () => const _ExerciseDetailSkeleton(),
                error: (e, _) => const _ExerciseDetailMessage(
                  text: 'No pudimos cargar el ejercicio.', // i18n
                ),
                data: (exercise) {
                  if (exercise == null) {
                    return const _ExerciseDetailMessage(
                      text: 'Ejercicio no encontrado.', // i18n
                    );
                  }
                  return _ExerciseDetailContent(exercise: exercise);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Discrimina el estado actual para el [TreinoStateSwitcher] del body —
/// `loading`/`error`/`notfound` son keys fijas, `data` cross-fadea contra
/// cualquiera de las anteriores cuando el fetch resuelve.
String _stateKey(AsyncValue<Exercise?> exerciseAsync) {
  if (exerciseAsync.hasError) return 'error';
  if (exerciseAsync.isLoading && !exerciseAsync.hasValue) return 'loading';
  return exerciseAsync.value == null ? 'notfound' : 'data';
}

/// Skeleton compacto de carga — placeholder de header + video + técnica
/// envueltos en [TreinoShimmer].
class _ExerciseDetailSkeleton extends StatelessWidget {
  const _ExerciseDetailSkeleton();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    Widget bar(double width, double height) => Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: palette.bgCard,
            borderRadius: BorderRadius.circular(AppRadius.sm),
          ),
        );

    return TreinoShimmer(
      child: SizedBox(
        height: 220,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            bar(120, 12),
            const SizedBox(height: AppSpacing.hairline),
            bar(80, 10),
            const SizedBox(height: AppSpacing.s18),
            bar(double.infinity, 140),
            const SizedBox(height: AppSpacing.s18),
            bar(160, 12),
          ],
        ),
      ),
    );
  }
}

/// Mensaje honesto de error o "no encontrado" — sin skeleton (nada está
/// cargando).
class _ExerciseDetailMessage extends StatelessWidget {
  const _ExerciseDetailMessage({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      height: 120,
      child: Center(
        child: Text(
          text,
          style: TextStyle(
            fontFamily: AppFonts.barlow,
            color: palette.textMuted,
          ),
        ),
      ),
    );
  }
}

/// Contenido del detalle: subtítulo de grupo muscular, video (si existe) y
/// técnica (si existe).
class _ExerciseDetailContent extends StatelessWidget {
  const _ExerciseDetailContent({required this.exercise});

  final Exercise exercise;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final instructions = exercise.techniqueInstructions;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        // ── Subtítulo: grupo muscular ──────────────────────────────────
        Text(
          muscleGroupLabel(exercise.muscleGroup).toUpperCase(), // i18n
          style: TextStyle(
            fontFamily: AppFonts.barlowCondensed,
            fontWeight: AppFonts.w600,
            fontSize: 12,
            color: palette.accent,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: AppSpacing.s18),
        // ── Video (omitido cuando videoUrl es null) ────────────────────
        if (exercise.videoUrl != null) ...[
          ExerciseVideoPlayer(videoUrl: exercise.videoUrl),
          const SizedBox(height: AppSpacing.s18),
        ],
        // ── Técnica ─────────────────────────────────────────────────────
        if (instructions != null && instructions.isNotEmpty) ...[
          Text(
            'TÉCNICA', // i18n
            style: TextStyle(
              fontFamily: AppFonts.barlowCondensed,
              fontWeight: AppFonts.w700,
              fontSize: 12,
              color: palette.textMuted,
              letterSpacing: 1,
            ),
          ),
          const SizedBox(height: AppSpacing.s8),
          for (var i = 0; i < instructions.length; i++) ...[
            TechniqueInstructionItem(
              index: i + 1,
              text: instructions[i],
            ),
            if (i < instructions.length - 1)
              const SizedBox(height: AppSpacing.s8),
          ],
        ] else
          Text(
            'Sin instrucciones de técnica todavía.', // i18n
            style: TextStyle(
              fontFamily: AppFonts.barlow,
              color: palette.textMuted,
              fontSize: 13,
            ),
          ),
      ],
    );
  }
}

/// Convenience: reads the current uid to determine ownerId for custom exercises.
/// Used by [EjerciciosTab] when tapping a card.
String? resolveOwnerId(WidgetRef ref, String category) {
  if (category != 'custom') return null;
  return ref.read(currentUidProvider);
}
