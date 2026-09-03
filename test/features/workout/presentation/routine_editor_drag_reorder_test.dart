import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/analytics/analytics_service.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/application/user_routines_providers.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/domain/set_spec.dart';
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../fixtures/routine_editor_ui.dart';
import '../../../helpers/fake_analytics_service.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

const _exercises = [
  Exercise(id: 'a', name: 'Ejercicio A', muscleGroup: 'Pecho', category: 'x'),
  Exercise(id: 'b', name: 'Ejercicio B', muscleGroup: 'Espalda', category: 'x'),
  Exercise(id: 'c', name: 'Ejercicio C', muscleGroup: 'Piernas', category: 'x'),
];

RoutineSlot _slot(String id, {int? group}) => RoutineSlot(
      exerciseId: id,
      exerciseName: 'Ejercicio ${id.toUpperCase()}',
      muscleGroup: 'Grupo',
      targetSets: 1,
      targetRepsMin: 10,
      targetRepsMax: 10,
      restSeconds: 60,
      supersetGroup: group,
      sets: const [SetSpec(reps: 10)],
    );

Routine _routine(String id, List<RoutineSlot> slots) => Routine(
      id: id,
      name: 'Rutina drag',
      split: null,
      level: ExperienceLevel.beginner,
      days: [RoutineDay(dayNumber: 1, name: 'Día 1', slots: slots)],
      source: RoutineSource.userCreated,
      visibility: RoutineVisibility.private,
    );

Future<_MockRoutineRepository> _pump(
  WidgetTester tester,
  Routine routine,
) async {
  usarViewportAlto(tester);
  final repo = _MockRoutineRepository();
  when(() => repo.getById(routine.id)).thenAnswer((_) async => routine);
  when(() => repo.updateUserOwned(
        uid: any(named: 'uid'),
        draft: any(named: 'draft'),
      )).thenAnswer(
    (invocation) async =>
        invocation.namedArguments[const Symbol('draft')] as Routine,
  );

  final router = GoRouter(
    initialLocation: '/editor',
    routes: [
      GoRoute(
        path: '/editor',
        builder: (_, __) => RoutineEditorScreen(
          mode: SelfCreating(existingRoutineId: routine.id),
        ),
      ),
      GoRoute(
        path: '/workout',
        builder: (_, __) => const Scaffold(body: Text('Workout')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue('athlete-1'),
        routineRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((_) async => _exercises),
        customExercisesForTrainerStreamProvider('athlete-1').overrideWith(
          (_) => Stream<List<CustomExercise>>.value(const []),
        ),
        userCreatedRoutinesProvider('athlete-1').overrideWith(
          (_) => Stream.value([routine]),
        ),
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        locale: const Locale('es', 'AR'),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repo;
}

Future<Routine> _guardar(
    WidgetTester tester, _MockRoutineRepository repo) async {
  await desplazarHasta(
    tester,
    find.widgetWithText(ElevatedButton, 'GUARDAR CAMBIOS'),
  );
  await tester.tap(find.widgetWithText(ElevatedButton, 'GUARDAR CAMBIOS'));
  await tester.pumpAndSettle();
  final call = verify(() => repo.updateUserOwned(
        uid: 'athlete-1',
        draft: captureAny(named: 'draft'),
      ));
  call.called(1);
  return call.captured.single as Routine;
}

/// Arrastra [handle] hasta pasar por debajo de [target].
///
/// `tester.drag` NO sirve acá. Hace down → un único move → up sin bombear un
/// solo frame, y `ReorderableListView` calcula el índice de destino **mientras**
/// el dedo se mueve, comparando la posición del ítem arrastrado contra la de sus
/// vecinos. Sin frames intermedios el `up` llega con el destino todavía en la
/// posición de origen: el gesto "pasa", el test queda verde en apariencia y el
/// orden no cambia — que es exactamente el falso negativo que este helper evita.
Future<void> _arrastrarDebajo(
  WidgetTester tester,
  Finder handle,
  Finder target,
) async {
  final desde = tester.getCenter(handle);
  final dy = tester.getCenter(target).dy - desde.dy + 20;
  final gesto = await tester.startGesture(desde);
  await tester.pump(kPressTimeout);
  const pasos = 10;
  for (var i = 0; i < pasos; i++) {
    await gesto.moveBy(Offset(0, dy / pasos));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesto.up();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      _routine('fallback', const []),
    );
  });

  testWidgets('arrastrar el agarre reordena los ejercicios en el modelo',
      (tester) async {
    final repo =
        await _pump(tester, _routine('standalone', [_slot('a'), _slot('b')]));

    await _arrastrarDebajo(
      tester,
      find.byKey(const Key('slot_drag_handle_0')),
      find.byKey(const Key('slot_drag_handle_1')),
    );

    final saved = await _guardar(tester, repo);
    expect(saved.days.single.slots.map((s) => s.exerciseId), ['b', 'a']);
  });

  testWidgets('tocar el agarre no despliega la card', (tester) async {
    await _pump(tester, _routine('tap', [_slot('a')]));
    final cuerpo = find.byKey(const Key('exercise_card_body'));
    expect(cuerpo, findsNothing);

    // El agarre nació DENTRO del InkWell del toggle, así que un tap sobre él
    // desplegaba la card: el gesto de "quiero mover esto" hacía lo contrario.
    await tester.tap(find.byKey(const Key('slot_drag_handle_0')));
    await tester.pumpAndSettle();
    expect(cuerpo, findsNothing);

    // Y el título sigue abriendo. El área tapeable no se perdió: se acotó a
    // lo que se lee como "abrime".
    await tester.tap(find.byKey(const Key('exercise_card_header')));
    await tester.pumpAndSettle();
    expect(cuerpo, findsOneWidget);
  });

  testWidgets('arrastrar una superserie mueve el bloque entero sin partirlo',
      (tester) async {
    final repo = await _pump(
      tester,
      _routine(
          'block', [_slot('a', group: 7), _slot('b', group: 7), _slot('c')]),
    );

    await _arrastrarDebajo(
      tester,
      find.byKey(const Key('superset_drag_handle')),
      find.byKey(const Key('slot_drag_handle_2')),
    );

    final saved = await _guardar(tester, repo);
    expect(saved.days.single.slots.map((s) => s.exerciseId), ['c', 'a', 'b']);
    expect(saved.days.single.slots.skip(1).map((s) => s.supersetGroup), [7, 7]);
  });

  testWidgets('arrastrar un miembro reordena dentro de la superserie',
      (tester) async {
    final repo = await _pump(
      tester,
      _routine('members', [_slot('a', group: 7), _slot('b', group: 7)]),
    );

    await _arrastrarDebajo(
      tester,
      find.byKey(const Key('slot_drag_handle_0')),
      find.byKey(const Key('slot_drag_handle_1')),
    );

    final saved = await _guardar(tester, repo);
    expect(saved.days.single.slots.map((s) => s.exerciseId), ['b', 'a']);
    expect(saved.days.single.slots.map((s) => s.supersetGroup), [7, 7]);
  });
}
