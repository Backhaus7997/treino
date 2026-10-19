import 'dart:math' as math;

import 'routine.dart';
import 'routine_day.dart';
import 'routine_slot.dart';
import 'set_enums.dart';
import 'set_spec.dart';
import 'superset_blocks.dart';

/// Result of [estimateRoutineDayMinutes]. `null` minutes means nothing
/// measurable on the day (callers render a placeholder). [authored] is true
/// when the value came from `day.estimatedMinutes` (trainer/athlete set it
/// explicitly) and false when computed from the slots — callers typically
/// prefix computed values with "~" to read as an estimate.
typedef RoutineDayDuration = ({int? minutes, bool authored});

/// Seconds per rep when estimating the work time of a rep-based set.
const int kSecondsPerRep = 4;

/// Minimum work time of any set, in seconds. Includes getting set up (load,
/// position, unrack) so a 2-rep set is not estimated at 8 s (#1562).
const int kMinSetWorkSeconds = 25;

/// Rest between sets, in seconds, when the slot carries none (`restSeconds`
/// 0). The domain has no compound/isolation signal on a slot, so this is flat.
/// An authored rest (> 0) REPLACES this value — it is never added on top.
const int kDefaultRestSeconds = 75;

/// Extra seconds between two blocks (walk, change load/machine). A block is a
/// single exercise or a whole superset. Counted between blocks only: never
/// inside a superset and never after the last block.
const int kExerciseTransitionSeconds = 120;

/// Fixed general warm-up added once per day, in seconds (owner's decision on
/// #1562). Only added when the day has at least one set — an empty day stays
/// `null`, never "~5 min".
const int kDayWarmUpSeconds = 300;

/// Estimated total minutes to complete [day] in the given 0-based [week].
///
/// Priority:
///   1. Authored `day.estimatedMinutes` when present → returns it with
///      `authored: true`.
///   2. Otherwise, over the slots present in the week with at least one set,
///      grouped into BLOCKS by [supersetBlockIndices] (a lone exercise, or
///      contiguous slots sharing `supersetGroup`):
///      - work per set: the set's `durationSeconds` when positive, else
///        `max(reps × [kSecondsPerRep], [kMinSetWorkSeconds])` using
///        `reps ?? repsMax ?? repsMin ?? 12`;
///      - rest: one per ROUND of the block — `rounds - 1` rests, where rounds
///        is the longest member's set count — of the LAST slot's
///        `restSeconds` (or [kDefaultRestSeconds] when 0). No rest after the
///        last round. For a lone exercise a round is a set, so this is the
///        usual "rest between sets";
///      - a round made only of [SetType.warmup] sets rests half;
///      - [kExerciseTransitionSeconds] between consecutive blocks;
///      - [kDayWarmUpSeconds] once.
///      Rounded to the nearest minute → `authored: false`.
///   3. Returns `minutes: null` when nothing measurable is on the day.
///
/// Pure function — no Flutter imports, no providers, safe to use from both
/// presentation widgets and Riverpod providers.
RoutineDayDuration estimateRoutineDayMinutes(RoutineDay day, {int week = 0}) {
  if (day.estimatedMinutes != null) {
    return (minutes: day.estimatedMinutes, authored: true);
  }

  // Same order as the session player (`session_notifier.dart`): drop the
  // slots absent this week FIRST, then cut blocks. So the estimate describes
  // the session the athlete will actually get — including two supersets with
  // the same number that become contiguous once the exercise between them is
  // absent, which the player also runs as one block.
  final present = [
    for (final s in day.slots)
      if (s.isPresentInWeek(week)) s,
  ];
  final blocks = <List<({RoutineSlot slot, List<SetSpec> sets})>>[];
  for (final indices
      in supersetBlockIndices([for (final s in present) s.supersetGroup])) {
    final members = [
      for (final i in indices)
        (slot: present[i], sets: present[i].effectiveSetsForWeek(week)),
    ].where((m) => m.sets.isNotEmpty).toList();
    if (members.isNotEmpty) blocks.add(members);
  }
  if (blocks.isEmpty) return (minutes: null, authored: false);

  var seconds = kDayWarmUpSeconds;
  seconds += kExerciseTransitionSeconds * (blocks.length - 1);
  for (final block in blocks) {
    for (final m in block) {
      for (final s in m.sets) {
        seconds += _workSeconds(s);
      }
    }
    final last = block.last.slot;
    final rest = last.restSeconds > 0 ? last.restSeconds : kDefaultRestSeconds;
    final rounds = block.map((m) => m.sets.length).reduce(math.max);
    for (var round = 0; round < rounds - 1; round++) {
      final warmUpOnly = block.every(
        (m) => round >= m.sets.length || m.sets[round].type == SetType.warmup,
      );
      seconds += warmUpOnly ? rest ~/ 2 : rest;
    }
  }
  return (minutes: (seconds / 60).round(), authored: false);
}

int _workSeconds(SetSpec s) {
  final duration = s.durationSeconds;
  if (duration != null && duration > 0) return duration;
  return math.max(
    (s.reps ?? s.repsMax ?? s.repsMin ?? 12) * kSecondsPerRep,
    kMinSetWorkSeconds,
  );
}

/// Estimated minutes of ONE session of [routine] — what a card shows to answer
/// "how long is this going to take me today?" (#639).
///
/// Priority:
///   1. Authored `routine.estimatedMinutesPerDay` → `authored: true`.
///   2. Otherwise the AVERAGE of [estimateRoutineDayMinutes] over the days
///      that yield a value. `authored` stays true only when every counted day
///      was itself authored — one computed day makes the whole figure an
///      estimate, and the UI must say so.
///   3. `minutes: null` when no day yields anything measurable. Callers render
///      NOTHING in that case — never "0 min" or a dash. Trainer- and
///      community-published routines are not guaranteed to carry duration
///      data, and inventing one for them is worse than staying quiet.
///
/// DECISION — average, not a range. Days of a routine can differ (an
/// Upper/Lower with a 50' day and an 80' day), so a range would be more
/// faithful for those. Average wins here because this feeds a two-line
/// metadata caption on a grid card where a range costs a line, and because the
/// question the card answers is "roughly how long", not "exactly which day".
/// The detail screen already shows the exact per-day figure. Revisit if
/// routines with wide day dispersion turn out to be common.
///
/// Pure function — same contract as [estimateRoutineDayMinutes]: no Flutter
/// imports, no providers.
RoutineDayDuration estimateRoutineSessionMinutes(
  Routine routine, {
  int week = 0,
}) {
  final authored = routine.estimatedMinutesPerDay;
  if (authored != null && authored > 0) {
    return (minutes: authored, authored: true);
  }

  var total = 0;
  var counted = 0;
  var everyDayAuthored = true;
  for (final day in routine.days) {
    final est = estimateRoutineDayMinutes(day, week: week);
    final minutes = est.minutes;
    if (minutes == null) continue;
    total += minutes;
    counted++;
    if (!est.authored) everyDayAuthored = false;
  }
  if (counted == 0) return (minutes: null, authored: false);
  return (minutes: (total / counted).round(), authored: everyDayAuthored);
}
