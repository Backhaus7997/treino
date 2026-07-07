// IMPORTANT: This widget MUST NOT import app_l10n.dart (R3 / SCENARIO-PROG-11C).
// All user-visible strings are injected as plain String parameters via
// [ExerciseProgressionSectionLabels]. The mobile caller resolves them from
// AppL10n; the web caller passes hardcoded Spanish strings.
//
// This is the shared section-level widget extracted from the duplicated
// `_ProgressionSection`/`_ProgressionChartLoader` (mobile coach shell) and
// `_ProgressionTabSection`/`_ProgressionChartLoader` (web coach_hub shell).
// AD1: dedupe at the SECTION level, not just the chart widget — both shells
// must render identically from ONE widget given the same data (dedup
// contract, see exercise_progression_section_test.dart).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../application/exercise_progression_providers.dart';
import 'exercise_progression_chart.dart';

/// Plain-string label bag for [ExerciseProgressionSection].
///
/// Wraps [ExerciseProgressionChartLabels] plus the section-level strings
/// (title, loading, error, empty state) so the whole section can be
/// label-injected without importing AppL10n.
class ExerciseProgressionSectionLabels {
  const ExerciseProgressionSectionLabels({
    required this.sectionTitle,
    required this.loadingText,
    this.exerciseListErrorText,
    required this.emptyStateText,
    required this.chartLabels,
    required this.localeName,
  });

  /// E.g. 'EVOLUCIÓN POR EJERCICIO'
  final String sectionTitle;

  /// E.g. 'Cargando…' — shown while the exercise list loads.
  final String loadingText;

  /// E.g. 'No se pudo cargar la evolución.' — shown on exercise-list error.
  /// Null preserves the mobile shell's original behavior of showing nothing
  /// on error (SizedBox.shrink).
  final String? exerciseListErrorText;

  /// E.g. 'Sin registros de series todavía.' — shown when no exercises exist.
  final String emptyStateText;

  /// Labels forwarded to [ExerciseProgressionChart].
  final ExerciseProgressionChartLabels chartLabels;

  /// Locale name for date formatting (e.g. 'es_AR', 'en').
  final String localeName;
}

/// Per-exercise progression section — shared between the mobile coach shell
/// and the web coach_hub shell (AD1).
///
/// Watches [athleteExerciseListProvider] to show an exercise picker row and
/// [exerciseProgressionProvider] to show the progression chart for the
/// selected exercise.
class ExerciseProgressionSection extends ConsumerStatefulWidget {
  const ExerciseProgressionSection({
    super.key,
    required this.athleteId,
    required this.labels,
  });

  final String athleteId;
  final ExerciseProgressionSectionLabels labels;

  @override
  ConsumerState<ExerciseProgressionSection> createState() =>
      _ExerciseProgressionSectionState();
}

class _ExerciseProgressionSectionState
    extends ConsumerState<ExerciseProgressionSection> {
  String? _selectedExerciseId;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final labels = widget.labels;
    final exerciseListAsync =
        ref.watch(athleteExerciseListProvider(widget.athleteId));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ──────────────────────────────────────────────
        Text(
          labels.sectionTitle,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.2,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 12),

        exerciseListAsync.when(
          loading: () => Text(
            labels.loadingText,
            style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
          ),
          error: (e, _) => labels.exerciseListErrorText == null
              ? const SizedBox.shrink()
              : Text(
                  labels.exerciseListErrorText!,
                  style: GoogleFonts.barlow(
                      fontSize: 13, color: palette.textMuted),
                ),
          data: (exercises) {
            // SCENARIO-PROG-08A: no exercises → empty state, no picker
            if (exercises.isEmpty) {
              return Text(
                labels.emptyStateText,
                style:
                    GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
              );
            }

            // SCENARIO-PROG-05B: default to most-recently-logged exercise
            final effectiveId =
                _selectedExerciseId ?? exercises.first.exerciseId;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Exercise picker chip row ──────────────────────────
                ExercisePickerRow(
                  exercises: exercises,
                  selectedId: effectiveId,
                  onSelect: (id) => setState(() => _selectedExerciseId = id),
                ),
                const SizedBox(height: 12),

                // ── Progression chart ─────────────────────────────────
                _ProgressionChartLoader(
                  athleteId: widget.athleteId,
                  exerciseId: effectiveId,
                  chartLabels: labels.chartLabels,
                  localeName: labels.localeName,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Loads and renders [ExerciseProgressionChart] for one exercise.
class _ProgressionChartLoader extends ConsumerWidget {
  const _ProgressionChartLoader({
    required this.athleteId,
    required this.exerciseId,
    required this.chartLabels,
    required this.localeName,
  });

  final String athleteId;
  final String exerciseId;
  final ExerciseProgressionChartLabels chartLabels;
  final String localeName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressionAsync = ref.watch(
      exerciseProgressionProvider(
          (athleteUid: athleteId, exerciseId: exerciseId)),
    );

    return progressionAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (progression) => ExerciseProgressionChart(
        progression: progression,
        labels: chartLabels,
        localeName: localeName,
      ),
    );
  }
}
