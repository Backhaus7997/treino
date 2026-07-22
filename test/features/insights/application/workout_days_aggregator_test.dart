import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/insights/application/workout_days_aggregator.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';

// Helper to make a finished session started at a given instant. [#379]
// trainedDaysInMonth now dedups by the ARGENTINA calendar day
// (toArgentina(startedAt)), so callers pass real UTC instants (e.g. NOON) to
// keep the ART day unambiguous — a LOCAL midnight would shift −3h into the
// previous day/month.
Session _finishedOn(DateTime startedAt, {String id = 's'}) => Session(
      id: id,
      uid: 'u1',
      routineId: 'r1',
      routineName: 'Test',
      startedAt: startedAt,
      status: SessionStatus.finished,
      wasFullyCompleted: true,
    );

void main() {
  group('trainedDaysInMonth (SCENARIO-WDC-01..05)', () {
    // SCENARIO-WDC-01: marks exactly the trained days of the month, incl.
    // the first and last day of the month (month-boundary fixture).
    test(
        'SCENARIO-WDC-01: marks trained days spanning month boundaries, '
        'excludes days outside the month', () {
      final month = DateTime(2026, 6); // June 2026
      final sessions = [
        _finishedOn(DateTime.utc(2026, 6, 1, 12), id: 's1'), // first day
        _finishedOn(DateTime.utc(2026, 6, 30, 12), id: 's2'), // last day
        _finishedOn(DateTime.utc(2026, 5, 31, 12), id: 's3'), // before → excl.
        _finishedOn(DateTime.utc(2026, 7, 1, 12), id: 's4'), // after → excl.
      ];

      final result = trainedDaysInMonth(sessions, month);

      expect(result, {
        DateTime(2026, 6, 1),
        DateTime(2026, 6, 30),
      });
    });

    // SCENARIO-WDC-02: only finished sessions count.
    test('SCENARIO-WDC-02: non-finished sessions are excluded', () {
      final month = DateTime(2026, 6);
      final sessions = [
        _finishedOn(DateTime.utc(2026, 6, 10, 12), id: 's1'),
        Session(
          id: 's2',
          uid: 'u1',
          routineId: 'r1',
          routineName: 'Test',
          startedAt: DateTime.utc(2026, 6, 11, 12),
          status: SessionStatus.active,
        ),
      ];

      final result = trainedDaysInMonth(sessions, month);

      expect(result, {DateTime(2026, 6, 10)});
    });

    // SCENARIO-WDC-03: duplicate sessions on the same day dedup to one entry.
    test('SCENARIO-WDC-03: multiple sessions same day count as one trained day',
        () {
      final month = DateTime(2026, 6);
      final sessions = [
        _finishedOn(DateTime(2026, 6, 15, 8, 0), id: 's1'),
        _finishedOn(DateTime(2026, 6, 15, 18, 0), id: 's2'),
      ];

      final result = trainedDaysInMonth(sessions, month);

      expect(result, {DateTime(2026, 6, 15)});
    });

    // SCENARIO-WDC-04: no sessions in the month → empty set.
    test('SCENARIO-WDC-04: no sessions in month → empty set', () {
      final month = DateTime(2026, 6);
      final sessions = [
        _finishedOn(DateTime(2026, 5, 20), id: 's1'),
      ];

      final result = trainedDaysInMonth(sessions, month);

      expect(result, isEmpty);
    });

    // SCENARIO-WDC-05: empty session list → empty set.
    test('SCENARIO-WDC-05: empty session list → empty set', () {
      final month = DateTime(2026, 6);

      final result = trainedDaysInMonth(const [], month);

      expect(result, isEmpty);
    });
  });
}
