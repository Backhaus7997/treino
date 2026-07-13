// Tests for RoutineEditorWebScreen — web MVP routine editor (create-only,
// single week, normal sets). Mirrors the mocking pattern of
// routine_editor_athlete_mode_test.dart (mobile).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/routine_editor/routine_editor_web_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart'
    show routineRepositoryProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

import '../../../../../fixtures/exercises.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockRoutineRepository extends Mock implements RoutineRepository {}

const _trainerId = 'trainer-1';
const _athleteId = 'athlete-1';

// ── Helpers ───────────────────────────────────────────────────────────────────

List<Override> _overrides({RoutineRepository? repo}) {
  final mockRepo = repo ?? _MockRoutineRepository();
  return [
    currentUidProvider.overrideWithValue(_trainerId),
    routineRepositoryProvider.overrideWithValue(mockRepo),
    exercisesProvider.overrideWith((ref) async => kExerciseSeed),
    customExercisesForTrainerStreamProvider(_trainerId).overrideWith(
      (ref) => Stream<List<CustomExercise>>.value(const []),
    ),
    userPublicProfileProvider(_athleteId).overrideWith(
      (ref) => Stream.value(
        const UserPublicProfile(uid: _athleteId, displayName: 'Juan Pérez'),
      ),
    ),
  ];
}

/// Pumps the editor. With [routineId] the edit route is pushed (edit mode);
/// without it, the create route (as before).
Future<void> _pumpEditor(
  WidgetTester tester, {
  RoutineRepository? repo,
  String? routineId,
}) async {
  // Desktop viewport — Coach Hub web dialogs (exercise picker) assume it.
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  // initialLocation is the alumno-detail stand-in, THEN we push the editor —
  // context.pop() needs real prior history to return to, not just a bare
  // initialLocation (which go_router can't pop past).
  final router = GoRouter(
    initialLocation: '/alumnos/$_athleteId',
    routes: [
      GoRoute(
        path: '/alumnos/:id',
        builder: (_, __) => const Scaffold(body: Text('AlumnoDetail')),
      ),
      GoRoute(
        path: '/routine-editor/:athleteId',
        // CoachHubScaffold (the real shell) provides the Material ancestor —
        // this test stands in for it, matching other section-screen tests.
        builder: (_, state) => Scaffold(
          body: RoutineEditorWebScreen(
            athleteId: state.pathParameters['athleteId']!,
          ),
        ),
      ),
      GoRoute(
        path: '/routine-editor/:athleteId/:routineId',
        builder: (_, state) => Scaffold(
          body: RoutineEditorWebScreen(
            athleteId: state.pathParameters['athleteId']!,
            routineId: state.pathParameters['routineId'],
          ),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(repo: repo),
      child: MaterialApp.router(theme: AppTheme.dark(), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();

  router.push(
    routineId == null
        ? '/routine-editor/$_athleteId'
        : '/routine-editor/$_athleteId/$routineId',
  );
  await tester.pumpAndSettle();
}

/// A web-editable (simple, single-week, reps) routine — the kind edit mode
/// accepts.
Routine _simpleRoutine({String id = 'r1', String name = 'Fuerza base'}) =>
    Routine(
      id: id,
      name: name,
      split: 'Full Body',
      level: ExperienceLevel.intermediate,
      source: RoutineSource.trainerAssigned,
      assignedBy: _trainerId,
      assignedTo: _athleteId,
      days: const [
        RoutineDay(
          dayNumber: 1,
          name: 'Día A',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: 1,
              targetRepsMin: 8,
              targetRepsMax: 8,
              restSeconds: 90,
              sets: [SetSpec(reps: 8, weightKg: 60)],
            ),
          ],
        ),
      ],
    );

/// Fills name + split and adds one exercise (via the mocked exercise picker
/// data) to the first day, then sets valid reps on its single default set.
Future<void> _fillMinimalValidForm(WidgetTester tester) async {
  await tester.enterText(
      find.byKey(const Key('routine_editor_name_field')), 'Fuerza 4x semana');
  await tester.enterText(
      find.byKey(const Key('routine_editor_split_field')), 'Push/Pull/Legs');

  await tester.tap(find.text('Agregar ejercicio'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Press de Banca'));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Agregar (1)'));
  await tester.pumpAndSettle();

  // Reps field for the single default set — located via its 'reps' hint
  // (not '.first' on any empty TextFormField, which would also match the
  // adjacent 'kg' weight field).
  await tester.enterText(
    find.ancestor(of: find.text('reps'), matching: find.byType(TextFormField)),
    '10',
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(const Routine(
      id: '',
      name: 'fallback',
      level: ExperienceLevel.beginner,
      days: [],
      source: RoutineSource.trainerAssigned,
    ));
  });

  group('RoutineEditorWebScreen — header', () {
    testWidgets('shows the athlete display name', (tester) async {
      await _pumpEditor(tester);
      expect(find.textContaining('Juan Pérez'), findsOneWidget);
    });
  });

  group('RoutineEditorWebScreen — validation', () {
    testWidgets('empty name blocks submit and shows an error', (
      tester,
    ) async {
      final repo = _MockRoutineRepository();
      await _pumpEditor(tester, repo: repo);

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text('Ponele un nombre a la rutina.'), findsOneWidget);
      verifyNever(() => repo.createAssigned(any()));
    });

    testWidgets('empty split blocks submit', (tester) async {
      final repo = _MockRoutineRepository();
      await _pumpEditor(tester, repo: repo);

      await tester.enterText(
          find.byKey(const Key('routine_editor_name_field')), 'Fuerza');
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('Contanos el split (ej: Push/Pull/Legs).'),
        findsOneWidget,
      );
      verifyNever(() => repo.createAssigned(any()));
    });

    testWidgets('a day with no exercise blocks submit', (tester) async {
      final repo = _MockRoutineRepository();
      await _pumpEditor(tester, repo: repo);

      await tester.enterText(
          find.byKey(const Key('routine_editor_name_field')), 'Fuerza');
      await tester.enterText(
          find.byKey(const Key('routine_editor_split_field')), 'PPL');
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('necesita al menos un ejercicio'),
          findsOneWidget);
      verifyNever(() => repo.createAssigned(any()));
    });

    testWidgets('a set without reps blocks submit', (tester) async {
      final repo = _MockRoutineRepository();
      await _pumpEditor(tester, repo: repo);

      await tester.enterText(
          find.byKey(const Key('routine_editor_name_field')), 'Fuerza');
      await tester.enterText(
          find.byKey(const Key('routine_editor_split_field')), 'PPL');
      await tester.tap(find.text('Agregar ejercicio'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Press de Banca'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Agregar (1)'));
      await tester.pumpAndSettle();

      // Reps left empty.
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(find.textContaining('tiene una serie sin reps'), findsOneWidget);
      verifyNever(() => repo.createAssigned(any()));
    });
  });

  group('RoutineEditorWebScreen — days', () {
    testWidgets('agregar día adds a new day card', (tester) async {
      await _pumpEditor(tester);

      expect(find.text('Día 1'), findsOneWidget);
      await tester.tap(find.byKey(const Key('routine_editor_add_day_button')));
      await tester.pumpAndSettle();

      expect(find.text('Día 2'), findsOneWidget);
    });
  });

  group('RoutineEditorWebScreen — submit', () {
    testWidgets(
        'valid form calls createAssigned with a well-formed single-week Routine',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createAssigned(any())).thenAnswer(
        (i) async => i.positionalArguments.first as Routine,
      );
      await _pumpEditor(tester, repo: repo);
      await _fillMinimalValidForm(tester);

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final captured = verify(() => repo.createAssigned(captureAny())).captured;
      final routine = captured.single as Routine;

      expect(routine.name, 'Fuerza 4x semana');
      expect(routine.split, 'Push/Pull/Legs');
      expect(routine.source, RoutineSource.trainerAssigned);
      expect(routine.assignedBy, _trainerId);
      expect(routine.assignedTo, _athleteId);
      // firestore.rules rejects 'public' on a trainer-assigned create — the
      // plan must be private (the model default 'public' would be denied).
      expect(routine.visibility, RoutineVisibility.private);
      expect(routine.numWeeks, 1);
      expect(routine.days, hasLength(1));

      final slot = routine.days.single.slots.single;
      expect(slot.exerciseId, 'bench-press');
      expect(slot.sets, hasLength(1));
      expect(slot.sets.single.reps, 10);
      expect(slot.weeklySets, isEmpty); // single-week → no periodization data
      expect(slot.activeWeeks, isEmpty); // present in all (the only) week
      expect(slot.supersetGroup, isNull);
    });

    testWidgets('repository failure surfaces a retry-friendly error message',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.createAssigned(any())).thenThrow(Exception('boom'));
      await _pumpEditor(tester, repo: repo);
      await _fillMinimalValidForm(tester);

      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos guardar la rutina. Probá de nuevo.'),
        findsOneWidget,
      );
    });
  });

  group('RoutineEditorWebScreen — discard guard', () {
    testWidgets('dirty form + back tap shows the discard confirmation', (
      tester,
    ) async {
      await _pumpEditor(tester);

      await tester.enterText(
          find.byKey(const Key('routine_editor_name_field')), 'Fuerza');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('¿Descartar los cambios?'), findsOneWidget);
    });

    testWidgets('confirming discard navigates back', (tester) async {
      await _pumpEditor(tester);

      await tester.enterText(
          find.byKey(const Key('routine_editor_name_field')), 'Fuerza');
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Descartar'));
      await tester.pumpAndSettle();

      expect(find.text('AlumnoDetail'), findsOneWidget);
    });

    testWidgets('a pristine form pops immediately without a dialog', (
      tester,
    ) async {
      await _pumpEditor(tester);

      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();

      expect(find.text('¿Descartar los cambios?'), findsNothing);
      expect(find.text('AlumnoDetail'), findsOneWidget);
    });
  });

  group('RoutineEditorWebScreen — edit mode', () {
    testWidgets('loads and populates an existing web-editable routine',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => _simpleRoutine());
      await _pumpEditor(tester, repo: repo, routineId: 'r1');

      expect(find.text('Editar rutina'), findsOneWidget); // header
      expect(find.text('Fuerza base'), findsOneWidget); // name field
      expect(find.text('Día A'), findsOneWidget); // day name
      expect(find.text('Press de Banca'), findsOneWidget); // slot
      expect(find.text('Guardar cambios'), findsOneWidget); // submit label
    });

    testWidgets(
        'saving calls updateAssigned on the same doc, not createAssigned',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => _simpleRoutine());
      when(() => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          )).thenAnswer((i) async => i.namedArguments[#draft] as Routine);
      await _pumpEditor(tester, repo: repo, routineId: 'r1');

      await tester.enterText(
          find.byKey(const Key('routine_editor_name_field')), 'Fuerza v2');
      await tester.tap(find.byKey(const Key('routine_editor_submit_button')));
      await tester.pumpAndSettle();

      final draft = verify(() => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: captureAny(named: 'draft'),
          )).captured.single as Routine;
      expect(draft.id, 'r1'); // UPDATE on the same document, not a new one
      expect(draft.name, 'Fuerza v2');
      expect(draft.numWeeks, 1);
      verifyNever(() => repo.createAssigned(any()));
    });

    testWidgets(
        'refuses a periodized routine and does not save (no truncation)',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any()))
          .thenAnswer((_) async => _simpleRoutine().copyWith(numWeeks: 4));
      await _pumpEditor(tester, repo: repo, routineId: 'r1');

      expect(find.textContaining('periodización'), findsOneWidget);
      expect(find.text('Volver'), findsOneWidget);
      expect(find.text('Guardar cambios'), findsNothing); // form/footer hidden
      expect(find.text('Fuerza base'), findsNothing); // not populated
      verifyNever(() => repo.updateAssigned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          ));
    });

    testWidgets('shows a not-found message when the routine is missing',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById(any())).thenAnswer((_) async => null);
      await _pumpEditor(tester, repo: repo, routineId: 'ghost');

      expect(find.text('No encontramos la rutina.'), findsOneWidget);
      expect(find.text('Guardar cambios'), findsNothing);
    });
  });
}
