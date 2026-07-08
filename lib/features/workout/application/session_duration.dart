import '../domain/session.dart';
import '../domain/set_log.dart';

const Duration maxWorkoutDuration = Duration(hours: 8);
const Duration maxWorkoutIdleGap = Duration(minutes: 30);

int sanitizedActiveSessionElapsedSeconds({
  required Session session,
  required List<SetLog> setLogs,
  required DateTime now,
}) {
  final rawElapsed = now.difference(session.startedAt).inSeconds;
  if (rawElapsed <= 0) return 0;
  if (rawElapsed <= maxWorkoutDuration.inSeconds) return rawElapsed;

  final recovered = _activeTimelineSeconds(
    startedAt: session.startedAt,
    setLogs: setLogs,
  );
  return recovered.clamp(0, maxWorkoutDuration.inSeconds);
}

int sanitizedFinishedSessionDurationMin({
  required Session session,
  required List<SetLog> setLogs,
}) {
  if (session.durationMin > 0 &&
      session.durationMin <= maxWorkoutDuration.inMinutes) {
    return session.durationMin;
  }

  final recoveredSeconds = _activeTimelineSeconds(
    startedAt: session.startedAt,
    setLogs: setLogs,
    finishedAt: session.finishedAt,
  );
  if (recoveredSeconds > 0) {
    return _ceilMinutes(recoveredSeconds).clamp(
      1,
      maxWorkoutDuration.inMinutes,
    );
  }

  return session.durationMin.clamp(0, maxWorkoutDuration.inMinutes);
}

int _activeTimelineSeconds({
  required DateTime startedAt,
  required List<SetLog> setLogs,
  DateTime? finishedAt,
}) {
  final completedTimes = setLogs
      .map((log) => log.completedAt)
      .where((time) => !time.isBefore(startedAt))
      .toList(growable: false)
    ..sort();

  final lastLoggedAt = completedTimes.isEmpty ? null : completedTimes.last;
  final end = lastLoggedAt ?? finishedAt;
  if (end == null) return 0;

  var totalSeconds = end.difference(startedAt).inSeconds;

  if (lastLoggedAt != null && finishedAt != null) {
    final finalGap = finishedAt.difference(lastLoggedAt).inSeconds;
    if (finalGap > 0 && finalGap <= maxWorkoutIdleGap.inSeconds) {
      totalSeconds += finalGap;
    }
  }

  return totalSeconds.clamp(0, maxWorkoutDuration.inSeconds);
}

int _ceilMinutes(int seconds) => (seconds + 59) ~/ 60;
