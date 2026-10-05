// Issue #910 — botón SIG. en la barra de accesorio del editor de rutina.
//
// Salta kg → reps → kg del set siguiente SIN cerrar el teclado, y en la última
// celda lo cierra en vez de dar la vuelta.
//
// Cubre: modo normal, modo rango (MÍN/MÁX), última celda, un set borrado en
// el medio, que el tap no le robe el foco al campo, y que no exista en modo
// duración (ahí la barra entera no existe, ver routine_editor_kg_steppers_test).
//
// No assertea anchos de texto: GoogleFonts no carga en tests.
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
import 'package:treino/features/workout/application/routine_providers.dart'
    show routineRepositoryProvider;
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/features/workout/application/user_routines_providers.dart'
    show userCreatedRoutinesProvider;
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/workout/domain/routine_source.dart';
import 'package:treino/features/workout/domain/routine_visibility.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../fixtures/exercises.dart';
import '../../../fixtures/routine_editor_ui.dart';
import '../../../helpers/fake_analytics_service.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

Routine _rutina({
  required String id,
  required RepMode repMode,
  ExerciseMode exerciseMode = ExerciseMode.reps,
  required List<SetSpec> sets,
}) =>
    Routine(
      id: id,
      name: 'Rutina SIG',
      split: 'PPL',
      level: ExperienceLevel.beginner,
      days: [
        RoutineDay(
          dayNumber: 1,
          name: 'Día 1',
          slots: [
            RoutineSlot(
              exerciseId: 'bench-press',
              exerciseName: 'Press de Banca',
              muscleGroup: 'chest',
              targetSets: sets.length,
              targetRepsMin: 10,
              targetRepsMax: repMode == RepMode.range ? 12 : 10,
              restSeconds: 90,
              exerciseMode: exerciseMode,
              repMode: repMode,
              sets: sets,
            ),
          ],
        ),
      ],
      source: RoutineSource.userCreated,
      visibility: RoutineVisibility.private,
    );

final _normal = _rutina(
  id: 'r-n',
  repMode: RepMode.single,
  sets: const [
    SetSpec(type: SetType.normal, weightKg: 60, reps: 10),
    SetSpec(type: SetType.normal, weightKg: 60, reps: 10),
    SetSpec(type: SetType.normal, weightKg: 60, reps: 10),
  ],
);

final _rango = _rutina(
  id: 'r-r',
  repMode: RepMode.range,
  sets: const [
    SetSpec(type: SetType.normal, weightKg: 20, repsMin: 8, repsMax: 12),
    SetSpec(type: SetType.normal, weightKg: 20, repsMin: 8, repsMax: 12),
  ],
);

final _duracion = _rutina(
  id: 'r-d',
  repMode: RepMode.single,
  exerciseMode: ExerciseMode.duration,
  sets: const [
    SetSpec(type: SetType.normal, durationSeconds: 60),
    SetSpec(type: SetType.normal, durationSeconds: 45),
  ],
);

Future<void> _abrir(WidgetTester tester, Routine rutina) async {
  final repo = _MockRoutineRepository();
  when(() => repo.getById(rutina.id)).thenAnswer((_) async => rutina);
  usarViewportAlto(tester);

  final router = GoRouter(
    initialLocation: '/workout/editor',
    routes: [
      GoRoute(
        path: '/workout/editor',
        pageBuilder: (context, state) => NoTransitionPage(
          child: RoutineEditorScreen(
            mode: SelfCreating(existingRoutineId: rutina.id),
          ),
        ),
      ),
      GoRoute(
        path: '/workout',
        pageBuilder: (_, __) => const NoTransitionPage(
          child: Scaffold(body: Center(child: Text('WorkoutHome'))),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue('athlete-1'),
        routineRepositoryProvider.overrideWithValue(repo),
        exercisesProvider.overrideWith((ref) async => kExerciseSeed),
        customExercisesForTrainerStreamProvider('athlete-1').overrideWith(
          (ref) => Stream<List<CustomExercise>>.value(const []),
        ),
        analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
        userCreatedRoutinesProvider('athlete-1')
            .overrideWith((ref) => Stream.value(const [])),
      ],
      child: MaterialApp.router(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.pump();
  await expandirEjercicios(tester);
}

Finder get _sig => find.byKey(const Key('accessory_next'));

Finder _celda(String hint, int fila) => celdasConHint(hint).at(fila);

bool _enfocada(WidgetTester tester, Finder campo) => tester
    .widget<EditableText>(
      find.descendant(of: campo, matching: find.byType(EditableText)),
    )
    .focusNode
    .hasFocus;

Future<void> _sigue(WidgetTester tester) async {
  await tester.tap(_sig);
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    registerFallbackValue(
      const Routine(
        id: '',
        name: 'fallback',
        split: null,
        level: ExperienceLevel.beginner,
        days: [],
        source: RoutineSource.userCreated,
      ),
    );
  });

  testWidgets('modo normal: kg → reps → kg del set siguiente', (tester) async {
    await _abrir(tester, _normal);
    await enfocarCelda(tester, _celda('kg', 0));
    expect(_enfocada(tester, _celda('kg', 0)), isTrue);

    await _sigue(tester);
    expect(_enfocada(tester, _celda('reps', 0)), isTrue);

    await _sigue(tester);
    expect(_enfocada(tester, _celda('kg', 1)), isTrue,
        reason: 'después de reps va el kg del set de abajo, no el borrar');
    expect(_enfocada(tester, _celda('reps', 0)), isFalse);
  });

  testWidgets('modo rango: kg → mín → máx → kg del set siguiente',
      (tester) async {
    await _abrir(tester, _rango);
    await enfocarCelda(tester, _celda('kg', 0));

    await _sigue(tester);
    expect(_enfocada(tester, _celda('mín', 0)), isTrue);
    await _sigue(tester);
    expect(_enfocada(tester, _celda('máx', 0)), isTrue);
    await _sigue(tester);
    expect(_enfocada(tester, _celda('kg', 1)), isTrue);
  });

  testWidgets('última celda: cierra el teclado en vez de dar la vuelta',
      (tester) async {
    await _abrir(tester, _normal);
    await enfocarCelda(tester, _celda('reps', 2));
    expect(_sig, findsOneWidget);

    await _sigue(tester);

    expect(_enfocada(tester, _celda('kg', 0)), isFalse,
        reason: 'no vuelve al principio');
    expect(_enfocada(tester, _celda('reps', 2)), isFalse);
    expect(_sig, findsNothing,
        reason: 'sin campo enfocado la barra se va junto con el teclado');
  });

  testWidgets('salta el set que se borró: sigue el siguiente VISIBLE',
      (tester) async {
    await _abrir(tester, _normal);
    // Borra el set del medio (botones de cerrar: uno por fila).
    await tester.tap(find.byTooltip('Cerrar').at(1));
    await tester.pumpAndSettle();
    expect(celdasConHint('kg'), findsNWidgets(2));

    await enfocarCelda(tester, _celda('reps', 0));
    await _sigue(tester);

    expect(_enfocada(tester, _celda('kg', 1)), isTrue);
  });

  testWidgets('tocar SIG. no le roba el foco al campo', (tester) async {
    await _abrir(tester, _normal);
    await enfocarCelda(tester, _celda('kg', 0));

    final gesto = await tester.startGesture(tester.getCenter(_sig));
    await tester.pump();
    // Con el dedo apoyado y antes de soltar: el campo todavía tiene el foco.
    expect(_enfocada(tester, _celda('kg', 0)), isTrue);
    await gesto.up();
    await tester.pumpAndSettle();

    // Y después del tap el foco es de OTRO campo de texto, nunca del botón.
    expect(_enfocada(tester, _celda('reps', 0)), isTrue);
    expect(_sig, findsOneWidget, reason: 'la barra sigue en pantalla');
  });

  testWidgets('modo duración: no hay barra, no hay SIG.', (tester) async {
    await _abrir(tester, _duracion);
    await enfocarCelda(tester, find.byType(TextField).last);

    expect(_sig, findsNothing);
  });
}
