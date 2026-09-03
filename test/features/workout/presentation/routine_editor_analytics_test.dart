// Widget tests de los tres eventos de forma de rutina que emite el editor:
// `routine_day_added`, `routine_week_added` y `routine_created`.
//
// Son la telemetría que decide si un paywall del alumno suelto tiene sentido
// y dónde mordería. Por eso acá se assertea `source` y los contadores, no sólo
// el nombre del evento: un `routine_day_added` sin `days_count` no responde
// "¿cuánta gente pasa de 1 a 2 días?", y un `routine_created` sin `source`
// mezcla al alumno suelto con el PF — que es exactamente lo que el evento
// existe para separar.

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
import 'package:treino/features/workout/domain/set_spec.dart';
import 'package:treino/features/workout/presentation/routine_editor_mode.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';
import 'package:treino/l10n/app_l10n.dart';

import '../../../fixtures/exercises.dart';
import '../../../fixtures/routine_editor_ui.dart';
import '../../../helpers/fake_analytics_service.dart';

class _MockRoutineRepository extends Mock implements RoutineRepository {}

// ── Pump ──────────────────────────────────────────────────────────────────────

Future<void> _pumpEditor(
  WidgetTester tester, {
  required RoutineEditorMode mode,
  required List<Override> overrides,
}) async {
  usarViewportAlto(tester);
  final router = GoRouter(
    initialLocation: '/workout/editor',
    routes: [
      GoRoute(
        path: '/workout/editor',
        pageBuilder: (_, __) => NoTransitionPage(
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
      overrides: overrides,
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
}

List<Override> _overrides({
  required FakeAnalyticsService analytics,
  RoutineRepository? repo,
  String uid = 'athlete-1',
}) {
  final mockRepo = repo ?? _MockRoutineRepository();
  return [
    currentUidProvider.overrideWithValue(uid),
    routineRepositoryProvider.overrideWithValue(mockRepo),
    exercisesProvider.overrideWith((ref) async => kExerciseSeed),
    customExercisesForTrainerStreamProvider(uid).overrideWith(
      (ref) => Stream<List<CustomExercise>>.value(const <CustomExercise>[]),
    ),
    analyticsServiceProvider.overrideWithValue(analytics),
    userCreatedRoutinesProvider(uid).overrideWith(
      (ref) => Stream<List<Routine>>.value(const []),
    ),
  ];
}

// ── Acciones ──────────────────────────────────────────────────────────────────

/// Tap en el "+" de la barra de pestañas de días (`DayTabBar`).
///
/// Por key y no por texto: el botón es sólo un ícono y "Agregar día" vive en
/// su `Semantics.label`, que `find.text` no ve.
Future<void> _tapAgregarDia(WidgetTester tester) async {
  // Si venimos de una operación de semana, la hoja modal tapa la barra.
  await cerrarDatosDelPlan(tester);
  final boton = find.byKey(const Key('day_tab_add'));
  await tester.ensureVisible(boton);
  await tester.tap(boton);
  await tester.pumpAndSettle();
}

/// Tap en "+ Semana", que desde #866 vive en la hoja "DATOS DEL PLAN".
Future<void> _tapAgregarSemana(WidgetTester tester) async {
  await abrirDatosDelPlan(tester);
  final boton = find.byKey(const Key('add_week_button'));
  await desplazarHasta(tester, boton);
  await tester.tap(boton);
  await tester.pumpAndSettle();
  await cerrarDatosDelPlan(tester);
}

// ── Fixture: plantilla del catálogo para "Usar como base" ─────────────────────

const _sourceId = 'ppl-principiante';
const _sourceTemplate = Routine(
  id: _sourceId,
  name: 'Push Pull Legs — Principiante',
  split: 'PPL',
  level: ExperienceLevel.intermediate,
  days: [
    RoutineDay(
      dayNumber: 1,
      name: 'Empuje',
      slots: [
        RoutineSlot(
          exerciseId: 'bench-press',
          exerciseName: 'Press de Banca',
          muscleGroup: 'chest',
          targetSets: 3,
          targetRepsMin: 8,
          targetRepsMax: 8,
          restSeconds: 90,
          weeklySets: [
            [SetSpec(reps: 8), SetSpec(reps: 8), SetSpec(reps: 8)],
            [SetSpec(reps: 10), SetSpec(reps: 10), SetSpec(reps: 10)],
          ],
        ),
      ],
    ),
  ],
  source: RoutineSource.system,
  visibility: RoutineVisibility.public,
  numWeeks: 2,
);

_MockRoutineRepository _repoWithTemplate() {
  final repo = _MockRoutineRepository();
  when(() => repo.getById(_sourceId)).thenAnswer((_) async => _sourceTemplate);
  return repo;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(() {
    registerFallbackValue(
      const Routine(
        id: '',
        name: '',
        split: null,
        level: ExperienceLevel.beginner,
        days: [],
        source: RoutineSource.userCreated,
        visibility: RoutineVisibility.private,
        numWeeks: 1,
      ),
    );
  });

  testWidgets(
      'SelfCreating: "Agregar día" emite routine_day_added con source self '
      'y el total DESPUÉS de agregar', (tester) async {
    final analytics = FakeAnalyticsService();
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(analytics: analytics),
    );
    expect(analytics.paramsOf('routine_day_added'), isEmpty,
        reason: 'abrir el editor en blanco no es agregar un día');

    await _tapAgregarDia(tester);
    await _tapAgregarDia(tester);

    // El contador es el total nuevo (N+1), no el índice ni el delta: es lo
    // que permite leer "cuánta gente llegó a 2 días" sin reconstruir nada.
    expect(analytics.paramsOf('routine_day_added'), [
      {'source': 'self', 'days_count': 2},
      {'source': 'self', 'days_count': 3},
    ]);
  });

  testWidgets(
      'SelfCreating: "+ Semana" emite routine_week_added con source self '
      'y el total DESPUÉS de agregar', (tester) async {
    final analytics = FakeAnalyticsService();
    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(analytics: analytics),
    );

    await _tapAgregarSemana(tester);

    expect(analytics.paramsOf('routine_week_added'), [
      {'source': 'self', 'weeks_count': 2},
    ]);
    expect(analytics.paramsOf('routine_day_added'), isEmpty,
        reason: 'agregar una semana no es agregar un día');
  });

  testWidgets(
      'SelfCreating: guardar emite routine_created con la forma que se '
      'persistió', (tester) async {
    final analytics = FakeAnalyticsService();
    final repo = _MockRoutineRepository();
    when(() => repo.createUserOwned(
          uid: any(named: 'uid'),
          draft: any(named: 'draft'),
        )).thenAnswer((inv) async {
      final draft = inv.namedArguments[const Symbol('draft')] as Routine;
      return draft.copyWith(id: 'gen-id');
    });

    await _pumpEditor(
      tester,
      mode: const SelfCreating(),
      overrides: _overrides(analytics: analytics, repo: repo),
    );

    // Misma receta que routine_editor_athlete_mode_test: nombre + un
    // ejercicio con reps es lo mínimo que habilita el submit.
    await tester.enterText(
        find.byKey(const Key('editor_name_field')), 'Mi rutina');
    await tester.pumpAndSettle();
    await desplazarHastaAgregarEjercicio(tester);
    await tester.tap(find.text('Agregar ejercicio'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Press de Banca').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Agregar 1 ejercicio'));
    await tester.pumpAndSettle();
    await expandirEjercicios(tester);
    final emptyFields = find.byType(TextField).evaluate().where((e) {
      final w = e.widget as TextField;
      return w.controller != null && w.controller!.text.isEmpty;
    }).toList();
    expect(emptyFields, isNotEmpty, reason: 'expected empty REPS field');
    final repsField = emptyFields.last.widget as TextField;
    await tester.enterText(find.byWidget(repsField), '10');
    await tester.pumpAndSettle();

    expect(analytics.paramsOf('routine_created'), isEmpty,
        reason: 'la rutina se cuenta al guardarse, no al armarse');

    await tester.tap(find.widgetWithText(ElevatedButton, 'CREAR RUTINA'));
    await tester.pumpAndSettle();

    verify(() => repo.createUserOwned(
          uid: 'athlete-1',
          draft: any(named: 'draft'),
        )).called(1);
    expect(analytics.paramsOf('routine_created'), [
      {'source': 'self', 'days_count': 1, 'weeks_count': 1},
    ]);
  });

  testWidgets(
      'SelfCustomizing ("Usar como base"): hidratar no emite nada y agregar '
      'un día lleva source self_from_template', (tester) async {
    final analytics = FakeAnalyticsService();
    await _pumpEditor(
      tester,
      mode: const SelfCustomizing(sourceRoutineId: _sourceId),
      overrides: _overrides(analytics: analytics, repo: _repoWithTemplate()),
    );

    // La plantilla trae 1 día y 2 semanas. Cargarlas en el editor NO es una
    // acción del usuario: si esto contara, cada "usar como base" inflaría
    // routine_week_added sin que nadie haya tocado nada.
    expect(analytics.paramsOf('routine_day_added'), isEmpty);
    expect(analytics.paramsOf('routine_week_added'), isEmpty);

    await _tapAgregarDia(tester);

    // Es la dimensión que el paywall necesita y `RoutineSource` no tiene:
    // en Firestore esta copia es `user-created` igual que una armada de cero.
    expect(analytics.paramsOf('routine_day_added'), [
      {'source': 'self_from_template', 'days_count': 2},
    ]);
  });

  testWidgets(
      'TrainerAssigning: el PF también cuenta, pero con source '
      'trainer_assigned — se filtra en el reporte, no se omite',
      (tester) async {
    final analytics = FakeAnalyticsService();
    await _pumpEditor(
      tester,
      mode: const TrainerAssigning(athleteId: 'athlete-9'),
      overrides: _overrides(analytics: analytics, uid: 'trainer-1'),
    );

    await _tapAgregarDia(tester);

    expect(analytics.paramsOf('routine_day_added'), [
      {'source': 'trainer_assigned', 'days_count': 2},
    ]);
  });
}
