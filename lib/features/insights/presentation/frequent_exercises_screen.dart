import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../workout/application/exercise_frequency_providers.dart';
import '../../workout/application/session_providers.dart'
    show sessionsByUidProvider;
import '../../workout/presentation/widgets/exercise_progression_section.dart'
    show ChartPeriodLabels;
import '../../workout/presentation/widgets/most_frequent_exercises_list.dart';
import '../domain/chart_period.dart';

/// [stats-hub] Athlete-side "Ejercicios frecuentes" screen — reuses the
/// coach-only [MostFrequentExercisesList] widget (PR4) with the athlete's
/// OWN uid (obs #445), as an "ESTADÍSTICAS AVANZADAS" tile destination.
///
/// NAVIGATION NOTE: en el shell del coach, tocar una fila selecciona el
/// ejercicio en una sección de progresión HERMANA, inline, en la MISMA pantalla
/// (`_ProgressionSection`/`_exerciseSelection` en
/// `coach/presentation/athlete_detail_screen.dart`) — no es un push de ruta.
///
/// Del lado del alumno NO existía destino, así que las filas eran no-navegantes
/// y esto quedó anotado como "flagged for a future slice". Ese slice ya está:
/// las filas hacen push a [ExerciseProgressionScreen]
/// (`/home/insights/exercise-progression?exerciseId=…`), que abre la progresión
/// del ejercicio tocado ya preseleccionado.
///
/// (Ojo: `ExerciseDetailScreen` en `/workout/exercise/:exerciseId` NO es este
/// destino — es la ficha del CATÁLOGO, no una vista de estadísticas.)
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
              // TREINO Motion PR2: cross-fade loading→data/error (key =
              // branch del `.when()`; sin keys distintas no anima).
              TreinoStateSwitcher(
                childKey: ValueKey(
                  entriesAsync.when(
                    loading: () => 'loading',
                    error: (_, __) => 'error',
                    data: (_) => 'data',
                  ),
                ),
                child: entriesAsync.when(
                  loading: () => const SizedBox(
                    height: 120,
                    child: Center(child: CircularProgressIndicator()),
                  ),
                  // QA-INS-005: nunca `SizedBox.shrink()` en error — dejaba la
                  // pantalla en blanco, sin mensaje ni forma de reintentar.
                  // `_ErrorState` (mensaje + retry) reintenta la carga vía
                  // [_retry] (#376: invalida también la dependencia fallida,
                  // no sólo este provider).
                  error: (_, __) => _ErrorState(
                    message: l10n.frequentExercisesLoadError,
                    retryLabel: l10n.coachRetryLabel,
                    onRetry: () => _retry(ref, widget.uid, _selectedPeriod),
                  ),
                  data: (entries) => MostFrequentExercisesList(
                    entries: entries,
                    selectedPeriod: _selectedPeriod,
                    // Ahora SÍ navegan: ExerciseProgressionScreen es el destino
                    // que faltaba (ver el doc de la clase, que lo dejaba
                    // anotado como "flagged for a future slice"). Toco una fila
                    // → abro la progresión de ESE ejercicio, ya preseleccionado.
                    onSelectExercise: (exerciseId) => context.push(
                      '/home/insights/exercise-progression?exerciseId=$exerciseId',
                    ),
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

/// #376: invalidates the frequency provider AND the sessions provider that
/// actually performs the fetch it depends on.
///
/// `ref.invalidate` does NOT cascade to dependencies, and the screen keeps
/// [sessionsByUidProvider] alive (watched via [exerciseFrequencyProvider]), so
/// its `AsyncError` stays cached across the rebuild. Invalidating only
/// [exerciseFrequencyProvider] would re-read the SAME cached sessions error
/// and re-render the identical error state: a retry button that can never
/// recover, precisely in the case that brings the user here (offline / failed
/// sessions fetch). Same fix as MuscleDistributionScreen's `_retry`; setlog
/// fetches run inside [exerciseFrequencyProvider]'s own body, so invalidating
/// it re-runs those.
void _retry(WidgetRef ref, String uid, ChartPeriod period) {
  ref.invalidate(sessionsByUidProvider(uid));
  ref.invalidate(
    exerciseFrequencyProvider((athleteUid: uid, period: period)),
  );
}

// ── Error state ───────────────────────────────────────────────────────────────

/// Message + retry CTA — same shape as [MuscleDistributionScreen]'s
/// `_ErrorState`. `retryLabel` is optional; falls back to [coachRetryLabel].
class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String? retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20),
      child: Column(
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
          ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: onRetry,
            child: Text(retryLabel ?? l10n.coachRetryLabel),
          ),
        ],
      ),
    );
  }
}
