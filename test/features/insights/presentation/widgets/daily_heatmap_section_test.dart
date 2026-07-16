import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/insights/presentation/widgets/day_strip_labels.dart';
import 'package:treino/features/insights/presentation/widgets/daily_heatmap_section.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider, sessionRepositoryProvider;
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/session_status.dart';

import '../../../../helpers/test_app_wrapper.dart';
import '../../../workout/application/stub_factories.dart';

class _MockSessionRepository extends Mock implements SessionRepository {}

// Both real coach shells place [DailyHeatmapSection] inside a scrollable
// container (mobile: `ListView`, web: `SingleChildScrollView`) — wrap it
// here too so the widget test's constraints match production instead of
// the bare `Scaffold` in `TestAppWrapper`, which would otherwise report a
// false-positive overflow for content taller than the default 800x600 test
// surface.
Widget _wrap(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: TestAppWrapper(child: SingleChildScrollView(child: child)),
    );

int _countMasksContaining(WidgetTester tester, String pathFragment) {
  return tester.widgetList<Image>(find.byType(Image)).where((img) {
    final provider = img.image;
    if (provider is! AssetImage) return false;
    return provider.assetName.contains(pathFragment);
  }).length;
}

DailyHeatmapSectionLabels _labels() => const DailyHeatmapSectionLabels(
      sectionTitle: 'MÚSCULOS DEL DÍA',
      dayStripLabels: DayStripLabels(
        todayLabel: 'HOY',
        emptyDayHint: 'No entrenaste este día.',
        weekdayLetters: ['L', 'M', 'M', 'J', 'V', 'S', 'D'],
      ),
    );

void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  testWidgets(
      'SCENARIO-DAILY-HEATMAP-SECTION-01: renders per-day data for a '
      'NON-current uid (proves no currentUidProvider leak — the shared '
      'section must be driven entirely by the athleteId param, as required '
      'when the coach views an alumno that is NOT the signed-in user)',
      (tester) async {
    final repo = _MockSessionRepository();
    final today = DateTime.now();
    final todayOnly = DateTime(today.year, today.month, today.day);

    const alumnoUid = 'alumno-999';
    const currentCoachUid = 'coach-111';

    final todaySession = makeSession(
      id: 's-today',
      uid: alumnoUid,
      startedAt: todayOnly.add(const Duration(hours: 9)),
      status: SessionStatus.finished,
      wasFullyCompleted: true,
      routineId: 'r1',
    );

    when(() => repo.listByUid(alumnoUid))
        .thenAnswer((_) async => [todaySession]);
    // If the widget ever leaks currentUidProvider instead of the explicit
    // athleteId param, this stub is what would get hit instead — and it
    // returns an EMPTY session list, so the test would fail loudly (blank
    // silhouette / 0 sets) rather than silently passing.
    when(() => repo.listByUid(currentCoachUid)).thenAnswer((_) async => []);
    when(() => repo.listSetLogs(uid: alumnoUid, sessionId: 's-today'))
        .thenAnswer((_) async => [makeSetLog(id: 'l1', exerciseId: 'e-chest')]);

    final overrides = <Override>[
      currentUidProvider.overrideWithValue(currentCoachUid),
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

    await tester.pumpWidget(
      _wrap(
        DailyHeatmapSection(athleteId: alumnoUid, labels: _labels()),
        overrides,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('MÚSCULOS DEL DÍA'), findsOneWidget);

    final pechoRowFinder =
        find.ancestor(of: find.text('PECHO'), matching: find.byType(Row)).first;
    expect(
      find.descendant(of: pechoRowFinder, matching: find.text('1')),
      findsOneWidget,
      reason: 'section must render the ALUMNO\'s trained muscle for today, '
          'not the signed-in coach\'s (empty) data',
    );
  });

  testWidgets(
      'SCENARIO-DAILY-HEATMAP-SECTION-02: empty day for the given athleteId '
      'shows the empty-day hint, not stale/leaked data', (tester) async {
    final repo = _MockSessionRepository();
    const alumnoUid = 'alumno-empty';

    when(() => repo.listByUid(alumnoUid)).thenAnswer((_) async => []);

    final overrides = <Override>[
      currentUidProvider.overrideWithValue('coach-111'),
      sessionRepositoryProvider.overrideWithValue(repo),
      exercisesProvider.overrideWith((ref) async => const []),
    ];

    await tester.pumpWidget(
      _wrap(
        DailyHeatmapSection(athleteId: alumnoUid, labels: _labels()),
        overrides,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('No entrenaste este día.'), findsWidgets);
  });

  testWidgets(
      'SCENARIO-DAILY-HEATMAP-SECTION-03 (SCENARIO-BACK-VIEW-COACH-01): '
      'section requests BOTH bodyfront and bodyback assets (showBack: true) '
      '— lets the coach see the alumno\'s back muscles, and does not '
      'overflow next to the sets list', (tester) async {
    final repo = _MockSessionRepository();
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);
    const alumnoUid = 'alumno-back-view';

    when(() => repo.listByUid(alumnoUid)).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            uid: alumnoUid,
            startedAt: todayOnly.add(const Duration(hours: 9)),
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            routineId: 'r1',
          ),
        ]);
    when(() => repo.listSetLogs(uid: alumnoUid, sessionId: 's1'))
        .thenAnswer((_) async => [
              makeSetLog(id: 'l1', exerciseId: 'e-chest'),
              makeSetLog(id: 'l2', exerciseId: 'e-back'),
            ]);

    final overrides = <Override>[
      currentUidProvider.overrideWithValue('coach-111'),
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

    await tester.pumpWidget(
      _wrap(
        DailyHeatmapSection(athleteId: alumnoUid, labels: _labels()),
        overrides,
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(_countMasksContaining(tester, 'assets/body/bodyfront.png'), 1);
    expect(_countMasksContaining(tester, 'assets/body/bodyback.png'), 1);
  });
}
