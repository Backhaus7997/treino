// Tests for AthleteRoutinesScreen — the per-athlete routines list reached from
// the Rutinas sidebar (elegí alumno → ver/crear/editar sus rutinas).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/rutinas/athlete_routines_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_status.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

const _athleteId = 'athlete-1';

Routine _routine({
  String id = 'r1',
  String name = 'Fuerza',
  int days = 1,
  int numWeeks = 1,
  RoutineStatus status = RoutineStatus.active,
  bool perWeek = false, // true → weeklySets populated → NOT web-editable
}) =>
    Routine(
      id: id,
      name: name,
      level: ExperienceLevel.beginner,
      source: RoutineSource.trainerAssigned,
      assignedBy: 'trainer-1',
      assignedTo: _athleteId,
      visibility: RoutineVisibility.private,
      status: status,
      numWeeks: numWeeks,
      days: [
        for (var i = 0; i < days; i++)
          RoutineDay(
            dayNumber: i + 1,
            name: 'Día ${i + 1}',
            slots: [
              RoutineSlot(
                exerciseId: 'e',
                exerciseName: 'Ex',
                muscleGroup: 'chest',
                targetSets: 1,
                targetRepsMin: 8,
                targetRepsMax: 8,
                restSeconds: 60,
                sets: const [SetSpec(reps: 8)],
                weeklySets: perWeek
                    ? const [
                        [SetSpec(reps: 10)],
                        [SetSpec(reps: 8)],
                      ]
                    : const [],
              ),
            ],
          ),
      ],
    );

Future<void> _pump(WidgetTester tester, List<Routine> routines) async {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final router = GoRouter(
    initialLocation: '/rutinas/$_athleteId',
    routes: [
      GoRoute(
        path: '/rutinas/:athleteId',
        builder: (_, s) => Scaffold(
          body:
              AthleteRoutinesScreen(athleteId: s.pathParameters['athleteId']!),
        ),
      ),
      // Editor stand-ins — assert navigation by the marker text.
      GoRoute(
        path: '/routine-editor/:athleteId',
        builder: (_, s) =>
            Scaffold(body: Text('CREATE ${s.pathParameters['athleteId']}')),
      ),
      GoRoute(
        path: '/routine-editor/:athleteId/:routineId',
        builder: (_, s) =>
            Scaffold(body: Text('EDIT ${s.pathParameters['routineId']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        assignedRoutinesProvider(_athleteId)
            .overrideWith((ref) async => routines),
        userPublicProfileProvider(_athleteId).overrideWith(
          (ref) => Stream.value(
            const UserPublicProfile(uid: _athleteId, displayName: 'Vicente'),
          ),
        ),
      ],
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('AthleteRoutinesScreen', () {
    testWidgets('lists active routines with the athlete name and a summary',
        (tester) async {
      await _pump(tester, [_routine(id: 'r1', name: 'Fuerza base', days: 3)]);

      expect(find.text('Rutinas de Vicente'), findsOneWidget);
      expect(find.text('Fuerza base'), findsOneWidget);
      expect(find.text('3 días · 1 semana'), findsOneWidget);
    });

    testWidgets('hides archived routines', (tester) async {
      await _pump(tester, [
        _routine(id: 'r1', name: 'Activa'),
        _routine(id: 'r2', name: 'Vieja', status: RoutineStatus.archived),
      ]);

      expect(find.text('Activa'), findsOneWidget);
      expect(find.text('Vieja'), findsNothing);
    });

    testWidgets('shows the empty state when there are no active routines',
        (tester) async {
      await _pump(tester, const []);

      expect(
        find.text('Todavía no le cargaste ninguna rutina.'),
        findsOneWidget,
      );
    });

    testWidgets('tapping a web-editable routine opens the editor for it',
        (tester) async {
      await _pump(tester, [_routine(id: 'r1', name: 'Fuerza base')]);

      await tester.tap(find.text('Fuerza base'));
      await tester.pumpAndSettle();

      expect(find.text('EDIT r1'), findsOneWidget);
    });

    testWidgets('"Nueva rutina" opens the create editor', (tester) async {
      await _pump(tester, const []);

      await tester.tap(find.text('Nueva rutina'));
      await tester.pumpAndSettle();

      expect(find.text('CREATE $_athleteId'), findsOneWidget);
    });

    testWidgets('a periodized routine is view-only (tap does not open editor)',
        (tester) async {
      await _pump(
          tester, [_routine(id: 'r9', name: 'Periodizada', perWeek: true)]);

      expect(find.text('Editá en la app'), findsOneWidget);

      await tester.tap(find.text('Periodizada'));
      await tester.pumpAndSettle();

      expect(find.text('EDIT r9'), findsNothing); // stayed on the list
      expect(find.text('Periodizada'), findsOneWidget);
    });
  });
}
