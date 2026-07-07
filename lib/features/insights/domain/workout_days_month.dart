import 'package:freezed_annotation/freezed_annotation.dart';

part 'workout_days_month.freezed.dart';

/// [AD6] Data backing [WorkoutDaysCalendar] for a single calendar [month] —
/// the set of trained days plus the athlete's current week-streak (Hevy
/// "Workout Days Log" parity).
///
/// [trainedDays] holds local calendar dates (time-of-day truncated) within
/// [month] on which at least one finished session was recorded — see
/// `trainedDaysInMonth`.
///
/// [streak] is the CURRENT streak (consecutive trained days ending today or
/// yesterday), computed via the shared `computeStreak` — same value shown
/// elsewhere in the app (home/profile), NOT re-derived. It is independent of
/// [month] (e.g. selecting a past month in the report still shows today's
/// live streak, matching Hevy's behavior of the streak badge being a
/// standalone indicator, not scoped to the viewed month). Zero is a valid,
/// explicitly-rendered value — not hidden.
@freezed
class WorkoutDaysMonth with _$WorkoutDaysMonth {
  const factory WorkoutDaysMonth({
    required DateTime month,
    required Set<DateTime> trainedDays,
    required int streak,
  }) = _WorkoutDaysMonth;
}
