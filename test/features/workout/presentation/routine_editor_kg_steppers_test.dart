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
//   - que la fila no se RE-INFLE al aparecer la barra (mismo EditableTextState)
//     y que el teclado del sistema quede abierto y usable con UN solo tap.
//   - que con la barra visible, tocar REPS/MÍN de la misma fila mueva el foco.
//   - que no exista en modo duración.
//   - que funcione en modo rango sin tocar MÍN/MÁX.
//   - que funcione en isTrainerMode (TrainerAssigning).
//   - que no permita valores negativos.
//
// Sobre el IME: los tests de teclado escriben por
// `tester.testTextInput.updateEditingValue`, NUNCA por `tester.enterText`.
// `enterText` llama a `showKeyboard()`, que vuelve a pedir el foco y reabre la
// conexión con el IME antes de cada tipeo — o sea, repara el bug en el harness
// y deja pasar una implementación que en un teléfono no deja escribir.
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
import '../../../fixtures/routine_editor_ui.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/workout/presentation/widgets/set_cell_field.dart';

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
  usarViewportAlto(tester);

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

  // La card de ejercicio arranca colapsada desde #864. Estos tests miran
  // valores de sets, así que necesitan la tabla en el árbol.
  await expandirEjercicios(tester);
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

// ── Sondas de bajo nivel ──────────────────────────────────────────────────────
//
// `TextField.focusNode` sólo sirve para el KG: es el ÚNICO campo de la fila que
// recibe una FocusNode externa. REPS/MÍN/MÁX dejan que `TextField` cree la suya
// internamente, así que para leerles el foco hay que bajar al `EditableText`.
// Bajar al EditableText además es lo que da la aserción que muerde: su State es
// el que muere cuando el subárbol se re-infla, no el `_SetRowState`.

Finder _editableOf(Finder field) =>
    find.descendant(of: field, matching: find.byType(EditableText));

EditableTextState _editableStateOf(WidgetTester tester, Finder field) =>
    tester.state<EditableTextState>(_editableOf(field));

bool _isFocused(WidgetTester tester, Finder field) =>
    tester.widget<EditableText>(_editableOf(field)).focusNode.hasFocus;

/// Manda una pulsación como la mandaría el teclado del sistema.
///
/// A propósito NO usa `tester.enterText`: ese helper llama a `showKeyboard()`,
/// que vuelve a pedir el foco y REABRE la conexión con el IME (ver
/// flutter_test/widget_tester.dart). O sea, repara el bug justo antes de cada
/// tipeo — un lujo que el usuario real no tiene. Escribir por
/// `testTextInput.updateEditingValue` sólo llega si hay un cliente conectado,
/// que es exactamente la propiedad que queremos custodiar.
Future<void> _typeThroughIme(WidgetTester tester, String text) async {
  tester.testTextInput.updateEditingValue(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );
  await tester.pumpAndSettle();
}

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

  group('columna de borrar', () {
    testWidgets('con un set único no reserva ancho: los campos lo recuperan',
        (tester) async {
      // Reportado mirando la app en un iPhone: con un solo set la fila se
      // veía corrida a la izquierda. La causa era un hueco de 40 px que la
      // fila reservaba para un botón de borrar que NO existe —con un set
      // único no se puede borrar, quedarías en cero—, más su placeholder
      // gemelo en la fila de headers.
      final repo = _MockRoutineRepository();
      when(() => repo.getById('r-1'))
          .thenAnswer((_) async => _singleModeRoutine());

      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'r-1'),
        repo: repo,
      );

      // La rutina viene con 2 sets: la columna existe y ocupa lugar.
      final borrar = find.byIcon(TreinoIcon.close);
      expect(borrar, findsNWidgets(2));
      final anchoConColumna =
          tester.getSize(find.byType(SetCellField).first).width;

      // Bajar a un set hace desaparecer la columna entera.
      await _tapVisible(tester, borrar.first);
      expect(find.byIcon(TreinoIcon.close), findsNothing);

      final anchoSinColumna =
          tester.getSize(find.byType(SetCellField).first).width;

      expect(
        anchoSinColumna,
        greaterThan(anchoConColumna),
        reason: 'Si los dos anchos son iguales, la fila sigue reservando '
            'espacio para un botón ausente y queda descentrada.',
      );
    });
  });

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
      // OJO con el alcance de estas dos: `_kgFocus` y `_kgCtrl` son campos
      // `late final` de `_SetRowState`, así que su identidad sólo prueba que el
      // State sobrevivió — es decir, que el ObjectKey no cambió porque _stepKg
      // muta el _EditableSet in place en vez de reemplazarlo como hace el fill
      // de columna. NO prueban que la fila no se haya re-inflado: el subárbol
      // puede morir entero y estos dos objetos sobreviven igual, porque los
      // posee el State y no el árbol. Esa otra propiedad la custodia el test
      // 'el subárbol de la fila NO se re-infla…' de acá abajo.
      expect(identical(before.focusNode, after.focusNode), isTrue,
          reason: 'misma FocusNode ⇒ mismo State ⇒ el ObjectKey no cambió');
      expect(identical(before.controller, after.controller), isTrue,
          reason: 'mismo TextEditingController ⇒ el stepper no reemplazó la '
              'instancia de _EditableSet');
      // Y la barra sigue en pantalla para el siguiente salto.
      expect(_plus5, findsOneWidget);
    });

    // ── Regresión: el teclado del sistema ────────────────────────────────────
    //
    // `build` devolvía `Row` sin foco y `Column` con foco. `Widget.canUpdate`
    // compara runtimeType, así que ese cambio de forma en la raíz hacía que
    // Flutter destruyera y re-inflara TODA la fila en cada cambio de foco del
    // campo KG. El `EditableText` nuevo no abre conexión con el IME
    // (`initState` no lo hace; sólo `_handleFocusChanged` —que necesita un
    // cambio de foco que ya ocurrió— y `requestKeyboard()` —que necesita otro
    // tap—), y el viejo la cerraba al morir. Resultado: el teclado subía y se
    // cerraba solo, y había que tocar el campo dos veces para escribir el peso.

    testWidgets('el subárbol de la fila NO se re-infla cuando aparece la barra',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('r-1'))
          .thenAnswer((_) async => _singleModeRoutine());

      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'r-1'),
        repo: repo,
      );

      final kgBefore = _editableStateOf(tester, _kgField(0));
      final repsBefore =
          _editableStateOf(tester, _fieldsWithHint('reps').at(0));

      await _tapVisible(tester, _kgField(0));
      expect(_anyStepper, findsNWidgets(4), reason: 'la barra sí apareció');

      // Ésta es la aserción que muerde: el State del EditableText vive en el
      // ÁRBOL, no en `_SetRowState`. Si la raíz de la fila cambia de tipo, éste
      // es el objeto que muere — y con él la conexión con el teclado.
      expect(identical(kgBefore, _editableStateOf(tester, _kgField(0))), isTrue,
          reason: 'el EditableText del KG no puede recrearse al tomar el foco: '
              'al morir cierra la conexión con el IME y el reemplazo no la '
              'reabre');
      expect(
          identical(repsBefore,
              _editableStateOf(tester, _fieldsWithHint('reps').at(0))),
          isTrue,
          reason: 'el resto de la fila tampoco: REPS crea su FocusNode adentro '
              'del TextField y perderla le come el próximo tap');
    });

    testWidgets('tocar el campo KG deja el teclado abierto y usable',
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

      expect(tester.testTextInput.hasAnyClients, isTrue,
          reason: 'un solo tap tiene que dejar conectado el IME');
      expect(tester.testTextInput.isVisible, isTrue,
          reason: 'el teclado sube y se QUEDA: si se cierra solo, el usuario '
              'tiene que tocar el campo una segunda vez para escribir el peso');

      // Y lo que teclea el usuario tiene que llegar al campo.
      await _typeThroughIme(tester, '75');
      expect(_kgText(tester, 0), '75',
          reason: 'sin cliente conectado la pulsación no llega a ningún lado y '
              'el campo se queda en 60');
    });

    testWidgets('el teclado sigue vivo después de tocar un stepper',
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
      await _tapVisible(tester, _plus5);

      expect(_kgText(tester, 0), '65');
      expect(tester.testTextInput.isVisible, isTrue,
          reason: 'el salto no puede tirarte el teclado: la barra existe para '
              'ahorrarte tipear, no para obligarte a reabrirlo');
      await _typeThroughIme(tester, '80');
      expect(_kgText(tester, 0), '80',
          reason: 'después del salto el campo sigue siendo tipeable');
    });

    // ── Regresión: la fila no puede atrapar el foco ──────────────────────────

    testWidgets(
        'con la barra visible, tocar REPS de la MISMA fila mueve el foco',
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
      expect(_anyStepper, findsNWidgets(4));

      await _tapVisible(tester, _fieldsWithHint('reps').at(0));

      expect(_isFocused(tester, _fieldsWithHint('reps').at(0)), isTrue,
          reason: 'un solo tap alcanza: si la fila se re-infla, la FocusNode '
              'interna de REPS se destruye justo después de ganar el foco y '
              'el foco rebota al KG');
      expect(
          tester.widget<TextField>(_kgField(0)).focusNode?.hasFocus, isFalse);
      expect(_anyStepper, findsNothing,
          reason: 'la barra se va con el foco del KG');
      expect(tester.testTextInput.isVisible, isTrue,
          reason: 'el teclado sigue arriba para escribir las repeticiones');
    });

    testWidgets('modo rango: tocar MÍN de la MISMA fila mueve el foco',
        (tester) async {
      final repo = _MockRoutineRepository();
      when(() => repo.getById('r-range'))
          .thenAnswer((_) async => _rangeModeRoutine);

      await _pumpEditor(
        tester,
        mode: const SelfCreating(existingRoutineId: 'r-range'),
        repo: repo,
      );

      await _tapVisible(tester, _kgField(0));
      expect(_anyStepper, findsNWidgets(4));

      await _tapVisible(tester, _fieldsWithHint('mín').at(0));

      expect(_isFocused(tester, _fieldsWithHint('mín').at(0)), isTrue,
          reason: 'MÍN y MÁX son el mismo _NumberField sin focusNode externa: '
              'les pega el mismo defecto que a REPS');
      expect(tester.testTextInput.isVisible, isTrue);
      expect(_anyStepper, findsNothing);
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
      await desplazarHasta(tester, find.byKey(const Key('slot_notes_field')));
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
