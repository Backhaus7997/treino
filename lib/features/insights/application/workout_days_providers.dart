import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/streak_calculator.dart';
import '../../workout/application/session_providers.dart';
import '../domain/workout_days_month.dart';
import 'workout_days_aggregator.dart';

/// [AD6] Family key for [athleteWorkoutDaysProvider]. Explicit [uid] (NOT
/// `currentUidProvider`) so the same provider can later serve a coach-side
/// surfacing of the calendar too, same pattern as
/// [athleteMonthlyReportProvider]/`athleteDayInsightsProvider`.
typedef AthleteWorkoutDaysKey = ({String uid, DateTime month});

/// [AD6] Trained-days-in-month + current streak for [key.uid], backing
/// [WorkoutDaysCalendar] (PR5b — Hevy "Workout Days Log" parity).
///
/// Reads the FULL session list via [sessionRepositoryProvider] (`listByUid`)
/// — same convention as `athleteMonthlyReportProvider` — since both
/// `trainedDaysInMonth` and `computeStreak` need the complete history, not a
/// capped/paged scan.
///
/// autoDispose: refreshes when the calendar section is re-mounted or the
/// selected month changes (family key includes [AthleteWorkoutDaysKey.month]).
final athleteWorkoutDaysProvider = FutureProvider.autoDispose
    .family<WorkoutDaysMonth, AthleteWorkoutDaysKey>((ref, key) async {
  if (key.uid.isEmpty) {
    return WorkoutDaysMonth(
      month: DateTime(key.month.year, key.month.month),
      trainedDays: const {},
      streak: 0,
    );
  }

  final repo = ref.watch(sessionRepositoryProvider);
  final sessions = await repo.listByUid(key.uid);

  return WorkoutDaysMonth(
    month: DateTime(key.month.year, key.month.month),
    trainedDays: trainedDaysInMonth(sessions, key.month),
    streak: computeStreak(sessions),
  );
});
