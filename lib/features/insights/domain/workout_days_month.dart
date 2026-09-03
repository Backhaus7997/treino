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
/// [streak] is the CURRENT streak in SEMANAS — semanas consecutivas en las
/// que el atleta cumplió el objetivo de días de su rutina activa, calculada
/// con `computeWeeklyStreak`. Mismo valor que se muestra en el resto de la app
/// (home/perfil), NO re-derivado. La semana en curso no la corta: mientras no
/// termine, no fracasó. It is independent of
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
