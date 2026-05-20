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

    return Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
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

          if (wi == null || wi.sessionsCount == 0) ...[
            // No sessions yet — placeholder
            const BodySilhouettePlaceholder(
              width: double.infinity,
              height: 120,
              label: 'Tocá para ver tus insights',
            ),
          ] else ...[
            // ── Streak row ─────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '${wi.streak}',
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 48,
                    height: 1,
                    color: palette.accent,
                  ),
                ),
                const SizedBox(width: 8),
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    'DÍAS',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      letterSpacing: 1.2,
                      color: palette.accent,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // ── Streak subtext ─────────────────────────────────────────────
            _StreakSubtext(insights: wi),
            const SizedBox(height: 14),

            // ── Day strip ─────────────────────────────────────────────────
            _DayStrip(insights: wi),
            const SizedBox(height: 14),

            // ── SEMANA / MES mini-stats ────────────────────────────────────
            Row(
              children: [
                _MiniStat(
                  label: 'SEMANA',
                  value: '${wi.sessionsCount}/${wi.plannedSessionsCount}',
                  palette: palette,
                ),
                const SizedBox(width: 20),
                _MiniStat(
                  label: 'MES',
                  value: '${wi.monthSessionsCount}',
                  palette: palette,
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── Body silhouette placeholder ────────────────────────────────
            const BodySilhouettePlaceholder(
              width: double.infinity,
              height: 100,
              label: '',
            ),
          ],
        ],
      ),
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
        ? '¡Llevas ${insights.streak} días seguidos!'
        : 'Seguí la racha — todavía no entrenaste hoy.';

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
    return Row(
      children: [
        for (var i = 0; i < 7; i++)
          Expanded(
            child: Center(
              child: _DayDot(
                label: _dayLabels[i],
                trained: insights.daysTrained[i],
                palette: palette,
              ),
            ),
          ),
      ],
    );
  }
}

class _DayDot extends StatelessWidget {
  const _DayDot({
    required this.label,
    required this.trained,
    required this.palette,
  });
  final String label;
  final bool trained;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          label,
          style: GoogleFonts.barlow(
            fontSize: 12,
            color: palette.textMuted,
          ),
        ),
        const SizedBox(height: 4),
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: trained ? palette.accent : palette.border,
            shape: BoxShape.circle,
          ),
        ),
      ],
    );
  }
}

// ── Mini-stat tile ────────────────────────────────────────────────────────────

class _MiniStat extends StatelessWidget {
  const _MiniStat({
    required this.label,
    required this.value,
    required this.palette,
  });
  final String label;
  final String value;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Column(
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
        Text(
          value,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 20,
            color: palette.accent,
          ),
        ),
      ],
    );
  }
}
