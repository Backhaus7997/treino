// NOTE: Scaffold y SafeArea los provee CoachHubScaffold (ADR-CHW-005).
// Todas las strings en español hardcodeado + // i18n.
// No se usa AppL10n (constraint C-6).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../../../app/theme/app_palette.dart';
import '../../../../../../core/widgets/treino_icon.dart';
import '../providers/biblioteca_providers.dart';
import 'biblioteca_filter_chips.dart';
import 'exercise_detail_dialog.dart';
import 'exercise_grid_card.dart';

/// Tab body for the "Ejercicios" tab of [BibliotecaWebScreen].
///
/// Layout: search field → [BibliotecaFilterChips] → Expanded [GridView].
///
/// REQ-BIBW-03, REQ-BIBW-04, REQ-BIBW-05, REQ-BIBW-06, REQ-BIBW-11.
/// SCENARIO-BIBW-03a, SCENARIO-BIBW-03b, SCENARIO-BIBW-11a.
class EjerciciosTab extends ConsumerWidget {
  const EjerciciosTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final exercisesAsync = ref.watch(bibliotecaExercisesProvider);

    return Column(
      children: [
        // ── Search field ───────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Buscar ejercicios...', // i18n
              hintStyle: GoogleFonts.barlow(color: palette.textMuted),
              prefixIcon: Icon(
                TreinoIcon.search,
                color: palette.textMuted,
                size: 20,
              ),
              filled: true,
              fillColor: palette.bgCard,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 12,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.border),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.border),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: palette.accent, width: 1.5),
              ),
            ),
            style: GoogleFonts.barlow(color: palette.textPrimary),
            onChanged: (v) {
              ref.read(bibliotecaQueryProvider.notifier).state = v;
            },
          ),
        ),
        // ── Filter chips ───────────────────────────────────────────────────
        const BibliotecaFilterChips(),
        // ── Exercise grid ──────────────────────────────────────────────────
        Expanded(
          child: exercisesAsync.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: palette.accent),
            ),
            error: (e, _) => Center(
              child: Text(
                'Error al cargar ejercicios.', // i18n
                style: GoogleFonts.barlow(
                  color: palette.textMuted,
                  fontSize: 14,
                ),
              ),
            ),
            data: (exercises) {
              if (exercises.isEmpty) {
                return Center(
                  child: Text(
                    'No se encontraron ejercicios.', // i18n
                    style: GoogleFonts.barlow(
                      color: palette.textMuted,
                      fontSize: 14,
                    ),
                  ),
                );
              }
              return GridView.builder(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 260,
                  childAspectRatio: 0.82,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                ),
                itemCount: exercises.length,
                itemBuilder: (context, index) {
                  final exercise = exercises[index];
                  return ExerciseGridCard(
                    exercise: exercise,
                    onTap: () {
                      showExerciseDetailDialog(
                        context,
                        exerciseId: exercise.id,
                        ownerId: resolveOwnerId(ref, exercise.category),
                        exerciseName: exercise.name,
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}
