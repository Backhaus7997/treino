import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../insights/application/insights_providers.dart';
import '../../insights/domain/weekly_insights.dart';
import '../../insights/presentation/widgets/body_silhouette_placeholder.dart';

/// ISO 8601 week number for [date] (1..53).
///
/// Handles the two year-boundary edge cases the naive formula misses:
/// a result < 1 belongs to the last week of the previous ISO year, and a
/// result of 53 in a year without 53 ISO weeks is week 1 of the next year.
int isoWeekNumber(DateTime date) {
  final dayOfYear =
      DateTime(date.year, date.month, date.day)
          .difference(DateTime(date.year, 1, 1))
          .inDays +
      1;
  final weekday = date.weekday; // 1..7 (Mon..Sun)
  final woy = ((dayOfYear - weekday + 10) / 7).floor();

  if (woy < 1) {
    // Belongs to the last week of the previous ISO year.
    return isoWeeksInYear(date.year - 1);
  }
  if (woy > isoWeeksInYear(date.year)) {
    // Overflow into week 1 of the next ISO year.
    return 1;
  }
  return woy;
}

/// Number of ISO 8601 weeks (52 or 53) in [year].
///
/// A year has 53 weeks iff its last day (Dec 31) is a Thursday, or the
/// previous year's last day is a Thursday (i.e. this year starts on Thu).
int isoWeeksInYear(int year) {
  int p(int y) => (y + (y ~/ 4) - (y ~/ 100) + (y ~/ 400)) % 7;
  return (p(year) == 4 || p(year - 1) == 3) ? 53 : 52;
}

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
      return const _EmptyState();
    }

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row: RACHA ACTUAL pill + SEM N · MMM ──────────────
          const _CardHeader(),
          const SizedBox(height: 18),

          // ── Streak number (big) + DÍAS ────────────────────────────────
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

          // ── Body silhouettes (front + back, full-width, prominent) ────
          const BodySilhouettePlaceholder(
            width: double.infinity,
            height: 280,
            showBack: true,
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

// ── Empty state — para users con 0 sesiones (cuenta nueva) ───────────────────
//
// Replace al placeholder "Tocá para ver tus insights" con un layout más
// motivador: titular grande + ícono de llama (TreinoIcon.streak) + copy
// invitante + CTA explícito que lleva a la tab Entrenar. Diseño 2026-05-22:
// no mostramos "0 días / 0 entrenos" porque desmotiva al primer login.

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _CardHeader(emptyState: true),
          const SizedBox(height: 18),
          Center(
            child: Text(
              'TU RACHA\nEMPIEZA ACÁ',
              textAlign: TextAlign.center,
              style: GoogleFonts.barlowCondensed(
                fontWeight: FontWeight.w700,
                fontSize: 32,
                height: 1.05,
                color: palette.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 18),
          Center(
            child: Icon(
              TreinoIcon.streak,
              size: 64,
              color: palette.accent,
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Cada entrenamiento alimenta tu racha. Hacé el primero y empezá a construir tu progreso.',
            textAlign: TextAlign.center,
            style: GoogleFonts.barlow(
              fontSize: 13,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: () => context.go('/workout'),
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: palette.accent, width: 1),
                foregroundColor: palette.accent,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9999),
                ),
              ),
              child: Text(
                'EXPLORAR RUTINAS  →',
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.8,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Card header: pill (left) + SEM N · MMM (right) ───────────────────────────
//
// `emptyState=true` cambia el label a "PRIMER PASO" — versión empty state.
// `emptyState=false` (default) muestra "RACHA ACTUAL" — versión con data.

class _CardHeader extends StatelessWidget {
  const _CardHeader({this.emptyState = false});

  final bool emptyState;

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

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final now = DateTime.now().toLocal();
    final week = isoWeekNumber(now);
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
                emptyState ? 'PRIMER PASO' : 'RACHA ACTUAL',
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
