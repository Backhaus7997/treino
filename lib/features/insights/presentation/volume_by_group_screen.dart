import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/utils/argentina_time.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../application/insights_providers.dart';
import '../domain/muscle_group.dart';
import '../domain/weekly_insights.dart';

/// [stats-hub] Dedicated screen promoting the current week's per-group set
/// volume vs. target — moved out of InsightsScreen's inline `_VolumeBarCard`
/// (obs #445) into its own "ESTADÍSTICAS AVANZADAS" tile destination.
/// Same data semantics as the card it replaces: current week only, via
/// [athleteWeekInsightsProvider] pinned to `mondayOfWeek(now)` (no week
/// paging here — that stays on the hub's SEMANA card).
///
/// [uid] is explicit — same reusability convention as the other promoted
/// screens ([MuscleDistributionScreen], [MonthlyReportScreen]).
class VolumeByGroupScreen extends ConsumerWidget {
  const VolumeByGroupScreen({super.key, required this.uid});

  final String uid;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final weekStart = mondayOfWeek(argentinaNow());
    final async = ref.watch(
      athleteWeekInsightsProvider((uid: uid, weekStart: weekStart)),
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: l10n.volumeByGroupScreenTitle),
        Expanded(
          // TREINO Motion PR2: cross-fade loading→data/error (key = branch
          // del `.when()`; sin keys distintas no anima).
          child: TreinoStateSwitcher(
            childKey: ValueKey(
              async.when(
                loading: () => 'loading',
                error: (_, __) => 'error',
                data: (_) => 'data',
              ),
            ),
            child: async.when(
              loading: () => Center(
                child: CircularProgressIndicator(color: palette.accent),
              ),
              error: (_, __) => _ErrorState(
                onRetry: () => ref.invalidate(
                  athleteWeekInsightsProvider((uid: uid, weekStart: weekStart)),
                ),
              ),
              data: (insights) => insights == null
                  ? Center(
                      child: Text(
                        l10n.insightsLoadError,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.barlow(
                          fontSize: 14,
                          color: palette.textMuted,
                        ),
                      ),
                    )
                  : ListView(
                      padding: EdgeInsets.fromLTRB(20, 12, 20,
                          20 + MediaQuery.paddingOf(context).bottom),
                      physics: const AlwaysScrollableScrollPhysics(),
                      children: [
                        _VolumeBarCard(insights: insights),
                      ],
                    ),
            ),
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

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              l10n.insightsLoadError,
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: Text(l10n.coachRetryLabel)),
          ],
        ),
      ),
    );
  }
}

// ── Card: VOLUMEN POR GRUPO ──────────────────────────────────────────────────
// Moved verbatim from insights_screen.dart's `_VolumeBarCard` (obs #445) —
// same data semantics, no behavior change.

class _VolumeBarCard extends StatelessWidget {
  const _VolumeBarCard({required this.insights});
  final WeeklyInsights insights;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final hasTarget = insights.targetByGroup.isNotEmpty;

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            // QA #371: misma clave que el header de la pantalla — el copy es
            // idéntico y así la card queda dentro del sistema l10n.
            l10n.volumeByGroupScreenTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          if (!hasTarget)
            Text(
              l10n.volumeByGroupEmptyTarget,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 13,
                color: palette.textMuted,
              ),
            )
          else
            for (final group in MuscleGroupDisplay.displayOrder)
              if ((insights.targetByGroup[group] ?? 0) > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: _VolumeBarRow(
                    label: group.displayLabel,
                    done: insights.setsByGroup[group] ?? 0,
                    target: insights.targetByGroup[group]!,
                  ),
                ),
        ],
      ),
    );
  }
}

class _VolumeBarRow extends StatelessWidget {
  const _VolumeBarRow({
    required this.label,
    required this.done,
    required this.target,
  });

  final String label;
  final int done;
  final int target;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final ratio = target == 0 ? 0.0 : (done / target).clamp(0.0, 1.0);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.8,
                  color: palette.textPrimary,
                ),
              ),
            ),
            Text(
              '$done / $target sets',
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w500,
                fontSize: 12,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(9999),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: 8,
            backgroundColor: palette.bg,
            valueColor: AlwaysStoppedAnimation(palette.accent),
          ),
        ),
      ],
    );
  }
}
