import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/argentina_time.dart';
import '../domain/exercise_progression.dart';
import '../domain/session.dart';
import '../domain/set_log.dart';
import 'exercise_progression_aggregator.dart';
import 'exercise_progression_providers.dart' show kProgressionSessionScan;
import 'session_providers.dart';
import 'session_recognition.dart';

/// Un récord personal logrado EN esta sesión: el valor de hoy superó
/// estrictamente al mejor histórico ([previousBest]) de ese [recordType].
/// Solo los 3 tipos por-set del detalle de ejercicio (peso máximo, 1RM
/// estimado, mejor volumen de set) — `bestSessionVolume` queda afuera a
/// propósito: el volumen de la sesión ya tiene su tile en el grid 2×2.
typedef SessionExerciseRecord = ({
  ProgressionRecordType recordType,
  double value,
  double previousBest,
});

/// Resumen por-ejercicio de la sesión, en orden de primera aparición.
///
/// [bestWeightKg]/[bestSetReps]: mejor set con la misma regla que
/// `deriveExerciseSessionHistory` (max peso, empate por reps; sesión solo
/// bodyweight → set de más reps con peso 0, convención #368).
/// [sessionVolumeKg] suma SOLO sets con peso (#368). [isFirstTime]: primera
/// vez que el atleta registra este ejercicio (ver reglas en
/// [aggregateSessionHighlights]).
typedef SessionExerciseSummary = ({
  String exerciseId,
  String exerciseName,
  int setCount,
  double bestWeightKg,
  int bestSetReps,
  double sessionVolumeKg,
  bool isFirstTime,
  List<SessionExerciseRecord> records,
});

/// Todo lo que el resumen post-entreno deriva de la sesión + su historial:
/// filas por ejercicio, récords logrados hoy y el reconocimiento elegido.
typedef SessionHighlights = ({
  List<SessionExerciseSummary> exercises,
  int recordCount,
  bool hasHistory,
  SessionRecognition recognition,
});

const SessionHighlights emptySessionHighlights = (
  exercises: <SessionExerciseSummary>[],
  recordCount: 0,
  hasHistory: false,
  recognition: noRecognition,
);

/// Sesiones previas contra las que se comparan los récords: anteriores a
/// [session] (no posteriores por `startedAt`, excluida por id), que cuentan
/// como entreno (#372), acotadas a [kProgressionSessionScan] — el MISMO tope
/// de scan del detalle de ejercicio, compartido por TODOS los ejercicios de
/// la sesión (un solo fan-out de setLogs, no uno por ejercicio).
///
/// Público para que el provider y el agregador deriven la misma lista (el
/// provider fetchea logs exactamente para estas sesiones).
List<Session> priorSessionsForHighlights({
  required Session session,
  required List<Session> sessionsDesc,
}) =>
    sessionsDesc
        .where((s) =>
            s.id != session.id &&
            s.countsAsWorkout &&
            !s.startedAt.isAfter(session.startedAt))
        .take(kProgressionSessionScan)
        .toList();

/// Pure top-level aggregator del resumen post-entreno — no Riverpod, fully
/// testable. Reusa [aggregateExerciseProgression] por ejercicio (mismos
/// filtros #368/#372 y mismo Epley [calculateOneRepMax] que Insights) sobre
/// el scan compartido de [priorSessionsForHighlights].
///
/// Reglas:
/// - Récord = valor de hoy ESTRICTAMENTE mayor al mejor previo del mismo
///   tipo. Sin marca previa de ese tipo no hay récord — la primera vez
///   establece el punto de partida, no "bate" nada (pedido explícito: sin
///   números inventados). Igualar la marca tampoco cuenta.
/// - Sesión que no cuenta (#372, abandonada): filas descriptivas sí, pero
///   cero récords, sin badges y reconocimiento none — lo mismo que Insights,
///   que la excluye de toda progresión.
/// - [isFirstTime] solo se marca cuando el scan vio la historia COMPLETA
///   (menos de [kProgressionSessionScan] sesiones previas): con historial
///   truncado "no está en el scan" no prueba "nunca lo hizo". Y en el primer
///   entreno de la historia no se marca nada — el banner ya cuenta esa
///   historia; badge en cada fila sería ruido.
SessionHighlights aggregateSessionHighlights({
  required Session session,
  required List<SetLog> sessionLogs,
  required List<Session> sessionsDesc,
  required Map<String, List<SetLog>> priorLogsBySession,
  required DateTime now,
}) {
  final prior =
      priorSessionsForHighlights(session: session, sessionsDesc: sessionsDesc);
  final hasHistory = prior.isNotEmpty;
  final canDetectFirstTime = prior.length < kProgressionSessionScan;
  final counts = session.countsAsWorkout;

  // Ejercicios en orden de primera aparición en los logs de la sesión.
  final orderedIds = <String>[];
  final logsByExercise = <String, List<SetLog>>{};
  for (final log in sessionLogs) {
    final bucket = logsByExercise[log.exerciseId];
    if (bucket == null) {
      orderedIds.add(log.exerciseId);
      logsByExercise[log.exerciseId] = [log];
    } else {
      bucket.add(log);
    }
  }

  final exercises = <SessionExerciseSummary>[];
  var recordCount = 0;

  for (final id in orderedIds) {
    final logs = logsByExercise[id]!;

    SetLog? best;
    var volume = 0.0;
    for (final log in logs) {
      if (log.weightKg > 0) volume += log.reps * log.weightKg;
      if (best == null ||
          log.weightKg > best.weightKg ||
          (log.weightKg == best.weightKg && log.reps > best.reps)) {
        best = log;
      }
    }

    final hadExerciseBefore = prior.any((s) =>
        (priorLogsBySession[s.id] ?? const []).any((l) => l.exerciseId == id));

    final records = <SessionExerciseRecord>[];
    if (counts && hadExerciseBefore) {
      final progression = aggregateExerciseProgression(
        exerciseId: id,
        sessionsDesc: prior,
        logsBySession: priorLogsBySession,
        now: now,
      );

      double? priorBestOf(ProgressionRecordType type) {
        for (final record in progression.personalRecords) {
          if (record.recordType == type) return record.value;
        }
        return null;
      }

      // Valores de HOY con las mismas reglas que las series históricas.
      double? todayMaxWeight;
      double? todayBestSetVolume;
      for (final log in logs) {
        if (log.weightKg <= 0) continue;
        if (todayMaxWeight == null || log.weightKg > todayMaxWeight) {
          todayMaxWeight = log.weightKg;
        }
        final setVolume = log.reps * log.weightKg;
        if (todayBestSetVolume == null || setVolume > todayBestSetVolume) {
          todayBestSetVolume = setVolume;
        }
      }
      double? todayOneRepMax;
      for (final log in logs) {
        final estimate =
            calculateOneRepMax(weightKg: log.weightKg, reps: log.reps);
        if (estimate == null) continue;
        if (todayOneRepMax == null || estimate > todayOneRepMax) {
          todayOneRepMax = estimate;
        }
      }

      void checkRecord(ProgressionRecordType type, double? today) {
        if (today == null) return;
        final previous = priorBestOf(type);
        if (previous != null && today > previous) {
          records.add(
            (recordType: type, value: today, previousBest: previous),
          );
        }
      }

      checkRecord(ProgressionRecordType.heaviestWeight, todayMaxWeight);
      checkRecord(ProgressionRecordType.oneRepMax, todayOneRepMax);
      checkRecord(ProgressionRecordType.bestSetVolume, todayBestSetVolume);
      recordCount += records.length;
    }

    exercises.add((
      exerciseId: id,
      exerciseName: logs.first.exerciseName,
      setCount: logs.length,
      bestWeightKg: best!.weightKg,
      bestSetReps: best.reps,
      sessionVolumeKg: volume,
      isFirstTime:
          counts && hasHistory && canDetectFirstTime && !hadExerciseBefore,
      records: records,
    ));
  }

  return (
    exercises: exercises,
    recordCount: recordCount,
    hasHistory: hasHistory,
    recognition: deriveSessionRecognition(
      session: session,
      sessionsDesc: sessionsDesc,
      recordCount: recordCount,
    ),
  );
}

/// Récords, filas por ejercicio y reconocimiento de la sesión del resumen.
///
/// Watchea [sessionSummaryProvider] con la MISMA key que la pantalla (fetch
/// compartido, Riverpod dedupea) y [sessionsByUidProvider] para el historial.
/// El fan-out de setLogs está acotado por [priorSessionsForHighlights] y es
/// UNO para todos los ejercicios de la sesión — mismo perfil de costo,
/// aceptado y documentado, que abrir el detalle de un ejercicio
/// (`exerciseProgressionProvider` + `exerciseSessionHistoryProvider`).
/// Para una sesión que no cuenta (#372) se saltea el fan-out por completo.
final sessionHighlightsProvider = FutureProvider.autoDispose
    .family<SessionHighlights, ({String uid, String sessionId})>(
        (ref, key) async {
  if (key.uid.isEmpty) return emptySessionHighlights;

  final summary = await ref.watch(sessionSummaryProvider(key).future);
  final session = summary.session;
  if (session == null || summary.setLogs.isEmpty) {
    return emptySessionHighlights;
  }

  final sessions = await ref.watch(sessionsByUidProvider(key.uid).future);

  final prior = session.countsAsWorkout
      ? priorSessionsForHighlights(session: session, sessionsDesc: sessions)
      : const <Session>[];

  final repo = ref.read(sessionRepositoryProvider);
  final logsPerSession = await Future.wait(
    prior.map((s) => repo.listSetLogs(uid: key.uid, sessionId: s.id)),
  );
  final priorLogsBySession = <String, List<SetLog>>{
    for (var i = 0; i < prior.length; i++) prior[i].id: logsPerSession[i],
  };

  return aggregateSessionHighlights(
    session: session,
    sessionLogs: summary.setLogs,
    sessionsDesc: sessions,
    priorLogsBySession: priorLogsBySession,
    now: argentinaNow(),
  );
});
