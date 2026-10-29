// "Crear como propio" en la vista previa del import periodizado: una fila sin
// match se puede crear como ejercicio propio SÓLO al confirmar el formulario
// (nunca al subir), respetando el tope del plan y sin registrar alias.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/coach/application/custom_exercise_quota_provider.dart';
import 'package:treino/features/coach_hub/application/cf_providers.dart';
import 'package:treino/features/coach_hub/data/exercise_matcher.dart';
import 'package:treino/features/coach_hub/application/plan_import_providers.dart';
import 'package:treino/features/coach_hub/data/periodized_import_draft.dart';
import 'package:treino/features/coach_hub/data/periodized_routine_mapper.dart';
import 'package:treino/features/coach_hub/presentation/coach_hub_plan_preview_screen.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:treino/features/profile/application/user_providers.dart';
import 'package:treino/features/profile/data/user_repository.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/application/custom_exercise_providers.dart';
import 'package:treino/features/workout/data/custom_exercise_repository.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/routine.dart';

import 'periodized_draft_fixtures.dart';

class _MockCustomRepo extends Mock implements CustomExerciseRepository {}

class _MockUserRepo extends Mock implements UserRepository {}

class _MockFunctions extends Mock implements FirebaseFunctions {}

List<MatcherExercise> _catalog() => [
      MatcherExercise(id: 'ex-A', name: 'Ejercicio A', muscleGroup: 'legs'),
    ];

PeriodizedImportDraft _draft() => draftOf(
      [
        [1, 'Ejercicio A', 60, ...sameWeeks('3x8')],
        [2, 'Press Raro', 60, ...sameWeeks('3x8')],
        // Mismo nombre normalizado (mayúsculas y espacios distintos).
        [3, '  press   RARO ', 60, ...sameWeeks('3x8')],
        // Parecido pero DISTINTO: no se resuelve solo.
        [4, 'Press Raro 2', 60, ...sameWeeks('3x8')],
      ],
      catalog: _catalog(),
    );

Future<CustomExercise> _created(Invocation inv) async => CustomExercise(
      id: 'custom-1',
      ownerId: kTrainerUid,
      name: inv.namedArguments[#name] as String,
      muscleGroup: inv.namedArguments[#muscleGroup] as String,
      createdAt: DateTime.utc(2026, 1, 1),
      updatedAt: DateTime.utc(2026, 1, 1),
    );

void _stubCreate(_MockCustomRepo repo) {
  when(() => repo.create(
        trainerId: any(named: 'trainerId'),
        name: any(named: 'name'),
        muscleGroup: any(named: 'muscleGroup'),
        secondaryMuscleGroup: any(named: 'secondaryMuscleGroup'),
        description: any(named: 'description'),
        videoUrl: any(named: 'videoUrl'),
        defaultRestSeconds: any(named: 'defaultRestSeconds'),
        equipment: any(named: 'equipment'),
      )).thenAnswer(_created);
}

void _verifyNeverCreated(_MockCustomRepo repo) => verifyNever(() => repo.create(
      trainerId: any(named: 'trainerId'),
      name: any(named: 'name'),
      muscleGroup: any(named: 'muscleGroup'),
      secondaryMuscleGroup: any(named: 'secondaryMuscleGroup'),
      description: any(named: 'description'),
      videoUrl: any(named: 'videoUrl'),
      defaultRestSeconds: any(named: 'defaultRestSeconds'),
      equipment: any(named: 'equipment'),
    ));

void main() {
  useTallSurface();

  late _MockCustomRepo customRepo;
  late _MockUserRepo userRepo;
  late _MockFunctions functions;
  late MockRoutineRepo routineRepo;

  setUpAll(() => registerFallbackValue(
        const Routine(
            id: '', name: '', level: ExperienceLevel.beginner, days: []),
      ));

  setUp(() {
    customRepo = _MockCustomRepo();
    userRepo = _MockUserRepo();
    functions = _MockFunctions();
    routineRepo = MockRoutineRepo();
    _stubCreate(customRepo);
    when(() => userRepo.registrarTopeDelPlanPf(any(), any()))
        .thenAnswer((_) async {});
  });

  Future<void> pump(
    WidgetTester tester, {
    CustomExerciseQuota quota = (limit: null, count: 0),
  }) =>
      pumpPreview(
        tester,
        _draft(),
        routineRepo,
        extra: [
          customExerciseRepositoryProvider.overrideWithValue(customRepo),
          customExerciseQuotaProvider.overrideWithValue(AsyncValue.data(quota)),
          userRepositoryProvider.overrideWithValue(userRepo),
          cloudFunctionsProvider.overrideWithValue(functions),
        ],
      );

  testWidgets(
      'una fila sin match ofrece las dos acciones y NO crea nada al subir',
      (tester) async {
    await pump(tester);

    expect(find.text('Vincular con la biblioteca'), findsNWidgets(3));
    expect(find.text('Crear como propio'), findsNWidgets(3));
    // Lo que matcheó no ofrece ninguna.
    expect(find.bySemanticsLabel('sin ejercicio de la biblioteca'),
        findsNWidgets(3));
    _verifyNeverCreated(customRepo);
  });

  testWidgets(
      '"Crear como propio" precarga el nombre, crea por el repo existente, '
      'resuelve la fila y los homónimos exactos, y desbloquea', (tester) async {
    await pump(tester);

    await tester.tap(find.text('Crear como propio').first);
    await tester.pumpAndSettle();

    // El formulario existente, con el texto original del PF.
    final field = tester.widget<TextField>(
      find.byKey(const Key('create_exercise_name_field')),
    );
    expect(field.controller!.text, 'Press Raro');
    _verifyNeverCreated(customRepo); // abrir el formulario no crea

    await tester.tap(find.byKey(const Key('create_exercise_submit_button')));
    await tester.pumpAndSettle();

    verify(() => customRepo.create(
          trainerId: kTrainerUid,
          name: 'Press Raro',
          muscleGroup: '',
          secondaryMuscleGroup: any(named: 'secondaryMuscleGroup'),
          description: any(named: 'description'),
          videoUrl: any(named: 'videoUrl'),
          defaultRestSeconds: any(named: 'defaultRestSeconds'),
          equipment: any(named: 'equipment'),
        )).called(1);

    // La fila y su homónimo exacto quedaron resueltos; "Press Raro 2" no.
    expect(find.bySemanticsLabel('sin ejercicio de la biblioteca'),
        findsOneWidget);
    expect(find.text('Crear como propio'), findsOneWidget);
    // Sin alias: el ejercicio propio no vive en el catálogo global.
    verifyNever(() => functions.httpsCallable(any()));

    // Resolver el último (con otro nombre editado) desbloquea la asignación.
    await tester.tap(find.text('Crear como propio'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('create_exercise_submit_button')));
    await tester.pumpAndSettle();
    expect(
        find.bySemanticsLabel('sin ejercicio de la biblioteca'), findsNothing);

    when(() => routineRepo.createAssigned(any())).thenAnswer((inv) async =>
        (inv.positionalArguments.first as Routine).copyWith(id: 'r-1'));
    await tester.tap(find.text('Ana'));
    await tester.pump();
    await tester.tap(find.text('ASIGNAR PLAN'));
    await tester.pumpAndSettle();
    verify(() => routineRepo.createAssigned(any())).called(1);
  });

  testWidgets('cancelar el formulario no crea nada y la fila sigue en rojo',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Crear como propio').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    _verifyNeverCreated(customRepo);
    expect(find.bySemanticsLabel('sin ejercicio de la biblioteca'),
        findsNWidgets(3));
  });

  testWidgets(
      'en el tope del plan la acción se bloquea con el aviso de siempre y no '
      'crea nada; "Vincular con la biblioteca" sigue disponible',
      (tester) async {
    await pump(tester, quota: (limit: 20, count: 20));

    await tester.tap(find.text('Crear como propio').first);
    await tester.pumpAndSettle();

    // Aviso del tope, sin formulario.
    expect(find.textContaining('ejercicios propios'), findsWidgets);
    expect(find.byKey(const Key('create_exercise_name_field')), findsNothing);
    _verifyNeverCreated(customRepo);
    verify(() =>
            userRepo.registrarTopeDelPlanPf(kTrainerUid, 'customExercises'))
        .called(1);
  });

  testWidgets(
      'doble tap en "Crear como propio": un solo diálogo y un solo ejercicio '
      'creado', (tester) async {
    await pump(tester);

    // Dos activaciones seguidas, sin frame en medio: la segunda llega mientras
    // la primera todavía espera el embudo del tope (un tap real no la alcanza
    // porque el diálogo ya tapó el botón).
    final onPressed = tester
        .widget<TreinoButton>(
          find.widgetWithText(TreinoButton, 'Crear como propio').first,
        )
        .onPressed!;
    onPressed();
    onPressed();
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('create_exercise_name_field')), findsOneWidget);

    await tester.tap(find.byKey(const Key('create_exercise_submit_button')));
    await tester.pumpAndSettle();

    verify(() => customRepo.create(
          trainerId: any(named: 'trainerId'),
          name: any(named: 'name'),
          muscleGroup: any(named: 'muscleGroup'),
          secondaryMuscleGroup: any(named: 'secondaryMuscleGroup'),
          description: any(named: 'description'),
          videoUrl: any(named: 'videoUrl'),
          defaultRestSeconds: any(named: 'defaultRestSeconds'),
          equipment: any(named: 'equipment'),
        )).called(1);
    // Y nada queda abierto: no hay un segundo diálogo detrás.
    expect(find.byKey(const Key('create_exercise_name_field')), findsNothing);
  });

  testWidgets(
      'si la fila se resuelve con el diálogo abierto, guardar no crea nada',
      (tester) async {
    await pump(tester);

    await tester.tap(find.text('Crear como propio').first);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('create_exercise_name_field')), findsOneWidget);

    // La fila (y sus homónimos) se resuelve por otro camino.
    final container = ProviderScope.containerOf(
        tester.element(find.byType(CoachHubPlanPreviewScreen)));
    var draft = container.read(periodizedImportProvider)!;
    final key = [
      for (final day in draft.plan.days)
        for (final row in day.rows)
          for (final ex in row.exercises)
            if (ex.rawName == 'Press Raro') exerciseKeyOf(day, row, ex)
    ].first;
    draft = draft.resolveWithSameName(
        key, MatcherExercise(id: 'ex-X', name: 'Press Raro'));
    container.read(periodizedImportProvider.notifier).state = draft;

    await tester.tap(find.byKey(const Key('create_exercise_submit_button')));
    await tester.pumpAndSettle();

    _verifyNeverCreated(customRepo);
    expect(find.byKey(const Key('create_exercise_name_field')), findsNothing);
  });
}
