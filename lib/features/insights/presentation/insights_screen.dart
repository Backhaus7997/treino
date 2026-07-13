import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../app/theme/app_motion.dart';
import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/motion/treino_fade_slide_in.dart';
import '../../../core/widgets/motion/treino_state_switcher.dart';
import '../../../core/widgets/motion/treino_tappable.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider;
import '../application/day_insights_providers.dart';
import '../application/insights_providers.dart';
import '../domain/muscle_group.dart';
import '../domain/weekly_insights.dart';
import 'widgets/body_silhouette_placeholder.dart';

/// Pantalla de Insights — agregados semanales por grupo muscular.
/// Mockup: `insights.png`. Acceso natural desde la card "Esta Semana"
/// del Home (tap en el body → `context.push('/workout/insights')`).
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  /// [REQ:heat-map-per-day][UX-week-day-selector] Day currently shown by the
  /// body silhouette. Defaults to today; changes when the athlete taps a
  /// weekday circle in [_WeekStripCard] (the SEMANA card doubles as the
  /// day selector — no separate day-strip inside the muscles card anymore).
  /// Independent of the shown week's window — the heat-map is per-day, the
  /// rest of the screen stays weekly.
  late DateTime _selectedDay = _todayOnly();

  /// [UX-week-day-selector] Monday 00:00 local of the week currently shown
  /// by the SEMANA card. Defaults to the current week; paged by the ‹ ›
  /// chevrons. Independent of `_selectedDay` — paging does NOT force-change
  /// the muscles card unless the selected day falls outside the new week.
  late DateTime _shownWeekStart = mondayOfWeek(DateTime.now().toLocal());

  /// [UX-week-day-selector] `true` once the athlete has paged away from the
  /// current week at least once. Gates the brand-new-account `_EmptyState`:
  /// that illustration only makes sense on first render of the CURRENT week
  /// with zero sessions ("you've never trained, start now"). Once the
  /// athlete is actively browsing past weeks, a week with 0 sessions is
  /// legitimate data ("you skipped this week") — the week card (0/5) must
  /// render instead, not the "start training" CTA.
  bool _hasPagedAway = false;

  static DateTime _todayOnly() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  /// [UX-week-day-selector] Future days of the current week are NOT
  /// selectable — `_DayChip` already de-emphasizes them and no-ops the tap,
  /// but this is the last line of defense against any programmatic call.
  void _onDaySelected(DateTime day) {
    if (day.isAfter(_todayOnly())) return;
    setState(() => _selectedDay = day);
  }

  /// [UX-week-day-selector] Pages the SEMANA card by [deltaWeeks] weeks
  /// (negative = previous, positive = next). Next-week paging is blocked at
  /// the current week — no future weeks. No back-limit: the athlete can page
  /// back indefinitely (bounded in practice by how far back they've trained;
  /// each week's data is fetched on demand).
  ///
  /// [UX-week-day-selector] If [_selectedDay] falls within the newly shown
  /// week, it's kept as-is (still valid, no change needed). If it falls
  /// OUTSIDE the new week, the muscles card is intentionally left alone —
  /// selection persists until the athlete explicitly taps a day in the new
  /// week. This avoids a jarring auto-jump of the card below while paging.
  void _pageWeek(int deltaWeeks) {
    final candidate = DateTime(
      _shownWeekStart.year,
      _shownWeekStart.month,
      _shownWeekStart.day + deltaWeeks * 7,
    );
    final currentWeekStart = mondayOfWeek(DateTime.now().toLocal());
    if (candidate.isAfter(currentWeekStart)) return;
    setState(() {
      _shownWeekStart = candidate;
      _hasPagedAway = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';
    final async = ref.watch(
      athleteWeekInsightsProvider((uid: uid, weekStart: _shownWeekStart)),
    );
    final isCurrentWeek =
        _shownWeekStart == mondayOfWeek(DateTime.now().toLocal());

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _InsightsHeader(),
        Expanded(
          // TREINO Motion PR2: cross-fade loading→data/error en vez de corte
          // seco. La key refleja el branch que el `.when()` de abajo eligió —
          // estados distintos DEBEN tener key distinta o el switcher no anima.
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
                  athleteWeekInsightsProvider(
                    (uid: uid, weekStart: _shownWeekStart),
                  ),
                ),
              ),
              data: (insights) {
                // Bug fix (abandoned-session-streak-reports): el CTA de
                // onboarding es SOLO para una cuenta que nunca completó un
                // entrenamiento. Antes se gateaba por `sessionsCount == 0`
                // de la semana mostrada, así que un atleta con historial
                // pero 0 sesiones ESTA semana no podía llegar a sus reportes
                // históricos (`_StatsHubTileList` vive dentro de esta misma
                // pantalla). `_hasPagedAway` se preserva sin cambios: pagear
                // a una semana pasada en 0 ya mostraba la week card, no el
                // CTA.
                if (insights == null ||
                    (!insights.hasEverCompletedAnyWorkout &&
                        isCurrentWeek &&
                        !_hasPagedAway)) {
                  return const _EmptyState();
                }
                // TREINO Motion PR3: entrada fade+slide staggerada de las
                // secciones. Seguro acá porque `ListView(children:)` es
                // EAGER (todos los States montan juntos una sola vez) — en
                // un builder lazy los ítems reciclados re-animarían al
                // scrollear. Los setState locales (seleccionar día, pagear
                // semana) NO re-animan: TreinoFadeSlideIn es one-shot y su
                // State sobrevive al rebuild.
                return ListView(
                  padding: EdgeInsets.fromLTRB(
                      20, 12, 20, 20 + MediaQuery.paddingOf(context).bottom),
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: [
                    TreinoFadeSlideIn(
                      delay: AppMotion.stagger(0),
                      child: _WeekStripCard(
                        insights: insights,
                        selectedDay: _selectedDay,
                        onDaySelected: _onDaySelected,
                        isCurrentWeek: isCurrentWeek,
                        onPreviousWeek: () => _pageWeek(-1),
                        onNextWeek: () => _pageWeek(1),
                      ),
                    ),
                    const SizedBox(height: 14),
                    TreinoFadeSlideIn(
                      delay: AppMotion.stagger(1),
                      child: _DailyMusclesCard(selectedDay: _selectedDay),
                    ),
                    const SizedBox(height: 20),
                    TreinoFadeSlideIn(
                      delay: AppMotion.stagger(2),
                      child: const _AdvancedStatsHeading(),
                    ),
                    const SizedBox(height: 12),
                    TreinoFadeSlideIn(
                      delay: AppMotion.stagger(3),
                      child: const _StatsHubTileList(),
                    ),
                    const SizedBox(height: 20),
                    TreinoFadeSlideIn(
                      delay: AppMotion.stagger(4),
                      child: _VolverButton(),
                    ),
                  ],
                );
              },
            ),
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
  const _WeekStripCard({
    required this.insights,
    required this.selectedDay,
    required this.onDaySelected,
    required this.isCurrentWeek,
    required this.onPreviousWeek,
    required this.onNextWeek,
  });
  final WeeklyInsights insights;

  /// [UX-week-day-selector] The day currently shown by the muscles card
  /// below. This card doubles as the day selector — tapping a past/today
  /// weekday circle drives [onDaySelected].
  final DateTime selectedDay;
  final ValueChanged<DateTime> onDaySelected;

  /// [UX-week-day-selector] `true` when [insights] is the CURRENT week —
  /// disables the › (next week) chevron, since future weeks don't exist.
  final bool isCurrentWeek;
  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;

  static const _dayLabels = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final today = DateTime.now().toLocal();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final todayIndex = today.weekday - DateTime.monday;
    final selectedOnly =
        DateTime(selectedDay.year, selectedDay.month, selectedDay.day);

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
              // [UX-week-day-selector] ‹ previous week. No back-limit — the
              // athlete can page back indefinitely; each week's data is
              // fetched on demand via `athleteWeekInsightsProvider`.
              IconButton(
                key: const Key('week-strip-previous-week'),
                icon: Icon(TreinoIcon.chevronLeft, color: palette.textMuted),
                onPressed: onPreviousWeek,
                tooltip: 'Semana anterior',
              ),
              Expanded(
                child: Text(
                  _formatRange(insights.weekStart, insights.weekEnd),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.barlowCondensed(
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                    letterSpacing: 1.2,
                    color: palette.textMuted,
                  ),
                ),
              ),
              // [UX-week-day-selector] › next week — disabled (null onTap)
              // on the current week, since there are no future weeks yet.
              IconButton(
                key: const Key('week-strip-next-week'),
                icon: Icon(TreinoIcon.chevronRight,
                    color: isCurrentWeek
                        ? palette.textMuted.withValues(alpha: 0.3)
                        : palette.textMuted),
                onPressed: isCurrentWeek ? null : onNextWeek,
                tooltip: 'Semana siguiente',
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
          // Chips por día — también funcionan como selector del día
          // mostrado en la card MÚSCULOS DEL DÍA.
          Row(
            children: [
              for (var i = 0; i < 7; i++)
                Builder(builder: (context) {
                  final day = DateTime(
                    insights.weekStart.year,
                    insights.weekStart.month,
                    insights.weekStart.day + i,
                  );
                  final isFuture = day.isAfter(todayOnly);
                  return Expanded(
                    child: Center(
                      child: _DayChip(
                        key: ValueKey(day),
                        trained: insights.daysTrained[i],
                        isToday: i == todayIndex,
                        isSelected: day == selectedOnly,
                        isFuture: isFuture,
                        dayOfMonth: day.day,
                        onTap: isFuture ? null : () => onDaySelected(day),
                      ),
                    ),
                  );
                }),
            ],
          ),
        ],
      ),
    );
  }
}

/// [UX-week-day-selector] Weekday circle in the SEMANA card. Doubles as the
/// day selector for the MÚSCULOS DEL DÍA card below: tapping selects
/// [dayOfMonth]'s day (past days and today only — [onTap] is `null` for
/// future days, which also render de-emphasized via reduced opacity).
///
/// [isSelected] draws an OUTER ring in `palette.highlight` (magenta) —
/// deliberately distinct from the `isToday`/trained marker, which stays
/// `palette.accent` (mint). This keeps "today" and "selected" visually
/// separable even when they're the same day (default selection = today).
class _DayChip extends StatelessWidget {
  const _DayChip({
    super.key,
    required this.trained,
    required this.isToday,
    required this.isSelected,
    required this.isFuture,
    required this.dayOfMonth,
    required this.onTap,
  });

  final bool trained;
  final bool isToday;
  final bool isSelected;
  final bool isFuture;
  final int dayOfMonth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    Widget circle;
    if (trained) {
      circle = Container(
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
    } else if (isToday) {
      circle = Container(
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
    } else {
      circle = Container(
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

    if (isSelected) {
      circle = Container(
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: palette.highlight, width: 2),
        ),
        child: circle,
      );
    }

    if (isFuture) {
      circle = Opacity(opacity: 0.4, child: circle);
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: circle,
    );
  }
}

// ── Card: MÚSCULOS DEL DÍA (per-day heat-map) ────────────────────────────────

/// [AD5][REQ:heat-map-per-day][UX-week-day-selector][UX-back-view] Replaces
/// the old week-accumulated "MÚSCULOS DE LA SEMANA" card. Each day starts
/// blank; the silhouette only paints the muscles trained on [selectedDay] —
/// no carry-over from other days (fixes the chest-Monday-bleeds-into-Tuesday
/// bug). The day-strip navigator that used to live INSIDE this card was
/// removed — the SEMANA card above is now the single day selector for the
/// whole screen (see `_WeekStripCard`). `DayStripNavigator`/`DayStripLabels`
/// stay in the codebase — the coach's `DailyHeatmapSection` still uses them.
///
/// [UX-back-view] `BodySilhouettePlaceholder(showBack: true)` — the athlete
/// can now see BACK muscles (espalda) too, not just the front silhouette.
/// Layout is a `Column` (silhouette full-width, list below) rather than the
/// old `Row` (silhouette beside the list) — the front+back pair needs more
/// horizontal room than a single body did, and stacking mirrors how home's
/// `EstaSemanaCard` already lays out its own `showBack: true` silhouette.
class _DailyMusclesCard extends ConsumerWidget {
  const _DailyMusclesCard({required this.selectedDay});

  final DateTime selectedDay;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final uid = ref.watch(currentUidProvider) ?? '';

    final selectedAsync = ref.watch(
      athleteDayInsightsProvider((uid: uid, day: selectedDay)),
    );

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
            'MÚSCULOS DEL DÍA',
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 12,
              letterSpacing: 1.2,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 14),
          selectedAsync.when(
            loading: () => const SizedBox(
              height: 240,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const SizedBox.shrink(),
            // [UX-back-view] `showBack: true` renders bodyfront + bodyback
            // side by side — that pair needs more horizontal room than the
            // old single-body 160px column had next to it. Stacked
            // (silhouettes full-width ABOVE the sets list) instead of the
            // old Row-beside-list layout, mirroring how home's
            // `EstaSemanaCard` lays out the same `showBack: true` silhouette
            // (full-width, own row, nothing beside it) — avoids a
            // RenderFlex overflow at narrow widths.
            data: (dayInsights) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                BodySilhouettePlaceholder(
                  width: double.infinity,
                  height: 220,
                  showBack: true,
                  setsByGroup: dayInsights.setsByGroup,
                  label: dayInsights.isEmpty ? l10n.insightsDayEmptyHint : null,
                ),
                const SizedBox(height: 14),
                for (final group in MuscleGroupDisplay.displayOrder)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: _MuscleSetsRow(
                      group: group,
                      sets: dayInsights.setsByGroup[group] ?? 0,
                    ),
                  ),
              ],
            ),
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

// ── ESTADÍSTICAS AVANZADAS heading + tile list (stats-hub, obs #445) ────────

/// Section heading above the tile list — same label style as the card
/// titles above it (SEMANA / MÚSCULOS DEL DÍA), just larger since it's a
/// section break rather than a card header.
class _AdvancedStatsHeading extends StatelessWidget {
  const _AdvancedStatsHeading();

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        l10n.insightsAdvancedStatsHeading,
        style: GoogleFonts.barlowCondensed(
          fontWeight: FontWeight.w700,
          fontSize: 16,
          letterSpacing: 1.0,
          color: palette.textPrimary,
        ),
      ),
    );
  }
}

/// [stats-hub][REQ:445] Hevy "Statistics" tile list — replaces the inline
/// radar/volume sections that used to live directly on this screen. Each
/// tile opens a DEDICATED full screen (see obs #445): Distribución
/// muscular, Ejercicios frecuentes (athlete's own uid), Reporte mensual,
/// Volumen por grupo.
class _StatsHubTileList extends StatelessWidget {
  const _StatsHubTileList();

  @override
  Widget build(BuildContext context) {
    final l10n = AppL10n.of(context);
    return Column(
      children: [
        _StatTile(
          icon: TreinoIcon.chartBar,
          title: l10n.insightsTileMuscleDistributionTitle,
          subtitle: l10n.insightsTileMuscleDistributionSubtitle,
          onTap: () => context.push('/home/insights/muscle-distribution'),
        ),
        const SizedBox(height: 12),
        _StatTile(
          icon: TreinoIcon.dumbbell,
          title: l10n.insightsTileFrequentExercisesTitle,
          subtitle: l10n.insightsTileFrequentExercisesSubtitle,
          onTap: () => context.push('/home/insights/frequent-exercises'),
        ),
        const SizedBox(height: 12),
        _StatTile(
          icon: TreinoIcon.calendar,
          title: l10n.insightsMonthlyReportTile,
          subtitle: l10n.insightsTileMonthlyReportSubtitle,
          onTap: () => context.push('/home/insights/monthly'),
        ),
        const SizedBox(height: 12),
        _StatTile(
          icon: TreinoIcon.scales,
          title: l10n.insightsTileVolumeByGroupTitle,
          subtitle: l10n.insightsTileVolumeByGroupSubtitle,
          onTap: () => context.push('/home/insights/volume-by-group'),
        ),
      ],
    );
  }
}

/// Single row in the "ESTADÍSTICAS AVANZADAS" tile list — icon + title +
/// one-line subtitle + trailing chevron (Hevy "Statistics" row parity).
class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    // TREINO Motion PR3: TreinoTappable reemplaza al GestureDetector — el
    // scale de presión es el feedback del tile (no había ripple que perder).
    return TreinoTappable(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(20),
        ),
        padding: const EdgeInsets.all(18),
        child: Row(
          children: [
            Icon(icon, color: palette.accent, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      letterSpacing: 0.6,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.barlow(
                      fontWeight: FontWeight.w400,
                      fontSize: 12,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
            ),
            Icon(TreinoIcon.forward, color: palette.textMuted, size: 18),
          ],
        ),
      ),
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
