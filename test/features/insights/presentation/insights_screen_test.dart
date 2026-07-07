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
      'SCENARIO-DAY-SCREEN-01: selecting a different day (tapping a past '
      'weekday circle in the SEMANA card) does NOT bleed the other day\'s '
      'trained muscle into the currently-displayed silhouette row (the '
      'exact PR2 regression fix), and defaults to today on first render',
      (tester) async {
    final repo = MockSessionRepository();
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    final weekStart = _mondayOfWeek(todayOnly);
    final todayIndex = todayOnly.weekday - DateTime.monday;

    // Skip the "tap a past day" portion on a Monday, when there is no past
    // day in the current week to tap — the default-selection assertion
    // still runs regardless of which weekday the suite executes on.
    final hasPastDayThisWeek = todayIndex > 0;
    final pastDay = hasPastDayThisWeek
        ? DateTime(todayOnly.year, todayOnly.month, todayOnly.day - 1)
        : todayOnly;

    final todaySession = makeSession(
      id: 's-today',
      startedAt: todayOnly.add(const Duration(hours: 9)),
      status: SessionStatus.finished,
      routineId: 'r1',
    );
    final pastSession = makeSession(
      id: 's-past',
      startedAt: pastDay.add(const Duration(hours: 9)),
      status: SessionStatus.finished,
      routineId: 'r1',
    );

    when(() => repo.listByUid('u1'))
        .thenAnswer((_) async => [todaySession, pastSession]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-today'))
        .thenAnswer((_) async => [makeSetLog(id: 'l1', exerciseId: 'e-chest')]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-past'))
        .thenAnswer((_) async => [makeSetLog(id: 'l2', exerciseId: 'e-legs')]);

    final daysTrained = List<bool>.filled(7, false);
    daysTrained[todayIndex] = true;
    if (hasPastDayThisWeek) daysTrained[todayIndex - 1] = true;

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
            weekStart: weekStart,
            weekEnd: weekStart.add(const Duration(days: 6)),
            daysTrained: daysTrained,
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
    // CUÁDRICEPS with 0 — the quad set was logged in the PAST day, so it
    // must not bleed into today's per-day silhouette/list. `find.ancestor`
    // with `.first` picks the INNERMOST matching Row (the _MuscleSetsRow).
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
      reason: 'the past day\'s leg session must not bleed into today\'s view',
    );

    if (!hasPastDayThisWeek) return;

    // Now tap the PAST day's weekday circle in the SEMANA card — the
    // display must FLIP: quads=1, chest=0. This proves the week card's
    // tap actually rewires the provider selection (setState → new
    // AthleteDayInsightsKey), not a static render.
    await tester.tap(find.byKey(ValueKey(pastDay)));
    await tester.pumpAndSettle();

    final pechoRowAfterTap =
        find.ancestor(of: find.text('PECHO'), matching: find.byType(Row)).first;
    expect(
      find.descendant(of: pechoRowAfterTap, matching: find.text('0')),
      findsOneWidget,
      reason: 'today\'s chest session must not bleed into the past day\'s view',
    );

    final cuadricepsRowAfterTap = find
        .ancestor(of: find.text('CUÁDRICEPS'), matching: find.byType(Row))
        .first;
    expect(
      find.descendant(of: cuadricepsRowAfterTap, matching: find.text('1')),
      findsOneWidget,
    );
  });

  testWidgets(
      'SCENARIO-DAY-SCREEN-02: tapping a future weekday circle in the '
      'SEMANA card does NOT change the selected day', (tester) async {
    final repo = MockSessionRepository();
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    final weekStart = _mondayOfWeek(todayOnly);
    final todayIndex = todayOnly.weekday - DateTime.monday;

    // Only meaningful when there IS a future day left in the current week.
    if (todayIndex >= 6) return;
    final futureDay =
        DateTime(todayOnly.year, todayOnly.month, todayOnly.day + 1);

    final todaySession = makeSession(
      id: 's-today',
      startedAt: todayOnly.add(const Duration(hours: 9)),
      status: SessionStatus.finished,
      routineId: 'r1',
    );

    when(() => repo.listByUid('u1')).thenAnswer((_) async => [todaySession]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-today'))
        .thenAnswer((_) async => [makeSetLog(id: 'l1', exerciseId: 'e-chest')]);

    final daysTrained = List<bool>.filled(7, false);
    daysTrained[todayIndex] = true;

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
          ]),
      routineByIdProvider('r1').overrideWith((ref) async => null),
      weeklyInsightsProvider.overrideWith((ref) async => WeeklyInsights(
            weekStart: weekStart,
            weekEnd: weekStart.add(const Duration(days: 6)),
            daysTrained: daysTrained,
            sessionsCount: 1,
            plannedSessionsCount: 5,
            setsByGroup: const {MuscleGroupDisplay.pecho: 1},
            targetByGroup: const {},
          )),
    ];

    await tester.pumpWidget(_wrap(const InsightsScreen(), overrides));
    await tester.pumpAndSettle();

    final pechoRowFinder =
        find.ancestor(of: find.text('PECHO'), matching: find.byType(Row)).first;
    expect(
      find.descendant(of: pechoRowFinder, matching: find.text('1')),
      findsOneWidget,
    );

    // Tapping the future day's circle must be a no-op — PECHO stays 1.
    await tester.tap(find.byKey(ValueKey(futureDay)));
    await tester.pumpAndSettle();

    final pechoRowAfterTap =
        find.ancestor(of: find.text('PECHO'), matching: find.byType(Row)).first;
    expect(
      find.descendant(of: pechoRowAfterTap, matching: find.text('1')),
      findsOneWidget,
      reason: 'tapping a future day must not change the selected day',
    );
  });
}

DateTime _mondayOfWeek(DateTime day) {
  final daysFromMonday = day.weekday - DateTime.monday;
  return DateTime(day.year, day.month, day.day - daysFromMonday);
}
