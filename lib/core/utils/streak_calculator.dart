import '../../features/workout/domain/session.dart';
import '../../features/workout/domain/session_status.dart';

/// Computes the current training streak for [sessions].
///
/// Algorithm (ADR-WRS-02 — Q2 lock):
///   1. Build a set of unique local dates where a finished session started.
///   2. Check if today is in the set (trained today):
///      → If yes, count backwards from today including today.
///   3. If today is NOT in the set (not yet trained today):
///      → Count backwards starting from yesterday.
///
/// O(n) to build the set + O(streak) to count.
///
/// [now] defaults to [DateTime.now()] when not provided (injectable for testing).
int computeStreak(List<Session> sessions, {DateTime? now}) {
  final todayLocal = (now ?? DateTime.now()).toLocal();
  final todayDate = DateTime(todayLocal.year, todayLocal.month, todayLocal.day);

  // Build a set of unique local dates with at least one finished session.
  final trainedDates =
      sessions.where((s) => s.status == SessionStatus.finished).map((s) {
    final local = s.startedAt.toLocal();
    return DateTime(local.year, local.month, local.day);
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
