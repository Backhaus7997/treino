import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart' as intl;

import '../../../app/theme/app_palette.dart';
import '../../../core/widgets/treino_icon.dart';
import '../../../l10n/app_l10n.dart';
import '../application/month_radar_providers.dart';
import '../application/monthly_report_providers.dart';
import '../application/workout_days_providers.dart';
import '../domain/monthly_report.dart';
import 'widgets/monthly_report_chart.dart';
import 'widgets/monthly_report_summary_cards.dart';
import 'widgets/muscle_distribution_radar.dart';
import 'widgets/workout_days_calendar.dart';

/// Monthly Report screen (Hevy "June Report" parity, AD6/PR5a) — 12-month
/// bar chart + metric tabs + summary cards for the selected month, the
/// workout-days streak calendar (AD6/PR5b), and the month-vs-month muscle
/// distribution radar (AD6/PR5c).
///
/// [uid] is explicit (not read from [currentUidProvider]) so this screen can
/// later be reused for coach-side surfacing without change, same pattern as
/// [athleteMonthlyReportProvider].
class MonthlyReportScreen extends ConsumerStatefulWidget {
  const MonthlyReportScreen({super.key, required this.uid});

  final String uid;

  @override
  ConsumerState<MonthlyReportScreen> createState() =>
      _MonthlyReportScreenState();
}

class _MonthlyReportScreenState extends ConsumerState<MonthlyReportScreen> {
  /// Defaults to the last (most recent/current) month once the report
  /// loads — set on first successful data emission.
  DateTime? _selectedMonth;
  _MonthlyReportGranularity _granularity = _MonthlyReportGranularity.month;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final async = ref.watch(athleteMonthlyReportProvider(widget.uid));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Header(title: l10n.monthlyReportTitle),
        Expanded(
          child: async.when(
            loading: () => Center(
              child: CircularProgressIndicator(color: palette.accent),
            ),
            error: (_, __) => _ErrorState(
              message: l10n.monthlyReportLoadError,
              retryLabel: l10n.coachRetryLabel,
              onRetry: () => ref.invalidate(
                athleteMonthlyReportProvider(widget.uid),
              ),
            ),
            data: (report) {
              final selectedMonth = _resolveSelectedMonth(report);
              final selectedPoint = report.points.firstWhere(
                (p) => p.month == selectedMonth,
                orElse: () => report.points.last,
              );
              final previousPoint = _previousPointFor(report, selectedPoint);

              return ListView(
                padding: EdgeInsets.fromLTRB(
                    20, 12, 20, 20 + MediaQuery.paddingOf(context).bottom),
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  Text(
                    _monthTitle(selectedPoint.month, l10n.localeName),
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w700,
                      fontSize: 20,
                      letterSpacing: 0.6,
                      color: palette.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _GranularitySwitch(
                    selected: _granularity,
                    monthLabel: l10n.monthlyReportByMonthLabel,
                    dayLabel: l10n.monthlyReportByDayLabel,
                    onSelect: (value) => setState(() => _granularity = value),
                  ),
                  const SizedBox(height: 12),
                  if (_granularity == _MonthlyReportGranularity.month)
                    MonthlyReportChart(
                      report: report,
                      labels: MonthlyReportChartLabels(
                        workoutsLabel: l10n.monthlyReportMetricWorkouts,
                        durationLabel: l10n.monthlyReportMetricDuration,
                        volumeLabel: l10n.monthlyReportMetricVolume,
                        setsLabel: l10n.monthlyReportMetricSets,
                        emptyHint: l10n.monthlyReportEmptyHint,
                      ),
                      localeName: l10n.localeName,
                      onMonthSelected: (m) =>
                          setState(() => _selectedMonth = m),
                    )
                  else
                    _DailyDurationSection(
                      uid: widget.uid,
                      month: selectedPoint.month,
                      emptyHint: l10n.monthlyReportDailyEmptyHint,
                    ),
                  const SizedBox(height: 14),
                  MonthlyReportSummaryCards(
                    selectedMonth: selectedPoint,
                    previousMonth: previousPoint,
                    labels: MonthlyReportSummaryLabels(
                      workoutsLabel: l10n.monthlyReportMetricWorkouts,
                      durationLabel: l10n.monthlyReportMetricDuration,
                      volumeLabel: l10n.monthlyReportMetricVolume,
                      setsLabel: l10n.monthlyReportMetricSets,
                      durationUnit: l10n.monthlyReportDurationHoursUnit,
                      volumeUnit: l10n.monthlyReportVolumeUnit,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _WorkoutDaysSection(
                    uid: widget.uid,
                    month: selectedPoint.month,
                    l10n: l10n,
                  ),
                  const SizedBox(height: 14),
                  // [AD6/PR5c] Month-vs-month muscle distribution radar —
                  // reuses MuscleDistributionRadar with a calendar-month
                  // window anchored at the selected month (Hevy "June
                  // Report" Muscle Distribution section).
                  _MonthRadarSection(
                    uid: widget.uid,
                    month: selectedPoint.month,
                    l10n: l10n,
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  DateTime _resolveSelectedMonth(MonthlyReport report) {
    final selected = _selectedMonth;
    if (selected != null && report.points.any((p) => p.month == selected)) {
      return selected;
    }
    return report.points.last.month;
  }

  MonthlyReportPoint? _previousPointFor(
    MonthlyReport report,
    MonthlyReportPoint selected,
  ) {
    final index = report.points.indexOf(selected);
    if (index <= 0) return null;
    return report.points[index - 1];
  }
}

enum _MonthlyReportGranularity { month, day }

void _safePopOrInsights(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go('/home/insights');
  }
}

String _monthTitle(DateTime month, String localeName) {
  final formatted = intl.DateFormat('MMMM yyyy', localeName).format(month);
  return formatted.isEmpty
      ? formatted
      : formatted[0].toUpperCase() + formatted.substring(1);
}

// ── Granularity switch ───────────────────────────────────────────────────────

class _GranularitySwitch extends StatelessWidget {
  const _GranularitySwitch({
    required this.selected,
    required this.monthLabel,
    required this.dayLabel,
    required this.onSelect,
  });

  final _MonthlyReportGranularity selected;
  final String monthLabel;
  final String dayLabel;
  final ValueChanged<_MonthlyReportGranularity> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);

    return Row(
      children: [
        _GranularityButton(
          label: monthLabel,
          isSelected: selected == _MonthlyReportGranularity.month,
          palette: palette,
          onTap: () => onSelect(_MonthlyReportGranularity.month),
        ),
        const SizedBox(width: 8),
        _GranularityButton(
          label: dayLabel,
          isSelected: selected == _MonthlyReportGranularity.day,
          palette: palette,
          onTap: () => onSelect(_MonthlyReportGranularity.day),
        ),
      ],
    );
  }
}

class _GranularityButton extends StatelessWidget {
  const _GranularityButton({
    required this.label,
    required this.isSelected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool isSelected;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? palette.accent : palette.bgCard,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? palette.accent : palette.border,
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 12,
            letterSpacing: 0.8,
            color: isSelected ? palette.bg : palette.textMuted,
          ),
        ),
      ),
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

// ── Workout-days streak calendar section ─────────────────────────────────────

/// [AD6/PR5b] Loads [athleteWorkoutDaysProvider] for [uid]/[month] and
/// renders [WorkoutDaysCalendar]. Re-fetches whenever [month] changes (the
/// selected bar in [MonthlyReportChart] above), via the provider's family
/// key — same re-fetch-on-selection pattern as the summary cards.
class _WorkoutDaysSection extends ConsumerWidget {
  const _WorkoutDaysSection({
    required this.uid,
    required this.month,
    required this.l10n,
  });

  final String uid;
  final DateTime month;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(
      athleteWorkoutDaysProvider((uid: uid, month: month)),
    );

    return async.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: CircularProgressIndicator(color: palette.accent),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (data) => WorkoutDaysCalendar(
        data: data,
        labels: WorkoutDaysCalendarLabels(
          streakLabelBuilder: l10n.workoutDaysCalendarStreak,
        ),
      ),
    );
  }
}

class _DailyDurationSection extends ConsumerWidget {
  const _DailyDurationSection({
    required this.uid,
    required this.month,
    required this.emptyHint,
  });

  final String uid;
  final DateTime month;
  final String emptyHint;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final l10n = AppL10n.of(context);
    final async = ref.watch(
      athleteDailyDurationReportProvider((uid: uid, month: month)),
    );

    return async.when(
      loading: () => Container(
        height: 228,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.bgCard,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: palette.border),
        ),
        child: CircularProgressIndicator(color: palette.accent),
      ),
      error: (_, __) => DailyDurationChart(
        points: const [],
        emptyHint: emptyHint,
        dayLabel: l10n.monthlyReportDailyTooltipDayLabel,
        minutesUnit: l10n.monthlyReportDurationUnit,
      ),
      data: (points) => DailyDurationChart(
        points: points,
        emptyHint: emptyHint,
        dayLabel: l10n.monthlyReportDailyTooltipDayLabel,
        minutesUnit: l10n.monthlyReportDurationUnit,
      ),
    );
  }
}

// ── Month-vs-month muscle distribution radar section ─────────────────────────

/// [AD6/PR5c] Loads [athleteMonthRadarInsightsProvider] for [uid]/[month]
/// and renders [MuscleDistributionRadar] with month-name legend labels
/// (e.g. "May 2026" / "Jun 2026") instead of the generic "Actual"/"Anterior"
/// pair the athlete-insights radar uses — same widget, different labels,
/// per the shared-widget dedup invariant (AD1/spec requirement 11).
///
/// Re-fetches whenever [month] changes (the selected bar in
/// [MonthlyReportChart] above), same re-fetch-on-selection pattern as
/// [_WorkoutDaysSection].
class _MonthRadarSection extends ConsumerWidget {
  const _MonthRadarSection({
    required this.uid,
    required this.month,
    required this.l10n,
  });

  final String uid;
  final DateTime month;
  final AppL10n l10n;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = AppPalette.of(context);
    final async = ref.watch(
      athleteMonthRadarInsightsProvider((uid: uid, month: month)),
    );

    return async.when(
      loading: () => Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Center(
          child: CircularProgressIndicator(color: palette.accent),
        ),
      ),
      error: (_, __) => const SizedBox.shrink(),
      data: (insights) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.muscleDistributionSectionTitle,
            style: GoogleFonts.barlowCondensed(
              fontWeight: FontWeight.w700,
              fontSize: 16,
              letterSpacing: 0.8,
              color: palette.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          MuscleDistributionRadar(
            insights: insights,
            labels: MuscleDistributionLabels(
              currentLabel: _monthLegendLabel(month, l10n.localeName),
              previousLabel: _monthLegendLabel(
                DateTime(month.year, month.month - 1, 1),
                l10n.localeName,
              ),
              emptyStateText: l10n.muscleDistributionEmptyState,
              workoutsLabel: l10n.muscleDistributionWorkoutsLabel,
              durationLabel: l10n.muscleDistributionDurationLabel,
              volumeLabel: l10n.muscleDistributionVolumeLabel,
              setsLabel: l10n.muscleDistributionSetsLabel,
              durationUnit: l10n.monthlyReportDurationUnit,
              volumeUnit: l10n.monthlyReportVolumeUnit,
            ),
          ),
        ],
      ),
    );
  }
}

/// Short month-name legend label, e.g. "May 2026" / "Jun 2026" — Capitalized
/// first letter (intl lower-cases month abbreviations by default), same
/// capitalize-first-letter convention as [_monthTitle].
String _monthLegendLabel(DateTime month, String localeName) {
  final formatted = intl.DateFormat('MMM yyyy', localeName).format(month);
  return formatted.isEmpty
      ? formatted
      : formatted[0].toUpperCase() + formatted.substring(1);
}

// ── Error state ───────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.retryLabel,
    required this.onRetry,
  });

  final String message;
  final String retryLabel;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.barlow(fontSize: 14, color: palette.textMuted),
            ),
            const SizedBox(height: 8),
            TextButton(onPressed: onRetry, child: Text(retryLabel)),
          ],
        ),
      ),
    );
  }
}
