import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../application/insights_providers.dart';
import '../domain/muscle_group.dart';
import '../domain/weekly_insights.dart';
import 'widgets/body_silhouette_placeholder.dart';

/// Pantalla de Insights — agregados semanales por grupo muscular.
/// Mockup: `insights.png`. Acceso natural desde la card "Esta Semana"
/// del Home (tap en el body → `context.push('/workout/insights')`).
class InsightsScreen extends ConsumerWidget {
  const InsightsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(weeklyInsightsProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InsightsHeader(),
        Expanded(
          child: async.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: palette.accent),
            ),
            error: (_, __) => _ErrorState(
              onRetry: () => ref.invalidate(weeklyInsightsProvider),
            ),
            data: (insights) {
              if (insights == null || insights.sessionsCount == 0) {
                return const _EmptyState();
              }
              return ListView(
                padding: EdgeInsets.fromLTRB(
                    20, 12, 20, 20 + MediaQuery.paddingOf(context).bottom),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  _WeekStripCard(insights: insights),
                  const SizedBox(height: 14),
                  _MusclesCard(insights: insights),
                  const SizedBox(height: 14),
                  _VolumeBarCard(insights: insights),
                  const SizedBox(height: 20),
                  _VolverButton(),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _InsightsHeader extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 20, 8),
      child: Row(
        children: [
          IconButton(
            icon: Icon(TreinoIcon.back, color: palette.textPrimary),
            onPressed: () => _safePopOrHome(context),
          ),
          const SizedBox(width: 8),
          Text(
            'INSIGHTS',
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

void _safePopOrHome(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/home');
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              TreinoIcon.chartBar,
              size: 48,
              color: palette.textMuted,
            ),
            const SizedBox(height: 18),
            Text(
              'Empezá a entrenar para ver tus insights.',
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(
                fontWeight: FontWeight.w400,
                fontSize: 14,
                color: palette.textMuted,
              ),
            ),
          ],
        ),
      ),
    );
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
              style: GoogleFonts.barlow(
                fontSize: 14,
                color: palette.textMuted,
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: onRetry,
              child: Text(l10n.coachRetryLabel),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Card: SEMANA + tira L-D ──────────────────────────────────────────────────

class _WeekStripCard extends StatelessWidget {
  const _WeekStripCard({required this.insights});
  final WeeklyInsights insights;

  static const _dayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final today = DateTime.now().toLocal();
    final todayIndex = today.weekday - DateTime.monday;

    return Container(
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _formatRange(insights.weekStart, insights.weekEnd),
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: palette.textMuted,
                  ),
                ),
              ),
              Text(
                '${insights.sessionsCount} / ${insights.plannedSessionsCount}',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 16,
                  letterSpacing: 0.6,
                  color: palette.accent,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          // Labels L M M J V S D
          Row(
            children: [
              for (final label in _dayLabels)
                Expanded(
                  child: Center(
                    child: Text(
                      label,
                      style: GoogleFonts.barlow(
                        fontWeight: FontWeight.w400,
                        fontSize: 12,
                        color: palette.textMuted,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          // Chips por día
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: _DayChip(
                      trained: insights.daysTrained[i],
                      isToday: i == todayIndex,
                      dayOfMonth: insights.weekStart.add(Duration(days: i)).day,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DayChip extends StatelessWidget {
  const _DayChip({
    required this.trained,
    required this.isToday,
    required this.dayOfMonth,
  });

  final bool trained;
  final bool isToday;
  final int dayOfMonth;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    if (trained) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: palette.accent,
          shape: BoxShape.circle,
        ),
        alignment: Alignment.center,
        child: Icon(
          TreinoIcon.checkCircleFill,
          color: palette.bg,
          size: 18,
        ),
      );
    }
    if (isToday) {
      return Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: palette.accent, width: 1.5),
        ),
        alignment: Alignment.center,
        child: Text(
          '$dayOfMonth',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            color: palette.accent,
          ),
        ),
      );
    }
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: palette.border, width: 1),
      ),
      alignment: Alignment.center,
      child: Text(
        '$dayOfMonth',
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w600,
          fontSize: 14,
          color: palette.textMuted,
        ),
      ),
    );
  }
}

// ── Card: MÚSCULOS DE LA SEMANA ──────────────────────────────────────────────

class _MusclesCard extends StatelessWidget {
  const _MusclesCard({required this.insights});
  final WeeklyInsights insights;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

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
            'MÚSCULOS DE LA SEMANA',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              BodySilhouettePlaceholder(
                width: 160,
                height: 240,
                setsByGroup: insights.setsByGroup,
                targetByGroup: insights.targetByGroup,
              ),
              const SizedBox(width: 18),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final group in MuscleGroupDisplay.displayOrder)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: _MuscleSetsRow(
                          group: group,
                          sets: insights.setsByGroup[group] ?? 0,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MuscleSetsRow extends StatelessWidget {
  const _MuscleSetsRow({required this.group, required this.sets});
  final MuscleGroupDisplay group;
  final int sets;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final hasSets = sets > 0;
    final dotColor = hasSets ? palette.accent : palette.textMuted;
    final labelColor = hasSets ? palette.textPrimary : palette.textMuted;

    return Row(
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            group.displayLabel,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              letterSpacing: 0.8,
              color: labelColor,
            ),
          ),
        ),
        Text(
          '$sets',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            color: labelColor,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'SETS',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w600,
            fontSize: 11,
            letterSpacing: 0.6,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}

// ── Card: VOLUMEN POR GRUPO ──────────────────────────────────────────────────

class _VolumeBarCard extends StatelessWidget {
  const _VolumeBarCard({required this.insights});
  final WeeklyInsights insights;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
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
            'VOLUMEN POR GRUPO',
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
              'Necesitás una rutina asignada para ver tu volumen objetivo.',
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

// ── Botón VOLVER ──────────────────────────────────────────────────────────────

class _VolverButton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton(
        onPressed: () => _safePopOrHome(context),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: palette.border, width: 1),
          minimumSize: const Size.fromHeight(56),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(9999),
          ),
        ),
        child: Text(
          'VOLVER',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 14,
            letterSpacing: 1.0,
            color: palette.textPrimary,
          ),
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

const _monthsEs = [
  'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', //
  'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC',
];

String _formatRange(DateTime start, DateTime end) {
  final s = '${start.day} ${_monthsEs[start.month - 1]}';
  final e = '${end.day} ${_monthsEs[end.month - 1]}';
  return 'SEMANA · $s – $e';
}
