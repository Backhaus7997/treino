// Issue #640 — PR#3: steppers +2.5 / +5 en la columna KG del editor.
//
// Decisiones que estos tests fijan:
//   - La afordancia es una BARRA ligada al foco del campo KG, no un par de
//     botones al lado de cada fila: el row ya es chip · KG · REPS · borrar
//     dentro de una card en un teléfono, y meter cuatro controles por fila
//     obligaba a achicar las columnas — o sea, a rediseñar, que el issue veta.
//   - Los decrementos entran. Un stepper que sólo sube devuelve al usuario al
//     teclado apenas se pasa, que es justo el tedio que venía a sacar.
//   - El peso NUNCA queda negativo: steppedWeightKg clampea en 0 y un 0
//     resuelve a null (campo vacío = sin peso), no a un "0 kg" prescripto.
//
// Cubre:
//   - incremento simple, y que el valor persista en el modelo Y se vea en el
//     campo (se captura el draft que llega al repositorio).
//   - que el foco sobreviva al tap: el _SetRow NO se recrea (misma FocusNode y
//     mismo TextEditingController antes y después).
//   - que no exista en modo duración.
//   - que funcione en modo rango sin tocar MÍN/MÁX.
//   - que funcione en isTrainerMode (TrainerAssigning).
//   - que no permita valores negativos.
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
import 'package:treino/features/workout/domain/set_limits.dart';
import 'package:treino/features/workout/domain/set_spec.dart';
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../fixtures/exercises.dart';
import '../../../helpers/fake_analytics_service.dart';

// ── Mocks ─────────────────────────────────────────────────────────────────────

class _MockRoutineRepository extends Mock implements RoutineRepository {}

// ── Seeded routines ───────────────────────────────────────────────────────────

/// Reps-based slot, RepMode.single (targetRepsMin == targetRepsMax, si no
/// `effectiveRepMode` fuerza range), dos sets con peso.
Routine _singleModeRoutine({
  RoutineSource source = RoutineSource.userCreated,
  String? assignedBy,
  String? assignedTo,
  double? weightKg = 60,
}) =>
    Routine(
      id: 'r-1',
      name: 'Rutina Steppers',
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
              targetSets: 2,
              targetRepsMin: 10,
              targetRepsMax: 10,
              restSeconds: 90,
              exerciseMode: ExerciseMode.reps,
              repMode: RepMode.single,
              sets: [
                SetSpec(type: SetType.normal, weightKg: weightKg, reps: 10),
                SetSpec(type: SetType.normal, weightKg: weightKg, reps: 10),
              ],
            ),
          ],
        ),
      ],
      source: source,
      assignedBy: assignedBy,
      assignedTo: assignedTo,
      visibility: RoutineVisibility.private,
    );

/// Slot en RepMode.range: el stepper tiene que seguir existiendo (KG vive) y
/// no puede rozar MÍN/MÁX.
const _rangeModeRoutine = Routine(
  id: 'r-range',
  name: 'Rutina Rango',
  split: 'PPL',
  level: ExperienceLevel.beginner,
  days: [
    RoutineDay(
      dayNumber: 1,
      name: 'Día 1',
      slots: [
        RoutineSlot(
          exerciseId: 'pull-up',
          exerciseName: 'Dominadas',
          muscleGroup: 'back',
          targetSets: 1,
          targetRepsMin: 8,
          targetRepsMax: 12,
          restSeconds: 60,
          exerciseMode: ExerciseMode.reps,
          repMode: RepMode.range,
          sets: [
            SetSpec(
                type: SetType.normal, weightKg: 20, repsMin: 8, repsMax: 12),
          ],
        ),
      ],
    ),
  ],
  source: RoutineSource.userCreated,
  visibility: RoutineVisibility.private,
);

/// Slot por tiempo: sin columna KG, la afordancia no debe existir.
const _durationRoutine = Routine(
  id: 'r-dur',
  name: 'Rutina Tiempo',
  split: 'PPL',
  level: ExperienceLevel.beginner,
  days: [
    RoutineDay(
      dayNumber: 1,
      name: 'Día 1',
      slots: [
        RoutineSlot(
          exerciseId: 'plank',
          exerciseName: 'Plancha',
          muscleGroup: 'core',
          targetSets: 2,
          targetRepsMin: 0,
          targetRepsMax: 0,
          restSeconds: 45,
          exerciseMode: ExerciseMode.duration,
          repMode: RepMode.single,
          sets: [
            SetSpec(type: SetType.normal, durationSeconds: 60),
            SetSpec(type: SetType.normal, durationSeconds: 45),
          ],
        ),
      ],
    ),
  ],
  source: RoutineSource.userCreated,
  visibility: RoutineVisibility.private,
);

// ── Widget harness ────────────────────────────────────────────────────────────

List<Override> _overrides(RoutineRepository repo, String uid) => [
      currentUidProvider.overrideWithValue(uid),
      routineRepositoryProvider.overrideWithValue(repo),
      exercisesProvider.overrideWith((ref) async => kExerciseSeed),
      customExercisesForTrainerStreamProvider(uid).overrideWith(
        (ref) => Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
      ),
      analyticsServiceProvider.overrideWithValue(FakeAnalyticsService()),
      userCreatedRoutinesProvider(uid).overrideWith(
        (ref) => Stream.value(const []),
      ),
    ];

Future<void> _pumpEditor(
  WidgetTester tester, {
  required RoutineEditorMode mode,
  required RoutineRepository repo,
  String uid = 'athlete-1',
}) async {
  final router = GoRouter(
    initialLocation: '/workout/editor',
    routes: [
      GoRoute(
        path: '/workout/editor',
        pageBuilder: (context, state) => NoTransitionPage(
          child: RoutineEditorScreen(mode: mode),
        ),
      ),
      GoRoute(
        path: '/workout',
        pageBuilder: (_, __) => const NoTransitionPage(
          child: Scaffold(body: Center(child: Text('WorkoutHome'))),
        ),
      ),
      GoRoute(
        path: '/coach',
        pageBuilder: (_, __) => const NoTransitionPage(
          child: Scaffold(body: Center(child: Text('CoachHome'))),
        ),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: _overrides(repo, uid),
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
  // Extra pump: the hydration path flips `_loading` in a post-frame setState.
  await tester.pump();
}

// ── Finders ───────────────────────────────────────────────────────────────────

Finder _fieldsWithHint(String hint) => find.byWidgetPredicate(
      (w) => w is TextField && w.decoration?.hintText == hint,
    );

Finder _kgField(int index) => _fieldsWithHint('kg').at(index);

Finder get _plus25 => find.byKey(const Key('kg_step_plus_2_5'));
Finder get _plus5 => find.byKey(const Key('kg_step_plus_5'));
Finder get _minus25 => find.byKey(const Key('kg_step_minus_2_5'));
Finder get _minus5 => find.byKey(const Key('kg_step_minus_5'));

Finder get _anyStepper => find.byWidgetPredicate(
      (w) =>
          w is GestureDetector &&
          w.key is ValueKey<String> &&
          (w.key as ValueKey<String>).value.startsWith('kg_step_'),
    );

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

String _kgText(WidgetTester tester, int index) =>
    tester.widget<TextField>(_kgField(index)).controller!.text;

void main() {
  setUpAll(() {
    // `any(named: 'draft')` necesita un fallback registrado para Routine.
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

  // ── Unit: steppedWeightKg ──────────────────────────────────────────────────

  group('steppedWeightKg', () {
    test('suma sobre un valor existente', () {
      expect(steppedWeightKg(60, 5), 65);
      expect(steppedWeightKg(60, 2.5), 62.5);
    });

    test('un campo vacío cuenta como 0, así que +2.5 escribe 2.5', () {
      expect(steppedWeightKg(null, 2.5), 2.5);
    });

    test('redondea la basura del punto flotante', () {
      // 17.3 + 2.5 == 19.799999999999997 en binario; el campo KG renderiza el
      // double crudo, así que eso llegaría a la pantalla tal cual.
      expect(steppedWeightKg(17.3, 2.5), 19.8);
    });

    test('nunca deja el peso en negativo: el piso es un campo vacío', () {
      expect(steppedWeightKg(2.5, -5), isNull);
      expect(steppedWeightKg(5, -5), isNull);
      expect(steppedWeightKg(null, -5), isNull);
      expect(steppedWeightKg(0, -2.5), isNull);
    });

    test('respeta el techo de dominio kMaxWeightKg', () {
      expect(steppedWeightKg(kMaxWeightKg - 1, 5), kMaxWeightKg);
      expect(steppedWeightKg(kMaxWeightKg, 5), kMaxWeightKg);
    });

    test('los saltos son de tamaño disco', () {
      expect(kKgStepsKg, [2.5, 5]);
    });
  });

  // ── Widget: visibilidad ligada al foco ─────────────────────────────────────

  group('afordancia', () {
    testWidgets('no se dibuja hasta que el campo KG toma el foco',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('r-1'))
          .thenAnswer((_) async => _singleModeRoutine());

      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'r-1'),
        repo: repo,
      );

      expect(_anyStepper, findsNothing,
          reason: 'sin foco no hay barra: la tabla no carga cuatro copias '
              'ociosas de los mismos cuatro botones');

      await _tapVisible(tester, _kgField(0));

      expect(_plus25, findsOneWidget);
      expect(_plus5, findsOneWidget);
      expect(_minus25, findsOneWidget);
      expect(_minus5, findsOneWidget);
      expect(_anyStepper, findsNWidgets(4),
          reason: 'una sola barra, la de la fila enfocada');
    });

    testWidgets('modo duración: no existe (no hay columna KG)', (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('r-dur'))
          .thenAnswer((_) async => _durationRoutine);

      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'r-dur'),
        repo: repo,
      );

      expect(find.text('TIEMPO'), findsOneWidget);
      expect(_fieldsWithHint('kg'), findsNothing);

      // Enfocar el campo de TIEMPO no puede hacer aparecer una afordancia de
      // peso: en modo duración el peso no se prescribe.
      await _tapVisible(tester, find.byType(TextField).last);

      expect(_anyStepper, findsNothing);
    });
  });

  // ── Widget: incremento ─────────────────────────────────────────────────────

  group('incremento', () {
    testWidgets('+5 sube el peso y se ve en el campo', (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('r-1'))
          .thenAnswer((_) async => _singleModeRoutine());

      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'r-1'),
        repo: repo,
      );

      await _tapVisible(tester, _kgField(0));
      expect(_kgText(tester, 0), '60');

      await _tapVisible(tester, _plus5);

      expect(_kgText(tester, 0), '65');
      // Sólo toca la fila enfocada.
      expect(_kgText(tester, 1), '60');
    });

    testWidgets('+2.5 escribe el decimal tal como lo formatea el campo',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('r-1'))
          .thenAnswer((_) async => _singleModeRoutine());

      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'r-1'),
        repo: repo,
      );

      await _tapVisible(tester, _kgField(0));
      await _tapVisible(tester, _plus25);

      expect(_kgText(tester, 0), '62.5');
    });

    testWidgets('el valor persiste en el modelo, no sólo en el campo',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('r-1'))
          .thenAnswer((_) async => _singleModeRoutine());

      Routine? captured;
      when(() => repo.updateUserOwned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          )).thenAnswer((inv) async {
        captured = inv.namedArguments[const Symbol('draft')] as Routine;
        return captured!;
      });

      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'r-1'),
        repo: repo,
      );

      await _tapVisible(tester, _kgField(0));
      await _tapVisible(tester, _plus5);
      await _tapVisible(tester, _plus25);
      expect(_kgText(tester, 0), '67.5');

      await _tapVisible(
          tester, find.widgetWithText(ElevatedButton, 'GUARDAR CAMBIOS'));

      expect(captured, isNotNull,
          reason: 'el botón de guardar tiene que estar habilitado: el stepper '
              'dispara onChanged y la validación inline se recalcula');
      final sets = captured!.days.first.slots.first.sets;
      expect(sets[0].weightKg, 67.5,
          reason: 'el modelo tiene que llevar el valor que muestra el campo');
      expect(sets[1].weightKg, 60, reason: 'las demás filas no se tocan');
      expect(sets[0].reps, 10, reason: 'el stepper mueve SÓLO el peso');
      expect(sets[0].type, SetType.normal);
    });
  });

  // ── Widget: el foco sobrevive ──────────────────────────────────────────────

  group('foco', () {
    testWidgets('el campo sigue enfocado y la fila NO se recrea',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('r-1'))
          .thenAnswer((_) async => _singleModeRoutine());

      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'r-1'),
        repo: repo,
      );

      await _tapVisible(tester, _kgField(0));
      final before = tester.widget<TextField>(_kgField(0));
      expect(before.focusNode?.hasFocus, isTrue);

      await _tapVisible(tester, _plus5);

      final after = tester.widget<TextField>(_kgField(0));
      expect(after.focusNode?.hasFocus, isTrue,
          reason: 'un stepper se toca con el campo enfocado; perder el foco '
              'obligaría a volver a tocar el campo entre salto y salto');
      // La prueba dura de que la fila no se recreó: si el stepper hubiese
      // reemplazado la instancia de _EditableSet (como hace el fill de
      // columna), el ObjectKey cambiaba, nacía un State nuevo y tanto la
      // FocusNode como el TextEditingController serían otros.
      expect(identical(before.focusNode, after.focusNode), isTrue,
          reason: 'misma FocusNode ⇒ mismo State ⇒ el ObjectKey no cambió');
      expect(identical(before.controller, after.controller), isTrue,
          reason: 'mismo TextEditingController ⇒ la fila no se reconstruyó');
      // Y la barra sigue en pantalla para el siguiente salto.
      expect(_plus5, findsOneWidget);
    });
  });

  // ── Widget: modo rango ─────────────────────────────────────────────────────

  group('modo rango', () {
    testWidgets('funciona y no roza MÍN/MÁX', (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('r-range'))
          .thenAnswer((_) async => _rangeModeRoutine);

      Routine? captured;
      when(() => repo.updateUserOwned(
            uid: any(named: 'uid'),
            draft: any(named: 'draft'),
          )).thenAnswer((inv) async {
        captured = inv.namedArguments[const Symbol('draft')] as Routine;
        return captured!;
      });

      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'r-range'),
        repo: repo,
      );

      expect(find.text('MÍN'), findsOneWidget);
      expect(find.text('MÁX'), findsOneWidget);

      await _tapVisible(tester, _kgField(0));
      await _tapVisible(tester, _plus25);

      expect(_kgText(tester, 0), '22.5');

      await _tapVisible(
          tester, find.widgetWithText(ElevatedButton, 'GUARDAR CAMBIOS'));

      final slot = captured!.days.first.slots.first;
      expect(slot.repMode, RepMode.range,
          reason: 'el modo del slot no se toca');
      expect(slot.sets.first.weightKg, 22.5);
      expect(slot.sets.first.repsMin, 8);
      expect(slot.sets.first.repsMax, 12);
    });
  });

  // ── Widget: modo entrenador ────────────────────────────────────────────────

  group('isTrainerMode', () {
    testWidgets('el atajo existe y funciona armando un plan asignado',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('r-1')).thenAnswer(
        (_) async => _singleModeRoutine(
          source: RoutineSource.trainerAssigned,
          assignedBy: 'trainer-1',
          assignedTo: 'athlete-x',
        ),
      );

      await _pumpEditor(
        tester,
        mode: const TrainerAssigning(
          athleteId: 'athlete-x',
          existingPlanId: 'r-1',
        ),
        repo: repo,
        uid: 'trainer-1',
      );

      // Confirma que estamos en modo entrenador: la nota al alumno sólo se
      // dibuja ahí (REQ-EN-002).
      expect(find.byKey(const Key('slot_notes_field')), findsOneWidget);

      await _tapVisible(tester, _kgField(0));
      expect(_plus5, findsOneWidget,
          reason: 'el editor es compartido: o funciona en los dos modos, o '
              'queda explícitamente gateado — acá funciona en los dos');

      await _tapVisible(tester, _plus5);
      expect(_kgText(tester, 0), '65');
    });
  });

  // ── Widget: nada de pesos negativos ────────────────────────────────────────

  group('sin valores negativos', () {
    testWidgets('bajar más de lo que hay deja el campo vacío, no un negativo',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('r-1'))
          .thenAnswer((_) async => _singleModeRoutine(weightKg: 2.5));

      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'r-1'),
        repo: repo,
      );

      await _tapVisible(tester, _kgField(0));
      expect(_kgText(tester, 0), '2.5');

      await _tapVisible(tester, _minus5);

      expect(_kgText(tester, 0), '',
          reason: 'el piso es "sin peso", no un 0 kg prescripto ni un -2.5');
      expect(_kgText(tester, 1), '2.5', reason: 'las demás filas no se tocan');
    });

    testWidgets('sin peso cargado los botones de bajar quedan deshabilitados',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('r-1'))
          .thenAnswer((_) async => _singleModeRoutine(weightKg: null));

      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'r-1'),
        repo: repo,
      );

      await _tapVisible(tester, _kgField(0));
      expect(_kgText(tester, 0), '');

      expect(tester.widget<GestureDetector>(_minus5).onTap, isNull);
      expect(tester.widget<GestureDetector>(_minus25).onTap, isNull);
      expect(tester.widget<GestureDetector>(_plus25).onTap, isNotNull,
          reason: 'sumar sobre vacío sí tiene sentido: parte de 0');

      // Y sumar desde vacío arranca en el salto elegido.
      await _tapVisible(tester, _plus25);
      expect(_kgText(tester, 0), '2.5');
      expect(tester.widget<GestureDetector>(_minus5).onTap, isNotNull,
          reason: 'con peso cargado bajar vuelve a habilitarse');
    });
  });
}
