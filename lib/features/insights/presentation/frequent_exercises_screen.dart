import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../workout/application/exercise_frequency_providers.dart';
import '../../workout/presentation/widgets/exercise_progression_section.dart'
    show ChartPeriodLabels;
import '../../workout/presentation/widgets/most_frequent_exercises_list.dart';
import '../domain/chart_period.dart';

/// [stats-hub] Athlete-side "Ejercicios frecuentes" screen — reuses the
/// coach-only [MostFrequentExercisesList] widget (PR4) with the athlete's
/// OWN uid (obs #445), as an "ESTADÍSTICAS AVANZADAS" tile destination.
///
/// NAVIGATION NOTE: on the coach side, tapping a row selects the exercise in
/// a SIBLING inline progression section on the SAME screen (see
/// `_ProgressionSection`/`_exerciseSelection` in
/// `coach/presentation/athlete_detail_screen.dart`) — it is NOT a route
/// push. No athlete-side per-exercise progression destination screen/route
/// exists today (`ExerciseDetailScreen` at `/workout/exercise/:exerciseId`
/// is a catalogue detail page, not a stats/progression view). Rows are
/// therefore NON-NAVIGATING here for now — flagged for a future slice once
/// an athlete-side exercise progression destination exists.
///
/// [uid] is explicit — same reusability convention as the other promoted
/// screens.
class FrequentExercisesScreen extends ConsumerStatefulWidget {
  const FrequentExercisesScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<FrequentExercisesScreen> createState() =>
      _FrequentExercisesScreenState();
}

class _FrequentExercisesScreenState
    extends ConsumerState<FrequentExercisesScreen> {
  ChartPeriod _selectedPeriod = ChartPeriod.defaultPeriod;

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    final entriesAsync = ref.watch(exerciseFrequencyProvider(
        (athleteUid: widget.uid, period: _selectedPeriod)));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: l10n.frequentExercisesScreenTitle),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, 20 + MediaQuery.paddingOf(context).bottom),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              entriesAsync.when(
                loading: () => const SizedBox(
                  height: 120,
                  child: Center(child: CircularProgressIndicator()),
                ),
                error: (_, __) => const SizedBox.shrink(),
                data: (entries) => MostFrequentExercisesList(
                  entries: entries,
                  selectedPeriod: _selectedPeriod,
                  // NON-NAVIGATING (see class doc) — no athlete-side
                  // exercise progression destination exists yet.
                  onSelectExercise: (_) {},
                  onSelectPeriod: (p) => setState(() => _selectedPeriod = p),
                  labels: MostFrequentExercisesListLabels(
                    sectionTitle: l10n.mostFrequentExercisesSectionTitle,
                    sessionCountLabel: (n) =>
                        l10n.mostFrequentExercisesSessionCount(n),
                    emptyText: l10n.mostFrequentExercisesEmpty,
                    periodLabels: ChartPeriodLabels(
                      last30dLabel: l10n.progressionPeriodLast30Days,
                      thisWeekLabel: l10n.progressionPeriodThisWeek,
                      monthLabel: l10n.progressionPeriodMonth,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _Header extends StatelessWidget {
  const _Header({required this.title});

  final String title;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(TreinoIcon.back, color: palette.textPrimary),
            onPressed: () => _safePopOrInsights(context),
          ),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 24,
              letterSpacing: 1.2,
              color: palette.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

void _safePopOrInsights(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/home/insights');
  }
}
