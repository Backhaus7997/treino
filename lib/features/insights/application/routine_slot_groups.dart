import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/routine_providers.dart';
import '../../workout/domain/session.dart';

/// [#442] Shared exerciseId → muscleGroup slot fallback for the Insights
/// aggregators (weekly aggregate, muscle distribution radar, month radar).
/// Resolves EVERY distinct routine referenced by [sessions] and folds their
/// slots' denormalized `muscleGroup` into one lookup map — the only source of
/// the group for custom exercises, which are NOT in the public catalog (their
/// setLogs only carry exerciseId).
///
/// Per-session resolution, never "the most-recent session's routine": any
/// window (week/period/month) can span multiple routines — the athlete
/// switched plans mid-window, or the caller paged into weeks logged under a
/// since-replaced routine — and assuming a single routine silently drops the
/// other routines' custom-exercise sets from the aggregate. That drop is
/// exactly how the SEMANA card diverged from the muscle distribution radar
/// (#442); every consumer now shares this resolver so the surfaces cannot
/// drift again.
///
/// [sessions] must be ordered newest-first (the callers' listByUid DESC
/// contract): when two routines denormalize DIFFERENT groups for the same
/// exerciseId, `putIfAbsent` keeps the newest session's routine, so all
/// consumers resolve conflicts identically.
///
/// [visibleRoutineByIdProvider], NOT [routineByIdProvider]: the resolved ids
/// can reach routines that are gone (deleted, or a trainer-template whose
/// owner revoked athlete sharing), and those reads come back as errors. An
/// unguarded `Future.wait` would propagate the first one and fail the WHOLE
/// aggregate because of one stale session. The slot fallback is best-effort
/// (the public catalog already resolves every non-custom exercise), so a
/// routine that is gone degrades to "no slot fallback for ITS exercises".
///
/// It does NOT swallow transient failures: those still propagate and surface
/// the consumer screen's error state. Silently treating a network blip as
/// "no routine" would drop custom-exercise sets from the aggregate with no
/// error shown — a wrong chart is worse than a visible error.
Future<Map<String, String>> slotMuscleGroupsForSessions(
  Ref ref,
  Iterable<Session> sessions,
) async {
  final distinctRoutineIds =
      sessions.map((s) => s.routineId).toSet().where((id) => id.isNotEmpty);
  final routines = await Future.wait(
    distinctRoutineIds
        .map((id) => ref.watch(visibleRoutineByIdProvider(id).future)),
  );
  final slotGroupById = <String, String>{};
  for (final routine in routines) {
    if (routine == null) continue;
    for (final day in routine.days) {
      for (final slot in day.slots) {
        slotGroupById.putIfAbsent(slot.exerciseId, () => slot.muscleGroup);
      }
    }
  }
  return slotGroupById;
}
