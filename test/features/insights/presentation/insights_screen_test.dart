import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/utils/argentina_time.dart';
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
import 'package:treino/l10n/app_l10n.dart';

import '../../../helpers/test_app_wrapper.dart';
import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

/// [UX-back-view] Counts mask `Image.asset` instances by asset path
/// substring — same idiom `body_silhouette_placeholder_test.dart` uses to
/// assert `showBack` wiring without depending on the widget's internal
/// Stack structure.
int _countMasksContaining(WidgetTester tester, String pathFragment) {
  return tester.widgetList<Image>(find.byType(Image)).where((img) {
    final provider = img.image;
    if (provider is! AssetImage) return false;
    return provider.assetName.contains(pathFragment);
  }).length;
}

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
    final now =
        argentinaNow(); // ART frame — matches the widget (argentinaNow); no-op on UTC-3, TZ-safe on UTC CI
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
      wasFullyCompleted: true,
      routineId: 'r1',
    );
    final pastSession = makeSession(
      id: 's-past',
      startedAt: pastDay.add(const Duration(hours: 9)),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
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
      visibleRoutineByIdProvider('r1').overrideWith((ref) async => null),
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

    // Today's card (default selection) must show PECHO with 1 SET.
    // `find.ancestor` with `.first` picks the INNERMOST matching Row (the
    // _MuscleSetsRow).
    final pechoRowFinder =
        find.ancestor(of: find.text('PECHO'), matching: find.byType(Row)).first;
    expect(
      find.descendant(of: pechoRowFinder, matching: find.text('1')),
      findsOneWidget,
    );

    final cuadricepsRowFinder = find
        .ancestor(of: find.text('CUÁDRICEPS'), matching: find.byType(Row))
        .first;

    // The "no bleed" assertion (CUÁDRICEPS = 0 on today's view) is only valid
    // when the seeded "past" session actually landed on a DIFFERENT day than
    // today. On a Monday `hasPastDayThisWeek` is false, so `pastDay` collapses
    // onto today (see the `pastDay` computation above) — both sessions are
    // then legitimately today's, and today's view correctly shows quads = 1.
    // Guarding here (instead of after) is the date-bomb fix: on a Monday the
    // old code asserted quads = 0 against data where the quad set WAS today,
    // failing ~1 day in 7. Mirrors the PR#307 day-strip date-bomb fix.
    if (!hasPastDayThisWeek) {
      expect(
        find.descendant(of: cuadricepsRowFinder, matching: find.text('1')),
        findsOneWidget,
        reason: "on a Monday the seeded 'past' session is today, so today's "
            'view legitimately shows the quad set',
      );
      return;
    }

    expect(
      find.descendant(of: cuadricepsRowFinder, matching: find.text('0')),
      findsOneWidget,
      reason: 'the past day\'s leg session must not bleed into today\'s view',
    );

    // Now tap the PAST day's weekday circle in the SEMANA card — the
    // display must FLIP: quads=1, chest=0. This proves the week card's
    // tap actually rewires the provider selection (setState → new
    // AthleteDayInsightsKey), not a static render.
    // The day-strip keys days with UTC-flagged ART dates (DateTime.utc), so the
    // tap target must use the same flag — a local-flagged ValueKey won't match.
    await tester.tap(find.byKey(
        ValueKey(DateTime.utc(pastDay.year, pastDay.month, pastDay.day))));
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
    final now =
        argentinaNow(); // ART frame — matches the widget (argentinaNow); no-op on UTC-3, TZ-safe on UTC CI
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
      wasFullyCompleted: true,
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
      visibleRoutineByIdProvider('r1').overrideWith((ref) async => null),
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
    await tester.tap(find.byKey(ValueKey(
        DateTime.utc(futureDay.year, futureDay.month, futureDay.day))));
    await tester.pumpAndSettle();

    final pechoRowAfterTap =
        find.ancestor(of: find.text('PECHO'), matching: find.byType(Row)).first;
    expect(
      find.descendant(of: pechoRowAfterTap, matching: find.text('1')),
      findsOneWidget,
      reason: 'tapping a future day must not change the selected day',
    );
  });

  testWidgets(
      'SCENARIO-WEEK-PAGE-01: tapping ‹ pages the SEMANA card to the '
      'previous week — title and adherence counter update to show that '
      'week\'s data', (tester) async {
    final repo = MockSessionRepository();
    final now =
        argentinaNow(); // ART frame — matches the widget (argentinaNow); no-op on UTC-3, TZ-safe on UTC CI
    final todayOnly = DateTime(now.year, now.month, now.day);
    final currentWeekStart = _mondayOfWeek(todayOnly);
    final prevWeekStart = DateTime(
      currentWeekStart.year,
      currentWeekStart.month,
      currentWeekStart.day - 7,
    );

    final currentWeekSession = makeSession(
      id: 's-current',
      startedAt: currentWeekStart.add(const Duration(hours: 9)),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
      routineId: 'r1',
    );
    final prevWeekSession = makeSession(
      id: 's-prev',
      startedAt: prevWeekStart.add(const Duration(hours: 9)),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
      routineId: 'r1',
    );

    when(() => repo.listByUid('u1'))
        .thenAnswer((_) async => [currentWeekSession, prevWeekSession]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-current'))
        .thenAnswer((_) async => [makeSetLog(id: 'l1', exerciseId: 'e-chest')]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-prev'))
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
      visibleRoutineByIdProvider('r1').overrideWith((ref) async => null),
    ];

    await tester.pumpWidget(_wrap(const InsightsScreen(), overrides));
    await tester.pumpAndSettle();

    // Current week shown first: 1/5 sessions.
    expect(find.text('1 / 5'), findsOneWidget);

    // Tap ‹ (previous week chevron) — must be the FIRST IconButton in the
    // header row (‹ comes before the title, › comes after).
    await tester.tap(find.byKey(const Key('week-strip-previous-week')));
    await tester.pumpAndSettle();

    // Previous week also had exactly 1 finished session — count stays
    // "1 / 5" but the underlying week (and its muscle data) changed, which
    // the VOLUMEN POR GRUPO card below reflects: chest (this week) becomes
    // 0 once we've paged away from it, legs (prev week) becomes visible.
    // Assert on the range title instead, which is unambiguous per week.
    final expectedPrevRangeMonth = _monthAbbrevEs[prevWeekStart.month - 1];
    expect(
      find.textContaining('${prevWeekStart.day} $expectedPrevRangeMonth'),
      findsOneWidget,
    );
  });

  testWidgets(
      'SCENARIO-WEEK-PAGE-02: › (next week) chevron is disabled while '
      'showing the current week', (tester) async {
    final repo = MockSessionRepository();
    final now =
        argentinaNow(); // ART frame — matches the widget (argentinaNow); no-op on UTC-3, TZ-safe on UTC CI
    final todayOnly = DateTime(now.year, now.month, now.day);

    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: todayOnly.add(const Duration(hours: 9)),
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            routineId: 'r1',
          ),
        ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
        .thenAnswer((_) async => [makeSetLog(id: 'l1', exerciseId: 'e-chest')]);

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
      visibleRoutineByIdProvider('r1').overrideWith((ref) async => null),
    ];

    await tester.pumpWidget(_wrap(const InsightsScreen(), overrides));
    await tester.pumpAndSettle();

    final nextButton = tester.widget<IconButton>(
      find.byKey(const Key('week-strip-next-week')),
    );
    expect(nextButton.onPressed, isNull,
        reason: '› must be disabled on the current week — no future weeks');
  });

  testWidgets(
      'SCENARIO-WEEK-PAGE-03: tapping a day in a past (paged-to) week '
      'updates the muscles card', (tester) async {
    final repo = MockSessionRepository();
    final now =
        argentinaNow(); // ART frame — matches the widget (argentinaNow); no-op on UTC-3, TZ-safe on UTC CI
    final todayOnly = DateTime(now.year, now.month, now.day);
    final currentWeekStart = _mondayOfWeek(todayOnly);
    final prevWeekMonday = DateTime(
      currentWeekStart.year,
      currentWeekStart.month,
      currentWeekStart.day - 7,
    );

    // A session THIS week (so the current week isn't the brand-new-account
    // empty state) plus one on the Monday of the PREVIOUS week.
    final currentWeekSession = makeSession(
      id: 's-current',
      startedAt: todayOnly.add(const Duration(hours: 9)),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
      routineId: 'r1',
    );
    final prevWeekSession = makeSession(
      id: 's-prev-mon',
      startedAt: prevWeekMonday.add(const Duration(hours: 9)),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
      routineId: 'r1',
    );

    when(() => repo.listByUid('u1'))
        .thenAnswer((_) async => [currentWeekSession, prevWeekSession]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-current'))
        .thenAnswer((_) async => [makeSetLog(id: 'l0', exerciseId: 'e-legs')]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-prev-mon'))
        .thenAnswer((_) async => [makeSetLog(id: 'l1', exerciseId: 'e-chest')]);

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
      visibleRoutineByIdProvider('r1').overrideWith((ref) async => null),
    ];

    await tester.pumpWidget(_wrap(const InsightsScreen(), overrides));
    await tester.pumpAndSettle();

    // Page back to the previous week, then tap its Monday (the day the
    // chest session lives on).
    await tester.tap(find.byKey(const Key('week-strip-previous-week')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey(DateTime.utc(
        prevWeekMonday.year, prevWeekMonday.month, prevWeekMonday.day))));
    await tester.pumpAndSettle();

    final pechoRowFinder =
        find.ancestor(of: find.text('PECHO'), matching: find.byType(Row)).first;
    expect(
      find.descendant(of: pechoRowFinder, matching: find.text('1')),
      findsOneWidget,
    );
  });

  testWidgets(
      'SCENARIO-BACK-VIEW-01: MÚSCULOS DEL DÍA card requests BOTH bodyfront '
      'and bodyback assets (showBack: true) — lets the athlete see back '
      'muscles, and does not overflow next to the sets list', (tester) async {
    final repo = MockSessionRepository();
    final now =
        argentinaNow(); // ART frame — matches the widget (argentinaNow); no-op on UTC-3, TZ-safe on UTC CI
    final todayOnly = DateTime(now.year, now.month, now.day);

    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: todayOnly.add(const Duration(hours: 9)),
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            routineId: 'r1',
          ),
        ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
        .thenAnswer((_) async => [
              makeSetLog(id: 'l1', exerciseId: 'e-chest'),
              makeSetLog(id: 'l2', exerciseId: 'e-back'),
            ]);

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
              id: 'e-back',
              name: 'Remo',
              muscleGroup: 'back',
              category: 'compound',
            ),
          ]),
      routineByIdProvider('r1').overrideWith((ref) async => null),
      visibleRoutineByIdProvider('r1').overrideWith((ref) async => null),
    ];

    // Narrow width — the regression this test guards against is a
    // RenderFlex overflow when the front+back silhouette pair sits next to
    // the muscle-sets list at phone-sized widths.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(_wrap(const InsightsScreen(), overrides));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_countMasksContaining(tester, 'assets/body/bodyfront.png'), 1);
    expect(_countMasksContaining(tester, 'assets/body/bodyback.png'), 1);
  });

  // SCENARIO-RADAR-SCREEN-01/02: MOVED to
  // test/features/insights/presentation/muscle_distribution_screen_test.dart
  // (stats-hub, obs #445) — the inline `_MuscleDistributionSection` was
  // promoted to a dedicated `MuscleDistributionScreen`, reached from the
  // hub's "ESTADÍSTICAS AVANZADAS" tile list instead of being inline.

  testWidgets(
      'SCENARIO-HUB-TILES-01: the ESTADÍSTICAS AVANZADAS tile list renders '
      'below the daily muscles card with all 4 tiles (Distribución '
      'muscular, Ejercicios frecuentes, Reporte mensual, Volumen por '
      'grupo)', (tester) async {
    final repo = MockSessionRepository();
    final now =
        argentinaNow(); // ART frame — matches the widget (argentinaNow); no-op on UTC-3, TZ-safe on UTC CI
    final todayOnly = DateTime(now.year, now.month, now.day);

    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: todayOnly.add(const Duration(hours: 9)),
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            routineId: 'r1',
          ),
        ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
        .thenAnswer((_) async => [makeSetLog(id: 'l1', exerciseId: 'e-chest')]);

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
      visibleRoutineByIdProvider('r1').overrideWith((ref) async => null),
    ];

    await tester.pumpWidget(_wrap(const InsightsScreen(), overrides));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Estadísticas avanzadas'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Estadísticas avanzadas'), findsOneWidget);
    expect(find.text('Distribución muscular'), findsOneWidget);
    expect(find.text('Ejercicios frecuentes'), findsOneWidget);
    expect(find.text('Reporte mensual'), findsOneWidget);
    expect(find.text('Volumen por grupo'), findsOneWidget);
    // Inline sections must be GONE — moved to dedicated screens.
    expect(find.text('DISTRIBUCIÓN MUSCULAR'), findsNothing);
    expect(find.text('VOLUMEN POR GRUPO'), findsNothing);
  });

  // Bug fix (abandoned-session-streak-reports): the report hub
  // (`_StatsHubTileList`) must NOT be gated behind THIS week having
  // sessions — an athlete with history but a quiet current week must still
  // reach their historical reports, not the onboarding CTA.
  testWidgets(
      'SCENARIO-EMPTY-GATE-01: athlete WITH history but 0 sessions THIS '
      'week → sees the reports hub, not the onboarding empty state',
      (tester) async {
    final repo = MockSessionRepository();
    final now =
        argentinaNow(); // ART frame — matches the widget (argentinaNow); no-op on UTC-3, TZ-safe on UTC CI
    // A completed session from far in the past — outside the current week,
    // so `sessionsCount` for the shown week is 0, but the athlete DID train
    // before (`hasEverCompletedAnyWorkout` must be true).
    final longAgo = DateTime(now.year - 1, 1, 15, 9);

    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's-old',
            startedAt: longAgo,
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            routineId: 'r1',
          ),
        ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-old'))
        .thenAnswer((_) async => const []);

    final overrides = <Override>[
      currentUidProvider.overrideWithValue('u1'),
      sessionRepositoryProvider.overrideWithValue(repo),
      exercisesProvider.overrideWith((ref) async => const []),
      routineByIdProvider('r1').overrideWith((ref) async => null),
      visibleRoutineByIdProvider('r1').overrideWith((ref) async => null),
    ];

    await tester.pumpWidget(_wrap(const InsightsScreen(), overrides));
    await tester.pumpAndSettle();

    expect(find.text('Empezá a entrenar para ver tus insights.'), findsNothing);

    await tester.scrollUntilVisible(
      find.text('Estadísticas avanzadas'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('Estadísticas avanzadas'), findsOneWidget);
    expect(find.text('Distribución muscular'), findsOneWidget);
  });

  // Bug fix (abandoned-session-streak-reports): a truly brand-new account
  // (never completed a workout) must still see the onboarding CTA.
  testWidgets(
      'SCENARIO-EMPTY-GATE-02: brand-new account with no workouts ever → '
      'sees the onboarding empty state', (tester) async {
    final repo = MockSessionRepository();
    when(() => repo.listByUid('u1')).thenAnswer((_) async => const []);

    final overrides = <Override>[
      currentUidProvider.overrideWithValue('u1'),
      sessionRepositoryProvider.overrideWithValue(repo),
      exercisesProvider.overrideWith((ref) async => const []),
    ];

    await tester.pumpWidget(_wrap(const InsightsScreen(), overrides));
    await tester.pumpAndSettle();

    expect(
        find.text('Empezá a entrenar para ver tus insights.'), findsOneWidget);
    expect(find.text('Estadísticas avanzadas'), findsNothing);
  });

  testWidgets(
      'SCENARIO-HUB-TILES-02: tapping each tile pushes its dedicated route',
      (tester) async {
    final repo = MockSessionRepository();
    final now =
        argentinaNow(); // ART frame — matches the widget (argentinaNow); no-op on UTC-3, TZ-safe on UTC CI
    final todayOnly = DateTime(now.year, now.month, now.day);

    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: todayOnly.add(const Duration(hours: 9)),
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            routineId: 'r1',
          ),
        ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
        .thenAnswer((_) async => [makeSetLog(id: 'l1', exerciseId: 'e-chest')]);

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
      visibleRoutineByIdProvider('r1').overrideWith((ref) async => null),
    ];

    final router = GoRouter(
      initialLocation: '/home/insights',
      routes: [
        GoRoute(
          path: '/home/insights',
          builder: (_, __) => const InsightsScreen(),
        ),
        GoRoute(
          path: '/home/insights/muscle-distribution',
          builder: (_, __) => const Scaffold(
            body: Text('muscle-distribution-route'),
          ),
        ),
        GoRoute(
          path: '/home/insights/frequent-exercises',
          builder: (_, __) => const Scaffold(
            body: Text('frequent-exercises-route'),
          ),
        ),
        GoRoute(
          path: '/home/insights/monthly',
          builder: (_, __) => const Scaffold(
            body: Text('monthly-route'),
          ),
        ),
        GoRoute(
          path: '/home/insights/volume-by-group',
          builder: (_, __) => const Scaffold(
            body: Text('volume-by-group-route'),
          ),
        ),
        GoRoute(
          path: '/home/insights/measurements',
          builder: (_, __) => const Scaffold(
            body: Text('measurements-route'),
          ),
        ),
        GoRoute(
          path: '/home/insights/exercise-progression',
          builder: (_, __) => const Scaffold(
            body: Text('exercise-progression-route'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          theme: AppTheme.dark(),
          routerConfig: router,
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('Distribución muscular'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Distribución muscular'));
    await tester.pumpAndSettle();
    expect(find.text('muscle-distribution-route'), findsOneWidget);

    router.go('/home/insights');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Ejercicios frecuentes'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ejercicios frecuentes'));
    await tester.pumpAndSettle();
    expect(find.text('frequent-exercises-route'), findsOneWidget);

    router.go('/home/insights');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Reporte mensual'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Reporte mensual'));
    await tester.pumpAndSettle();
    expect(find.text('monthly-route'), findsOneWidget);

    router.go('/home/insights');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Volumen por grupo'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Volumen por grupo'));
    await tester.pumpAndSettle();
    expect(find.text('volume-by-group-route'), findsOneWidget);

    // MEDIDAS: el PF carga peso y circunferencias del alumno; ahora el alumno
    // las ve. (Rendimiento NO se surfacea — evaluaciones profesionales del PF.)
    router.go('/home/insights');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Medidas'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Medidas'));
    await tester.pumpAndSettle();
    expect(find.text('measurements-route'), findsOneWidget);

    // Evolución por ejercicio: el destino que no existía del lado del alumno.
    router.go('/home/insights');
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.text('Evolución por ejercicio'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Evolución por ejercicio'));
    await tester.pumpAndSettle();
    expect(find.text('exercise-progression-route'), findsOneWidget);
  });
}

const _monthAbbrevEs = [
  'ENE', 'FEB', 'MAR', 'ABR', 'MAY', 'JUN', //
  'JUL', 'AGO', 'SEP', 'OCT', 'NOV', 'DIC',
];

DateTime _mondayOfWeek(DateTime day) {
  final daysFromMonday = day.weekday - DateTime.monday;
  return DateTime(day.year, day.month, day.day - daysFromMonday);
}
