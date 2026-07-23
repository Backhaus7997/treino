// Tests for AthleteDetailScreen — SCENARIO-455, 456, REQ-SETLOGS-008..010
// REQ-COACH-PLANS-020, 021, 022

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/presentation/athlete_detail_screen.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart'
    show routineByIdStreamProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show
        currentUidProvider,
        sessionsByUidProvider,
        coachSessionSetLogsProvider,
        sessionRepositoryProvider;
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/performance/domain/performance_test.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/measurements/presentation/log_measurement_screen.dart';

class _MockSessionRepository extends Mock implements SessionRepository {}

// ── Fixtures ──────────────────────────────────────────────────────────────────

Session _makeSession({
  required String id,
  required bool wasFullyCompleted,
  SessionStatus status = SessionStatus.finished,
}) =>
    Session(
      id: id,
      uid: 'athlete-1',
      routineId: 'routine-1',
      routineName: 'Plan Test',
      startedAt: DateTime(2024, 1, 10, 8),
      finishedAt: DateTime(2024, 1, 10, 9),
      status: status,
      wasFullyCompleted: wasFullyCompleted,
      totalVolumeKg: 500,
      durationMin: 60,
    );

SetLog _makeSetLog({
  required String id,
  String exerciseId = 'ex-1',
  String exerciseName = 'Sentadilla',
  int setNumber = 1,
  int reps = 10,
  double weightKg = 80.0,
}) =>
    SetLog(
      id: id,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      setNumber: setNumber,
      reps: reps,
      weightKg: weightKg,
      completedAt: DateTime(2024, 1, 10, 9),
    );

UserPublicProfile _makeProfile(String uid, String name) => UserPublicProfile(
      uid: uid,
      displayName: name,
      displayNameLowercase: name.toLowerCase(),
    );

/// QA-PERF-104 fixture: whole-number doubles (cmjCm/squat1rmKg/vo2maxMlKgMin)
/// must render without the ".0" tail; sprint keeps its one decimal.
PerformanceTest _makePerfTest() => PerformanceTest(
      id: 'pt-1',
      athleteId: 'athlete-1',
      recordedBy: 'trainer-1',
      recordedAt: DateTime(2026, 1, 15),
      cmjCm: 30,
      squat1rmKg: 100,
      sprint20mS: 2.9,
      vo2maxMlKgMin: 55,
    );

Routine _makePlan({
  String id = 'plan-1',
  String name = 'Plan Fuerza',
  String assignedBy = 'trainer-1',
  String assignedTo = 'athlete-1',
}) =>
    Routine(
      id: id,
      name: name,
      split: 'PPL',
      level: ExperienceLevel.beginner,
      days: const [],
      source: RoutineSource.trainerAssigned,
      assignedBy: assignedBy,
      assignedTo: assignedTo,
      visibility: RoutineVisibility.private,
    );

/// Same plan as [_makePlan] but with a non-empty `days` list, so that when
/// `routineByIdStreamProvider` resolves with this value, RoutineDetailScreen
/// renders `_RoutineDetailContent` (the day title + stat row) instead of
/// `_EmptyState` — proof the detail screen shows real content, not blank.
/// `slots: const []` on the single day keeps `_SlotRowWithLastWeight` out of
/// the tree (spec SCENARIO-046 allows empty slots), which sidesteps needing
/// to override `currentUidProvider`/`lastWeightByExerciseProvider` — mirrors
/// the override footprint router_workout_routes_test.dart uses for
/// SCENARIO-110 (only `routineByIdStreamProvider` overridden).
Routine _makeDetailedPlan({
  required String id,
  required String name,
  required String assignedBy,
  required String assignedTo,
}) =>
    Routine(
      id: id,
      name: name,
      split: 'PPL',
      level: ExperienceLevel.beginner,
      days: const [
        RoutineDay(dayNumber: 1, name: 'Día de Empuje', slots: []),
      ],
      source: RoutineSource.trainerAssigned,
      assignedBy: assignedBy,
      assignedTo: assignedTo,
      visibility: RoutineVisibility.private,
    );

// ── Helpers ───────────────────────────────────────────────────────────────────

Future<void> _pumpScreen(
  WidgetTester tester, {
  required String athleteId,
  required List<Override> overrides,
}) async {
  final router = GoRouter(
    initialLocation: '/coach/athlete/$athleteId',
    routes: [
      ShellRoute(
        builder: (context, state, child) =>
            Scaffold(body: child, bottomNavigationBar: const SizedBox()),
        routes: [
          GoRoute(
            path: '/coach/athlete/:athleteId',
            builder: (context, state) => AthleteDetailScreen(
              athleteId: state.pathParameters['athleteId']!,
            ),
          ),
          GoRoute(
            path: '/workout/routine-editor/:athleteId',
            builder: (_, state) => Scaffold(
              body: Text('RoutineEditor:${state.pathParameters['athleteId']}'),
            ),
          ),
        ],
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('AthleteDetailScreen', () {
    testWidgets(
        'SCENARIO-455: renders athlete header, empty plans list, and CREAR PLAN CTA',
        (tester) async {
      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          currentUidProvider.overrideWithValue('trainer-1'),
          userPublicProfileProvider('athlete-1').overrideWith(
            (ref) => Stream.value(_makeProfile('athlete-1', 'Martín García')),
          ),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) async => const [],
          ),
        ],
      );

      await tester.pumpAndSettle();

      // Athlete name in header (appears in AppBar title and in body header)
      expect(find.text('Martín García'), findsWidgets);
      // Empty state text
      expect(find.text('Todavía no le asignaste planes.'), findsOneWidget);
      // CREAR PLAN button
      expect(find.text('CREAR PLAN'), findsOneWidget);
    });

    testWidgets(
        'SCENARIO-455 (triangulate): renders plan cards when trainer has assigned plans',
        (tester) async {
      final myPlan = _makePlan(
        id: 'plan-1',
        name: 'Plan Hipertrofia',
        assignedBy: 'trainer-1',
        assignedTo: 'athlete-1',
      );
      final otherPlan = _makePlan(
        id: 'plan-2',
        name: 'Plan Otro PF',
        assignedBy: 'trainer-99',
        // should be filtered out
        assignedTo: 'athlete-1',
      );

      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          currentUidProvider.overrideWithValue('trainer-1'),
          userPublicProfileProvider('athlete-1').overrideWith(
            (ref) => Stream.value(_makeProfile('athlete-1', 'Martín García')),
          ),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) async => [myPlan, otherPlan],
          ),
        ],
      );

      await tester.pumpAndSettle();

      // Only the plan assigned by the current trainer should be visible
      expect(find.text('Plan Hipertrofia'), findsOneWidget);
      expect(find.text('Plan Otro PF'), findsNothing);
      // No empty state because trainer has plans
      expect(find.text('Todavía no le asignaste planes.'), findsNothing);
    });

    testWidgets(
        'SCENARIO-456: tapping CREAR PLAN navigates to routine-editor route',
        (tester) async {
      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          currentUidProvider.overrideWithValue('trainer-1'),
          userPublicProfileProvider('athlete-1').overrideWith(
            (ref) => Stream.value(_makeProfile('athlete-1', 'Martín García')),
          ),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) async => const [],
          ),
        ],
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('CREAR PLAN'));
      await tester.pumpAndSettle();

      expect(find.text('RoutineEditor:athlete-1'), findsOneWidget);
    });

    testWidgets('Fase B: renderiza botón MENSAJE en el footer', (tester) async {
      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          currentUidProvider.overrideWithValue('trainer-1'),
          userPublicProfileProvider('athlete-1').overrideWith(
            (ref) => Stream.value(_makeProfile('athlete-1', 'Martín García')),
          ),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) async => const [],
          ),
        ],
      );

      await tester.pumpAndSettle();

      expect(find.text('MENSAJE'), findsOneWidget);
    });
  });

  // ── Issue #399 — plan-card tap must land on the top-level plan route ──────
  //
  // The bug: AthleteDetailScreen lives OUTSIDE the ShellRoute (top-level,
  // wrapped in `_immersive`), but the plan card's onTap used to push
  // '/workout/routine/{id}' — a route INSIDE the ShellRoute. Crossing from a
  // top-level route into a shell route that way rebuilds the shell branch and
  // renders blank. The fix registers a new top-level route
  // '/coach/athlete/:athleteId/plan/:routineId' (see router.dart, right after
  // '/coach/athlete/:athleteId') and the card now pushes that instead.
  //
  // `_pumpScreen` above nests '/coach/athlete/:athleteId' INSIDE a ShellRoute,
  // which does NOT reproduce production's placement — that's why the bug
  // shipped without a failing test. This group builds a router with BOTH
  // routes top-level (siblings, no ShellRoute wrapper), matching router.dart.
  group('AthleteDetailScreen — issue #399 (plan card cross-shell navigation)',
      () {
    // Mirrors router.dart's private `_immersive(child)` helper: both
    // '/coach/athlete/:athleteId' and the new plan route wrap their screen
    // in a Scaffold this way in production (screens are bare Columns with no
    // Scaffold of their own). Reproducing it here matters functionally, not
    // just cosmetically — AthleteDetailScreen's plan-card InkWell needs a
    // Material ancestor, which only the Scaffold provides.
    Widget immersive(Widget child) => Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(child: child),
        );

    Future<GoRouter> pumpWithTopLevelPlanRoute(
      WidgetTester tester, {
      required String athleteId,
      required List<Override> overrides,
    }) async {
      final router = GoRouter(
        initialLocation: '/coach/athlete/$athleteId',
        routes: [
          // Top-level — mirrors router.dart's '/coach/athlete/:athleteId'
          // (outside any ShellRoute, wrapped in `_immersive` in production).
          GoRoute(
            path: '/coach/athlete/:athleteId',
            builder: (context, state) => immersive(
              AthleteDetailScreen(
                athleteId: state.pathParameters['athleteId']!,
              ),
            ),
          ),
          // Top-level — mirrors router.dart's new
          // '/coach/athlete/:athleteId/plan/:routineId' sibling route, added
          // by the #399 fix. MUST NOT be nested in a ShellRoute: that would
          // silently "fix" the test without reproducing the bug's condition.
          GoRoute(
            path: '/coach/athlete/:athleteId/plan/:routineId',
            builder: (context, state) => immersive(
              RoutineDetailScreen(
                routineId: state.pathParameters['routineId']!,
              ),
            ),
          ),
        ],
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides,
          child: MaterialApp.router(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            routerConfig: router,
          ),
        ),
      );
      return router;
    }

    testWidgets(
        'REGRESSION-399: tapping a plan card navigates to the top-level '
        'plan route and renders RoutineDetailScreen content (not blank)',
        (tester) async {
      final myPlan = _makePlan(
        id: 'plan-1',
        name: 'Plan Hipertrofia',
        assignedBy: 'trainer-1',
        assignedTo: 'athlete-1',
      );
      // Separate fixture with non-empty `days` so RoutineDetailScreen renders
      // real content once routineByIdStreamProvider resolves — same `id` as
      // myPlan so it's what the pushed route looks up.
      final detailedPlan = _makeDetailedPlan(
        id: 'plan-1',
        name: 'Plan Hipertrofia',
        assignedBy: 'trainer-1',
        assignedTo: 'athlete-1',
      );

      final router = await pumpWithTopLevelPlanRoute(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          currentUidProvider.overrideWithValue('trainer-1'),
          userPublicProfileProvider('athlete-1').overrideWith(
            (ref) => Stream.value(_makeProfile('athlete-1', 'Martín García')),
          ),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) async => [myPlan],
          ),
          // RoutineDetailScreen watches this for widget.routineId — override
          // so it resolves to a routine with content instead of hanging in
          // loading (StreamProvider.autoDispose.family<Routine?, String>).
          routineByIdStreamProvider('plan-1').overrideWith(
            (ref) => Stream.value(detailedPlan),
          ),
        ],
      );

      await tester.pumpAndSettle();

      // Sanity check: the plan card rendered before we tap it.
      expect(find.text('Plan Hipertrofia'), findsOneWidget);

      // Sanity check: the tap target InkWell (whole card) exists — asserted
      // separately from the tap itself, which targets the plan-name Text.
      // Tapping the InkWell's own bounding-box center would land on one of
      // the trailing 44x44 edit/delete IconButtons instead (their own
      // InkResponse claims the hit first), so tap the Text directly — it
      // sits unambiguously inside the card's InkWell and outside both
      // IconButtons' hit areas.
      expect(
        find.ancestor(
          of: find.text('Plan Hipertrofia'),
          matching: find.byType(InkWell),
        ),
        findsOneWidget,
      );

      await tester.tap(find.text('Plan Hipertrofia'));
      await tester.pumpAndSettle();

      // Real assertion #1: the router's match stack actually landed on the
      // new top-level plan route, not the old in-shell '/workout/routine/:id'.
      // NOTE: `currentConfiguration.uri` deliberately does NOT reflect
      // ImperativeRouteMatch entries (go_router's own doc comment on
      // RouteMatchList.uri) — context.push() always produces one, so the
      // pushed leaf must be read from `matches.last.matchedLocation` instead.
      expect(
        router.routerDelegate.currentConfiguration.matches.last.matchedLocation,
        equals('/coach/athlete/athlete-1/plan/plan-1'),
      );

      // Real assertion #2: RoutineDetailScreen actually rendered content for
      // that routine (the day title), proving the screen is NOT blank —
      // this is the exact failure mode issue #399 produced.
      expect(find.byType(RoutineDetailScreen), findsOneWidget);
      expect(find.text('DÍA DE EMPUJE'), findsOneWidget);
    });
  });

  // ── REQ-SETLOGS-008, 009, 010 — Session history section ──────────────────

  group('AthleteDetailScreen — historial de sesiones (REQ-SETLOGS-010)', () {
    // Overrides shared by all history tests (profile + plans stay fixed).
    List<Override> _base() => [
          currentUidProvider.overrideWithValue('trainer-1'),
          userPublicProfileProvider('athlete-1').overrideWith(
            (ref) => Stream.value(_makeProfile('athlete-1', 'Martín García')),
          ),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) async => const [],
          ),
        ];

    testWidgets(
        'REQ-SETLOGS-010: muestra sesiones completadas y oculta las abandonadas',
        (tester) async {
      final finished = _makeSession(id: 'ses-1', wasFullyCompleted: true);
      final abandoned = _makeSession(id: 'ses-2', wasFullyCompleted: false);

      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          ..._base(),
          sessionsByUidProvider('athlete-1').overrideWith(
            (ref) async => [finished, abandoned],
          ),
          coachSessionSetLogsProvider(
                  (athleteUid: 'athlete-1', sessionId: 'ses-1'))
              .overrideWith((ref) async => []),
        ],
      );

      await tester.pumpAndSettle();

      // Section label must appear
      expect(find.text('HISTORIAL DE SESIONES'), findsOneWidget);
      // The finished session's routine name appears; abandoned does NOT add a
      // second row (same routineName so check the section label presence is
      // enough — both have same name, so we verify count instead).
      expect(find.text('Plan Test'), findsOneWidget);
    });

    testWidgets(
        'REQ-SETLOGS-010: tap en sesión carga coachSessionSetLogsProvider',
        (tester) async {
      final finished = _makeSession(id: 'ses-1', wasFullyCompleted: true);
      final log = _makeSetLog(id: 'log-1');

      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          ..._base(),
          sessionsByUidProvider('athlete-1').overrideWith(
            (ref) async => [finished],
          ),
          coachSessionSetLogsProvider(
                  (athleteUid: 'athlete-1', sessionId: 'ses-1'))
              .overrideWith((ref) async => [log]),
        ],
      );

      await tester.pumpAndSettle();

      // Tap the session row to expand
      await tester.tap(find.text('Plan Test'));
      await tester.pumpAndSettle();

      // SessionExerciseBlock should render the exercise name
      expect(find.text('Sentadilla'), findsOneWidget);
    });

    testWidgets(
        'REQ-SETLOGS-008: permission-denied muestra coachAthleteNoSharePlaceholder',
        (tester) async {
      final finished = _makeSession(id: 'ses-1', wasFullyCompleted: true);

      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          ..._base(),
          sessionsByUidProvider('athlete-1').overrideWith(
            (ref) async => [finished],
          ),
          coachSessionSetLogsProvider(
                  (athleteUid: 'athlete-1', sessionId: 'ses-1'))
              .overrideWith((ref) async => throw FirebaseException(
                    plugin: 'cloud_firestore',
                    code: 'permission-denied',
                  )),
        ],
      );

      await tester.pumpAndSettle();

      // Tap to expand
      await tester.tap(find.text('Plan Test'));
      await tester.pumpAndSettle();

      // Placeholder appears, no crash
      expect(find.text('El alumno no compartió su historial todavía.'),
          findsOneWidget);
    });

    testWidgets(
        'REQ-SETLOGS-009: no hay botón de editar/borrar en la expansión',
        (tester) async {
      final finished = _makeSession(id: 'ses-1', wasFullyCompleted: true);
      final log = _makeSetLog(id: 'log-1');

      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          ..._base(),
          sessionsByUidProvider('athlete-1').overrideWith(
            (ref) async => [finished],
          ),
          coachSessionSetLogsProvider(
                  (athleteUid: 'athlete-1', sessionId: 'ses-1'))
              .overrideWith((ref) async => [log]),
        ],
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Plan Test'));
      await tester.pumpAndSettle();

      // No edit or delete button should exist in the tree
      expect(find.byTooltip('Editar'), findsNothing);
      expect(find.byTooltip('Eliminar'), findsNothing);
    });

    testWidgets(
        'REQ-SETLOGS-010: setLogs vacíos muestran coachSessionSetLogsEmpty',
        (tester) async {
      final finished = _makeSession(id: 'ses-1', wasFullyCompleted: true);

      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          ..._base(),
          sessionsByUidProvider('athlete-1').overrideWith(
            (ref) async => [finished],
          ),
          coachSessionSetLogsProvider(
                  (athleteUid: 'athlete-1', sessionId: 'ses-1'))
              .overrideWith((ref) async => []),
        ],
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Plan Test'));
      await tester.pumpAndSettle();

      expect(
          find.text('Esta sesión no tiene sets registrados.'), findsOneWidget);
    });
  });

  // ── PR2b — Daily heat-map section wrapper (AD5) ───────────────────────────

  group('AthleteDetailScreen — daily heat-map section (PR2b, AD5)', () {
    setUpAll(() {
      registerFallbackValue(
          _makeSession(id: 'fallback', wasFullyCompleted: true));
    });

    testWidgets(
        'SCENARIO-DAILY-HEATMAP-COACH-01: renders the mobile wrapper\'s '
        'AppL10n section title, driven by the alumno\'s athleteId',
        (tester) async {
      final repo = _MockSessionRepository();
      when(() => repo.listByUid('athlete-1')).thenAnswer((_) async => []);

      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          currentUidProvider.overrideWithValue('trainer-1'),
          userPublicProfileProvider('athlete-1').overrideWith(
            (ref) => Stream.value(_makeProfile('athlete-1', 'Martín García')),
          ),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) async => const [],
          ),
          sessionsByUidProvider('athlete-1').overrideWith(
            (ref) async => const [],
          ),
          sessionRepositoryProvider.overrideWithValue(repo),
          exercisesProvider.overrideWith((ref) async => const []),
        ],
      );

      await tester.pumpAndSettle();

      // The wrapper injects l10n.coachDailyHeatmapSectionTitle — proves the
      // AD5 label bag reaches the shared DailyHeatmapSection correctly.
      expect(find.text('MÚSCULOS DEL DÍA'), findsOneWidget);
    });
  });

  // ── QA-PERF-104 — última-evaluación card formats doubles via the helper ───

  group('AthleteDetailScreen — QA-PERF-104 (performance card formatting)', () {
    setUpAll(() {
      registerFallbackValue(
          _makeSession(id: 'fallback', wasFullyCompleted: true));
    });

    testWidgets(
        'QA-PERF-104: the latest-evaluation card formats doubles with '
        '_formatMetricValue (30.0 -> 30) instead of interpolating the raw value',
        (tester) async {
      final repo = _MockSessionRepository();
      when(() => repo.listByUid('athlete-1')).thenAnswer((_) async => []);

      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          currentUidProvider.overrideWithValue('trainer-1'),
          userPublicProfileProvider('athlete-1').overrideWith(
            (ref) => Stream.value(_makeProfile('athlete-1', 'Martín García')),
          ),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) async => const [],
          ),
          sessionsByUidProvider('athlete-1').overrideWith(
            (ref) async => const [],
          ),
          sessionRepositoryProvider.overrideWithValue(repo),
          exercisesProvider.overrideWith((ref) async => const []),
          performanceTestsForAthleteProvider('athlete-1').overrideWith(
            (ref) => Stream.value([_makePerfTest()]),
          ),
        ],
      );

      await tester.pumpAndSettle();

      // Whole-number doubles render without the ".0" tail…
      expect(find.text('30 cm'), findsOneWidget);
      expect(find.text('100 kg'), findsOneWidget);
      expect(find.text('55 ml/kg/min'), findsOneWidget);
      // …a one-decimal value keeps its decimal (the helper trims to 1 dp).
      expect(find.text('2.9 s'), findsOneWidget);
      // Regression guard: the raw double interpolation ("30.0 cm") is gone.
      expect(find.text('30.0 cm'), findsNothing);
    });
  });

  // ── #439 — ANTROPOMETRÍA: historial con editar/borrar por fila ────────────
  // El comportamiento del listado (dialog de confirmación, orden, cap) se
  // testea en measurement_history_list_test.dart; acá va el CABLEADO de la
  // sección del PF: gate de autoría con trainerUid, tag de self-log, y que
  // editar abre LogMeasurementScreen pre-poblado en modo edición.

  group('AthleteDetailScreen — ANTROPOMETRÍA historial (#439)', () {
    testWidgets(
        'acciones sólo en filas registradas por ESTE PF; self-log read-only; '
        'editar abre el form pre-poblado', (tester) async {
      final repo = _MockSessionRepository();
      when(() => repo.listByUid('athlete-1')).thenAnswer((_) async => []);

      final mine = Measurement(
        id: 'm-mine',
        athleteId: 'athlete-1',
        recordedBy: 'trainer-1',
        recordedAt: DateTime.utc(2026, 1, 10),
        weightKg: 82,
      );
      final selfLogged = Measurement(
        id: 'm-self',
        athleteId: 'athlete-1',
        recordedBy: 'athlete-1',
        recordedAt: DateTime.utc(2026, 2, 10),
        weightKg: 78,
      );

      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          currentUidProvider.overrideWithValue('trainer-1'),
          userPublicProfileProvider('athlete-1').overrideWith(
            (ref) => Stream.value(_makeProfile('athlete-1', 'Martín García')),
          ),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) async => const [],
          ),
          sessionsByUidProvider('athlete-1').overrideWith(
            (ref) async => const [],
          ),
          sessionRepositoryProvider.overrideWithValue(repo),
          exercisesProvider.overrideWith((ref) async => const []),
          measurementsForAthleteProvider('athlete-1').overrideWith(
            (ref) => Stream.value([mine, selfLogged]),
          ),
        ],
      );
      await tester.pumpAndSettle();

      final l10n = AppL10n.of(tester.element(find.byType(AthleteDetailScreen)));

      await tester.scrollUntilVisible(
        find.byTooltip(l10n.measurementHistoryEditTooltip),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      // Sólo la fila registrada por este trainer ofrece acciones — el mismo
      // pin (recordedBy == uid) que exigen las rules de update/delete.
      expect(
          find.byTooltip(l10n.measurementHistoryEditTooltip), findsOneWidget);
      expect(
          find.byTooltip(l10n.measurementHistoryDeleteTooltip), findsOneWidget);
      expect(find.text(l10n.measurementHistorySelfLoggedTag), findsOneWidget);

      await tester.tap(find.byTooltip(l10n.measurementHistoryEditTooltip));
      await tester.pumpAndSettle();

      expect(find.byType(LogMeasurementScreen), findsOneWidget);
      expect(find.text('GUARDAR CAMBIOS'), findsOneWidget);
      expect(find.text('82'), findsOneWidget); // peso pre-poblado
    });
  });

  // ── #503 — el detalle NO puede explotar entero si falla UNA sección ───────
  //
  // El bug: `_AthleteDetailBody.build()` gateaba TODO (header, planes,
  // antropometría, rendimiento, historial, cobro, nota) detrás de
  // `plansAsync.hasError` / `profileAsync.hasError`, sin scope por sección.
  // Repro real: el alumno corta con el PF A y se vincula con el PF B; B abre
  // el detalle antes de que la CF `cleanupAssignedPlansOnUnlink` borre las
  // rutinas viejas → las rules niegan la query entera → `permission-denied` →
  // toda la pantalla (incluidos cobro y notas) mostraba la excepción cruda.
  // Cada sección tiene que degradar sola, como ya hacen antropometría,
  // rendimiento, historial, cobro y nota.

  group('AthleteDetailScreen — degradación por sección (#503)', () {
    List<Override> baseOverrides(_MockSessionRepository repo) => [
          currentUidProvider.overrideWithValue('trainer-1'),
          sessionsByUidProvider('athlete-1').overrideWith(
            (ref) async => const [],
          ),
          sessionRepositoryProvider.overrideWithValue(repo),
          exercisesProvider.overrideWith((ref) async => const []),
        ];

    testWidgets(
        'un permission-denied en planes degrada SOLO la sección de planes',
        (tester) async {
      final repo = _MockSessionRepository();
      when(() => repo.listByUid('athlete-1')).thenAnswer((_) async => []);

      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          ...baseOverrides(repo),
          userPublicProfileProvider('athlete-1').overrideWith(
            (ref) => Stream.value(_makeProfile('athlete-1', 'Martín García')),
          ),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) => Future<List<Routine>>.error(
              FirebaseException(
                plugin: 'cloud_firestore',
                code: 'permission-denied',
                message: 'Missing or insufficient permissions.',
              ),
            ),
          ),
        ],
      );

      await tester.pumpAndSettle();

      // La sección de planes degrada con un mensaje propio…
      expect(
        find.text(
          'No pudimos cargar los planes. Puede que el vínculo con este '
          'alumno se haya actualizado recién.',
        ),
        findsOneWidget,
      );
      // …y ya no filtra la excepción cruda a la UI del PF.
      expect(find.textContaining('permission-denied'), findsNothing);
      expect(find.textContaining('FirebaseException'), findsNothing);

      // El resto de la pantalla sigue viva.
      expect(find.text('Martín García'), findsWidgets);
      expect(find.text('PLANES ASIGNADOS'), findsOneWidget);
      expect(find.text('ANTROPOMETRÍA'), findsOneWidget);
      expect(find.text('MENSAJE'), findsOneWidget);
      expect(find.text('CREAR PLAN'), findsOneWidget);

      // Cobro y nota viven abajo de todo en el ListView — son justo las
      // secciones que el gate global se llevaba puestas.
      await tester.scrollUntilVisible(
        find.text('NOTA DEL ALUMNO'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      expect(find.text('COBRO'), findsOneWidget);
      expect(find.text('NOTA DEL ALUMNO'), findsOneWidget);
    });

    testWidgets('un error de perfil degrada SOLO el header', (tester) async {
      final repo = _MockSessionRepository();
      when(() => repo.listByUid('athlete-1')).thenAnswer((_) async => []);

      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          ...baseOverrides(repo),
          userPublicProfileProvider('athlete-1').overrideWith(
            (ref) => Stream<UserPublicProfile?>.error(
              FirebaseException(
                plugin: 'cloud_firestore',
                code: 'permission-denied',
              ),
            ),
          ),
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) async => const [],
          ),
        ],
      );

      await tester.pumpAndSettle();

      final l10n = AppL10n.of(tester.element(find.byType(AthleteDetailScreen)));

      // Aviso acotado al header…
      expect(find.text(l10n.athleteDetailProfileLoadError), findsOneWidget);
      // …y el resto de la pantalla sigue operativa.
      expect(find.text('Todavía no le asignaste planes.'), findsOneWidget);
      expect(find.text('ANTROPOMETRÍA'), findsOneWidget);
      expect(find.text('CREAR PLAN'), findsOneWidget);
    });

    testWidgets('planes colgado en loading no bloquea el resto de la pantalla',
        (tester) async {
      final repo = _MockSessionRepository();
      when(() => repo.listByUid('athlete-1')).thenAnswer((_) async => []);

      await _pumpScreen(
        tester,
        athleteId: 'athlete-1',
        overrides: [
          ...baseOverrides(repo),
          userPublicProfileProvider('athlete-1').overrideWith(
            (ref) => Stream.value(_makeProfile('athlete-1', 'Martín García')),
          ),
          // Nunca resuelve: simula la query de rutinas colgada.
          assignedRoutinesProvider('athlete-1').overrideWith(
            (ref) => Completer<List<Routine>>().future,
          ),
        ],
      );

      await tester.pumpAndSettle();

      // Sin el scope, un plansAsync.isLoading dejaba toda la pantalla en un
      // spinner infinito (y pumpAndSettle ni siquiera podía asentar).
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('PLANES ASIGNADOS'), findsOneWidget);
      expect(find.text('ANTROPOMETRÍA'), findsOneWidget);
      expect(find.text('CREAR PLAN'), findsOneWidget);
    });
  });
}
