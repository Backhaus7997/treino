// IMPORTANT: This widget MUST NOT import app_l10n.dart (R3 convention, same
// as exercise_progression_chart.dart / _section.dart / personal_records_list.dart).
// All user-visible strings are injected via [MostFrequentExercisesListLabels].
// The mobile caller resolves them from AppL10n; the web caller passes
// hardcoded Spanish strings.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../../insights/domain/chart_period.dart';
import '../../domain/exercise_frequency.dart';
import 'exercise_progression_section.dart'
    show ChartPeriodLabels, ChartPeriodSelector;

/// Plain-string label bag for [MostFrequentExercisesList] — same R3
/// no-AppL10n convention as the other progression widgets.
class MostFrequentExercisesListLabels {
  const MostFrequentExercisesListLabels({
    required this.sectionTitle,
    required this.sessionCountLabel,
    required this.emptyText,
    required this.periodLabels,
  });

  /// E.g. 'EJERCICIOS MÁS FRECUENTES'.
  final String sectionTitle;

  /// Converts a session count to a display string.
  /// E.g. (n) => n == 1 ? '1 sesión' : '$n sesiones'.
  final String Function(int count) sessionCountLabel;

  /// Shown when [MostFrequentExercisesList.entries] is empty.
  final String emptyText;

  /// [AD7] Labels for the shared chart period selector.
  final ChartPeriodLabels periodLabels;
}

/// [PR4] Most-frequent-exercises list (Hevy's "Main exercises"): ranks
/// exercises by session count within the selected [ChartPeriod] window.
///
/// Shared between the mobile coach shell and the web coach_hub shell (same
/// dedup convention as [ExerciseProgressionSection]/[PersonalRecordsList] —
/// one widget, same data in → same render out).
///
/// - Each row is tappable via [onSelectExercise] — callers wire this to
///   select the exercise in the existing per-exercise progression section
///   (navigable to the existing exercise progression/detail).
/// - Empty [entries] → [MostFrequentExercisesListLabels.emptyText].
class MostFrequentExercisesList extends StatelessWidget {
  const MostFrequentExercisesList({
    super.key,
    required this.entries,
    required this.selectedPeriod,
    required this.labels,
    required this.onSelectExercise,
    required this.onSelectPeriod,
  });

  final List<ExerciseFrequencyEntry> entries;
  final ChartPeriod selectedPeriod;
  final MostFrequentExercisesListLabels labels;
  final void Function(String exerciseId) onSelectExercise;
  final void Function(ChartPeriod period) onSelectPeriod;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                labels.sectionTitle,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: palette.textMuted,
                ),
              ),
            ),
            ChartPeriodSelector(
              selected: selectedPeriod,
              labels: labels.periodLabels,
              onSelect: onSelectPeriod,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty)
          Text(
            labels.emptyText,
            style: GoogleFonts.barlow(fontSize: 13, color: palette.textMuted),
          )
        else
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: palette.bgCard,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: palette.border),
            ),
            child: Column(
              children: [
                for (var i = 0; i < entries.length; i++) ...[
                  if (i > 0) Divider(color: palette.border, height: 18),
                  _FrequencyRow(
                    entry: entries[i],
                    sessionCountLabel: labels.sessionCountLabel,
                    onTap: () => onSelectExercise(entries[i].exerciseId),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }
}

class _FrequencyRow extends StatelessWidget {
  const _FrequencyRow({
    required this.entry,
    required this.sessionCountLabel,
    required this.onTap,
  });

  final ExerciseFrequencyEntry entry;
  final String Function(int count) sessionCountLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return InkWell(
      onTap: onTap,
      child: Row(
        children: [
          Expanded(
            child: Text(
              entry.exerciseName,
              style: GoogleFonts.barlow(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: palette.textPrimary,
              ),
            ),
          ),
          Text(
            sessionCountLabel(entry.sessionCount),
            style: GoogleFonts.barlow(fontSize: 12, color: palette.textMuted),
          ),
          const SizedBox(width: 6),
          Icon(TreinoIcon.chevronRight, size: 16, color: palette.textMuted),
        ],
      ),
    );
  }
}
