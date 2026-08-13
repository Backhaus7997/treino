import '../../features/workout/domain/session.dart';
import 'argentina_time.dart';

/// Computes the current training streak for [sessions].
///
/// Algorithm (ADR-WRS-02 — Q2 lock):
///   1. Build a set of unique Argentina calendar dates where a finished session
///      started.
///   2. Check if today is in the set (trained today):
///      → If yes, count backwards from today including today.
///   3. If today is NOT in the set (not yet trained today):
///      → Count backwards starting from yesterday.
///
/// O(n) to build the set + O(streak) to count.
///
/// Day buckets are derived in the Argentina calendar frame (ART, UTC-3, no DST)
/// via [toArgentina], consistent with Insights (#379), `listFinishedToday` and
/// the trainer dashboard (#395) — NOT the device timezone. See
/// [argentina_time.dart] for why calendar concepts must be anchored to ART.
///
/// [now] is a REAL instant (any flag) — it is normalized with `.toUtc()`
/// internally, so do NOT pass `argentinaNow()` (that would double-shift it).
/// Defaults to [DateTime.now()] when not provided (injectable for testing).
int computeStreak(List<Session> sessions, {DateTime? now}) {
  final todayArt = toArgentina((now ?? DateTime.now()).toUtc());
  final todayDate = DateTime.utc(todayArt.year, todayArt.month, todayArt.day);

  // Build a set of unique Argentina calendar dates with at least one completed
  // session. Abandoned sessions (status=finished, wasFullyCompleted=false) must
  // NOT count towards the streak. `session.startedAt` is always UTC-flagged
  // (TimestampConverter.fromJson does `.toUtc()`), so `toArgentina` is exact.
  final trainedDates = sessions.where((s) => s.countsAsWorkout).map((s) {
    final art = toArgentina(s.startedAt);
    return DateTime.utc(art.year, art.month, art.day);
  }).toSet();

  var streak = 0;
  var cursor = todayDate;

  // Try counting from today.
  while (trainedDates.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }

  // If today was not trained, try counting from yesterday.
  if (streak == 0) {
    cursor = todayDate.subtract(const Duration(days: 1));
    while (trainedDates.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
  }

  return streak;
}
