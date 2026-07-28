import '../../../core/utils/argentina_time.dart';
import '../../insights/domain/chart_period.dart';
import '../domain/exercise_progression.dart';
import '../domain/session.dart';
import '../domain/set_log.dart';

/// [AD2] Epley one-rep-max estimate: `weight * (1 + reps/30.0)`.
///
/// Full double precision — callers round to 0.5kg ONLY at display time
/// (see [roundToNearestHalfKg]). Returns `null` for `reps <= 0` (not a
/// valid set for 1RM estimation — skip rather than divide/multiply into
/// a meaningless value) and for `weightKg <= 0` (#368: bodyweight sets are
/// logged with `weightKg = 0` — an Epley estimate of 0kg is not a record,
/// it's the absence of one).
double? calculateOneRepMax({required double weightKg, required int reps}) {
  if (reps <= 0 || weightKg <= 0) return null;
  return weightKg * (1 + reps / 30.0);
}

/// [AD2] Rounds a raw metric value to the nearest 0.5kg — DISPLAY ONLY.
/// Internal aggregation always keeps full double precision.
double roundToNearestHalfKg(double value) => (value * 2).round() / 2;

/// [#377] Whether [session] falls inside [window]'s CURRENT period — the
/// exact calendar-day (ART) comparison [aggregateExerciseProgression] applies
/// before building the 4 series. Shared with `athleteExerciseListProvider`'s
/// per-period data flags so the picker's notion of "has data in this period"
/// can never drift from what the chart actually renders.
///
/// Inclusive by calendar day: `currentEnd` is compared against the END of
/// that day, so a session logged later that same day (any time-of-day) is
/// still included.
bool sessionInCurrentWindow(Session session, ChartPeriodWindow window) {
  final endExclusive = DateTime.utc(
    window.currentEnd.year,
    window.currentEnd.month,
    window.currentEnd.day + 1,
  );
  final local = toArgentina(session.startedAt);
  return !local.isBefore(window.currentStart) && local.isBefore(endExclusive);
}

/// [AD3] Derives the first-achieved-date [PersonalRecord] for a single
/// series — i.e. the point with the max [ProgressionPoint.value], picking
/// the EARLIEST date if the max is reached more than once.
///
/// [series] is assumed already ASC-ordered by date (matches
/// [aggregateExerciseProgression]'s output contract). Returns an empty list
/// when [series] is empty.
List<PersonalRecord> derivePersonalRecords(
  List<ProgressionPoint> series, {
  ProgressionRecordType recordType = ProgressionRecordType.heaviestWeight,
}) {
  if (series.isEmpty) return const [];

  ProgressionPoint best = series.first;
  for (final point in series.skip(1)) {
    if (point.value > best.value) {
      best = point;
    }
    // Equal value: keep the earlier one already held in `best` — series is
    // ASC by date, so the first occurrence of the max is naturally kept.
  }

  return [
    PersonalRecord(
      recordType: recordType,
      value: best.value,
      achievedAt: best.date,
    ),
  ];
}

/// One HISTORIAL row of the exercise detail screen — a single session's
/// snapshot of the exercise, at per-session granularity (the 4 series above
/// collapse these same metrics into chart points).
///
/// [bestWeightKg] is 0 for bodyweight-only sessions (#368 convention: the
/// player logs bodyweight sets with `weightKg = 0`) — callers render the
/// best set as reps-only in that case. [sessionVolume] sums ONLY weighted
/// sets (same #368 rule as [aggregateExerciseProgression]'s volume series),
/// so it is 0 for bodyweight-only sessions.
typedef ExerciseSessionHistoryEntry = ({
  DateTime date,
  int setCount,
  double bestWeightKg,
  int bestSetReps,
  double sessionVolume,
});

/// Upper bound on the rows [deriveExerciseSessionHistory] returns. The scan
/// already caps at `kProgressionSessionScan` sessions; this caps the RENDERED
/// list so the detail screen's HISTORIAL stays a bounded card, not an
/// unbounded feed (pagination is a follow-up if ever needed).
const int kExerciseHistoryMaxEntries = 20;

/// Derives the per-session HISTORIAL rows for [exerciseId] — most recent
/// first, mirroring [sessionsDesc]'s order. Pure top-level function, no
/// Riverpod, fully testable (same convention as
/// [aggregateExerciseProgression]).
///
/// Deliberately NOT period-bounded: HISTORIAL answers "when did I last train
/// this and how did it go", which must survive period switches — and lets the
/// screen distinguish "never trained" (empty here) from "no data in the
/// selected period" (empty series in the aggregation).
///
/// Same session/set filters as the aggregator:
/// - only `countsAsWorkout` sessions (#372 — abandoned/in-progress excluded);
/// - the best set is max `weightKg`, ties broken by max reps; a
///   bodyweight-only session (#368, all `weightKg = 0`) yields its top-reps
///   set with `bestWeightKg = 0`;
/// - `setCount` is weight-agnostic (a bodyweight set still counts as a set,
///   matching the frecuencia stat's weight-agnostic spirit);
/// - dates are `startedAt.toLocal()` for display (#380).
List<ExerciseSessionHistoryEntry> deriveExerciseSessionHistory({
  required String exerciseId,
  required List<Session> sessionsDesc,
  required Map<String, List<SetLog>> logsBySession,
  int maxEntries = kExerciseHistoryMaxEntries,
}) {
  if (exerciseId.isEmpty) return const [];

  final entries = <ExerciseSessionHistoryEntry>[];
  for (final session in sessionsDesc) {
    if (!session.countsAsWorkout) continue;
    final logs = logsBySession[session.id] ?? const [];
    final exerciseLogs = logs.where((l) => l.exerciseId == exerciseId);
    if (exerciseLogs.isEmpty) continue;

    SetLog? best;
    var volume = 0.0;
    var setCount = 0;
    for (final log in exerciseLogs) {
      setCount++;
      if (log.weightKg > 0) volume += log.reps * log.weightKg;
      if (best == null ||
          log.weightKg > best.weightKg ||
          (log.weightKg == best.weightKg && log.reps > best.reps)) {
        best = log;
      }
    }

    entries.add((
      date: session.startedAt.toLocal(),
      setCount: setCount,
      bestWeightKg: best!.weightKg,
      bestSetReps: best.reps,
      sessionVolume: volume,
    ));
    if (entries.length >= maxEntries) break;
  }
  return entries;
}

/// Pure top-level aggregator — no Riverpod, fully testable.
///
/// [exerciseId]   the target exercise to aggregate.
/// [sessionsDesc] sessions ordered DESC by startedAt (most-recent first),
///                already bounded to the last 60 (caller's responsibility).
/// [logsBySession] map from sessionId → list of SetLogs for that session.
/// [now]          injectable reference time for the legacy 8-week Frecuencia
///                window (only used when [periodWindow] is null).
/// [periodWindow] [AD7] optional current-period window (see [ChartPeriod]).
///                When non-null, sessions with `startedAt` outside
///                `[currentStart, currentEnd]` (inclusive, by calendar day)
///                are excluded from all 4 series AND from
///                [frequencySessionCount] (#555 — the Frecuencia stat used
///                to be a fixed `now`-relative 56-day count regardless of
///                the selector, so "3 sesiones en las últimas 8 semanas"
///                could coexist with a 1-point chart + "necesitás al menos
///                2 sesiones" for the active period). When null (default),
///                ALL scanned sessions are included and Frecuencia keeps
///                the legacy 56-day window — backward-compatible with
///                callers that don't select a period.
///
/// [AD3] Returns [ExerciseProgression] with 4 distinct client-computed
/// series (all ASC by startedAt):
///   - [ExerciseProgression.heaviestWeightSeries]: max(weightKg) per session
///     (renamed from the mislabeled "PR" — UI label is "Peso máximo").
///   - [ExerciseProgression.oneRepMaxSeries]: max Epley-estimated 1RM per
///     session (AD2), full double precision; sessions where every set has
///     reps<=0 are omitted from this series entirely.
///   - [ExerciseProgression.bestSetVolumeSeries]: max(reps×weightKg) of a
///     single set per session.
///   - [ExerciseProgression.bestSessionVolumeSeries]: Σ(reps×weightKg) per
///     session (renamed from the old `volumeSeries` — same semantics).
///   [#368] All 4 series consider ONLY sets with `weightKg > 0` — bodyweight
///   sets are logged as 0kg by the player and must not produce 0-valued
///   points (nor, downstream, "0 kg" personal records). A session whose sets
///   are all 0kg is omitted from these series entirely, mirroring how
///   all-reps<=0 sessions drop out of the 1RM series.
///   - [ExerciseProgression.personalRecords]: first-achieved-date record per
///     series that has data, via [derivePersonalRecords].
///   - [ExerciseProgression.frequencySessionCount]: count of sessions with
///     ≥1 set for [exerciseId] inside [periodWindow]'s current window (or,
///     legacy, the last 56 days when no window is given). Uses
///     [Session.startedAt], NEVER weekNumber.
ExerciseProgression aggregateExerciseProgression({
  required String exerciseId,
  required List<Session> sessionsDesc,
  required Map<String, List<SetLog>> logsBySession,
  required DateTime now,
  ChartPeriodWindow? periodWindow,
}) {
  // Guard: empty exerciseId → no-op, zero reads
  if (exerciseId.isEmpty) {
    return ExerciseProgression.empty(exerciseId: '', exerciseName: '');
  }

  final cutoff = now.subtract(const Duration(days: 56));

  // Reverse DESC→ASC once — traverse in ascending date order for output.
  // [AD7] `sessionsAsc` is what the 4 metric series iterate over (subject to
  // periodWindow filtering below). `frecuencia` traverses the UNFILTERED
  // list separately and resolves its own window per session (#555: the
  // active period's when a periodWindow is given, the legacy 56 days when
  // not) — see the frecuencia loop below.
  // #372: exclude sessions that don't count as a completed workout (abandoned
  // `wasFullyCompleted=false` / in-progress `active`) BEFORE deriving anything —
  // both the 4 metric series AND the frecuencia stat must ignore them,
  // matching the criterion the other Insights screens use. Without this an
  // abandoned session's sets inflated progression/PRs while the same session
  // was absent from the radar/monthly report.
  final countsSessionsDesc =
      sessionsDesc.where((s) => s.countsAsWorkout).toList();
  final sessionsAscUnfiltered = countsSessionsDesc.reversed.toList();
  var sessionsAsc = sessionsAscUnfiltered;

  // [AD7] Filter to the selected period's CURRENT window, inclusive by
  // calendar day (see [sessionInCurrentWindow]).
  if (periodWindow != null) {
    sessionsAsc = sessionsAsc
        .where((s) => sessionInCurrentWindow(s, periodWindow))
        .toList();
  }

  final heaviestWeightPoints = <ProgressionPoint>[];
  final oneRepMaxPoints = <ProgressionPoint>[];
  final bestSetVolumePoints = <ProgressionPoint>[];
  final bestSessionVolumePoints = <ProgressionPoint>[];
  int frecuencia = 0;
  String? resolvedName;

  for (final session in sessionsAsc) {
    final logs = logsBySession[session.id] ?? const [];
    final exerciseLogs = logs.where((l) => l.exerciseId == exerciseId).toList();

    if (exerciseLogs.isEmpty) continue;

    // Points feed chart labels and PR dates — a real UTC instant must be
    // localized for display (#380). Window/frecuencia filtering above uses the
    // raw `session.startedAt` separately, so this only affects what's shown.
    // Shifting every point by the same offset preserves ordering, so
    // derivePersonalRecords (first-occurrence-of-max) is unaffected.
    final localDate = session.startedAt.toLocal();

    // Extract exercise name from the first matching log (denormalized)
    resolvedName ??= exerciseLogs.first.exerciseName;

    // #368: bodyweight sets are logged with weightKg = 0 (player convention,
    // same value routine_detail's "ÚLTIMO" badge already treats as "no
    // data"). They carry no signal for the weight-based metrics, so they are
    // excluded from the 3 series below (and from 1RM via
    // calculateOneRepMax's own guard). Name resolution above and frecuencia
    // below stay weight-agnostic on purpose.
    final weightedLogs = exerciseLogs.where((l) => l.weightKg > 0).toList();

    if (weightedLogs.isNotEmpty) {
      // Heaviest Weight = max(weightKg) for this session
      final maxWeight =
          weightedLogs.map((l) => l.weightKg).reduce((a, b) => a > b ? a : b);
      heaviestWeightPoints
          .add(ProgressionPoint(date: localDate, value: maxWeight));

      // Best Set Volume = max(reps × weightKg) of a single set this session
      final maxSetVolume = weightedLogs
          .map((l) => l.reps * l.weightKg)
          .reduce((a, b) => a > b ? a : b);
      bestSetVolumePoints
          .add(ProgressionPoint(date: localDate, value: maxSetVolume));

      // Best Session Volume = Σ(reps × weightKg) for this session
      final sessionVolume = weightedLogs.fold<double>(
        0.0,
        (sum, l) => sum + l.reps * l.weightKg,
      );
      bestSessionVolumePoints
          .add(ProgressionPoint(date: localDate, value: sessionVolume));
    }

    // [AD2] 1RM = max Epley estimate across this session's valid sets
    // (reps<=0 and weightKg<=0 sets are skipped by calculateOneRepMax).
    // Session is omitted from this series entirely if it has zero valid sets.
    double? maxOneRepMax;
    for (final log in exerciseLogs) {
      final estimate =
          calculateOneRepMax(weightKg: log.weightKg, reps: log.reps);
      if (estimate == null) continue;
      if (maxOneRepMax == null || estimate > maxOneRepMax) {
        maxOneRepMax = estimate;
      }
    }
    if (maxOneRepMax != null) {
      oneRepMaxPoints
          .add(ProgressionPoint(date: localDate, value: maxOneRepMax));
    }
  }

  // [AD7]/[#555] Frecuencia: count sessions matching [exerciseId]'s logs
  // inside the ACTIVE period window when one is given — the stat renders
  // right above a period selector, so it must answer for the same window the
  // chart draws (the old fixed 8-week count contradicted the period-scoped
  // single-point hint). Without a periodWindow, keep the legacy 56-day
  // cutoff (inclusive lower bound). Weight-agnostic on purpose: a session
  // whose sets are all bodyweight still counts as having trained.
  for (final session in sessionsAscUnfiltered) {
    final logs = logsBySession[session.id] ?? const [];
    final hasExerciseLog = logs.any((l) => l.exerciseId == exerciseId);
    if (!hasExerciseLog) continue;
    final inFrequencyWindow = periodWindow != null
        ? sessionInCurrentWindow(session, periodWindow)
        : !toArgentina(session.startedAt).isBefore(cutoff);
    if (inFrequencyWindow) {
      frecuencia++;
    }
  }

  final personalRecords = <PersonalRecord>[
    ...derivePersonalRecords(heaviestWeightPoints,
        recordType: ProgressionRecordType.heaviestWeight),
    ...derivePersonalRecords(oneRepMaxPoints,
        recordType: ProgressionRecordType.oneRepMax),
    ...derivePersonalRecords(bestSetVolumePoints,
        recordType: ProgressionRecordType.bestSetVolume),
    ...derivePersonalRecords(bestSessionVolumePoints,
        recordType: ProgressionRecordType.bestSessionVolume),
  ];

  return ExerciseProgression(
    exerciseId: exerciseId,
    exerciseName: resolvedName ?? '',
    heaviestWeightSeries: heaviestWeightPoints,
    oneRepMaxSeries: oneRepMaxPoints,
    bestSetVolumeSeries: bestSetVolumePoints,
    bestSessionVolumeSeries: bestSessionVolumePoints,
    personalRecords: personalRecords,
    frequencySessionCount: frecuencia,
  );
}
