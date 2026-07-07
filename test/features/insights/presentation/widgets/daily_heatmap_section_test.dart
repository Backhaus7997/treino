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

Widget _wrap(Widget child, List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: TestAppWrapper(child: child),
    );

DailyHeatmapSectionLabels _labels() => const DailyHeatmapSectionLabels(
      sectionTitle: 'MÚSCULOS DEL DÍA',
      dayStripLabels: DayStripLabels(
        todayLabel: 'HOY',
        emptyDayHint: 'No entrenaste este día.',
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
}
