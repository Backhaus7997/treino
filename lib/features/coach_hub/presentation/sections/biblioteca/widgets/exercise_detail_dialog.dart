// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../workout/application/exercise_providers.dart';
import '../../../../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../../../../../workout/domain/muscle_group.dart';
import '../../../../../workout/presentation/widgets/exercise_video_player.dart';
import '../../../../../workout/presentation/widgets/technique_instruction_item.dart';

/// Opens an [AlertDialog] with exercise details.
///
/// Entry point: [showExerciseDetailDialog].
///
/// The dialog is a [ConsumerWidget] that watches [slotExerciseProvider] to
/// re-fetch the full custom doc when needed (lossy grid projection never leaks
/// — ADR-BIBW-02). Mirrors [AppointmentDetailDialog] from the agenda section.
///
/// Constraints: width 520, maxHeight 560, SingleChildScrollView,
/// RoundedRectangleBorder radius 20. No Scaffold, no navigation (ADR-CHW-005,
/// ADR-BIBW-03).
///
/// REQ-BIBW-07, SCENARIO-BIBW-07a, SCENARIO-BIBW-07b.
void showExerciseDetailDialog(
  BuildContext context, {
  required String exerciseId,
  String? ownerId,
  String? exerciseName,
}) {
  showDialog<void>(
    context: context,
    builder: (_) => _ExerciseDetailDialog(
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
    final palette = AppPalette.of(context);
    final exerciseAsync = ref.watch(
      slotExerciseProvider((
        exerciseId: exerciseId,
        ownerId: ownerId,
        exerciseName: exerciseName,
      )),
    );

    final content = exerciseAsync.when(
      loading: () => const SizedBox(
        height: 120,
        child: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => SizedBox(
        height: 120,
        child: Center(
          child: Text(
            'No pudimos cargar el ejercicio.', // i18n
            style: GoogleFonts.barlow(color: palette.textMuted),
          ),
        ),
      ),
      data: (exercise) {
        if (exercise == null) {
          return SizedBox(
            height: 120,
            child: Center(
              child: Text(
                'Ejercicio no encontrado.', // i18n
                style: GoogleFonts.barlow(color: palette.textMuted),
              ),
            ),
          );
        }

        final instructions = exercise.techniqueInstructions;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header row ───────────────────────────────────────────────────
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        exercise.name,
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 20,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        muscleGroupLabel(exercise.muscleGroup)
                            .toUpperCase(), // i18n
                        style: GoogleFonts.barlowCondensed(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: palette.accent,
                          letterSpacing: 1,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // ── Video (omitted when videoUrl is null) ─────────────────────
            if (exercise.videoUrl != null) ...[
              ExerciseVideoPlayer(videoUrl: exercise.videoUrl),
              const SizedBox(height: 16),
            ],
            // ── Technique instructions ────────────────────────────────────
            if (instructions != null && instructions.isNotEmpty) ...[
              Text(
                'TÉCNICA', // i18n
                style: GoogleFonts.barlowCondensed(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: palette.textMuted,
                  letterSpacing: 1,
                ),
              ),
              const SizedBox(height: 8),
              for (var i = 0; i < instructions.length; i++) ...[
                TechniqueInstructionItem(
                  index: i + 1,
                  text: instructions[i],
                ),
                if (i < instructions.length - 1) const SizedBox(height: 8),
              ],
            ] else
              Text(
                'Sin instrucciones de técnica todavía.', // i18n
                style: GoogleFonts.barlow(
                  color: palette.textMuted,
                  fontSize: 13,
                ),
              ),
          ],
        );
      },
    );

    return AlertDialog(
      backgroundColor: palette.bgCard,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(20)),
      ),
      content: SizedBox(
        width: 520,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 560),
          child: SingleChildScrollView(child: content),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cerrar', // i18n
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w600,
              color: palette.accent,
            ),
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
