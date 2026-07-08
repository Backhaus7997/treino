import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/application/session_duration.dart';
import 'package:treino/features/workout/domain/session_status.dart';

import 'stub_factories.dart';

void main() {
  group('session duration sanitizing', () {
    test('keeps normal finished duration untouched', () {
      final session = makeSession(
        status: SessionStatus.finished,
        durationMin: 75,
      );

      expect(
        sanitizedFinishedSessionDurationMin(
          session: session,
          setLogs: const [],
        ),
        75,
      );
    });

    test('recovers suspicious finished duration from set-log timestamps', () {
      final startedAt = DateTime.utc(2026, 6, 1, 10);
      final session = makeSession(
        status: SessionStatus.finished,
        startedAt: startedAt,
        finishedAt: startedAt.add(const Duration(days: 2)),
        durationMin: 20000,
      );
      final logs = [
        makeSetLog(completedAt: startedAt.add(const Duration(minutes: 10))),
        makeSetLog(completedAt: startedAt.add(const Duration(minutes: 45))),
      ];

      expect(
        sanitizedFinishedSessionDurationMin(
          session: session,
          setLogs: logs,
        ),
        45,
      );
    });

    test('stale active resume does not count overnight idle time', () {
      final startedAt = DateTime.utc(2026, 6, 1, 10);
      final session = makeSession(
        status: SessionStatus.active,
        startedAt: startedAt,
      );
      final logs = [
        makeSetLog(completedAt: startedAt.add(const Duration(minutes: 12))),
        makeSetLog(completedAt: startedAt.add(const Duration(minutes: 42))),
      ];

      final elapsed = sanitizedActiveSessionElapsedSeconds(
        session: session,
        setLogs: logs,
        now: startedAt.add(const Duration(days: 1)),
      );

      expect(elapsed, const Duration(minutes: 42).inSeconds);
    });
  });
}
