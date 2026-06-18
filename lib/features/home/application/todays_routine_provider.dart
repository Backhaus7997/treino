import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/assigned_routine_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider, sessionsByUidProvider;
import '../../workout/application/user_routines_providers.dart';
import '../../workout/domain/routine.dart';
import '../../workout/domain/routine_day.dart';
import '../../workout/domain/session.dart';
import '../../workout/domain/session_status.dart';
import 'active_routine_provider.dart';

/// Resolved "what to train today" snapshot for the home `EmpezarEntrenamientoCard`.
///
/// Pure data record — UI computes display strings (heroLabel, muscle subtitle,
/// duration, exercise count) from these fields via the domain helpers.
typedef TodaysRoutine = ({
  Routine routine,
  RoutineDay day,
  int dayNumber, // 1-based, matches RoutineDay.dayNumber
  int weekNumber, // 0-based, advances on day rollover for periodized plans
});

/// Resolves the routine + day the athlete should train next, applying the
/// priority + progress-based day calculation we agreed on in the home card
/// redesign (decision log 2026-06-18):
///
///   PRIORITY
///   1. Trainer-assigned plan (any in `assignedRoutinesProvider`). Picks
///      the newest if multiple — repo already orders desc by `createdAt`.
///   2. Single self-created routine (`userCreatedRoutinesProvider.length == 1`).
///   3. Multi self-created → the routine marked as active in
///      `UserProfile.activeRoutineId`. PR#2 (active-routine marker).
///   4. Returns null — multi-rutina without an active marker. Home falls
///      back to the empty CTA + nudges the user to mark one via
///      MisRutinasSection overflow menu.
///
///   DAY CALCULATION (progress-based)
///   * Looks at the latest FINISHED session for the resolved routine.
///   * nextDayNumber = (lastDayNumber % numDays) + 1 — rolls Día 5 → Día 1.
///   * weekNumber rolls only when day wraps: stays on the same week as long
///     as `lastDayNumber < numDays`; advances to `(lastWeek + 1) % numWeeks`
///     on rollover. First session ever: dayNumber 1, weekNumber 0.
///
///   SKIPPED DAYS
///   * Pure last-completed + 1. If the athlete skips Día 2 and only ever
///     does Día 1 and Día 3, the next will be Día 4 — not the missed Día 2.
///     Matches Hevy/Strong, intuitive for users who occasionally miss days.
///     Manual override still available via the day selector in routine_detail.
///
/// Returns null when:
///   * uid is empty/unauthenticated
///   * No routine matches the priority chain
///   * Resolved routine has no days (defensive)
final todaysRoutineProvider = FutureProvider.autoDispose<TodaysRoutine?>(
  (ref) async {
    final uid = ref.watch(currentUidProvider) ?? '';
    if (uid.isEmpty) return null;

    // Tier 1: trainer-assigned plan wins.
    final assigned = await ref.watch(assignedRoutinesProvider(uid).future);
    Routine? routine;
    if (assigned.isNotEmpty) {
      routine = assigned.first;
    } else {
      final selfCreated =
          await ref.watch(userCreatedRoutinesProvider(uid).future);
      if (selfCreated.length == 1) {
        // Tier 2: single self-created routine auto-activates — no manual
        // marker needed when there's nothing to disambiguate.
        routine = selfCreated.first;
      } else if (selfCreated.length > 1) {
        // Tier 3: multi self-created → require an explicit active marker
        // (PR#2). [activeRoutineProvider] already validates the id against
        // the live user-created list; a stale pointer (routine archived/
        // deleted) resolves to null and the home falls back to the empty CTA.
        routine = ref.watch(activeRoutineProvider);
      }
    }

    if (routine == null || routine.days.isEmpty) return null;

    // Find the most recent FINISHED session for THIS routine (sessions are
    // already ordered startedAt desc by the repo).
    final sessions = await ref.watch(sessionsByUidProvider(uid).future);
    Session? lastFinished;
    for (final s in sessions) {
      if (s.routineId == routine.id && s.status == SessionStatus.finished) {
        lastFinished = s;
        break;
      }
    }

    final numDays = routine.days.length;
    final int nextDayNumber;
    final int weekNumber;
    if (lastFinished == null) {
      // First session ever for this routine.
      nextDayNumber = 1;
      weekNumber = 0;
    } else {
      nextDayNumber = (lastFinished.dayNumber % numDays) + 1;
      // Week rolls over only when day wraps. numWeeks defaults to 1 so the
      // modulo is a no-op for non-periodized plans.
      final rolledOver = lastFinished.dayNumber >= numDays;
      weekNumber = rolledOver
          ? (lastFinished.weekNumber + 1) % routine.numWeeks
          : lastFinished.weekNumber;
    }

    // Resolve the RoutineDay. Defensive against non-contiguous dayNumbers
    // (shouldn't happen, but a hand-edited Firestore doc could).
    RoutineDay? day;
    for (final d in routine.days) {
      if (d.dayNumber == nextDayNumber) {
        day = d;
        break;
      }
    }
    day ??= routine.days.first;

    return (
      routine: routine,
      day: day,
      dayNumber: nextDayNumber,
      weekNumber: weekNumber,
    );
  },
);
