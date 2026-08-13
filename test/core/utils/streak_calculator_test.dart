import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/streak_calculator.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

// Helper to make a COMPLETED (not abandoned) finished session on a given
// Argentina calendar date. Fixtures are UTC-flagged at NOON
// (`DateTime.utc(y, m, d, 12)`) for two reasons:
//   1. It mirrors real data — `session.startedAt` is always UTC-flagged
//      (TimestampConverter.fromJson does `.toUtc()`), which is what computeStreak
//      now assumes when it buckets by Argentina calendar day (#411).
//   2. It is TZ-INDEPENDENT — noon UTC maps to 09:00 ART, the same calendar day
//      under any test-runner timezone (CI runs in UTC, the dev machine in ART).
//      It never crosses the midnight boundary, so the expected streak is stable.
// `wasFullyCompleted: true` is required — `status: finished` alone also matches
// an abandoned session (see Session.countsAsWorkout).
Session _finishedOn(DateTime utcDate, {String id = 's'}) => Session(
      id: id,
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Test',
      startedAt: utcDate,
      status: SessionStatus.finished,
      wasFullyCompleted: true,
    );

void main() {
  group('computeStreak (SCENARIO-300..303)', () {
    // `now` is a REAL instant — UTC-flagged at noon so it maps to the same ART
    // calendar day (2026-05-14) under any runner timezone. See _finishedOn.
    // SCENARIO-300: Streak when trained today (includes today)
    test('SCENARIO-300: trained today → streak starts from today', () {
      final today = DateTime.utc(2026, 5, 14, 12); // Wednesday (ART)
      final sessions = [
        _finishedOn(DateTime.utc(2026, 5, 14, 12), id: 's1'),
        _finishedOn(DateTime.utc(2026, 5, 13, 12), id: 's2'),
        _finishedOn(DateTime.utc(2026, 5, 12, 12), id: 's3'),
      ];
      final result = computeStreak(sessions, now: today);
      expect(result, 3);
    });

    // SCENARIO-301: Streak when not yet trained today (starts from yesterday)
    test('SCENARIO-301: not trained today → streak starts from yesterday', () {
      final today = DateTime.utc(2026, 5, 14, 12);
      final sessions = [
        _finishedOn(DateTime.utc(2026, 5, 13, 12), id: 's1'),
        _finishedOn(DateTime.utc(2026, 5, 12, 12), id: 's2'),
      ];
      final result = computeStreak(sessions, now: today);
      expect(result, 2);
    });

    // SCENARIO-302: Streak resets after a missed day
    test(
        'SCENARIO-302: gap in history → streak only counts from most recent run',
        () {
      final today = DateTime.utc(2026, 5, 14, 12);
      final sessions = [
        _finishedOn(DateTime.utc(2026, 5, 14, 12), id: 's1'),
        // gap: no May 13
        _finishedOn(DateTime.utc(2026, 5, 12, 12), id: 's2'),
        _finishedOn(DateTime.utc(2026, 5, 11, 12), id: 's3'),
      ];
      final result = computeStreak(sessions, now: today);
      expect(result, 1); // only today counts; gap breaks the chain
    });

    // SCENARIO-303: Streak is zero for user with no finished sessions
    test('SCENARIO-303: no finished sessions → streak is 0', () {
      final today = DateTime.utc(2026, 5, 14, 12);
      final result = computeStreak([], now: today);
      expect(result, 0);
    });

    // Extra: duplicate dates (same day trained twice) should count as 1
    test('dedup: training twice in one day counts as 1 streak day', () {
      final today = DateTime.utc(2026, 5, 14, 12);
      final sessions = [
        _finishedOn(DateTime.utc(2026, 5, 14, 8, 0), id: 's1'),
        _finishedOn(DateTime.utc(2026, 5, 14, 18, 0), id: 's2'), // same ART day
        _finishedOn(DateTime.utc(2026, 5, 13, 12), id: 's3'),
      ];
      final result = computeStreak(sessions, now: today);
      expect(result, 2); // today + yesterday = 2, not 3
    });

    // Extra: long streak with no gap
    test('long continuous streak from yesterday', () {
      final today = DateTime.utc(2026, 5, 14, 12);
      final sessions = List.generate(
        7,
        (i) => _finishedOn(
          DateTime.utc(2026, 5, 13 - i, 12),
          id: 's$i',
        ),
      );
      final result = computeStreak(sessions, now: today);
      expect(result, 7);
    });

    // Extra: trained today only → streak = 1
    test('single training today → streak = 1', () {
      final today = DateTime.utc(2026, 5, 14, 12);
      final sessions = [
        _finishedOn(DateTime.utc(2026, 5, 14, 12), id: 's1'),
      ];
      final result = computeStreak(sessions, now: today);
      expect(result, 1);
    });

    // Bug fix (abandoned-session-streak-reports): an abandoned session
    // (status=finished, wasFullyCompleted=false — see
    // `SessionNotifier.abandonSession`) must NOT count towards the streak.
    test('abandoned session today does NOT reactivate/count the streak', () {
      final today = DateTime.utc(2026, 5, 14, 12);
      final sessions = [
        Session(
          id: 'abandoned-today',
          uid: 'u1',
          routineId: 'r1',
          routineName: 'Test',
          startedAt: DateTime.utc(2026, 5, 14, 12),
          status: SessionStatus.finished,
          wasFullyCompleted: false,
        ),
        _finishedOn(DateTime.utc(2026, 5, 12, 12), id: 's2'),
        _finishedOn(DateTime.utc(2026, 5, 11, 12), id: 's3'),
      ];
      final result = computeStreak(sessions, now: today);
      // Today's session is abandoned (doesn't count) and yesterday (5/13) has
      // no session at all → gap breaks the chain → streak is 0, NOT 1 or 3.
      expect(result, 0);
    });
  });
}
