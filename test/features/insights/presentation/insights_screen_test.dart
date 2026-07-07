import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/insights/application/insights_providers.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';
import 'package:treino/features/insights/domain/weekly_insights.dart';
import 'package:treino/features/insights/presentation/insights_screen.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/session_status.dart';

import '../../../helpers/test_app_wrapper.dart';
import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

Widget _wrap(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: TestAppWrapper(child: child),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  testWidgets(
      'SCENARIO-DAY-SCREEN-01: selecting a different day tile in the '
      'day-strip does NOT bleed the other day\'s trained muscle into the '
      'currently-displayed silhouette row (the exact PR2 regression fix)',
      (tester) async {
    final repo = MockSessionRepository();
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);
    final yesterday =
        DateTime(todayOnly.year, todayOnly.month, todayOnly.day - 1);

    final todaySession = makeSession(
      id: 's-today',
      startedAt: todayOnly.add(const Duration(hours: 9)),
      status: SessionStatus.finished,
      routineId: 'r1',
    );
    final yesterdaySession = makeSession(
      id: 's-yesterday',
      startedAt: yesterday.add(const Duration(hours: 9)),
      status: SessionStatus.finished,
      routineId: 'r1',
    );

    when(() => repo.listByUid('u1'))
        .thenAnswer((_) async => [todaySession, yesterdaySession]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-today'))
        .thenAnswer((_) async => [makeSetLog(id: 'l1', exerciseId: 'e-chest')]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-yesterday'))
        .thenAnswer((_) async => [makeSetLog(id: 'l2', exerciseId: 'e-legs')]);

    final overrides = <Override>[
      currentUidProvider.overrideWithValue('u1'),
      sessionRepositoryProvider.overrideWithValue(repo),
      exercisesProvider.overrideWith((ref) async => [
            const Exercise(
              id: 'e-chest',
              name: 'Press',
              muscleGroup: 'chest',
              category: 'compound',
            ),
            const Exercise(
              id: 'e-legs',
              name: 'Sentadilla',
              muscleGroup: 'quads',
              category: 'compound',
            ),
          ]),
      routineByIdProvider('r1').overrideWith((ref) async => null),
      weeklyInsightsProvider.overrideWith((ref) async => WeeklyInsights(
            weekStart: todayOnly,
            weekEnd: todayOnly,
            daysTrained: List<bool>.filled(7, false),
            sessionsCount: 2,
            plannedSessionsCount: 5,
            setsByGroup: const {
              MuscleGroupDisplay.pecho: 1,
              MuscleGroupDisplay.cuadriceps: 1,
            },
            targetByGroup: const {},
          )),
    ];

    await tester.pumpWidget(_wrap(const InsightsScreen(), overrides));
    await tester.pumpAndSettle();

    // Today's card (default selection) must show PECHO with 1 SET and
    // CUÁDRICEPS with 0 — the quad set was logged YESTERDAY, so it must
    // not bleed into today's per-day silhouette/list. `find.ancestor` with
    // `.first` picks the INNERMOST matching Row (the _MuscleSetsRow itself).
    final pechoRowFinder =
        find.ancestor(of: find.text('PECHO'), matching: find.byType(Row)).first;
    expect(
      find.descendant(of: pechoRowFinder, matching: find.text('1')),
      findsOneWidget,
    );

    final cuadricepsRowFinder = find
        .ancestor(of: find.text('CUÁDRICEPS'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: cuadricepsRowFinder, matching: find.text('0')),
      findsOneWidget,
      reason: 'yesterday\'s leg session must not bleed into today\'s view',
    );

    // Now tap YESTERDAY's tile — the display must FLIP: quads=1, chest=0.
    // This proves DayStripNavigator's tap actually rewires the provider
    // selection (setState → new AthleteDayInsightsKey), not a static render.
    await tester.tap(find.byKey(ValueKey(yesterday)));
    await tester.pumpAndSettle();

    final pechoRowAfterTap =
        find.ancestor(of: find.text('PECHO'), matching: find.byType(Row)).first;
    expect(
      find.descendant(of: pechoRowAfterTap, matching: find.text('0')),
      findsOneWidget,
      reason: 'today\'s chest session must not bleed into yesterday\'s view',
    );

    final cuadricepsRowAfterTap = find
        .ancestor(of: find.text('CUÁDRICEPS'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: cuadricepsRowAfterTap, matching: find.text('1')),
      findsOneWidget,
    );
  });
}
