// Vista previa del import de PDF en mobile (docs/plan-import-pdf.md, pasos
// 4 a 6): los cuatro estados del ejercicio, «Crear N propios» con y sin
// cupo, ASIGNAR bloqueado con pendientes y la asignación exitosa.

import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/core/moderation/moderation_guard.dart';
import 'package:treino/features/coach/application/custom_exercise_quota_provider.dart';
import 'package:treino/features/coach/presentation/plan_pdf_import_preview_screen.dart';
import 'package:treino/features/coach_hub/application/cf_providers.dart';
import 'package:treino/features/coach_hub/application/plan_import_providers.dart';
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';
import 'package:treino/features/coach_hub/data/periodized_import_draft.dart';
import 'package:treino/features/coach_hub/domain/periodized_plan.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/data/custom_exercise_repository.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

import '../../coach_hub/presentation/periodized_draft_fixtures.dart';

class _MockCustomRepo extends Mock implements CustomExerciseRepository {}

class _MockUserRepo extends Mock implements UserRepository {}

class _MockFunctions extends Mock implements FirebaseFunctions {}

final _press =
    MatcherExercise(id: 'ex-press', name: 'Press banca', muscleGroup: 'chest');
final _sentadilla =
    MatcherExercise(id: 'ex-squat', name: 'Sentadilla', muscleGroup: 'legs');
final _remo =
    MatcherExercise(id: 'ex-row', name: 'Remo con barra', muscleGroup: 'back');
final _remoM = MatcherExercise(
    id: 'ex-row-db', name: 'Remo con mancuerna', muscleGroup: 'back');

PeriodizedExercise _ex(int c, String name, {String? src}) => PeriodizedExercise(
      component: c,
      rawName: name,
      weeks: const [
        [SetSpec(reps: 8), SetSpec(reps: 8)],
        [SetSpec(reps: 6)],
      ],
      sourceText: src,
    );

PeriodizedRow _row(int pos, List<PeriodizedExercise> exs, {int? number}) =>
    PeriodizedRow(
        position: pos, number: number ?? pos, restSeconds: 90, exercises: exs);

const _k1 = (dayNumber: 1, row: 1, component: 0); // matcheado
const _k2 = (dayNumber: 1, row: 2, component: 0); // sugerido
const _k3 = (dayNumber: 1, row: 3, component: 0); // sugerido + alternativa
const _k4 = (dayNumber: 1, row: 4, component: 0); // sin match
const _k5 = (dayNumber: 1, row: 4, component: 1); // sin match (superserie)
const _k6 = (dayNumber: 2, row: 1, component: 0); // sin match, homónimo de k4

/// Un plan PDF con los cuatro estados.
PeriodizedImportDraft _draft() {
  final plan = PeriodizedPlan(numWeeks: 2, days: [
    PeriodizedDay(dayNumber: 1, rows: [
      _row(1, [_ex(0, 'Press banca plano', src: 'Press banca 2x8 @60kg')]),
      _row(2, [_ex(0, 'Sentadiya')]),
      _row(3, [_ex(0, 'Remo')]),
      _row(4, [_ex(0, 'Remo Pendlay'), _ex(1, 'Plancha copenhague')]),
    ]),
    PeriodizedDay(dayNumber: 2, rows: [
      _row(1, [_ex(0, 'remo  PENDLAY')]),
    ]),
  ]);
  return PeriodizedImportDraft(
    plan: plan,
    warnings: const [],
    name: 'Plan de Ana',
    assignments: {_k1: _press},
    suggestions: {_k2: _sentadilla, _k3: _remo},
    alternatives: {_k3: _remoM},
  );
}

/// Todo resuelto menos la sugerencia de [_k2]: confirmarla habilita ASIGNAR
/// y deja la pantalla «tocada» (salir pide confirmación).
PeriodizedImportDraft _casiResuelto() {
  final d = _resolved();
  return PeriodizedImportDraft(
    plan: d.plan,
    warnings: const [],
    name: d.name,
    assignments: {...d.assignments}..remove(_k2),
    suggestions: {_k2: _sentadilla},
  );
}

/// Todo resuelto: ASIGNAR habilitado.
PeriodizedImportDraft _resolved() {
  final d = _draft();
  return PeriodizedImportDraft(
    plan: d.plan,
    warnings: const [],
    name: d.name,
    assignments: {
      _k1: _press,
      _k2: _sentadilla,
      _k3: _remo,
      _k4: _remo,
      _k5: _press,
      _k6: _remo,
    },
    suggestions: const {},
  );
}

void main() {
  useTallSurface();

  late _MockCustomRepo customRepo;
  late _MockUserRepo userRepo;
  late _MockFunctions functions;
  late MockRoutineRepo routineRepo;
  late List<String> createdNames;

  setUpAll(() => registerFallbackValue(
        const Routine(
            id: '', name: '', level: ExperienceLevel.beginner, days: []),
      ));

  setUp(() {
    customRepo = _MockCustomRepo();
    userRepo = _MockUserRepo();
    functions = _MockFunctions();
    routineRepo = MockRoutineRepo();
    createdNames = [];
    when(() => customRepo.create(
          trainerId: any(named: 'trainerId'),
          name: any(named: 'name'),
          muscleGroup: any(named: 'muscleGroup'),
          secondaryMuscleGroup: any(named: 'secondaryMuscleGroup'),
          description: any(named: 'description'),
          videoUrl: any(named: 'videoUrl'),
          defaultRestSeconds: any(named: 'defaultRestSeconds'),
          equipment: any(named: 'equipment'),
        )).thenAnswer((inv) async {
      final name = inv.namedArguments[#name] as String;
      createdNames.add(name);
      return CustomExercise(
        id: 'custom-${createdNames.length}',
        ownerId: kTrainerUid,
        name: name,
        muscleGroup: (inv.namedArguments[#muscleGroup] as String?) ?? '',
        createdAt: DateTime.utc(2026, 1, 1),
        updatedAt: DateTime.utc(2026, 1, 1),
      );
    });
    when(() => userRepo.registrarTopeDelPlanPf(any(), any()))
        .thenAnswer((_) async {});
    when(() => functions.httpsCallable(any()))
        .thenThrow(Exception('sin red en tests'));
  });

  Future<ProviderContainer> pump(
    WidgetTester tester,
    PeriodizedImportDraft draft, {
    CustomExerciseQuota quota = (limit: null, count: 0),
    String? owner = kAthleteId,
  }) async {
    final router = GoRouter(
      initialLocation: '/coach/athlete/$kAthleteId',
      routes: [
        GoRoute(
          path: '/coach/athlete/:athleteId',
          builder: (_, __) => const Scaffold(body: Text('FICHA')),
        ),
        GoRoute(
          path: '/preview',
          builder: (_, __) =>
              const PlanPdfImportPreviewScreen(athleteId: kAthleteId),
        ),
        GoRoute(
          path: '/workout/routine-editor/:athleteId',
          builder: (_, state) => Scaffold(
            body: Text('editor:${state.pathParameters['athleteId']}:'
                '${state.extra}'),
          ),
        ),
      ],
    );
    final container = ProviderContainer(overrides: [
      ...previewOverrides(routineRepo),
      periodizedImportProvider.overrideWith(
          (ref) => owner == null ? draft : draft.forAthlete(owner)),
      customExerciseRepositoryProvider.overrideWithValue(customRepo),
      customExerciseQuotaProvider.overrideWithValue(AsyncValue.data(quota)),
      customExercisesForTrainerStreamProvider(kTrainerUid)
          .overrideWith((ref) => Stream.value(const <CustomExercise>[])),
      exercisesProvider.overrideWith((ref) async => const []),
      userRepositoryProvider.overrideWithValue(userRepo),
      cloudFunctionsProvider.overrideWithValue(functions),
    ]);
    addTearDown(container.dispose);
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: appWith(router, const []),
    ));
    router.push('/preview');
    await tester.pumpAndSettle();
    return container;
  }

  Finder assignButton() => find.byKey(const Key('pdf_import_assign'));
  bool assignEnabled(WidgetTester t) =>
      t.widget<ElevatedButton>(assignButton()).onPressed != null;

  group('los cuatro estados del ejercicio', () {
    testWidgets('matcheado: el nombre del catálogo, sin acciones',
        (tester) async {
      await pump(tester, _draft());
      expect(find.text('Press banca'), findsOneWidget);
      expect(find.text('Press banca plano'), findsNothing);
    });

    testWidgets('sugerido: Confirmar lo asigna', (tester) async {
      final c = await pump(tester, _draft());
      expect(find.text('Sugerencia: Sentadilla'), findsOneWidget);

      await tester.tap(find.text('Confirmar').first);
      await tester.pumpAndSettle();

      expect(c.read(periodizedImportProvider)!.assignments[_k2], _sentadilla);
      expect(find.text('Sugerencia: Sentadilla'), findsNothing);
    });

    testWidgets('con alternativa del LLM: Usar alternativa la asigna',
        (tester) async {
      final c = await pump(tester, _draft());
      expect(find.text('Sugerencia: Remo con barra'), findsOneWidget);
      expect(find.text('Alternativa: Remo con mancuerna'), findsOneWidget);
      // Sólo la fila con alternativa lo ofrece.
      expect(find.text('Usar alternativa'), findsOneWidget);

      await tester.tap(find.text('Usar alternativa'));
      await tester.pumpAndSettle();

      expect(c.read(periodizedImportProvider)!.assignments[_k3], _remoM);
    });

    testWidgets('sin match: vincular o crear como propio', (tester) async {
      await pump(tester, _draft());
      // Remo Pendlay ×2 y Plancha: tres filas en rojo.
      expect(find.text('sin match'), findsNWidgets(3));
      expect(find.text('Vincular con la biblioteca'), findsNWidgets(3));
      expect(find.text('Crear como propio'), findsNWidgets(3));
    });

    testWidgets('el texto del PDF se despliega y se pliega', (tester) async {
      await pump(tester, _draft());
      expect(find.text('Press banca 2x8 @60kg'), findsNothing);

      await tester.tap(find.text('Ver texto del PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Press banca 2x8 @60kg'), findsOneWidget);

      await tester.tap(find.text('Ocultar texto del PDF'));
      await tester.pumpAndSettle();
      expect(find.text('Press banca 2x8 @60kg'), findsNothing);
    });
  });

  group('Crear N propios', () {
    testWidgets('con cupo: crea uno por nombre distinto y resuelve homónimos',
        (tester) async {
      final c = await pump(tester, _draft());
      // Remo Pendlay (×2, mismo nombre normalizado) y Plancha: 2, no 3.
      // Las sugerencias no entran.
      expect(find.text('CREAR 2 PROPIOS'), findsOneWidget);

      await tester.tap(find.text('CREAR 2 PROPIOS'));
      await tester.pumpAndSettle();

      expect(createdNames, ['Remo Pendlay', 'Plancha copenhague']);
      final d = c.read(periodizedImportProvider)!;
      expect(d.assignments[_k4]!.id, d.assignments[_k6]!.id);
      expect(d.assignments[_k5]!.name, 'Plancha copenhague');
      expect(find.text('sin match'), findsNothing);
    });

    testWidgets('sin cupo para todos: avisa cuántos y crea sólo esos',
        (tester) async {
      await pump(tester, _draft(), quota: (limit: 20, count: 19));

      await tester.tap(find.text('CREAR 2 PROPIOS'));
      await tester.pumpAndSettle();
      expect(find.text('Te alcanza para 1 de 2'), findsOneWidget);

      await tester.tap(find.text('CREAR 1 PROPIO'));
      await tester.pumpAndSettle();

      expect(createdNames, ['Remo Pendlay']);
      expect(find.text('sin match'), findsOneWidget);
    });

    testWidgets('en el tope: no crea nada', (tester) async {
      await pump(tester, _draft(), quota: (limit: 20, count: 20));

      await tester.tap(find.text('CREAR 2 PROPIOS'));
      await tester.pumpAndSettle();

      expect(createdNames, isEmpty);
      expect(find.text('Te alcanza para 0 de 2'), findsNothing);
      expect(find.text('sin match'), findsNWidgets(3));
    });
  });

  testWidgets('pantalla chica, letra grande y nombres largos: sin desbordes',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.platformDispatcher.textScaleFactorTestValue = 1.6;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    const largo = 'Press inclinado con mancuernas en banco a 30 grados con '
        'pausa isométrica de dos segundos abajo';
    final plan = PeriodizedPlan(numWeeks: 8, days: [
      PeriodizedDay(dayNumber: 1, rows: [
        _row(1, [_ex(0, largo, src: largo), _ex(1, largo)]),
      ]),
    ]);
    await pump(
      tester,
      PeriodizedImportDraft(
        plan: plan,
        warnings: const [],
        name: largo,
        assignments: const {},
        suggestions: {_k1: _remoM},
        alternatives: {_k1: _remo},
      ),
    );
    final list = find
        .descendant(
            of: find.byType(ListView), matching: find.byType(Scrollable))
        .first;
    await tester.scrollUntilVisible(find.text('Ver texto del PDF'), 200,
        scrollable: list);
    await tester.tap(find.text('Ver texto del PDF'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Usar alternativa'), 200,
        scrollable: list);

    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('pdf_import_assign')), findsOneWidget);
  });

  group('asignar', () {
    testWidgets('deshabilitado mientras haya pendientes', (tester) async {
      await pump(tester, _draft());
      expect(assignEnabled(tester), isFalse);
      expect(find.byKey(const Key('pdf_import_pending')), findsOneWidget);
      verifyNever(() => routineRepo.createAssigned(any()));
    });

    testWidgets(
        'con todo resuelto asigna al alumno, vuelve a la ficha y ofrece el '
        'editor', (tester) async {
      when(() => routineRepo.createAssigned(any())).thenAnswer((inv) async =>
          (inv.positionalArguments.first as Routine).copyWith(id: 'nuevo-1'));
      final c = await pump(tester, _casiResuelto());
      expect(assignEnabled(tester), isFalse);
      // Resolver lo último a mano: desbloquea, y la pantalla queda «tocada»
      // (su PopScope ya no deja salir sin preguntar). Igual tiene que volver.
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();
      expect(assignEnabled(tester), isTrue);

      await tester.tap(assignButton());
      await tester.pumpAndSettle();

      final routine = verify(() => routineRepo.createAssigned(captureAny()))
          .captured
          .single as Routine;
      expect(routine.assignedTo, kAthleteId);
      expect(routine.assignedBy, kTrainerUid);
      expect(find.text('FICHA'), findsOneWidget);
      expect(c.read(periodizedImportProvider), isNull);

      await tester.tap(find.text('ABRIR EDITOR'));
      await tester.pumpAndSettle();
      expect(find.text('editor:$kAthleteId:nuevo-1'), findsOneWidget);
    });

    testWidgets('salir con cosas resueltas pregunta; «Salir igual» descarta',
        (tester) async {
      final c = await pump(tester, _casiResuelto());
      await tester.tap(find.text('Confirmar'));
      await tester.pumpAndSettle();

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.text('¿Salir sin guardar el plan?'), findsOneWidget);
      await tester.tap(find.text('Cancelar'));
      await tester.pumpAndSettle();
      expect(find.text('FICHA'), findsNothing);

      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salir igual'));
      await tester.pumpAndSettle();
      expect(find.text('FICHA'), findsOneWidget);
      expect(c.read(periodizedImportProvider), isNull);
    });

    testWidgets(
        'mientras guarda, ni el atrás de la barra ni el del sistema salen ni '
        'limpian el borrador', (tester) async {
      final pending = Completer<Routine>();
      when(() => routineRepo.createAssigned(any()))
          .thenAnswer((_) => pending.future);
      final c = await pump(tester, _resolved());

      await tester.tap(assignButton());
      await tester.pump();

      final back = find.byTooltip('Volver');
      expect(
          tester
              .widget<IconButton>(
                  find.ancestor(of: back, matching: find.byType(IconButton)))
              .onPressed,
          isNull);
      await tester.tap(back, warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.text('FICHA'), findsNothing);
      expect(find.text('¿Salir sin guardar el plan?'), findsNothing);
      expect(c.read(periodizedImportProvider), isNotNull);

      pending.complete(const Routine(
          id: 'nuevo-1',
          name: 'Plan de Ana',
          level: ExperienceLevel.intermediate,
          days: []));
      await tester.pumpAndSettle();
      expect(find.text('FICHA'), findsOneWidget);
    });

    testWidgets('dos taps en el mismo frame crean una sola rutina',
        (tester) async {
      final pending = Completer<Routine>();
      when(() => routineRepo.createAssigned(any()))
          .thenAnswer((_) => pending.future);
      await pump(tester, _resolved());

      // Sin pump entre los dos: el botón todavía está habilitado.
      await tester.tap(assignButton());
      await tester.tap(assignButton());
      await tester.pump();

      verify(() => routineRepo.createAssigned(any())).called(1);
      pending.complete(const Routine(
          id: 'nuevo-1',
          name: 'Plan de Ana',
          level: ExperienceLevel.intermediate,
          days: []));
      await tester.pumpAndSettle();
      verifyNever(() => routineRepo.createAssigned(any()));
    });

    testWidgets('si falla, el error queda en la pantalla y el plan también',
        (tester) async {
      when(() => routineRepo.createAssigned(any()))
          .thenThrow(Exception('offline'));
      final c = await pump(tester, _resolved());

      await tester.tap(assignButton());
      await tester.pumpAndSettle();

      expect(find.text('No pudimos guardar el plan. Probá de nuevo.'),
          findsOneWidget);
      expect(c.read(periodizedImportProvider), isNotNull);
      expect(find.text('FICHA'), findsNothing);
    });
  });

  group('nombre de la rutina', () {
    const bloqueado = 'Ese texto no se puede publicar porque incumple las '
        'Normas de Comunidad. Revisalo y volvé a intentar.';
    Finder nameField() => find.byKey(const Key('pdf_import_name'));

    testWidgets(
        'arranca con el del borrador y lo que escribe el PF es el nombre',
        (tester) async {
      final created = <Routine>[];
      when(() => routineRepo.createAssigned(any())).thenAnswer((inv) async {
        final r = inv.positionalArguments.first as Routine;
        created.add(r);
        return r.copyWith(id: 'nuevo-1');
      });
      final c = await pump(tester, _resolved());
      expect(tester.widget<TextField>(nameField()).controller!.text,
          'Plan de Ana');

      await tester.enterText(nameField(), 'Fuerza bloque 1');
      await tester.pump();
      expect(c.read(periodizedImportProvider)!.name, 'Fuerza bloque 1');

      await tester.tap(assignButton());
      await tester.pumpAndSettle();
      expect(created.single.name, 'Fuerza bloque 1');
    });

    testWidgets(
        'si la moderación rechaza el nombre, el foco va al campo con el '
        'mensaje y se reintenta sin volver a importar', (tester) async {
      final created = <Routine>[];
      var calls = 0;
      when(() => routineRepo.createAssigned(any())).thenAnswer((inv) async {
        calls++;
        if (calls == 1) throw const ModerationBlockedException('name');
        final r = inv.positionalArguments.first as Routine;
        created.add(r);
        return r.copyWith(id: 'nuevo-1');
      });
      final c = await pump(tester, _resolved());

      await tester.tap(assignButton());
      await tester.pumpAndSettle();

      expect(find.descendant(of: nameField(), matching: find.text(bloqueado)),
          findsOneWidget);
      expect(tester.widget<TextField>(nameField()).focusNode!.hasFocus, isTrue);
      // El borrador sigue: no hay que volver a importar.
      expect(c.read(periodizedImportProvider), isNotNull);
      expect(find.text('FICHA'), findsNothing);

      await tester.enterText(nameField(), 'Plan de fuerza');
      await tester.pump();
      expect(find.text(bloqueado), findsNothing);

      await tester.tap(assignButton());
      await tester.pumpAndSettle();
      expect(calls, 2);
      expect(created.single.name, 'Plan de fuerza');
      expect(find.text('FICHA'), findsOneWidget);
    });
  });

  group('el borrador es de un alumno', () {
    testWidgets('el de A abierto en la ruta de B no se muestra ni se asigna',
        (tester) async {
      final c = await pump(tester, _resolved(), owner: 'otro-alumno');

      expect(find.byKey(const Key('pdf_import_assign')), findsNothing);
      expect(find.text('Plan de Ana'), findsNothing);
      expect(find.text('FICHA'), findsOneWidget);
      verifyNever(() => routineRepo.createAssigned(any()));
      // Y no queda colgado para la próxima vista previa.
      expect(c.read(periodizedImportProvider), isNull);
    });

    testWidgets('sin alumno (el del Excel del Hub) tampoco', (tester) async {
      await pump(tester, _resolved(), owner: null);
      expect(find.byKey(const Key('pdf_import_assign')), findsNothing);
      expect(find.text('FICHA'), findsOneWidget);
    });

    testWidgets('resolver a mano conserva el alumno del borrador',
        (tester) async {
      final c = await pump(tester, _draft());
      await tester.tap(find.text('Confirmar').first);
      await tester.pumpAndSettle();
      expect(c.read(periodizedImportProvider)!.athleteId, kAthleteId);
      expect(find.byKey(const Key('pdf_import_assign')), findsOneWidget);
    });

    testWidgets('si la ruta se cierra sin asignar, el borrador se descarta',
        (tester) async {
      final c = await pump(tester, _resolved());
      GoRouter.of(tester.element(find.byKey(const Key('pdf_import_assign'))))
          .go('/coach/athlete/$kAthleteId');
      await tester.pumpAndSettle();

      expect(find.text('FICHA'), findsOneWidget);
      expect(c.read(periodizedImportProvider), isNull);
    });
  });
}
