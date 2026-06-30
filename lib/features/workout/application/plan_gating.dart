// Gating pure functions for periodized routines (Model B).
//
// All functions are top-level and stateless. week is 0-based; day is 1-based
// (matching RoutineDay.dayNumber).
//
// HISTORICAL CONTEXT (and current policy):
//
// The original Model B (Phase 2 periodized routines) enforced a strict
// sequential gate: a day was startable only if every prior day of its week
// was completed AND every prior week was fully done. The intent was to
// preserve the coach's progressive overload plan — a periodized fuerza block
// is designed assuming Week N is finished before Week N+1.
//
// Reality contradicted that intent: athletes miss gym days (or arrive on a
// day not feeling pecho, want to do espalda) and the lock turned the editor
// into a wall ("DÍA BLOQUEADO" / "SEMANA BLOQUEADA"). The single-week plan
// already bypassed the gate (REQ-PERIOD-042) — multi-week behaviour was the
// only place where the wall lived.
//
// Decision A1 (2026-06-29): drop the lock entirely for both periodized AND
// single-week plans. Every day of every week is always unlocked. The athlete
// is an adult and knows what they are doing; if they want to skip ahead, they
// skip ahead. The only signal we keep is "this day is already completed"
// (drives the "ENTRENADO" badge, not a hard lock).
//
// `isStartable` therefore reduces to "not already completed". `isDayUnlocked`
// and `isWeekUnlocked` are kept (returning constant true) so call sites that
// branch on them stay source-compatible — easier to delete the branches in a
// follow-up than to refactor 4 call sites in this PR.
//
// Phase 3 addition (REQ-WPRES-022): the optional [requiredPairs] parameter
// is preserved on every function for source compatibility, but it is no
// longer consulted by the unlock helpers (since they always return true).
// `isStartable` continues to ignore it as well — an "absent" day still maps
// to the same "not completed" branch.

import 'plan_progress.dart' show CompletedKey;

/// Always returns true (decision A1, 2026-06-29 — athlete can jump to any
/// week without finishing the previous one). Kept as a function so callers
/// that read its result for UI affordances stay source-compatible.
bool isWeekUnlocked(
  int week,
  Set<CompletedKey> completed,
  List<int> dayNumbers, {
  Set<CompletedKey>? requiredPairs,
}) =>
    true;

/// Always returns true (decision A1, 2026-06-29). See [isWeekUnlocked].
bool isDayUnlocked(
  int week,
  int day,
  Set<CompletedKey> completed,
  List<int> dayNumbers, {
  Set<CompletedKey>? requiredPairs,
}) =>
    true;

/// Returns true when the athlete can start the given (week, day).
///
/// A day is startable iff it is NOT already fully completed. The historical
/// "all prior days/weeks must be done" gate was removed — see file header.
bool isStartable(
  int week,
  int day,
  Set<CompletedKey> completed,
  List<int> dayNumbers, {
  Set<CompletedKey>? requiredPairs,
}) =>
    !completed.contains((week: week, day: day));
