import '../domain/exercise_progression.dart';
import '../domain/session.dart';
import '../domain/set_log.dart';

/// Pure top-level aggregator — no Riverpod, fully testable.
///
/// [exerciseId]   the target exercise to aggregate.
/// [sessionsDesc] sessions ordered DESC by startedAt (most-recent first),
///                already bounded to the last 60 (caller's responsibility).
/// [logsBySession] map from sessionId → list of SetLogs for that session.
/// [now]          injectable reference time for the 8-week Frecuencia window.
///
/// Returns [ExerciseProgression] with:
///   - [prSeries]    max(weightKg) per session, ASC by startedAt.
///   - [volumeSeries] Σ(reps×weightKg) per session, ASC by startedAt.
///   - [frequencyLast8Weeks] count of sessions within last 56 days that have
///     ≥1 set for [exerciseId]. Uses [Session.startedAt], NEVER weekNumber.
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

  final prPoints = <ProgressionPoint>[];
  final volumePoints = <ProgressionPoint>[];
  int frecuencia = 0;
  String? resolvedName;

  for (final session in sessionsAsc) {
    final logs = logsBySession[session.id] ?? const [];
    final exerciseLogs = logs.where((l) => l.exerciseId == exerciseId).toList();

    if (exerciseLogs.isEmpty) continue;

    // Extract exercise name from the first matching log (denormalized)
    resolvedName ??= exerciseLogs.first.exerciseName;

    // PR = max(weightKg) for this session
    final maxWeight =
        exerciseLogs.map((l) => l.weightKg).reduce((a, b) => a > b ? a : b);

    // Volumen = Σ(reps × weightKg) for this session
    final volumen = exerciseLogs.fold<double>(
      0.0,
      (sum, l) => sum + l.reps * l.weightKg,
    );

    prPoints.add(ProgressionPoint(date: session.startedAt, value: maxWeight));
    volumePoints.add(ProgressionPoint(date: session.startedAt, value: volumen));

    // Frecuencia: count sessions with startedAt >= cutoff (inclusive lower bound)
    if (!session.startedAt.isBefore(cutoff)) {
      frecuencia++;
    }
  }

  return ExerciseProgression(
    exerciseId: exerciseId,
    exerciseName: resolvedName ?? '',
    prSeries: prPoints,
    volumeSeries: volumePoints,
    frequencyLast8Weeks: frecuencia,
  );
}
