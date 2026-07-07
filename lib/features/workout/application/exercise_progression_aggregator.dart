import '../domain/exercise_progression.dart';
import '../domain/session.dart';
import '../domain/set_log.dart';

/// [AD2] Epley one-rep-max estimate: `weight * (1 + reps/30.0)`.
///
/// Full double precision — callers round to 0.5kg ONLY at display time
/// (see [roundToNearestHalfKg]). Returns `null` for `reps <= 0` (not a
/// valid set for 1RM estimation — skip rather than divide/multiply into
/// a meaningless value).
double? calculateOneRepMax({required double weightKg, required int reps}) {
  if (reps <= 0) return null;
  return weightKg * (1 + reps / 30.0);
}

/// [AD2] Rounds a raw metric value to the nearest 0.5kg — DISPLAY ONLY.
/// Internal aggregation always keeps full double precision.
double roundToNearestHalfKg(double value) => (value * 2).round() / 2;

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

/// Pure top-level aggregator — no Riverpod, fully testable.
///
/// [exerciseId]   the target exercise to aggregate.
/// [sessionsDesc] sessions ordered DESC by startedAt (most-recent first),
///                already bounded to the last 60 (caller's responsibility).
/// [logsBySession] map from sessionId → list of SetLogs for that session.
/// [now]          injectable reference time for the 8-week Frecuencia window.
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
///   - [ExerciseProgression.personalRecords]: first-achieved-date record per
///     series that has data, via [derivePersonalRecords].
///   - [ExerciseProgression.frequencyLast8Weeks]: count of sessions within
///     the last 56 days that have ≥1 set for [exerciseId]. Uses
///     [Session.startedAt], NEVER weekNumber.
ExerciseProgression aggregateExerciseProgression({
  required String exerciseId,
  required List<Session> sessionsDesc,
  required Map<String, List<SetLog>> logsBySession,
  required DateTime now,
}) {
  // Guard: empty exerciseId → no-op, zero reads
  if (exerciseId.isEmpty) {
    return ExerciseProgression.empty(exerciseId: '', exerciseName: '');
  }

  final cutoff = now.subtract(const Duration(days: 56));

  // Reverse DESC→ASC once — traverse in ascending date order for output
  final sessionsAsc = sessionsDesc.reversed.toList();

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

    // Extract exercise name from the first matching log (denormalized)
    resolvedName ??= exerciseLogs.first.exerciseName;

    // Heaviest Weight = max(weightKg) for this session
    final maxWeight =
        exerciseLogs.map((l) => l.weightKg).reduce((a, b) => a > b ? a : b);
    heaviestWeightPoints
        .add(ProgressionPoint(date: session.startedAt, value: maxWeight));

    // Best Set Volume = max(reps × weightKg) of a single set this session
    final maxSetVolume = exerciseLogs
        .map((l) => l.reps * l.weightKg)
        .reduce((a, b) => a > b ? a : b);
    bestSetVolumePoints
        .add(ProgressionPoint(date: session.startedAt, value: maxSetVolume));

    // Best Session Volume = Σ(reps × weightKg) for this session
    final sessionVolume = exerciseLogs.fold<double>(
      0.0,
      (sum, l) => sum + l.reps * l.weightKg,
    );
    bestSessionVolumePoints
        .add(ProgressionPoint(date: session.startedAt, value: sessionVolume));

    // [AD2] 1RM = max Epley estimate across this session's valid sets
    // (reps<=0 sets are skipped by calculateOneRepMax). Session is omitted
    // from this series entirely if it has zero valid sets.
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
          .add(ProgressionPoint(date: session.startedAt, value: maxOneRepMax));
    }

    // Frecuencia: count sessions with startedAt >= cutoff (inclusive lower bound)
    if (!session.startedAt.isBefore(cutoff)) {
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
    frequencyLast8Weeks: frecuencia,
  );
}
