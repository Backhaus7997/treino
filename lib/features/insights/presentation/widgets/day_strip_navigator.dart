import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../../app/theme/app_palette.dart';
import '../../../../core/widgets/treino_icon.dart';
import '../../domain/day_insights.dart';
import 'day_strip_labels.dart';

/// [AD5][REQ:heat-map-per-day] Hevy-style "last 7 days" day-strip. One tile
/// per day (oldest first, today last) — tapping a tile selects that day's
/// [DayInsights] for the heat-map above it. Trained days show a filled
/// check; the selected day is outlined in `palette.accent`; today (when not
/// selected/trained) shows [DayStripLabels.todayLabel] instead of the
/// weekday letter.
///
/// AppL10n-free by design (same pattern as `ChartPeriodSelector` from PR1c) —
/// both coach shells inject their own [DayStripLabels].
class DayStripNavigator extends StatelessWidget {
  const DayStripNavigator({
    super.key,
    required this.days,
    required this.selectedDay,
    required this.onDaySelected,
    required this.labels,
  });

  /// Exactly 7 entries, oldest first, today last — see
  /// `athleteLast7DaysInsightsProvider`.
  final List<DayInsights> days;

  /// The currently selected day (calendar day, time-of-day ignored).
  final DateTime selectedDay;

  final ValueChanged<DateTime> onDaySelected;
  final DayStripLabels labels;

  static const _weekdayLettersEs = ['L', 'M', 'M', 'J', 'V', 'S', 'D'];

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    return SizedBox(
      height: 64,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          for (final dayInsights in days)
            _DayTile(
              key: ValueKey(dayInsights.day),
              day: dayInsights.day,
              trained: !dayInsights.isEmpty,
              isToday: dayInsights.day == todayOnly,
              isSelected: dayInsights.day == _dateOnly(selectedDay),
              weekdayLetter:
                  _weekdayLettersEs[dayInsights.day.weekday - DateTime.monday],
              todayLabel: labels.todayLabel,
              palette: palette,
              onTap: () => onDaySelected(dayInsights.day),
            ),
        ],
      ),
    );
  }

  static DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);
}

class _DayTile extends StatelessWidget {
  const _DayTile({
    super.key,
    required this.day,
    required this.trained,
    required this.isToday,
    required this.isSelected,
    required this.weekdayLetter,
    required this.todayLabel,
    required this.palette,
    required this.onTap,
  });

  final DateTime day;
  final bool trained;
  final bool isToday;
  final bool isSelected;
  final String weekdayLetter;
  final String todayLabel;
  final AppPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final circleColor = trained ? palette.accent : Colors.transparent;
    final borderColor = isSelected
        ? palette.accent
        : (trained ? palette.accent : palette.border);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isToday ? todayLabel : weekdayLetter,
            style: GoogleFonts.barlow(
              fontWeight: FontWeight.w400,
              fontSize: 11,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: circleColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: borderColor,
                width: isSelected ? 2 : 1,
              ),
            ),
            alignment: Alignment.center,
            child: trained
                ? Icon(
                    TreinoIcon.checkCircleFill,
                    color: palette.bg,
                    size: 16,
                  )
                : Text(
                    '${day.day}',
                    style: GoogleFonts.barlowCondensed(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: palette.textMuted,
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
