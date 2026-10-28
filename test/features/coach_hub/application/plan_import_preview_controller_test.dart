// PlanImportPreviewController: la orquestación de la vista previa sin
// widgets. La usan el Coach Hub (Excel) y mobile (PDF).

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/core/moderation/moderation_guard.dart';
import 'package:treino/features/coach/application/custom_exercise_quota_provider.dart';
import 'package:treino/features/coach_hub/application/cf_providers.dart';
import 'package:treino/features/coach_hub/application/plan_import_preview_controller.dart';
import 'package:treino/features/coach_hub/application/plan_import_providers.dart';
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';
import 'package:treino/features/coach_hub/data/periodized_import_draft.dart';
import 'package:treino/features/coach_hub/domain/periodized_plan.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/data/custom_exercise_repository.dart';
import 'package:treino/features/workout/data/routine_repository.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

class _MockRoutineRepo extends Mock implements RoutineRepository {}

class _MockCustomRepo extends Mock implements CustomExerciseRepository {}

class _MockFunctions extends Mock implements FirebaseFunctions {}

class _MockCallable extends Mock implements HttpsCallable {}

class _MockResult extends Mock implements HttpsCallableResult<dynamic> {}

const _trainer = 'trainer-1';
final _press = MatcherExercise(id: 'press', name: 'Press de banca');
final _remo = MatcherExercise(id: 'remo', name: 'Remo con barra');

ExerciseKey _k(int row) => (dayNumber: 1, row: row, component: 0);

/// Un día con un renglón por nombre, en orden.
PeriodizedPlan _plan(List<String> names) => PeriodizedPlan(numWeeks: 1, days: [
      PeriodizedDay(dayNumber: 1, rows: [
        for (var i = 0; i < names.length; i++)
          PeriodizedRow(
            position: i + 1,
            number: i + 1,
            restSeconds: 60,
            exercises: [
              PeriodizedExercise(
                component: 0,
                rawName: names[i],
                weeks: const [
                  [SetSpec(reps: 8)],
                ],
              ),
            ],
          ),
      ]),
    ]);

PeriodizedImportDraft _draft(
  List<String> names, {
  Map<ExerciseKey, MatcherExercise> assignments = const {},
  Map<ExerciseKey, MatcherExercise> suggestions = const {},
}) =>
    PeriodizedImportDraft(
      plan: _plan(names),
      warnings: const [],
      name: 'Plan',
      assignments: assignments,
      suggestions: suggestions,
    );

CustomExercise _custom(String id, String name) => CustomExercise(
      id: id,
      ownerId: _trainer,
      name: name,
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

void main() {
  late _MockRoutineRepo routines;
  late _MockFunctions functions;
  late _MockCallable addAlias;
  late List<Map<String, dynamic>> aliases;

  setUpAll(() {
    registerFallbackValue(buildAssignedRoutine(
      _draft(['x'], assignments: {_k(1): _press}),
      trainerUid: 't',
      athleteId: 'a',
      routineName: 'r',
      level: ExperienceLevel.beginner,
    ));
  });

  setUp(() {
    routines = _MockRoutineRepo();
    functions = _MockFunctions();
    addAlias = _MockCallable();
    aliases = [];
    when(() => functions.httpsCallable('addAlias')).thenReturn(addAlias);
    when(() => addAlias.call(any())).thenAnswer((inv) async {
      aliases.add(Map<String, dynamic>.from(
          inv.positionalArguments.single as Map<String, dynamic>));
      return _MockResult();
    });
  });

  ProviderContainer container(
    PeriodizedImportDraft draft, {
    List<Override> extra = const [],
  }) {
    final c = ProviderContainer(overrides: [
      ...extra,
      periodizedImportProvider.overrideWith((_) => draft),
      routineRepositoryProvider.overrideWithValue(routines),
      cloudFunctionsProvider.overrideWithValue(functions),
      currentUidProvider.overrideWithValue(_trainer),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  group('resolver', () {
    test('resuelve por clave exacta y registra el alias con el texto del PF',
        () async {
      final c = container(_draft(['Press banca', 'Press banca']));
      final ctrl = c.read(planImportPreviewControllerProvider);

      expect(ctrl.resolve(_k(1), _press), isTrue);
      await Future<void>.delayed(Duration.zero);

      final draft = c.read(periodizedImportProvider)!;
      expect(draft.assignments[_k(1)], same(_press));
      // El homónimo NO se resuelve: vincular es por renglón.
      expect(draft.isResolved(_k(2)), isFalse);
      expect(aliases, [
        {'exerciseId': 'press', 'alias': 'Press banca'}
      ]);
    });

    test('un componente ya resuelto no se resuelve dos veces', () async {
      final c = container(_draft(['Press banca']));
      final ctrl = c.read(planImportPreviewControllerProvider);

      ctrl.resolve(_k(1), _press);
      expect(ctrl.resolve(_k(1), _remo), isFalse);
      await Future<void>.delayed(Duration.zero);

      expect(
          c.read(periodizedImportProvider)!.assignments[_k(1)], same(_press));
      expect(aliases, hasLength(1));
    });

    test('confirmar la sugerencia la asigna', () {
      final c =
          container(_draft(['Remo pendlay'], suggestions: {_k(1): _remo}));

      expect(
          c.read(planImportPreviewControllerProvider).confirmSuggestion(_k(1)),
          isTrue);
      final draft = c.read(periodizedImportProvider)!;
      expect(draft.assignments[_k(1)], same(_remo));
      expect(draft.suggestions, isEmpty);
    });

    test(
        'confirmar las N: confirma sólo las sugeridas, en orden y con su '
        'alias; las sin match y las resueltas no se tocan', () async {
      final c = container(_draft(
        ['Press banca', 'Remo pendlay', 'Plancha rara', 'Pres banka'],
        assignments: {_k(1): _press},
        suggestions: {_k(2): _remo, _k(4): _press},
      ));
      final ctrl = c.read(planImportPreviewControllerProvider);
      expect(ctrl.draft!.pendingSuggestions, 2);

      expect(ctrl.confirmAllSuggestions(), 2);
      await Future<void>.delayed(Duration.zero);

      final draft = c.read(periodizedImportProvider)!;
      expect(draft.assignments[_k(2)], same(_remo));
      expect(draft.assignments[_k(4)], same(_press));
      expect(draft.isResolved(_k(3)), isFalse);
      expect(draft.pendingSuggestions, 0);
      expect(draft.withoutSuggestion, 1);
      // Igual que confirmar fila por fila: un alias por cada una, y ninguno
      // por la que ya venía resuelta.
      expect(aliases, [
        {'exerciseId': 'remo', 'alias': 'Remo pendlay'},
        {'exerciseId': 'press', 'alias': 'Pres banka'},
      ]);
    });

    test('confirmar las N es idempotente: la segunda vez no hace nada',
        () async {
      final c = container(_draft(['Remo pendlay', 'Plancha rara'],
          suggestions: {_k(1): _remo}));
      final ctrl = c.read(planImportPreviewControllerProvider);

      expect(ctrl.confirmAllSuggestions(), 1);
      final after = c.read(periodizedImportProvider);
      expect(ctrl.confirmAllSuggestions(), 0);
      await Future<void>.delayed(Duration.zero);

      expect(c.read(periodizedImportProvider), same(after));
      expect(aliases, hasLength(1));
    });

    test('confirmar las N sin sugerencias ni borrador devuelve 0', () {
      expect(
          container(_draft(['Plancha rara']))
              .read(planImportPreviewControllerProvider)
              .confirmAllSuggestions(),
          0);
      final empty = ProviderContainer(overrides: [
        periodizedImportProvider.overrideWith((_) => null),
      ]);
      addTearDown(empty.dispose);
      expect(
          empty
              .read(planImportPreviewControllerProvider)
              .confirmAllSuggestions(),
          0);
    });

    test('«Cambiar» sobre una resuelta (replace) la reemplaza; el mismo no',
        () async {
      final c =
          container(_draft(['Remo pendlay'], assignments: {_k(1): _press}));
      final ctrl = c.read(planImportPreviewControllerProvider);

      expect(ctrl.resolve(_k(1), _press, replace: true), isFalse);
      expect(ctrl.resolve(_k(1), _remo, replace: true), isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(c.read(periodizedImportProvider)!.assignments[_k(1)], same(_remo));
      expect(aliases, [
        {'exerciseId': 'remo', 'alias': 'Remo pendlay'}
      ]);
    });

    test('crear un propio resuelve sus homónimos sin alias', () async {
      final c = container(_draft(['Remo Pendlay', 'remo pendlay ', 'Otro']));
      final ctrl = c.read(planImportPreviewControllerProvider);

      final ok = await ctrl.createCustomFor(
        _k(1),
        canCreate: () async => true,
        openForm: (rawName, canSave) async {
          expect(rawName, 'Remo Pendlay');
          expect(canSave(), isTrue);
          return _custom('c-1', rawName);
        },
      );

      expect(ok, isTrue);
      final draft = c.read(planImportPreviewControllerProvider).draft!;
      expect(draft.assignments[_k(1)]!.id, 'c-1');
      expect(draft.assignments[_k(2)]!.id, 'c-1');
      expect(draft.isResolved(_k(3)), isFalse);
      expect(aliases, isEmpty);
    });

    test('en el tope del plan no abre el formulario', () async {
      final c = container(_draft(['Remo Pendlay']));
      var opened = false;

      final ok =
          await c.read(planImportPreviewControllerProvider).createCustomFor(
                _k(1),
                canCreate: () async => false,
                openForm: (_, __) async {
                  opened = true;
                  return null;
                },
              );

      expect(ok, isFalse);
      expect(opened, isFalse);
    });
  });

  group('asignar', () {
    Future<PlanAssignOutcome> assign(
      ProviderContainer c, [
      List<String> athletes = const ['a1', 'a2'],
    ]) =>
        c.read(planImportPreviewControllerProvider).assign(
              athleteIds: athletes,
              trainerUid: _trainer,
              routineName: '  Mi plan ',
              level: ExperienceLevel.advanced,
            );

    PeriodizedImportDraft resolved() =>
        _draft(['Press de banca'], assignments: {_k(1): _press});

    test('devuelve los ids creados en el orden de los alumnos', () async {
      when(() => routines.createAssigned(any())).thenAnswer((inv) async {
        final r = inv.positionalArguments.single as Routine;
        // El primero termina último: el orden no es el de llegada.
        if (r.assignedTo == 'a1') {
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        return r.copyWith(id: 'r-${r.assignedTo}');
      });
      final c = container(resolved());

      final outcome = await assign(c);

      expect((outcome as PlanAssignSuccess).routineIds, ['r-a1', 'r-a2']);
    });

    test('a todos: crea una rutina asignada por alumno', () async {
      final saved = <Routine>[];
      when(() => routines.createAssigned(any())).thenAnswer((inv) async {
        saved.add(inv.positionalArguments.single as Routine);
        return inv.positionalArguments.single as Routine;
      });
      final c = container(resolved());

      final outcome = await assign(c);

      expect((outcome as PlanAssignSuccess).assigned, 2);
      expect(saved.map((r) => r.assignedTo), ['a1', 'a2']);
      expect(saved.first.assignedBy, _trainer);
      expect(saved.first.name, 'Mi plan');
      expect(saved.first.level, ExperienceLevel.advanced);
      // El borrador lo limpia la UI, no el controller.
      expect(c.read(periodizedImportProvider), isNotNull);
    });

    test('parcial: devuelve sólo los que fallaron', () async {
      when(() => routines.createAssigned(any())).thenAnswer((inv) async {
        final r = inv.positionalArguments.single as Routine;
        if (r.assignedTo == 'a2') throw Exception('red');
        return inv.positionalArguments.single as Routine;
      });

      final outcome = await assign(container(resolved()), ['a1', 'a2', 'a3']);

      outcome as PlanAssignPartial;
      expect(outcome.assigned, 2);
      expect(outcome.failedAthleteIds, ['a2']);
    });

    test('todos fallan', () async {
      when(() => routines.createAssigned(any())).thenThrow(Exception('red'));

      expect(await assign(container(resolved())), isA<PlanAssignAllFailed>());
    });

    test('moderación: bloquea con el campo, no como fallo de red', () async {
      when(() => routines.createAssigned(any()))
          .thenThrow(const ModerationBlockedException('days.0.slots.0.notes'));

      final outcome = await assign(container(resolved()));

      expect((outcome as PlanAssignModerationBlocked).campo,
          'days.0.slots.0.notes');
    });

    test('con una sugerencia pendiente no escribe nada', () async {
      final c =
          container(_draft(['Remo pendlay'], suggestions: {_k(1): _remo}));

      final outcome = await assign(c);

      expect((outcome as PlanAssignBlockedUnresolved).pendingSuggestions, 1);
      verifyNever(() => routines.createAssigned(any()));
    });

    test('sin alumnos no escribe nada', () async {
      expect(await assign(container(resolved()), const []),
          isA<PlanAssignNoAthletes>());
      verifyNever(() => routines.createAssigned(any()));
    });
  });

  group('crear N propios', () {
    late _MockCustomRepo customs;
    late List<String> createdNames;

    setUp(() {
      customs = _MockCustomRepo();
      createdNames = [];
      when(() => customs.create(
          trainerId: any(named: 'trainerId'),
          name: any(named: 'name'))).thenAnswer((inv) async {
        final name = inv.namedArguments[#name] as String;
        createdNames.add(name);
        return _custom('c-${createdNames.length}', name);
      });
    });

    /// Remo Pendlay ×2 (uno con otras mayúsculas), Face pull, Press banca con
    /// sugerencia (no cuenta), Hip thrust: N = 3.
    PeriodizedImportDraft plan() => _draft(
          [
            'Remo Pendlay',
            'Face pull',
            'REMO  pendlay',
            'Press banca',
            'Hip thrust',
          ],
          suggestions: {_k(4): _press},
        );

    ProviderContainer withQuota(AsyncValue<CustomExerciseQuota> quota) =>
        container(plan(), extra: [
          customExerciseRepositoryProvider.overrideWithValue(customs),
          customExerciseQuotaProvider.overrideWithValue(quota),
        ]);

    test('N cuenta nombres distintos y deja afuera las sugerencias', () {
      final ctrl = withQuota(const AsyncValue.data((limit: null, count: 0)))
          .read(planImportPreviewControllerProvider);

      expect(ctrl.bulkCustomGroups.map((g) => g.name),
          ['Remo Pendlay', 'Face pull', 'Hip thrust']);
    });

    test('entran todos: crea los N y resuelve también los homónimos', () async {
      final c = withQuota(const AsyncValue.data((limit: 20, count: 5)));
      final ctrl = c.read(planImportPreviewControllerProvider);

      final check = await ctrl.checkBulkCustom() as BulkCustomReady;
      expect((check.total, check.allowed), (3, 3));
      final result = await ctrl.createCustomInBulk(max: check.allowed);

      expect(result.created, 3);
      expect(createdNames, ['Remo Pendlay', 'Face pull', 'Hip thrust']);
      final draft = ctrl.draft!;
      expect(draft.assignments[_k(1)]!.id, 'c-1');
      expect(draft.assignments[_k(3)]!.id, 'c-1');
      // La sugerencia sigue pendiente: no se pisa con un propio.
      expect(draft.unresolved, [_k(4)]);
      expect(aliases, isEmpty);
    });

    test('te alcanza para X de N: crea los primeros X en orden', () async {
      final c = withQuota(const AsyncValue.data((limit: 20, count: 19)));
      final ctrl = c.read(planImportPreviewControllerProvider);

      final check = await ctrl.checkBulkCustom() as BulkCustomReady;
      expect((check.total, check.allowed), (3, 1));
      await ctrl.createCustomInBulk(max: check.allowed);

      expect(createdNames, ['Remo Pendlay']);
      expect(ctrl.draft!.isResolved(_k(2)), isFalse);
      expect(ctrl.draft!.isResolved(_k(5)), isFalse);
    });

    test('tope alcanzado: allowed 0 y no se crea nada', () async {
      final c = withQuota(const AsyncValue.data((limit: 20, count: 20)));
      final ctrl = c.read(planImportPreviewControllerProvider);

      final check = await ctrl.checkBulkCustom() as BulkCustomReady;
      final result = await ctrl.createCustomInBulk(max: check.allowed);

      expect(check.allowed, 0);
      expect(result.created, 0);
      expect(createdNames, isEmpty);
    });

    test('cuota en error: «no sé», no «entran todos»', () async {
      final c = withQuota(AsyncValue.error(StateError('x'), StackTrace.empty));

      final check =
          await c.read(planImportPreviewControllerProvider).checkBulkCustom();

      expect(check, isA<BulkCustomQuotaUnknown>());
      expect(check.total, 3);
    });

    test('si la regla rechaza a mitad, corta y conserva lo creado', () async {
      var calls = 0;
      when(() => customs.create(
          trainerId: any(named: 'trainerId'),
          name: any(named: 'name'))).thenAnswer((inv) async {
        if (++calls == 2) throw StateError('permission-denied');
        return _custom('c-$calls', inv.namedArguments[#name] as String);
      });
      final ctrl = withQuota(const AsyncValue.data((limit: null, count: 0)))
          .read(planImportPreviewControllerProvider);

      final result = await ctrl.createCustomInBulk(max: 3);

      expect((result.created, result.requested), (1, 3));
      expect(result.error, isA<StateError>());
      expect(ctrl.draft!.isResolved(_k(1)), isTrue);
      expect(ctrl.draft!.isResolved(_k(2)), isFalse);
    });
  });
}
