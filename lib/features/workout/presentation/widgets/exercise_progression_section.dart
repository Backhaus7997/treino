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
import '../../../../core/widgets/treino_icon.dart';
import '../../../insights/domain/chart_period.dart';
import '../../application/exercise_progression_providers.dart';
import 'exercise_progression_chart.dart';
import 'personal_records_list.dart';

/// [AD7] Plain-string label bag for the chart period selector — one label
/// per [ChartPeriod] variant. NEVER imports AppL10n (same R3 rule as the
/// rest of this file's label bags).
class ChartPeriodLabels {
  const ChartPeriodLabels({
    required this.last30dLabel,
    required this.thisWeekLabel,
    required this.monthLabel,
  });

  /// E.g. 'Últimos 30 días' — [ChartPeriod.last30d] (default).
  final String last30dLabel;

  /// E.g. 'Esta semana' — [ChartPeriod.thisWeek].
  final String thisWeekLabel;

  /// E.g. 'Este mes' — [ChartPeriod.month].
  final String monthLabel;

  String labelFor(ChartPeriod period) {
    switch (period) {
      case ChartPeriod.last30d:
        return last30dLabel;
      case ChartPeriod.thisWeek:
        return thisWeekLabel;
      case ChartPeriod.month:
        return monthLabel;
    }
  }
}

/// Plain-string label bag for [ExerciseProgressionSection].
///
/// Wraps [ExerciseProgressionChartLabels] plus the section-level strings
/// (title, loading, error, empty state) so the whole section can be
/// label-injected without importing AppL10n.
///
/// [AD3] [chartLabels] now carries 4 distinct metric labels (Heaviest
/// Weight/1RM/Best Set Volume/Best Session Volume) instead of the original
/// 2 (PR/Volumen) — see exercise_progression_chart.dart.
class ExerciseProgressionSectionLabels {
  const ExerciseProgressionSectionLabels({
    required this.sectionTitle,
    required this.loadingText,
    this.exerciseListErrorText,
    required this.emptyStateText,
    required this.chartLabels,
    required this.periodLabels,
    required this.localeName,
    required this.personalRecordsLabels,
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

  /// [AD7] Labels for the chart period selector.
  final ChartPeriodLabels periodLabels;

  /// Locale name for date formatting (e.g. 'es_AR', 'en').
  final String localeName;

  /// [AD3] Labels for the per-exercise [PersonalRecordsList] shown below the
  /// progression chart.
  final PersonalRecordsListLabels personalRecordsLabels;
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
    this.externalExerciseSelection,
  });

  final String athleteId;
  final ExerciseProgressionSectionLabels labels;

  /// [PR4] Optional external-selection hook — when a sibling widget (e.g.
  /// [MostFrequentExercisesList]) wants to drive which exercise this section
  /// displays (navigable to the existing exercise progression/detail),
  /// it calls `.value = exerciseId` on this notifier. Purely additive: when
  /// null (default), the section behaves exactly as before, owning its own
  /// selection state internally.
  final ValueNotifier<String?>? externalExerciseSelection;

  @override
  ConsumerState<ExerciseProgressionSection> createState() =>
      _ExerciseProgressionSectionState();
}

class _ExerciseProgressionSectionState
    extends ConsumerState<ExerciseProgressionSection> {
  String? _selectedExerciseId;

  /// [AD7] Defaults to [ChartPeriod.defaultPeriod] (last30d).
  ChartPeriod _selectedPeriod = ChartPeriod.defaultPeriod;

  @override
  void initState() {
    super.initState();
    widget.externalExerciseSelection?.addListener(_onExternalSelection);
  }

  @override
  void dispose() {
    widget.externalExerciseSelection?.removeListener(_onExternalSelection);
    super.dispose();
  }

  void _onExternalSelection() {
    final id = widget.externalExerciseSelection?.value;
    if (id != null) {
      setState(() => _selectedExerciseId = id);
    }
  }

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

                // ── Period selector ────────────────────────────────────
                Align(
                  alignment: Alignment.centerRight,
                  child: ChartPeriodSelector(
                    selected: _selectedPeriod,
                    labels: labels.periodLabels,
                    onSelect: (p) => setState(() => _selectedPeriod = p),
                  ),
                ),
                const SizedBox(height: 8),

                // ── Progression chart ─────────────────────────────────
                _ProgressionChartLoader(
                  athleteId: widget.athleteId,
                  exerciseId: effectiveId,
                  chartLabels: labels.chartLabels,
                  localeName: labels.localeName,
                  period: _selectedPeriod,
                  personalRecordsLabels: labels.personalRecordsLabels,
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Loads and renders [ExerciseProgressionChart] + [PersonalRecordsList] for
/// one exercise — both are derived from the same [exerciseProgressionProvider]
/// read (single Firestore-backed fetch, see [ExerciseProgression]).
class _ProgressionChartLoader extends ConsumerWidget {
  const _ProgressionChartLoader({
    required this.athleteId,
    required this.exerciseId,
    required this.chartLabels,
    required this.localeName,
    required this.period,
    required this.personalRecordsLabels,
  });

  final String athleteId;
  final String exerciseId;
  final ExerciseProgressionChartLabels chartLabels;
  final String localeName;

  /// [AD7] Selected chart period — bounds the returned series.
  final ChartPeriod period;

  /// [AD3] Labels for the [PersonalRecordsList] shown below the chart.
  final PersonalRecordsListLabels personalRecordsLabels;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progressionAsync = ref.watch(
      exerciseProgressionProvider(
          (athleteUid: athleteId, exerciseId: exerciseId, period: period)),
    );

    return progressionAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (e, _) => const SizedBox.shrink(),
      data: (progression) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExerciseProgressionChart(
            progression: progression,
            labels: chartLabels,
            localeName: localeName,
          ),
          const SizedBox(height: 14),
          PersonalRecordsList(
            records: progression.personalRecords,
            labels: personalRecordsLabels,
          ),
        ],
      ),
    );
  }
}

// ── Period selector ──────────────────────────────────────────────────────────

/// [AD7] Hevy-style period selector pill — tap to pick [ChartPeriod.last30d]
/// (default) / [ChartPeriod.thisWeek] / [ChartPeriod.month].
class ChartPeriodSelector extends StatelessWidget {
  const ChartPeriodSelector({
    super.key,
    required this.selected,
    required this.labels,
    required this.onSelect,
  });

  final ChartPeriod selected;
  final ChartPeriodLabels labels;
  final void Function(ChartPeriod) onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return PopupMenuButton<ChartPeriod>(
      initialValue: selected,
      onSelected: onSelect,
      color: palette.bgCard,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: palette.border),
      ),
      itemBuilder: (context) => ChartPeriod.values
          .map(
            (p) => PopupMenuItem<ChartPeriod>(
              value: p,
              child: Text(
                labels.labelFor(p),
                style: GoogleFonts.barlow(
                  fontSize: 13,
                  fontWeight: p == selected ? FontWeight.w700 : FontWeight.w400,
                  color: p == selected ? palette.accent : palette.textPrimary,
                ),
              ),
            ),
          )
          .toList(),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              labels.labelFor(selected),
              style: GoogleFonts.barlow(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
            const SizedBox(width: 4),
            Icon(TreinoIcon.chevronDown, size: 14, color: palette.textMuted),
          ],
        ),
      ),
    );
  }
}
