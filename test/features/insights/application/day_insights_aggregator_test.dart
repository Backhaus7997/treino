import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/insights/application/day_insights_aggregator.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';

import '../../workout/application/stub_factories.dart';

void main() {
  group('aggregateDayInsights', () {
    test(
        'SCENARIO-DAY-AGG-01: a day with no finished session returns empty, '
        'not carried over from a previous day', () {
      final day = DateTime(2026, 7, 6);
      final result = aggregateDayInsights(
        day: day,
        sessions: const [],
        setLogsBySessionId: const {},
        muscleGroupByExerciseId: const {},
      );

      expect(result.day, day);
      expect(result.isEmpty, isTrue);
      expect(result.setsByGroup, isEmpty);
      expect(result.sessionsCount, 0);
    });

    test(
        'SCENARIO-DAY-AGG-02: chest Monday + legs Tuesday — Tuesday must NOT '
        'show Monday\'s chest sets (per-day, not weekly-accumulated)', () {
      final monday = DateTime(2026, 7, 6);
      final tuesday = DateTime(2026, 7, 7);

      final mondaySession = makeSession(
        id: 's-mon',
        startedAt: monday.add(const Duration(hours: 10)),
        status: SessionStatus.finished,
      );
      final tuesdaySession = makeSession(
        id: 's-tue',
        startedAt: tuesday.add(const Duration(hours: 10)),
        status: SessionStatus.finished,
      );

      final setLogsBySessionId = {
        's-mon': [makeSetLog(id: 'l1', exerciseId: 'e-chest')],
        's-tue': [makeSetLog(id: 'l2', exerciseId: 'e-legs')],
      };
      final muscleGroupByExerciseId = {
        'e-chest': 'chest',
        'e-legs': 'quads',
      };

      final tuesdayResult = aggregateDayInsights(
        day: tuesday,
        sessions: [mondaySession, tuesdaySession],
        setLogsBySessionId: setLogsBySessionId,
        muscleGroupByExerciseId: muscleGroupByExerciseId,
      );

      expect(tuesdayResult.setsByGroup[MuscleGroupDisplay.cuadriceps], 1);
      expect(
        tuesdayResult.setsByGroup.containsKey(MuscleGroupDisplay.pecho),
        isFalse,
        reason: 'chest was trained Monday — Tuesday must render blank for it',
      );
      expect(tuesdayResult.sessionsCount, 1);
    });

    test(
        'SCENARIO-DAY-AGG-03: excludes non-finished sessions from the day '
        'aggregate', () {
      final day = DateTime(2026, 7, 6);
      final activeSession = makeSession(
        id: 's-active',
        startedAt: day.add(const Duration(hours: 10)),
        status: SessionStatus.active,
      );

      final result = aggregateDayInsights(
        day: day,
        sessions: [activeSession],
        setLogsBySessionId: {
          's-active': [makeSetLog(id: 'l1', exerciseId: 'e-chest')],
        },
        muscleGroupByExerciseId: const {'e-chest': 'chest'},
      );

      expect(result.sessionsCount, 0);
      expect(result.setsByGroup, isEmpty);
    });

    test(
        'SCENARIO-DAY-AGG-04: unknown muscleGroup strings are skipped '
        'silently (same cutoff-2B convention as weeklyInsightsProvider)', () {
      final day = DateTime(2026, 7, 6);
      final session = makeSession(
        id: 's1',
        startedAt: day.add(const Duration(hours: 10)),
        status: SessionStatus.finished,
      );

      final result = aggregateDayInsights(
        day: day,
        sessions: [session],
        setLogsBySessionId: {
          's1': [makeSetLog(id: 'l1', exerciseId: 'e-legacy')],
        },
        muscleGroupByExerciseId: const {'e-legacy': 'brazos'},
      );

      expect(result.setsByGroup, isEmpty);
      expect(result.sessionsCount, 1);
    });

    test(
        'SCENARIO-DAY-AGG-05: multiple finished sessions same day sum their '
        'sets into the same day bucket', () {
      final day = DateTime(2026, 7, 6);
      final s1 = makeSession(
        id: 's1',
        startedAt: day.add(const Duration(hours: 8)),
        status: SessionStatus.finished,
      );
      final s2 = makeSession(
        id: 's2',
        startedAt: day.add(const Duration(hours: 18)),
        status: SessionStatus.finished,
      );

      final result = aggregateDayInsights(
        day: day,
        sessions: [s1, s2],
        setLogsBySessionId: {
          's1': [makeSetLog(id: 'l1', exerciseId: 'e-chest')],
          's2': [
            makeSetLog(id: 'l2', exerciseId: 'e-chest'),
            makeSetLog(id: 'l3', exerciseId: 'e-chest'),
          ],
        },
        muscleGroupByExerciseId: const {'e-chest': 'chest'},
      );

      expect(result.setsByGroup[MuscleGroupDisplay.pecho], 3);
      expect(result.sessionsCount, 2);
    });
  });

  group('lastNDays', () {
    test(
        'SCENARIO-DAY-AGG-06: returns N calendar days ending at anchor, '
        'oldest first', () {
      final anchor = DateTime(2026, 7, 7); // Tuesday
      final days = lastNDays(anchor, 7);

      expect(days.length, 7);
      expect(days.first, DateTime(2026, 7, 1));
      expect(days.last, DateTime(2026, 7, 7));
    });

    test('SCENARIO-DAY-AGG-07: truncates time-of-day from anchor', () {
      final anchor = DateTime(2026, 7, 7, 23, 45);
      final days = lastNDays(anchor, 1);

      expect(days.single, DateTime(2026, 7, 7));
    });
  });
}
