import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

void main() {
  group('Session.countsAsWorkout', () {
    Session buildSession({
      required SessionStatus status,
      required bool wasFullyCompleted,
    }) {
      return Session(
        id: 'session-001',
        uid: 'user-abc',
        routineId: 'routine-ppl',
        routineName: 'Push Pull Legs',
        startedAt: DateTime.utc(2026, 5, 18, 10, 0, 0),
        status: status,
        wasFullyCompleted: wasFullyCompleted,
      );
    }

    test('true for finished + wasFullyCompleted', () {
      final session = buildSession(
        status: SessionStatus.finished,
        wasFullyCompleted: true,
      );

      expect(session.countsAsWorkout, isTrue);
    });

    test('false for finished + NOT wasFullyCompleted (abandonada)', () {
      final session = buildSession(
        status: SessionStatus.finished,
        wasFullyCompleted: false,
      );

      expect(session.countsAsWorkout, isFalse);
    });

    test('false for active session, regardless of wasFullyCompleted', () {
      final active = buildSession(
        status: SessionStatus.active,
        wasFullyCompleted: false,
      );
      final activeCompletedFlag = buildSession(
        status: SessionStatus.active,
        wasFullyCompleted: true,
      );

      expect(active.countsAsWorkout, isFalse);
      expect(activeCompletedFlag.countsAsWorkout, isFalse);
    });
  });
}
