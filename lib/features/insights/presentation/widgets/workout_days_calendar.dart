// IMPORTANT: This widget MUST NOT import app_l10n.dart — same
// AppL10n-free-widget convention as MonthlyReportChart/DayStripNavigator.
// All user-visible strings are injected via [WorkoutDaysCalendarLabels].

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../domain/workout_days_month.dart';

// ── Label bag ─────────────────────────────────────────────────────────────────

/// Plain-string label bag for [WorkoutDaysCalendar] — mirrors the
/// [DayStripLabels]/[MonthlyReportChartLabels] convention.
@immutable
class WorkoutDaysCalendarLabels {
  const WorkoutDaysCalendarLabels({
    required this.streakLabelBuilder,
    this.weekdayLetters = const ['L', 'M', 'M', 'J', 'V', 'S', 'D'],
  });

  /// Builds the streak line's full text from the current streak value, e.g.
  /// `(n) => 'Racha de $n días'`. Zero is a valid input — must be rendered,
  /// not treated as a signal to hide the row.
  final String Function(int streak) streakLabelBuilder;

  /// Mon..Sun single-letter column headers. Defaults to Spanish letters
  /// (same set as [DayStripNavigator]'s `_weekdayLettersEs`) since the app
  /// is currently locked to es-AR — callers may override for future
  /// locales.
  final List<String> weekdayLetters;
}

// ── Public widget ───────────────────────────────────────────────────────────

/// [AD6][REQ:workout-days-calendar] Month calendar grid (Mon-Sun columns,
/// one row per week) marking trained days, plus a week-streak indicator row
/// (flame icon + streak text) — Hevy "Workout Days Log" parity (PR5b).
///
/// Pure layout from [data] — day-bucketing itself happens upstream in
/// `trainedDaysInMonth`/`computeStreak` (via `athleteWorkoutDaysProvider`),
/// this widget only renders the grid. Days outside [data.month] (leading/
/// trailing blanks needed to complete the first/last week row) render as
/// empty cells — never a day number from an adjacent month, to avoid
/// implying they belong to the displayed month.
class WorkoutDaysCalendar extends StatelessWidget {
  const WorkoutDaysCalendar({
    super.key,
    required this.data,
    required this.labels,
  });

  final WorkoutDaysMonth data;
  final WorkoutDaysCalendarLabels labels;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final weeks = _weeksOf(data.month);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StreakRow(streak: data.streak, labels: labels, palette: palette),
          const SizedBox(height: 14),
          _WeekdayHeaderRow(letters: labels.weekdayLetters, palette: palette),
          const SizedBox(height: 8),
          for (final week in weeks) ...[
            _WeekRow(
              days: week,
              trainedDays: data.trainedDays,
              palette: palette,
            ),
            const SizedBox(height: 8),
          ],
        ],
      ),
    );
  }

  /// Splits [month] into Mon-Sun week rows (each exactly 7 cells). Cells
  /// outside the month (leading days before day 1, trailing days after the
  /// last day) are `null` — rendered as blank cells by [_WeekRow].
  static List<List<DateTime?>> _weeksOf(DateTime month) {
    final anchor = DateTime(month.year, month.month);
    final daysInMonth = DateTime(anchor.year, anchor.month + 1, 0).day;

    // ISO weekday: Monday=1..Sunday=7. Leading blanks = days between the
    // grid's Monday column and day 1's actual weekday.
    final leadingBlanks = anchor.weekday - DateTime.monday;

    final cells = <DateTime?>[
      for (var i = 0; i < leadingBlanks; i++) null,
      for (var d = 1; d <= daysInMonth; d++)
        DateTime(anchor.year, anchor.month, d),
    ];

    // Pad the final week row to a full 7 cells with trailing blanks.
    final trailingBlanks = (7 - (cells.length % 7)) % 7;
    for (var i = 0; i < trailingBlanks; i++) {
      cells.add(null);
    }

    return [
      for (var i = 0; i < cells.length; i += 7) cells.sublist(i, i + 7),
    ];
  }
}

// ── Streak row ────────────────────────────────────────────────────────────────

class _StreakRow extends StatelessWidget {
  const _StreakRow({
    required this.streak,
    required this.labels,
    required this.palette,
  });

  final int streak;
  final WorkoutDaysCalendarLabels labels;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(TreinoIcon.streak, size: 20, color: palette.highlight),
        const SizedBox(width: 8),
        Text(
          labels.streakLabelBuilder(streak),
          style: GoogleFonts.barlowCondensed(
            fontWeight: FontWeight.w700,
            fontSize: 16,
            letterSpacing: 0.4,
            color: palette.textPrimary,
          ),
        ),
      ],
    );
  }
}

// ── Weekday header row ───────────────────────────────────────────────────────

class _WeekdayHeaderRow extends StatelessWidget {
  const _WeekdayHeaderRow({required this.letters, required this.palette});

  final List<String> letters;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final letter in letters)
          Expanded(
            child: Center(
              child: Text(
                letter,
                style: GoogleFonts.barlowCondensed(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: palette.textMuted,
                ),
              ),
            ),
          ),
      ],
    );
  }
}

// ── Week row ──────────────────────────────────────────────────────────────────

class _WeekRow extends StatelessWidget {
  const _WeekRow({
    required this.days,
    required this.trainedDays,
    required this.palette,
  });

  /// Exactly 7 entries, Mon..Sun. `null` = blank cell (outside the month).
  final List<DateTime?> days;
  final Set<DateTime> trainedDays;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (var i = 0; i < days.length; i++)
          Expanded(
            child: days[i] == null
                ? SizedBox(
                    key: ValueKey('workout-day-blank-leading-$i'),
                    height: 32,
                  )
                : _DayCell(
                    day: days[i]!,
                    trained: trainedDays.contains(days[i]),
                    palette: palette,
                  ),
          ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell(
      {required this.day, required this.trained, required this.palette});

  final DateTime day;
  final bool trained;
  final AppPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        key: trained ? const ValueKey('workout-day-trained') : null,
        width: 32,
        height: 32,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: trained ? palette.accent : Colors.transparent,
          shape: BoxShape.circle,
        ),
        child: Text(
          '${day.day}',
          style: GoogleFonts.barlow(
            fontSize: 13,
            fontWeight: trained ? FontWeight.w700 : FontWeight.w500,
            color: trained ? palette.bg : palette.textPrimary,
          ),
        ),
      ),
    );
  }
}
