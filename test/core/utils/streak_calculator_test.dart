import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/streak_calculator.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

// Helper to make a COMPLETED (not abandoned) finished session on a given
// local date. `wasFullyCompleted: true` is required — `status: finished`
// alone also matches an abandoned session (see Session.countsAsWorkout).
Session _finishedOn(DateTime localDate, {String id = 's'}) => Session(
      id: id,
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Test',
      startedAt: localDate,
      status: SessionStatus.finished,
      wasFullyCompleted: true,
    );

void main() {
  group('computeStreak (SCENARIO-300..303)', () {
    // SCENARIO-300: Streak when trained today (includes today)
    test('SCENARIO-300: trained today → streak starts from today', () {
      final today = DateTime(2026, 5, 14); // Wednesday
      final sessions = [
        _finishedOn(DateTime(2026, 5, 14), id: 's1'),
        _finishedOn(DateTime(2026, 5, 13), id: 's2'),
        _finishedOn(DateTime(2026, 5, 12), id: 's3'),
      ];
      final result = computeStreak(sessions, now: today);
      expect(result, 3);
    });

    // SCENARIO-301: Streak when not yet trained today (starts from yesterday)
    test('SCENARIO-301: not trained today → streak starts from yesterday', () {
      final today = DateTime(2026, 5, 14);
      final sessions = [
        _finishedOn(DateTime(2026, 5, 13), id: 's1'),
        _finishedOn(DateTime(2026, 5, 12), id: 's2'),
      ];
      final result = computeStreak(sessions, now: today);
      expect(result, 2);
    });

    // SCENARIO-302: Streak resets after a missed day
    test(
        'SCENARIO-302: gap in history → streak only counts from most recent run',
        () {
      final today = DateTime(2026, 5, 14);
      final sessions = [
        _finishedOn(DateTime(2026, 5, 14), id: 's1'),
        // gap: no May 13
        _finishedOn(DateTime(2026, 5, 12), id: 's2'),
        _finishedOn(DateTime(2026, 5, 11), id: 's3'),
      ];
      final result = computeStreak(sessions, now: today);
      expect(result, 1); // only today counts; gap breaks the chain
    });

    // SCENARIO-303: Streak is zero for user with no finished sessions
    test('SCENARIO-303: no finished sessions → streak is 0', () {
      final today = DateTime(2026, 5, 14);
      final result = computeStreak([], now: today);
      expect(result, 0);
    });

    // Extra: duplicate dates (same day trained twice) should count as 1
    test('dedup: training twice in one day counts as 1 streak day', () {
      final today = DateTime(2026, 5, 14);
      final sessions = [
        _finishedOn(DateTime(2026, 5, 14, 8, 0), id: 's1'),
        _finishedOn(DateTime(2026, 5, 14, 18, 0), id: 's2'), // same day
        _finishedOn(DateTime(2026, 5, 13), id: 's3'),
      ];
      final result = computeStreak(sessions, now: today);
      expect(result, 2); // today + yesterday = 2, not 3
    });

    // Extra: long streak with no gap
    test('long continuous streak from yesterday', () {
      final today = DateTime(2026, 5, 14);
      final sessions = List.generate(
        7,
        (i) => _finishedOn(
          DateTime(2026, 5, 13 - i),
          id: 's$i',
        ),
      );
      final result = computeStreak(sessions, now: today);
      expect(result, 7);
    });

    // Extra: trained today only → streak = 1
    test('single training today → streak = 1', () {
      final today = DateTime(2026, 5, 14);
      final sessions = [
        _finishedOn(DateTime(2026, 5, 14), id: 's1'),
      ];
      final result = computeStreak(sessions, now: today);
      expect(result, 1);
    });

    // Bug fix (abandoned-session-streak-reports): an abandoned session
    // (status=finished, wasFullyCompleted=false — see
    // `SessionNotifier.abandonSession`) must NOT count towards the streak.
    test('abandoned session today does NOT reactivate/count the streak', () {
      final today = DateTime(2026, 5, 14);
      final sessions = [
        Session(
          id: 'abandoned-today',
          uid: 'u1',
          routineId: 'r1',
          routineName: 'Test',
          startedAt: DateTime(2026, 5, 14),
          status: SessionStatus.finished,
          wasFullyCompleted: false,
        ),
        _finishedOn(DateTime(2026, 5, 12), id: 's2'),
        _finishedOn(DateTime(2026, 5, 11), id: 's3'),
      ];
      final result = computeStreak(sessions, now: today);
      // Today's session is abandoned (doesn't count) and yesterday (5/13) has
      // no session at all → gap breaks the chain → streak is 0, NOT 1 or 3.
      expect(result, 0);
    });
  });
}
