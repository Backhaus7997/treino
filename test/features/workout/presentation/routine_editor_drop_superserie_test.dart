import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/app/theme/tokens/tokens.dart';
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
import 'package:treino/features/workout/presentation/widgets/superset_block.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_card.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../fixtures/routine_editor_ui.dart';
import '../../../helpers/fake_analytics_service.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

const _exercises = [
  Exercise(id: 'a', name: 'Ejercicio A', muscleGroup: 'Pecho', category: 'x'),
  Exercise(id: 'b', name: 'Ejercicio B', muscleGroup: 'Espalda', category: 'x'),
  Exercise(id: 'c', name: 'Ejercicio C', muscleGroup: 'Piernas', category: 'x'),
  Exercise(id: 'd', name: 'Ejercicio D', muscleGroup: 'Brazos', category: 'x'),
];

RoutineSlot _slot(
  String id, {
  int? group,
  List<int> activeWeeks = const [],
  int semanas = 1,
  bool sinReps = false,
}) =>
    RoutineSlot(
      exerciseId: id,
      exerciseName: 'Ejercicio ${id.toUpperCase()}',
      muscleGroup: 'Grupo',
      targetSets: 1,
      targetRepsMin: 10,
      targetRepsMax: 10,
      restSeconds: 60,
      supersetGroup: group,
      activeWeeks: activeWeeks,
      sets: sinReps ? const [SetSpec()] : const [SetSpec(reps: 10)],
      // Con `numWeeks > 1` el editor valida CADA semana. Sin `weeklySets`, la
      // semana 2 nace vacia y el pie bloquea el guardado: el test fallaba en
      // `updateUserOwned` sin haber llegado a ejercitar la union.
      weeklySets: List.filled(
        semanas,
        sinReps ? const [SetSpec()] : const [SetSpec(reps: 10)],
      ),
    );

Routine _routine(String id, List<RoutineSlot> slots, {int numWeeks = 1}) =>
    Routine(
      id: id,
      name: 'Rutina drag',
      split: null,
      level: ExperienceLevel.beginner,
      days: [RoutineDay(dayNumber: 1, name: 'Día 1', slots: slots)],
      source: RoutineSource.userCreated,
      visibility: RoutineVisibility.private,
      numWeeks: numWeeks,
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
  WidgetTester tester,
  _MockRoutineRepository repo,
) async {
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

Future<TestGesture> _arrastrarHasta(
  WidgetTester tester,
  Finder handle,
  Offset Function() destino,
) async {
  final desde = tester.getCenter(handle);
  final gesto = await tester.startGesture(desde);
  await tester.pump(kPressTimeout);
  const pasos = 10;
  for (var i = 1; i <= pasos; i++) {
    final hasta = destino();
    await gesto.moveTo(Offset.lerp(desde, hasta, i / pasos)!);
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesto.moveTo(destino());
  await tester.pump(const Duration(milliseconds: 16));
  return gesto;
}

void main() {
  setUpAll(() {
    registerFallbackValue(_routine('fallback', const []));
  });

  testWidgets('soltar un suelto en el centro lo une a esa superserie',
      (tester) async {
    final repo = await _pump(
      tester,
      _routine(
        'merge-center',
        [_slot('a', group: 7), _slot('b', group: 7), _slot('c')],
      ),
    );
    final superset = find.byType(SupersetBlock);

    final gesto = await _arrastrarHasta(
      tester,
      find.byKey(const Key('slot_drag_handle_2')),
      () => tester.getCenter(superset),
    );
    expect(
      tester.widget<SupersetBlock>(superset).resaltadoParaUnir,
      isTrue,
    );
    await gesto.up();
    await tester.pumpAndSettle();

    final saved = await _guardar(tester, repo);
    expect(saved.days.single.slots.map((slot) => slot.exerciseId), ['a', 'b', 'c']);
    expect(saved.days.single.slots.map((slot) => slot.supersetGroup), [7, 7, 7]);
  });

  testWidgets('soltar junto al borde sólo reordena y no une', (tester) async {
    final repo = await _pump(
      tester,
      _routine(
        'reorder-edge',
        [_slot('a', group: 7), _slot('b', group: 7), _slot('c')],
      ),
    );
    final superset = find.byType(SupersetBlock);

    final gesto = await _arrastrarHasta(
      tester,
      find.byKey(const Key('slot_drag_handle_2')),
      () {
        final rect = tester.getRect(superset);
        return Offset(rect.center.dx, rect.top + AppSpacing.hairline);
      },
    );
    expect(
      tester.widget<SupersetBlock>(superset).resaltadoParaUnir,
      isFalse,
    );
    await gesto.up();
    await tester.pumpAndSettle();

    final saved = await _guardar(tester, repo);
    expect(saved.days.single.slots.map((slot) => slot.exerciseId), ['c', 'a', 'b']);
    expect(saved.days.single.slots.map((slot) => slot.supersetGroup), [null, 7, 7]);
  });

  testWidgets('arrastrar una superserie nunca activa un destino de unión',
      (tester) async {
    final repo = await _pump(
      tester,
      _routine(
        'block-no-merge',
        [_slot('a', group: 7), _slot('b', group: 7), _slot('c')],
      ),
    );

    final gesto = await _arrastrarHasta(
      tester,
      find.byKey(const Key('superset_drag_handle')),
      () => tester.getCenter(find.byKey(const Key('slot_drag_handle_2'))),
    );
    expect(
      tester.widgetList<SupersetBlock>(find.byType(SupersetBlock))
          .every((block) => !block.resaltadoParaUnir),
      isTrue,
    );
    await gesto.up();
    await tester.pumpAndSettle();

    final saved = await _guardar(tester, repo);
    expect(saved.days.single.slots.map((slot) => slot.exerciseId), ['c', 'a', 'b']);
    expect(saved.days.single.slots.map((slot) => slot.supersetGroup), [null, 7, 7]);
  });

  testWidgets('la unión compacta el grupo aunque haya un slot oculto en medio',
      (tester) async {
    final repo = await _pump(
      tester,
      _routine(
        'merge-hidden',
        [
          _slot('a', group: 7, semanas: 2),
          _slot('b', group: 7, semanas: 2),
          _slot('d', activeWeeks: const [1], semanas: 2),
          _slot('c', semanas: 2),
        ],
        numWeeks: 2,
      ),
    );
    final superset = find.byType(SupersetBlock);

    final gesto = await _arrastrarHasta(
      tester,
      find.byKey(const Key('slot_drag_handle_3')),
      () => tester.getCenter(superset),
    );
    await gesto.up();
    await tester.pumpAndSettle();

    final saved = await _guardar(tester, repo);
    expect(saved.days.single.slots.map((slot) => slot.exerciseId), ['a', 'b', 'c', 'd']);
    expect(saved.days.single.slots.map((slot) => slot.supersetGroup), [7, 7, 7, null]);
  });

  testWidgets(
      'soltar en la zona central SIN cruzar el punto medio también une',
      (tester) async {
    // El caso que el test del centro exacto no toca. Flutter llama `onReorder`
    // SÓLO si el índice cambió: `SliverReorderableListState._dropCompleted`
    // hace `if (fromIndex != toIndex) widget.onReorder(...)`. El reorderable
    // cambia el índice recién cuando el proxy cruza el punto medio del vecino,
    // pero la zona de unión arranca al 20% de su alto. Entre el 50% y el 80%
    // hay una franja donde el bloque PROMETE que va a absorber y el índice no
    // se movió — y ahí una unión colgada de `onReorder` no se ejecuta nunca.
    final repo = await _pump(
      tester,
      _routine(
        'merge-sin-swap',
        [
          _slot('a', group: 7),
          _slot('b', group: 7),
          _slot('c', group: 7),
          _slot('d'),
        ],
      ),
    );
    final superset = find.byType(SupersetBlock);

    Offset destino() {
      final rect = tester.getRect(superset);
      return Offset(rect.center.dx, rect.top + rect.height * 0.70);
    }

    final gesto = await _arrastrarHasta(
      tester,
      find.byKey(const Key('slot_drag_handle_3')),
      destino,
    );
    expect(
      tester.widget<SupersetBlock>(superset).resaltadoParaUnir,
      isTrue,
      reason: 'el bloque promete absorber',
    );

    await gesto.up();
    await tester.pumpAndSettle();

    // Y tiene que CUMPLIR la promesa.
    final saved = await _guardar(tester, repo);
    expect(
      saved.days.single.slots.map((slot) => slot.supersetGroup),
      [7, 7, 7, 7],
    );
  });

  testWidgets('el agarre es un target grande y NO define el alto de la card',
      (tester) async {
    await _pump(tester, _routine('target', [_slot('a')]));

    final agarre = tester.getSize(find.byKey(const Key('slot_drag_handle_0')));

    // Ancho: bien arriba del mínimo de 44. Es lo barato de agrandar.
    expect(agarre.width, greaterThanOrEqualTo(56));

    // Alto: clavado al del ⋮. La fila mide lo que mide su hijo más alto, así
    // que un agarre más alto que 48 engorda CADA card de la pantalla. La
    // primera versión de esto puso 52 creyendo que la cabecera ya era más
    // alta; medía 44, y la card crecía. De ahí este test.
    expect(
      agarre.height,
      lessThanOrEqualTo(48),
      reason: 'el agarre pasó a ser lo más alto de la fila y engorda la card',
    );

    // Y el target igual es sustancialmente más grande que el mínimo.
    expect(agarre.width * agarre.height, greaterThan(44 * 44 * 1.3));
  });

  testWidgets('arrastrar un miembro FUERA del bloque lo saca de la superserie',
      (tester) async {
    final repo = await _pump(
      tester,
      _routine('sacar', [
        _slot('a', group: 7),
        _slot('b', group: 7),
        _slot('c', group: 7),
        _slot('d'),
      ]),
    );
    final superset = find.byType(SupersetBlock);
    final rect = tester.getRect(superset);

    final gesto = await _arrastrarHasta(
      tester,
      find.byKey(const Key('slot_drag_handle_0')),
      () => Offset(rect.center.dx, rect.bottom + 80),
    );
    await gesto.up();
    await tester.pumpAndSettle();

    final saved = await _guardar(tester, repo);
    // 'a' sale del grupo; los otros dos siguen juntos.
    final porId = {
      for (final s in saved.days.single.slots) s.exerciseId: s.supersetGroup,
    };
    expect(porId['a'], isNull, reason: 'salió del grupo');
    expect(porId['b'], 7);
    expect(porId['c'], 7);
  });

  testWidgets('arrastrar un miembro DENTRO del bloque sigue reordenando',
      (tester) async {
    final repo = await _pump(
      tester,
      _routine('adentro', [
        _slot('a', group: 7),
        _slot('b', group: 7),
        _slot('c', group: 7),
      ]),
    );

    // Del primer miembro al último, sin salir nunca del bloque.
    final gesto = await _arrastrarHasta(
      tester,
      find.byKey(const Key('slot_drag_handle_0')),
      () => tester.getCenter(find.byKey(const Key('slot_drag_handle_2'))),
    );
    await gesto.up();
    await tester.pumpAndSettle();

    final saved = await _guardar(tester, repo);
    // Nadie se separó: moverse adentro no es salirse.
    expect(
      saved.days.single.slots.map((s) => s.supersetGroup),
      [7, 7, 7],
      reason: 'reordenar dentro del grupo no puede desarmarlo',
    );
  });

  testWidgets('una rutina con ejercicios sin completar abre TODA plegada',
      (tester) async {
    await _pump(
      tester,
      _routine('sin-reps', [_slot('a', sinReps: true), _slot('b')]),
    );

    // Antes, una card con `hasSlotError` nacía desplegada. Con cinco
    // ejercicios eso era entrar a la pantalla con todo abierto.
    expect(find.byKey(const Key('exercise_card_body')), findsNothing);

    // Y la que falta completar se distingue igual, por el borde.
    const palette = AppPalette.mintMagenta;
    final bordes = tester
        .widgetList<Container>(find.descendant(
          of: find.byType(ExerciseCard),
          matching: find.byType(Container),
        ))
        .map((c) => c.decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.border != null && d.color == palette.bg)
        .map((d) => (d.border! as Border).top.color)
        .toList();
    expect(bordes, contains(palette.danger),
        reason: 'la que no está completa tiene que verse desde afuera');
    expect(bordes, contains(palette.border),
        reason: 'la que sí está completa NO se pinta');
  });

  testWidgets('reacomodar no despliega las cards sin completar',
      (tester) async {
    await _pump(
      tester,
      _routine('reacomodo', [
        _slot('a', group: 7),
        _slot('b', group: 7),
        _slot('c', sinReps: true),
      ]),
    );
    expect(find.byKey(const Key('exercise_card_body')), findsNothing);

    final superset = find.byType(SupersetBlock);
    final gesto = await _arrastrarHasta(
      tester,
      find.byKey(const Key('slot_drag_handle_2')),
      () => tester.getCenter(superset),
    );
    await gesto.up();
    await tester.pumpAndSettle();

    // Mover el slot a la lista ANIDADA del grupo lo cambia de lugar en el
    // árbol y Flutter recrea su State. Mientras `_expanded` era una variable
    // local inicializada con `hasSlotError`, ese inicializador volvía a correr
    // y la card se abría sola — reportado en device. Ahora el estado vive en
    // el modelo, que se mueve con el slot.
    expect(
      find.byKey(const Key('exercise_card_body')),
      findsNothing,
      reason: 'reacomodar no puede desplegar nada',
    );
  });

  testWidgets('sacar un miembro hacia ARRIBA lo deja delante de la superserie',
      (tester) async {
    final repo = await _pump(
      tester,
      _routine('salir-arriba', [
        _slot('a', group: 7),
        _slot('b', group: 7),
        _slot('c', group: 7),
      ]),
    );
    final rect = tester.getRect(find.byType(SupersetBlock));

    // El ÚLTIMO miembro, arrastrado por encima del bloque. Es el caso que
    // fallaba: `_conGruposContiguos` deja al que sale del medio o del final
    // siempre detrás, así que el gesto hacia arriba terminaba abajo.
    final gesto = await _arrastrarHasta(
      tester,
      find.byKey(const Key('slot_drag_handle_2')),
      () => Offset(rect.center.dx, rect.top - 60),
    );
    await gesto.up();
    await tester.pumpAndSettle();

    final saved = await _guardar(tester, repo);
    expect(
      saved.days.single.slots.map((s) => s.exerciseId),
      ['c', 'a', 'b'],
      reason: 'lo arrastré hacia arriba: tiene que quedar arriba',
    );
    expect(saved.days.single.slots.map((s) => s.supersetGroup), [null, 7, 7]);
  });

  testWidgets('sacar un miembro hacia ABAJO lo deja detrás de la superserie',
      (tester) async {
    final repo = await _pump(
      tester,
      _routine('salir-abajo', [
        _slot('a', group: 7),
        _slot('b', group: 7),
        _slot('c', group: 7),
      ]),
    );
    final rect = tester.getRect(find.byType(SupersetBlock));

    // El PRIMER miembro, arrastrado por debajo. Simétrico del anterior: sin
    // mirar el lado, compactar lo dejaría primero por ser el primero del grupo.
    final gesto = await _arrastrarHasta(
      tester,
      find.byKey(const Key('slot_drag_handle_0')),
      () => Offset(rect.center.dx, rect.bottom + 60),
    );
    await gesto.up();
    await tester.pumpAndSettle();

    final saved = await _guardar(tester, repo);
    expect(
      saved.days.single.slots.map((s) => s.exerciseId),
      ['b', 'c', 'a'],
      reason: 'lo arrastré hacia abajo: tiene que quedar abajo',
    );
    expect(saved.days.single.slots.map((s) => s.supersetGroup), [7, 7, null]);
  });

  testWidgets('sostener el arrastre contra el borde scrollea la pantalla',
      (tester) async {
    // Rutina larga: sin contenido que sobre, no hay scroll que probar.
    await _pump(
      tester,
      _routine('largo', [for (var i = 0; i < 16; i++) _slot('e$i')]),
    );

    final vertical = find.byWidgetPredicate(
      (w) => w is Scrollable && w.axisDirection == AxisDirection.down,
    );
    final posicion = tester.state<ScrollableState>(vertical.first).position;
    final antes = posicion.pixels;
    expect(posicion.maxScrollExtent, greaterThan(0),
        reason: 'el fixture tiene que dar para scrollear');

    final agarre = find.byKey(const Key('slot_drag_handle_0'));
    final gesto = await tester.startGesture(tester.getCenter(agarre));
    await tester.pump(kPressTimeout);

    // Hasta la franja de abajo, y ahí el dedo se QUEDA QUIETO. Ése es el caso
    // que importa: el `ReorderableListView` trae auto-scroll propio pero acá
    // está en shrinkWrap dentro del ListView del editor y no conoce el scroll
    // de afuera, así que sin esto sostener el dedo en el borde no hace nada.
    final viewport = tester.getRect(vertical.first);
    await gesto.moveTo(Offset(viewport.center.dx, viewport.bottom - 20));
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      tester.state<ScrollableState>(vertical.first).position.pixels,
      greaterThan(antes),
      reason: 'el dedo quieto contra el borde tiene que mover la lista',
    );

    await gesto.up();
    await tester.pumpAndSettle();

    // Y al soltar el timer se frena: si quedara vivo seguiría scrolleando sola.
    final alSoltar = tester.state<ScrollableState>(vertical.first).position.pixels;
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.state<ScrollableState>(vertical.first).position.pixels,
      alSoltar,
      reason: 'soltar tiene que frenar el auto-scroll',
    );
  });
}
