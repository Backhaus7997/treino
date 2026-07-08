import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../workout/presentation/widgets/exercise_progression_section.dart'
    show ChartPeriodLabels, ChartPeriodSelector;
import '../application/muscle_distribution_providers.dart';
import '../domain/chart_period.dart';
import 'widgets/muscle_distribution_radar.dart';

/// [stats-hub] Dedicated screen for the current-vs-previous 6-axis muscle
/// distribution radar — promoted out of the InsightsScreen's inline
/// `_MuscleDistributionSection` (obs #445) so the hub can list it as an
/// "ESTADÍSTICAS AVANZADAS" tile (Hevy "Statistics" parity) instead of one
/// long scroll. Same [MuscleDistributionRadar] widget + [ChartPeriodSelector]
/// pattern as the section it replaces — only the hosting shell changed.
///
/// [uid] is explicit (not read from `currentUidProvider` directly) — same
/// reusability convention as [MonthlyReportScreen].
class MuscleDistributionScreen extends ConsumerStatefulWidget {
  const MuscleDistributionScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<MuscleDistributionScreen> createState() =>
      _MuscleDistributionScreenState();
}

class _MuscleDistributionScreenState
    extends ConsumerState<MuscleDistributionScreen> {
  ChartPeriod _selectedPeriod = ChartPeriod.defaultPeriod;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);

    final periodLabels = ChartPeriodLabels(
      last30dLabel: l10n.progressionPeriodLast30Days,
      thisWeekLabel: l10n.progressionPeriodThisWeek,
      monthLabel: l10n.progressionPeriodMonth,
    );

    final radarLabels = MuscleDistributionLabels(
      currentLabel: l10n.muscleDistributionCurrentLabel,
      previousLabel: l10n.muscleDistributionPreviousLabel,
      emptyStateText: l10n.muscleDistributionEmptyState,
      workoutsLabel: l10n.muscleDistributionWorkoutsLabel,
      durationLabel: l10n.muscleDistributionDurationLabel,
      volumeLabel: l10n.muscleDistributionVolumeLabel,
      setsLabel: l10n.muscleDistributionSetsLabel,
      durationUnit: 'min',
      volumeUnit: 'kg',
    );

    final insightsAsync = ref.watch(
      muscleDistributionInsightsProvider(
        (uid: widget.uid, period: _selectedPeriod),
      ),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: l10n.muscleDistributionScreenTitle),
        Expanded(
          child: ListView(
            padding: EdgeInsets.fromLTRB(
                20, 12, 20, 20 + MediaQuery.paddingOf(context).bottom),
            physics: const AlwaysScrollableScrollPhysics(),
            children: [
              Container(
                decoration: BoxDecoration(
                  color: palette.bgCard,
                  borderRadius: BorderRadius.circular(20),
                ),
                padding: const EdgeInsets.all(18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.muscleDistributionSectionTitle,
                            style: GoogleFonts.barlowCondensed(
                              fontWeight: FontWeight.w700,
                              fontSize: 12,
                              letterSpacing: 1.2,
                              color: palette.textMuted,
                            ),
                          ),
                        ),
                        ChartPeriodSelector(
                          selected: _selectedPeriod,
                          labels: periodLabels,
                          onSelect: (p) => setState(() => _selectedPeriod = p),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    insightsAsync.when(
                      loading: () => const SizedBox(
                        height: 240,
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (_, __) => const SizedBox.shrink(),
                      data: (insights) => MuscleDistributionRadar(
                        insights: insights,
                        labels: radarLabels,
                      ),
                    ),
                  ],
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
