// Tests for AthleteDetailScreen — SCENARIO-455, 456, REQ-SETLOGS-008..010
// REQ-COACH-PLANS-020, 021, 022

import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseException;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/presentation/athlete_detail_screen.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider, sessionsByUidProvider, coachSessionSetLogsProvider;
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/features/workout/domain/session_status.dart';
import 'package:treino/features/workout/domain/set_log.dart';

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
}
