import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../insights/application/insights_providers.dart';
import '../../insights/domain/weekly_insights.dart';
import '../../insights/presentation/widgets/body_silhouette_placeholder.dart';

/// Card "Esta Semana" del Home.
/// Wired to [weeklyInsightsProvider] — muestra racha, tira de días,
/// contadores SEMANA/MES y el mapa muscular placeholder.
/// Etapa 6 completa (wire-real-stats PR#1).
class EstaSemanaCard extends ConsumerWidget {
  const EstaSemanaCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(weeklyInsightsProvider);

    return GestureDetector(
      onTap: () => context.push('/home/insights'),
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: palette.border, width: 1),
        ),
        child: async.when(
          loading: () => const _Skeleton(),
          error: (_, __) => const _ErrorFallback(),
          data: (insights) => _Loaded(insights: insights),
        ),
      ),
    );
  }
}

// ── Loading skeleton ──────────────────────────────────────────────────────────

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ESTA SEMANA',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              letterSpacing: 1.4,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: CircularProgressIndicator(color: palette.accent),
          ),
        ],
      ),
    );
  }
}

// ── Error fallback ────────────────────────────────────────────────────────────

class _ErrorFallback extends StatelessWidget {
  const _ErrorFallback();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ESTA SEMANA',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 14,
              letterSpacing: 1.4,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'No pudimos cargar tus insights.',
            style: GoogleFonts.barlow(
              fontSize: 13,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Loaded state ──────────────────────────────────────────────────────────────

class _Loaded extends StatelessWidget {
  const _Loaded({required this.insights});

  final WeeklyInsights? insights;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final wi = insights;

    if (wi == null || wi.sessionsCount == 0) {
      return const Padding(
        padding: EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _CardHeader(),
            SizedBox(height: 18),
            BodySilhouettePlaceholder(
              width: double.infinity,
              height: 120,
              label: 'Tocá para ver tus insights',
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row: RACHA ACTUAL pill + SEM N · MMM ──────────────
          const _CardHeader(),
          const SizedBox(height: 18),

          // ── Streak number (big) ───────────────────────────────────────
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${wi.streak}',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 96,
                  height: 1,
                  color: palette.textPrimary,
                ),
              ),
              const SizedBox(width: 8),
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Text(
                  'DÍAS',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 20,
                    letterSpacing: 1.2,
                    color: palette.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // ── Streak subtext ────────────────────────────────────────────
          _StreakSubtext(insights: wi),
          const SizedBox(height: 14),

          // ── Day strip (bars) ──────────────────────────────────────────
          _DayStrip(insights: wi),
          const SizedBox(height: 14),

          // ── Body silhouette placeholder (anatomical SVG deferred) ─────
          const BodySilhouettePlaceholder(
            width: double.infinity,
            height: 120,
            label: '',
          ),
          const SizedBox(height: 14),

          // ── SEMANA / MES cards ─────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: _PeriodCard(
                  label: 'SEMANA',
                  count: wi.sessionsCount,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _PeriodCard(
                  label: 'MES',
                  count: wi.monthSessionsCount,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Card header: RACHA ACTUAL pill (left) + SEM N · MMM (right) ──────────────

class _CardHeader extends StatelessWidget {
  const _CardHeader();

  static const _monthsEs = [
    'ENE',
    'FEB',
    'MAR',
    'ABR',
    'MAY',
    'JUN',
    'JUL',
    'AGO',
    'SEP',
    'OCT',
    'NOV',
    'DIC',
  ];

  /// ISO 8601 week number for [date].
  int _isoWeekNumber(DateTime date) {
    final dayOfYear = int.parse(
          DateTime(date.year, date.month, date.day)
              .difference(DateTime(date.year, 1, 1))
              .inDays
              .toString(),
        ) +
        1;
    final weekday = date.weekday; // 1..7 (Mon..Sun)
    return ((dayOfYear - weekday + 10) / 7).floor();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final now = DateTime.now().toLocal();
    final week = _isoWeekNumber(now);
    final month = _monthsEs[now.month - 1];

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        // Pill "● RACHA ACTUAL"
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            border: Border.all(color: palette.accent, width: 1),
            borderRadius: BorderRadius.circular(9999),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: palette.accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'RACHA ACTUAL',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 1.2,
                  color: palette.accent,
                ),
              ),
            ],
          ),
        ),
        // "SEM N · MMM"
        Text(
          'SEM $week · $month',
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.2,
            color: palette.textMuted,
          ),
        ),
      ],
    );
  }
}

// ── Streak subtext ────────────────────────────────────────────────────────────

class _StreakSubtext extends StatelessWidget {
  const _StreakSubtext({required this.insights});
  final WeeklyInsights insights;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final now = DateTime.now().toLocal();
    final todayIndex = now.weekday - DateTime.monday;
    final trainedToday =
        todayIndex >= 0 && todayIndex < 7 && insights.daysTrained[todayIndex];

    final text = trainedToday
        ? 'No rompas la racha — entrenaste hoy.'
        : 'No rompas la racha — entrená hoy.';

    return Text(
      text,
      style: GoogleFonts.barlow(
        fontSize: 13,
        color: palette.textMuted,
      ),
    );
  }
}

// ── Day strip ─────────────────────────────────────────────────────────────────

class _DayStrip extends StatelessWidget {
  const _DayStrip({required this.insights});
  final WeeklyInsights insights;

  static const _dayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final now = DateTime.now().toLocal();
    final todayIndex = now.weekday - DateTime.monday;

    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < 6 ? 8 : 0),
              child: _DayBar(
                label: _dayLabels[i],
                trained: insights.daysTrained[i],
                isToday: i == todayIndex,
                isPast: i < todayIndex,
                palette: palette,
              ),
            ),
          ),
      ],
    );
  }
}

class _DayBar extends StatelessWidget {
  const _DayBar({
    required this.label,
    required this.trained,
    required this.isToday,
    required this.isPast,
    required this.palette,
  });
  final String label;
  final bool trained;
  final bool isToday;
  final bool isPast;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    final Color barColor;
    final Border? barBorder;

    if (trained) {
      barColor = palette.accent;
      barBorder = null;
    } else if (isToday) {
      // Today, not yet trained — outline only (dashed approximated by border).
      barColor = palette.bgCard;
      barBorder = Border.all(color: palette.accent, width: 1.5);
    } else if (isPast) {
      // Past day not trained — muted filled bar.
      barColor = palette.border;
      barBorder = null;
    } else {
      // Future day — very faint bar.
      barColor = palette.border.withValues(alpha: 0.4);
      barBorder = null;
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 8,
          decoration: BoxDecoration(
            color: barColor,
            border: barBorder,
            borderRadius: BorderRadius.circular(9999),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 1.2,
            color: trained || isToday ? palette.accent : palette.textMuted,
          ),
        ),
      ],
    );
  }
}

// ── Period card (SEMANA / MES) ────────────────────────────────────────────────

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.label, required this.count});
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      decoration: BoxDecoration(
        color: palette.bg,
        border: Border.all(color: palette.border, width: 1),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            '$count',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 32,
              height: 1,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'entrenos',
            style: GoogleFonts.barlow(
              fontSize: 12,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}
