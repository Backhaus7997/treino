import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/exercise_progression.dart';
import '../domain/set_log.dart';
import 'exercise_progression_aggregator.dart';
import 'session_providers.dart'
    show sessionRepositoryProvider, sessionsByUidProvider;

/// Number of sessions to scan for exercise progression.
/// Shared constant — mirrors the design's D6 bound.
const int kProgressionSessionScan = 60;

/// Family key for [exerciseProgressionProvider].
typedef ExerciseProgressionKey = ({String athleteUid, String exerciseId});

/// Derives [ExerciseProgression] for a given athlete + exercise.
///
/// Bounded scan: at most the last [kProgressionSessionScan] sessions.
/// Delegates math to the pure [aggregateExerciseProgression] function.
/// autoDispose: cache drops when the screen closes.
final exerciseProgressionProvider = FutureProvider.autoDispose
    .family<ExerciseProgression, ExerciseProgressionKey>((ref, key) async {
  if (key.athleteUid.isEmpty) {
    return ExerciseProgression.empty(
      exerciseId: key.exerciseId,
      exerciseName: '',
    );
  }

  final sessions =
      await ref.watch(sessionsByUidProvider(key.athleteUid).future);
  final repo = ref.read(sessionRepositoryProvider);

  final scanned = sessions.take(kProgressionSessionScan).toList();

  // Fetch setLogs for all scanned sessions in parallel
  final logsPerSession = await Future.wait(
    scanned.map(
      (s) => repo.listSetLogs(uid: key.athleteUid, sessionId: s.id),
    ),
  );

  // Build map sessionId → logs
  final logsBySession = <String, List<SetLog>>{
    for (var i = 0; i < scanned.length; i++) scanned[i].id: logsPerSession[i],
  };

  return aggregateExerciseProgression(
    exerciseId: key.exerciseId,
    sessionsDesc: scanned, // already DESC from sessionsByUidProvider
    logsBySession: logsBySession,
    now: DateTime.now(),
  );
});

/// Derives the deduplicated list of exercises found in the bounded scan,
/// ordered so the most-recently-logged exercise appears first.
///
/// [exerciseName] is read from the denormalized field on [SetLog] —
/// no exercise-catalogue Firestore read is performed.
/// autoDispose: cache drops when no longer watched.
final athleteExerciseListProvider = FutureProvider.autoDispose
    .family<List<ExerciseListEntry>, String>((ref, athleteUid) async {
  if (athleteUid.isEmpty) return const [];

  final sessions = await ref.watch(sessionsByUidProvider(athleteUid).future);
  final repo = ref.read(sessionRepositoryProvider);

  final scanned = sessions.take(kProgressionSessionScan).toList();

  final logsPerSession = await Future.wait(
    scanned.map(
      (s) => repo.listSetLogs(uid: athleteUid, sessionId: s.id),
    ),
  );

  // Walk sessions DESC (most-recent first) to preserve most-recent ordering
  final seen = <String>{};
  final result = <ExerciseListEntry>[];

  for (final logs in logsPerSession) {
    for (final log in logs) {
      if (seen.add(log.exerciseId)) {
        result.add(ExerciseListEntry(
          exerciseId: log.exerciseId,
          exerciseName: log.exerciseName,
        ));
      }
    }
  }

  return result;
});
