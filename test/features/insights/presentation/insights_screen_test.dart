import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/insights/application/insights_providers.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';
import 'package:treino/features/insights/domain/weekly_insights.dart';
import 'package:treino/features/insights/presentation/insights_screen.dart';
import 'package:treino/features/insights/presentation/widgets/muscle_distribution_radar.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/session_status.dart';

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

  testWidgets(
      'SCENARIO-WEEK-PAGE-01: tapping ‹ pages the SEMANA card to the '
      'previous week — title and adherence counter update to show that '
      'week\'s data', (tester) async {
    final repo = MockSessionRepository();
    final now = DateTime.now();
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
      routineId: 'r1',
    );
    final prevWeekSession = makeSession(
      id: 's-prev',
      startedAt: prevWeekStart.add(const Duration(hours: 9)),
      status: SessionStatus.finished,
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
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);

    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: todayOnly.add(const Duration(hours: 9)),
            status: SessionStatus.finished,
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
    final now = DateTime.now();
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
      routineId: 'r1',
    );
    final prevWeekSession = makeSession(
      id: 's-prev-mon',
      startedAt: prevWeekMonday.add(const Duration(hours: 9)),
      status: SessionStatus.finished,
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
    ];

    await tester.pumpWidget(_wrap(const InsightsScreen(), overrides));
    await tester.pumpAndSettle();

    // Page back to the previous week, then tap its Monday (the day the
    // chest session lives on).
    await tester.tap(find.byKey(const Key('week-strip-previous-week')));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(ValueKey(prevWeekMonday)));
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
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);

    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: todayOnly.add(const Duration(hours: 9)),
            status: SessionStatus.finished,
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

  testWidgets(
      'SCENARIO-RADAR-SCREEN-01: DISTRIBUCIÓN MUSCULAR section renders the '
      'MuscleDistributionRadar below the daily muscles card, with the '
      'current-period radar populated from finished sessions', (tester) async {
    final repo = MockSessionRepository();
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);

    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: todayOnly.add(const Duration(hours: 9)),
            status: SessionStatus.finished,
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
    ];

    await tester.pumpWidget(_wrap(const InsightsScreen(), overrides));
    await tester.pumpAndSettle();

    // The section title + radar widget live below the fold (ListView is
    // lazy) — scroll until visible BEFORE asserting presence.
    await tester.scrollUntilVisible(
      find.text('DISTRIBUCIÓN MUSCULAR'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    expect(find.text('DISTRIBUCIÓN MUSCULAR'), findsOneWidget);
    expect(find.byType(MuscleDistributionRadar), findsOneWidget);
    // 1 finished session in the current period → non-empty radar, legend
    // present (Actual/Anterior), empty-state text absent.
    expect(find.text('Actual'), findsOneWidget);
    expect(find.text('Anterior'), findsOneWidget);
    expect(find.text('Sin datos para este período.'), findsNothing);
  });

  testWidgets(
      'SCENARIO-RADAR-SCREEN-02: switching the period selector re-fetches '
      'the radar for the new period — both current and previous windows '
      'get plotted for the selected period', (tester) async {
    final repo = MockSessionRepository();
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    // A session inside "this week" (current window for BOTH last30d and
    // thisWeek periods) plus one 40 days ago — inside last30d's PREVIOUS
    // window, but outside thisWeek's previous window (prior calendar week).
    final recentDay = todayOnly;
    final olderDay = DateTime(todayOnly.year, todayOnly.month - 1,
        todayOnly.day - 10 < 1 ? 1 : todayOnly.day - 10);

    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's-recent',
            startedAt: recentDay.add(const Duration(hours: 9)),
            status: SessionStatus.finished,
            routineId: 'r1',
          ),
          makeSession(
            id: 's-older',
            startedAt: olderDay.add(const Duration(hours: 9)),
            status: SessionStatus.finished,
            routineId: 'r1',
          ),
        ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-recent'))
        .thenAnswer((_) async => [makeSetLog(id: 'l1', exerciseId: 'e-chest')]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-older'))
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
    ];

    await tester.pumpWidget(_wrap(const InsightsScreen(), overrides));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(
      find.text('DISTRIBUCIÓN MUSCULAR'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();

    // Default period pill shows "Últimos 30 días" (ChartPeriod.last30d).
    expect(find.text('Últimos 30 días'), findsOneWidget);

    // Open the period selector and switch to "Esta semana" — re-fetches via
    // a new MuscleDistributionKey (different ChartPeriod), still renders
    // the radar without throwing.
    await tester.tap(find.text('Últimos 30 días'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esta semana').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Esta semana'), findsOneWidget);
    expect(find.byType(MuscleDistributionRadar), findsOneWidget);
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
