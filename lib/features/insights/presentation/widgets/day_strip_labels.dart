import 'package:flutter/foundation.dart';

/// [AD5] Plain-String label bag for [DayStripNavigator] — same
/// AppL10n-free-widget pattern as `ChartPeriodLabels`
/// (`exercise_progression_section.dart`, PR1c) so the widget itself has zero
/// AppL10n coupling and both coach shells (mobile AppL10n-resolving / web
/// hardcoded-Spanish) can supply their own strings.
@immutable
class DayStripLabels {
  const DayStripLabels({
    required this.todayLabel,
    required this.emptyDayHint,
    required this.weekdayLetters,
  });

  /// Shown under the tile representing today (instead of the weekday letter).
  final String todayLabel;

  /// Shown when the selected day has no finished session (blank silhouette).
  final String emptyDayHint;

  /// Mon..Sun single-letter weekday labels, indexed by `weekday -
  /// DateTime.monday`. [DayStripNavigator] is AppL10n-free (R3) — the caller
  /// must compute these (e.g. via `weekdayInitials(localeName)` from
  /// `core/utils/date_labels.dart`) and inject them here.
  final List<String> weekdayLetters;
}
