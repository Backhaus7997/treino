import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/presentation/frequent_exercises_screen.dart';
import 'package:treino/features/insights/domain/chart_period.dart';
import 'package:treino/features/workout/application/exercise_frequency_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/exercise_frequency.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../workout/application/stub_factories.dart';

class MockSessionRepository extends Mock implements SessionRepository {}

/// [stats-hub] Athlete-side "Ejercicios frecuentes" screen — reuses the
/// coach-only MostFrequentExercisesList widget with the athlete's OWN uid
/// (obs #445). Mirrors (inverted) the non-current-uid test pattern used
/// elsewhere in the app: here we assert the screen's OWN uid ('me') is the
/// one whose data renders, NOT some other athlete's uid ('other-athlete').
void main() {
  Widget wrap(Widget child, {required List<Override> overrides}) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(body: FrequentExercisesScreen(uid: 'me')),
        ),
      );

  testWidgets(
      'SCENARIO-FREQ-SCREEN-01: renders the OWN uid\'s frequency data (not '
      'another athlete\'s), proving the screen queries the athlete\'s own '
      'uid rather than a hardcoded/coach-selected uid', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
        exerciseFrequencyProvider((
          athleteUid: 'me',
          period: ChartPeriod.defaultPeriod,
        )).overrideWith((ref) async => const [
              ExerciseFrequencyEntry(
                exerciseId: 'e-press',
                exerciseName: 'Press Banca',
                sessionCount: 5,
              ),
            ]),
        // Different uid's data must NOT be the one rendered — proves the
        // screen is wired to 'me', not to this other athlete.
        exerciseFrequencyProvider((
          athleteUid: 'other-athlete',
          period: ChartPeriod.defaultPeriod,
        )).overrideWith((ref) async => const [
              ExerciseFrequencyEntry(
                exerciseId: 'e-squat',
                exerciseName: 'Sentadilla',
                sessionCount: 99,
              ),
            ]),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('EJERCICIOS FRECUENTES'), findsOneWidget);
    expect(find.text('Press Banca'), findsOneWidget);
    expect(find.text('Sentadilla'), findsNothing);
  });

  testWidgets(
      'SCENARIO-FREQ-SCREEN-02: tocar una fila navega a la progresión de ESE '
      'ejercicio, ya preseleccionado', (tester) async {
    // Este escenario afirmaba lo CONTRARIO ("tapping a row is a no-op — no
    // athlete-side exercise progression destination exists yet"). Ese "yet"
    // era una promesa: ExerciseProgressionScreen es ahora ese destino, y las
    // filas navegan pasándole el exerciseId por query param.
    final router = GoRouter(
      initialLocation: '/home/insights/frequent-exercises',
      routes: [
        GoRoute(
          path: '/home/insights/frequent-exercises',
          builder: (_, __) => const Scaffold(
            body: FrequentExercisesScreen(uid: 'me'),
          ),
        ),
        GoRoute(
          path: '/home/insights/exercise-progression',
          builder: (_, state) => Scaffold(
            // Se assertea el exerciseId, no sólo que "navegó a algún lado":
            // llegar a la pantalla sin el ejercicio tocado sería un bug mudo.
            body: Text(
              'progression:${state.uri.queryParameters['exerciseId']}',
            ),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        exerciseFrequencyProvider((
          athleteUid: 'me',
          period: ChartPeriod.defaultPeriod,
        )).overrideWith((ref) async => const [
              ExerciseFrequencyEntry(
                exerciseId: 'e-press',
                exerciseName: 'Press Banca',
                sessionCount: 5,
              ),
            ]),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        routerConfig: router,
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Press Banca'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('progression:e-press'), findsOneWidget);
  });

  testWidgets(
      'SCENARIO-FREQ-SCREEN-03: switching the period selector re-fetches '
      'for the new period', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
        exerciseFrequencyProvider((
          athleteUid: 'me',
          period: ChartPeriod.defaultPeriod,
        )).overrideWith((ref) async => const [
              ExerciseFrequencyEntry(
                exerciseId: 'e-press',
                exerciseName: 'Press Banca',
                sessionCount: 5,
              ),
            ]),
        exerciseFrequencyProvider((
          athleteUid: 'me',
          period: ChartPeriod.thisWeek,
        )).overrideWith((ref) async => const [
              ExerciseFrequencyEntry(
                exerciseId: 'e-row',
                exerciseName: 'Remo',
                sessionCount: 2,
              ),
            ]),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Últimos 30 días'), findsOneWidget);
    expect(find.text('Press Banca'), findsOneWidget);

    await tester.tap(find.text('Últimos 30 días'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esta semana').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Esta semana'), findsOneWidget);
    expect(find.text('Remo'), findsOneWidget);
  });

  testWidgets(
      'SCENARIO-FREQ-SCREEN-04 (QA-INS-005): on load failure shows the error '
      'message + retry, NOT a blank screen', (tester) async {
    // Antes esta rama era `SizedBox.shrink()`: una carga fallida dejaba la
    // pantalla en blanco, sin mensaje ni forma de reintentar.
    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
        exerciseFrequencyProvider((
          athleteUid: 'me',
          period: ChartPeriod.defaultPeriod,
        )).overrideWith((ref) async => throw Exception('boom')),
      ],
    ));
    await tester.pumpAndSettle();

    expect(
      find.text('No pudimos cargar tus ejercicios frecuentes. Probá de nuevo.'),
      findsOneWidget,
    );
    expect(find.text('Reintentar'), findsOneWidget);
  });

  testWidgets(
      'SCENARIO-FREQ-SCREEN-05 (#376): tapping Reintentar actually recovers — '
      'it re-fetches the sessions dependency, not just the frequency provider',
      (tester) async {
    // `ref.invalidate` does NOT cascade to dependencies, and the screen keeps
    // sessionsByUidProvider alive (watched via exerciseFrequencyProvider), so
    // its AsyncError stays cached across the rebuild. Invalidating only
    // exerciseFrequencyProvider replayed the SAME cached sessions error
    // forever, so the button could never recover the very case that brings
    // the user here (offline / failed sessions fetch). Same graph-shaped bug
    // muscle_distribution_screen already pinned with its recovery test.
    final repo = MockSessionRepository();
    final now = DateTime.now();
    final todayOnly = DateTime(now.year, now.month, now.day);

    // Cold sessions fetch fails once (offline), then succeeds.
    var sessionAttempts = 0;
    when(() => repo.listByUid('me', limit: any(named: 'limit')))
        .thenAnswer((_) async {
      sessionAttempts++;
      if (sessionAttempts == 1) throw Exception('sessions fetch failed');
      return [
        makeSession(
          id: 's1',
          startedAt: todayOnly.add(const Duration(hours: 9)),
          status: SessionStatus.finished,
          wasFullyCompleted: true,
        ),
      ];
    });
    when(() => repo.listSetLogs(uid: 'me', sessionId: 's1'))
        .thenAnswer((_) async => [
              makeSetLog(
                id: 'l1',
                exerciseId: 'e-press',
                exerciseName: 'Press Banca',
              ),
            ]);

    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [sessionRepositoryProvider.overrideWithValue(repo)],
    ));
    await tester.pumpAndSettle();

    expect(
      find.text('No pudimos cargar tus ejercicios frecuentes. Probá de nuevo.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(sessionAttempts, 2,
        reason: 'retry must re-fetch sessions, not replay the cached error');
    expect(find.text('Press Banca'), findsOneWidget);
    expect(
      find.text('No pudimos cargar tus ejercicios frecuentes. Probá de nuevo.'),
      findsNothing,
    );
  });
}
