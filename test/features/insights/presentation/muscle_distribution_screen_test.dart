import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/presentation/muscle_distribution_screen.dart';
import 'package:treino/features/insights/presentation/widgets/muscle_distribution_radar.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

/// [stats-hub] Tests moved from insights_screen_test.dart's
/// SCENARIO-RADAR-SCREEN-01/02 (obs #445) — the inline
/// `_MuscleDistributionSection` was promoted to this dedicated screen,
/// reached from InsightsScreen's "ESTADÍSTICAS AVANZADAS" tile list.
void main() {
  setUpAll(() {
    registerFallbackValue(makeSession());
    registerFallbackValue(makeSetLog());
  });

  Widget wrap(Widget child, {required List<Override> overrides}) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(body: MuscleDistributionScreen(uid: 'u1')),
        ),
      );

  testWidgets(
      'SCENARIO-RADAR-SCREEN-01: renders MuscleDistributionRadar with the '
      'current-period radar populated from finished sessions', (tester) async {
    final repo = MockSessionRepository();
    final now = DateTime.now();
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

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => [
              const Exercise(
                id: 'e-chest',
                name: 'Press',
                muscleGroup: 'chest',
                category: 'compound',
              ),
            ]),
        visibleRoutineByIdProvider('r1').overrideWith((ref) async => null),
      ],
    ));
    await tester.pumpAndSettle();

    // Both the header title and the card's section title read
    // "DISTRIBUCIÓN MUSCULAR" (same label bag) — 2 matches, not 1.
    expect(find.text('DISTRIBUCIÓN MUSCULAR'), findsNWidgets(2));
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
            wasFullyCompleted: true,
            routineId: 'r1',
          ),
          makeSession(
            id: 's-older',
            startedAt: olderDay.add(const Duration(hours: 9)),
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            routineId: 'r1',
          ),
        ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-recent'))
        .thenAnswer((_) async => [makeSetLog(id: 'l1', exerciseId: 'e-chest')]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's-older'))
        .thenAnswer((_) async => [makeSetLog(id: 'l2', exerciseId: 'e-legs')]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
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
        visibleRoutineByIdProvider('r1').overrideWith((ref) async => null),
      ],
    ));
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

  testWidgets(
      'a session whose routine is GONE still renders the radar — one dead '
      'routine must not blank the whole card', (tester) async {
    // Regression for the reported bug: the card rendered EMPTY (no chart, no
    // empty state) because the routine read for a deleted routine failed,
    // erroring the whole provider, and the error branch was a silent
    // SizedBox.shrink().
    final repo = MockSessionRepository();
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);

    when(() => repo.listByUid('u1')).thenAnswer((_) async => [
          makeSession(
            id: 's1',
            startedAt: todayOnly.add(const Duration(hours: 9)),
            status: SessionStatus.finished,
            wasFullyCompleted: true,
            routineId: 'deleted-routine',
          ),
        ]);
    when(() => repo.listSetLogs(uid: 'u1', sessionId: 's1'))
        .thenAnswer((_) async => [makeSetLog(id: 'l1', exerciseId: 'e-chest')]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => [
              const Exercise(
                id: 'e-chest',
                name: 'Press',
                muscleGroup: 'chest',
                category: 'compound',
              ),
            ]),
        visibleRoutineByIdProvider('deleted-routine')
            .overrideWith((ref) async => null),
      ],
    ));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(MuscleDistributionRadar), findsOneWidget);
    expect(find.text('Actual'), findsOneWidget);
    expect(
        find.text(
            'No pudimos cargar tu distribución muscular. Probá de nuevo.'),
        findsNothing);
  });

  testWidgets(
      'a provider failure surfaces a visible error state — never a blank card',
      (tester) async {
    // The silent `SizedBox.shrink()` error branch is what made the original
    // bug undiagnosable: an empty card is indistinguishable from "no data".
    // Any future failure must be VISIBLE.
    final repo = MockSessionRepository();
    when(() => repo.listByUid('u1'))
        .thenAnswer((_) async => throw Exception('boom'));

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => []),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.byType(MuscleDistributionRadar), findsNothing);
    expect(
      find.text('No pudimos cargar tu distribución muscular. Probá de nuevo.'),
      findsOneWidget,
    );
  });

  testWidgets(
      'tapping Reintentar actually recovers — it re-fetches the dependencies, '
      'not just the radar provider', (tester) async {
    // The retry was a permanent no-op: `ref.invalidate` does NOT cascade to
    // dependencies, and exercisesProvider is NOT autoDispose — it caches its
    // AsyncError for the container's lifetime. Invalidating only the radar
    // provider replayed the SAME cached catalogue error forever, so the button
    // could never recover the very case that brings the user here.
    final repo = MockSessionRepository();
    final now = DateTime.now();
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

    // Cold catalogue fetch fails once (offline), then succeeds.
    var catalogAttempts = 0;

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
        sessionRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async {
          catalogAttempts++;
          if (catalogAttempts == 1) throw Exception('catalogue fetch failed');
          return [
            const Exercise(
              id: 'e-chest',
              name: 'Press',
              muscleGroup: 'chest',
              category: 'compound',
            ),
          ];
        }),
        visibleRoutineByIdProvider('r1').overrideWith((ref) async => null),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.byType(MuscleDistributionRadar), findsNothing);
    expect(
      find.text('No pudimos cargar tu distribución muscular. Probá de nuevo.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(catalogAttempts, 2,
        reason:
            'retry must re-fetch the catalogue, not replay its cached error');
    expect(find.byType(MuscleDistributionRadar), findsOneWidget);
    expect(
      find.text('No pudimos cargar tu distribución muscular. Probá de nuevo.'),
      findsNothing,
    );
  });
}
