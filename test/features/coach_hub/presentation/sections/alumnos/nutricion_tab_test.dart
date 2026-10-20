// Widget tests for the Coach Hub web "Nutrición" tab
// (alumno_detail_screen.dart, W2+).
//
// Covered:
//   - empty state: seed presets (6 comidas default)
//   - populated: existing plan renders title + meals
//   - save flow: tap "GUARDAR PLAN" hits repository.save() with the draft
//   - cross-alumno: swap athlete resets the draft

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/athlete_file_providers.dart';
import 'package:treino/features/coach/application/athlete_note_providers.dart';
import 'package:treino/features/coach/application/follow_up_entry_providers.dart';
import 'package:treino/features/coach/application/nutrition_plan_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/data/athlete_file_repository.dart';
import 'package:treino/features/coach/data/athlete_note_repository.dart';
import 'package:treino/features/coach/data/nutrition_plan_repository.dart';
import 'package:treino/features/coach/domain/athlete_file.dart';
import 'package:treino/features/coach/domain/athlete_note.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart';
import 'package:treino/features/coach_hub/presentation/widgets/button/treino_button.dart';
import 'package:treino/features/gyms/application/gym_providers.dart';
import 'package:treino/features/gyms/domain/gym.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/payments/application/billing_providers.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart';
import 'package:treino/features/performance/application/performance_test_providers.dart';
import 'package:treino/features/performance/domain/performance_test.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/assigned_routine_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/session.dart';
import 'package:treino/l10n/app_l10n.dart';

import 'alumno_detail_test_navigation.dart';

const _trainerUid = 't1';
const _athleteUid = 'a1';

TrainerLink _link(String athleteUid) => TrainerLink(
      id: '${_trainerUid}_$athleteUid',
      trainerId: _trainerUid,
      athleteId: athleteUid,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime(2026, 6, 1),
      acceptedAt: DateTime(2026, 6, 1),
    );

UserPublicProfile _profile(String uid) =>
    UserPublicProfile(uid: uid, displayName: 'Sofía');

class _StubNoteRepo implements AthleteNoteRepository {
  @override
  Future<void> setNote(AthleteNote note) async {}
  @override
  Stream<AthleteNote?> watch(String trainerId, String athleteId) =>
      const Stream.empty();
}

class _StubFileRepo implements AthleteFileRepository {
  @override
  Future<AthleteFile> upload({
    required String trainerId,
    required String athleteId,
    required String fileName,
    required String contentType,
    required dynamic bytes,
    bool sharedWithAthlete = true,
  }) async =>
      throw UnimplementedError();
  @override
  Stream<List<AthleteFile>> watch(String trainerId, String athleteId) =>
      const Stream.empty();
  @override
  Stream<List<AthleteFile>> watchSharedForAthlete(String athleteId) =>
      const Stream.empty();
  @override
  Future<void> setShared(AthleteFile file, bool shared) async {}
  @override
  Future<void> delete(AthleteFile file) async {}
}

class _StubNutritionRepo implements NutritionPlanRepository {
  final List<NutritionPlan> saved = [];

  @override
  Future<NutritionPlan?> get(String trainerId, String athleteId) async => null;

  @override
  Stream<NutritionPlan?> watch(String trainerId, String athleteId) =>
      const Stream<NutritionPlan?>.empty();

  @override
  Future<void> save(NutritionPlan plan) async {
    saved.add(plan);
  }

  @override
  Future<void> delete(String trainerId, String athleteId) async {}
}

List<Override> _baseOverrides({
  required String athleteUid,
  NutritionPlan? existing,
  NutritionPlanRepository? repo,
  Stream<NutritionPlan?>? planStream,
}) =>
    [
      currentUidProvider.overrideWithValue(_trainerUid),
      alumnoDetailIndicatorsProvider(_athleteUid).overrideWithValue(
        const AlumnoDetailIndicators(),
      ),
      trainerLinksStreamProvider
          .overrideWith((ref) => Stream.value([_link(athleteUid)])),
      userPublicProfilesBatchProvider
          .overrideWith((ref, key) => {athleteUid: _profile(athleteUid)}),
      userPublicProfileProvider
          .overrideWith((ref, id) => Stream.value(_profile(id))),
      pagosPorCobrarProvider
          .overrideWith((ref) => const AsyncData(<CobroPendiente>[])),
      finishedTodayByUidProvider.overrideWith((ref, uid) => const <Session>[]),
      measurementsForAthleteProvider
          .overrideWith((ref, id) => Stream.value(const <Measurement>[])),
      performanceTestsForAthleteProvider
          .overrideWith((ref, id) => Stream.value(const <PerformanceTest>[])),
      gymsProvider.overrideWith((ref) => const <Gym>[]),
      athleteBillingProvider.overrideWith((ref, id) => Stream.value(null)),
      sessionsByUidProvider.overrideWith((ref, id) => const <Session>[]),
      assignedRoutinesByTrainerProvider
          .overrideWith((ref, key) => const <Routine>[]),
      athleteNoteProvider(
        (trainerId: _trainerUid, athleteId: athleteUid),
      ).overrideWith((ref) => const Stream.empty()),
      athleteNoteRepositoryProvider.overrideWithValue(_StubNoteRepo()),
      athleteFilesProvider(
        (trainerId: _trainerUid, athleteId: athleteUid),
      ).overrideWith((ref) => const Stream.empty()),
      athleteFileRepositoryProvider.overrideWithValue(_StubFileRepo()),
      followUpEntriesProvider(
        (trainerId: _trainerUid, athleteId: athleteUid),
      ).overrideWith((ref) => const Stream.empty()),
      nutritionPlanProvider(
        (trainerId: _trainerUid, athleteId: athleteUid),
      ).overrideWith((ref) => planStream ?? Stream.value(existing)),
      if (repo != null) nutritionPlanRepositoryProvider.overrideWithValue(repo),
    ];

Widget _wrap(List<Override> overrides, String athleteUid) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: AlumnoDetailScreen(athleteId: athleteUid),
        ),
      ),
    );

void _useDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _selectNutricionTab(WidgetTester tester) async {
  await navigateAlumnoDetail(
    tester,
    group: 'Plan',
    subview: 'Nutrición',
  );
}

void main() {
  testWidgets('empty state: se seedean los 6 presets default', (tester) async {
    _useDesktopViewport(tester);
    await tester.pumpWidget(
        _wrap(_baseOverrides(athleteUid: _athleteUid), _athleteUid));
    await _selectNutricionTab(tester);

    expect(find.text('Plan de alimentación'), findsOneWidget);
    // Los 6 presets por nombre. Uso findsWidgets porque algunos names
    // ("Colación") coinciden entre un meal y un grupo dentro de otro meal.
    expect(find.text('Desayuno'), findsOneWidget);
    expect(find.text('Media mañana'), findsOneWidget);
    expect(find.text('Almuerzo'), findsOneWidget);
    expect(find.text('Merienda'), findsOneWidget);
    expect(find.text('Colación'), findsWidgets);
    expect(find.text('Cena'), findsOneWidget);
  });

  testWidgets('populated: plan existente renderiza título y comidas',
      (tester) async {
    final existing = NutritionPlan(
      id: '${_trainerUid}_$_athleteUid',
      trainerId: _trainerUid,
      athleteId: _athleteUid,
      title: 'Progresión 4 - Semana 9',
      meals: [
        const Meal(
          id: 'm1',
          name: 'Desayuno post entrenamiento',
          time: '07:00',
          groups: [
            FoodGroup(
              id: 'g1',
              name: 'Hidratos',
              selectionMode: SelectionMode.chooseOne,
              options: [
                FoodOption(
                  id: 'o1',
                  name: '5 discos de arroz',
                  quantity: '5',
                  unit: 'unidades',
                ),
              ],
            ),
          ],
        ),
      ],
      updatedAt: DateTime(2026, 7, 1),
    );
    _useDesktopViewport(tester);
    await tester.pumpWidget(
      _wrap(
        _baseOverrides(athleteUid: _athleteUid, existing: existing),
        _athleteUid,
      ),
    );
    await _selectNutricionTab(tester);

    expect(find.text('Progresión 4 - Semana 9'), findsOneWidget);
    expect(find.text('Desayuno post entrenamiento'), findsOneWidget);
    expect(find.text('5 discos de arroz'), findsOneWidget);
  });

  testWidgets('GUARDAR PLAN llama repository.save con el draft',
      (tester) async {
    final repo = _StubNutritionRepo();
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(
      _baseOverrides(athleteUid: _athleteUid, repo: repo),
      _athleteUid,
    ));
    await _selectNutricionTab(tester);

    await tester.tap(find.text('GUARDAR PLAN'));
    await tester.pumpAndSettle();

    expect(repo.saved.length, 1);
    expect(repo.saved.first.trainerId, _trainerUid);
    expect(repo.saved.first.athleteId, _athleteUid);
    // Presets seeded → 6 meals.
    expect(repo.saved.first.meals.length, 6);
  });

  testWidgets(
      'save() persiste con trainerId y athleteId correctos del par actual',
      (tester) async {
    // Sanity check: el draft persistido debe llevar el par correcto — evita
    // el bug clásico de que el estado quede pegado del alumno anterior. El
    // reset visual entre alumnos ya está cubierto por `didUpdateWidget` y
    // por los tests equivalentes de Notas privadas / Seguimiento.
    final repo = _StubNutritionRepo();
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(
      _baseOverrides(athleteUid: _athleteUid, repo: repo),
      _athleteUid,
    ));
    await _selectNutricionTab(tester);
    await tester.tap(find.text('GUARDAR PLAN'));
    await tester.pumpAndSettle();

    expect(repo.saved.length, 1);
    final persisted = repo.saved.first;
    expect(persisted.trainerId, _trainerUid);
    expect(persisted.athleteId, _athleteUid);
  });

  // ── #1553 ────────────────────────────────────────────────────────────────

  NutritionPlan planWith(List<Meal> meals) => NutritionPlan(
        id: '${_trainerUid}_$_athleteUid',
        trainerId: _trainerUid,
        athleteId: _athleteUid,
        title: '',
        meals: meals,
        updatedAt: DateTime(2026, 7, 1),
      );

  // El contador de ids arrancaba en 0 cada vez que se abría el editor: sobre
  // un plan con `meal-1` guardado, la comida nueva salía con el mismo id, y
  // escribir su nombre renombraba también la guardada.
  testWidgets('una comida nueva no hereda el id de una ya guardada',
      (tester) async {
    final repo = _StubNutritionRepo();
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(
      _baseOverrides(
        athleteUid: _athleteUid,
        existing: planWith(const [
          Meal(id: 'meal-1', name: 'Desayuno', groups: []),
        ]),
        repo: repo,
      ),
      _athleteUid,
    ));
    await _selectNutricionTab(tester);

    await tester.tap(find.text('AGREGAR COMIDA'));
    await tester.pumpAndSettle();
    // `.last`: el hint queda en el árbol aunque el campo tenga texto, así que
    // también matchea el de «Desayuno». La comida nueva es la última.
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Nombre de la comida').last,
      'Cena',
    );
    await tester.tap(find.text('GUARDAR PLAN'));
    await tester.pumpAndSettle();

    final meals = repo.saved.single.meals;
    expect(meals.map((m) => m.name), ['Desayuno', 'Cena']);
    expect(meals.map((m) => m.id).toSet().length, 2);
  });

  // Un plan ya guardado con ids repetidos (el bug de arriba) se normaliza al
  // abrirlo: editar una comida no arrastra a su gemela.
  testWidgets('un plan guardado con ids repetidos se edita comida por comida',
      (tester) async {
    final repo = _StubNutritionRepo();
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(
      _baseOverrides(
        athleteUid: _athleteUid,
        existing: planWith(const [
          Meal(id: 'meal-1', name: 'Desayuno', groups: []),
          Meal(id: 'meal-1', name: 'Cena', groups: []),
        ]),
        repo: repo,
      ),
      _athleteUid,
    ));
    await _selectNutricionTab(tester);

    await tester.enterText(
      find.widgetWithText(TextFormField, 'Desayuno'),
      'Desayuno liviano',
    );
    await tester.tap(find.text('GUARDAR PLAN'));
    await tester.pumpAndSettle();

    expect(
      repo.saved.single.meals.map((m) => m.name),
      ['Desayuno liviano', 'Cena'],
    );
  });

  // Sin `Key`, Flutter reusa el estado del campo por POSICIÓN: al borrar la
  // primera comida, la card que quedaba arriba mostraba el nombre de la
  // borrada sobre los datos de la siguiente.
  testWidgets('borrar la primera comida no deja su nombre en la siguiente',
      (tester) async {
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(
      _baseOverrides(
        athleteUid: _athleteUid,
        existing: planWith(const [
          Meal(id: 'm1', name: 'Desayuno', groups: []),
          Meal(id: 'm2', name: 'Almuerzo', groups: []),
        ]),
      ),
      _athleteUid,
    ));
    await _selectNutricionTab(tester);

    await tester.tap(find.byTooltip('Eliminar comida').first);
    await tester.pumpAndSettle();

    expect(find.widgetWithText(TextFormField, 'Desayuno'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Almuerzo'), findsOneWidget);
  });

  // Si la lectura fallaba, el editor arrancaba de los presets y dejaba
  // guardar: un GUARDAR PLAN pisaba el plan real que no se pudo leer.
  testWidgets('si la lectura falla no ofrece guardar un plan de presets',
      (tester) async {
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(
      _baseOverrides(
        athleteUid: _athleteUid,
        planStream: Stream<NutritionPlan?>.error(Exception('offline')),
      ),
      _athleteUid,
    ));
    await _selectNutricionTab(tester);

    expect(find.text('No pudimos cargar el plan nutricional.'), findsOneWidget);
    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('GUARDAR PLAN'), findsNothing);
    expect(find.text('Desayuno'), findsNothing);
  });

  // El alumno ve el plan en mobile (MI PLAN NUTRICIONAL): decirle al PF que
  // sólo lo ve él es una advertencia falsa (AGENTS.md §11.1).
  testWidgets('el subtítulo no dice que el plan es privado', (tester) async {
    _useDesktopViewport(tester);
    await tester.pumpWidget(
        _wrap(_baseOverrides(athleteUid: _athleteUid), _athleteUid));
    await _selectNutricionTab(tester);

    expect(find.textContaining('Solo vos lo ves'), findsNothing);
    expect(find.textContaining('Tu alumno lo ve'), findsOneWidget);
  });

  // ── #1581: el error de lectura gana sobre la copia de la caché ──────────
  //
  // Con la copia buena en la caché y el doc que el servidor devuelve ilegible,
  // Riverpod deja un `AsyncError` CON el valor viejo adentro. Sembrar de ahí
  // dejaba GUARDAR PLAN pisando el doc del servidor con la copia vieja.
  group('el error de lectura gana sobre la copia de la caché', () {
    late StreamController<NutritionPlan?> lectura;
    final ilegible = Exception('NutritionPlanIlegible: meals no es lista');
    const avisoBloqueo = 'No pudimos leer el plan guardado. Para no pisarlo, '
        'GUARDAR PLAN queda bloqueado hasta volver a leerlo.';

    setUp(() => lectura = StreamController<NutritionPlan?>.broadcast());
    tearDown(() => lectura.close());

    Future<void> montar(WidgetTester tester) async {
      _useDesktopViewport(tester);
      await tester.pumpWidget(_wrap(
        _baseOverrides(athleteUid: _athleteUid, planStream: lectura.stream),
        _athleteUid,
      ));
    }

    TreinoButton guardar(WidgetTester tester) => tester.widget<TreinoButton>(
          find.widgetWithText(TreinoButton, 'GUARDAR PLAN'),
        );

    testWidgets('abrir con el error ya puesto no siembra la copia vieja',
        (tester) async {
      await montar(tester);
      final container = ProviderScope.containerOf(
        tester.element(find.byType(AlumnoDetailScreen)),
      );
      const key = (trainerId: _trainerUid, athleteId: _athleteUid);
      final sub = container.listen(nutritionPlanProvider(key), (_, __) {});
      addTearDown(sub.close);
      lectura.add(planWith(const [
        Meal(id: 'm1', name: 'Desayuno viejo', groups: []),
      ]));
      await tester.pump();
      lectura.addError(ilegible);
      await tester.pump();
      final estado = container.read(nutritionPlanProvider(key));
      expect(estado.hasValue && estado.hasError, isTrue,
          reason: 'el caso a probar: error con el valor viejo adentro');

      await _selectNutricionTab(tester);

      expect(
        find.text('No pudimos cargar el plan nutricional.'),
        findsOneWidget,
      );
      expect(find.text('GUARDAR PLAN'), findsNothing);
      expect(find.text('Desayuno viejo'), findsNothing);
    });

    testWidgets(
        'carrera sin ediciones: se descarta el borrador y gana el error',
        (tester) async {
      await montar(tester);
      await _selectNutricionTab(tester);
      lectura.add(planWith(const [
        Meal(id: 'm1', name: 'Desayuno', groups: []),
      ]));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(TextFormField, 'Desayuno'), findsOneWidget);

      lectura.addError(ilegible);
      await tester.pumpAndSettle();

      expect(
        find.text('No pudimos cargar el plan nutricional.'),
        findsOneWidget,
      );
      expect(find.text('GUARDAR PLAN'), findsNothing);
    });

    testWidgets(
        'carrera con ediciones: conserva el borrador y bloquea GUARDAR PLAN '
        'hasta volver a leer', (tester) async {
      final repo = _StubNutritionRepo();
      _useDesktopViewport(tester);
      await tester.pumpWidget(_wrap(
        _baseOverrides(
          athleteUid: _athleteUid,
          planStream: lectura.stream,
          repo: repo,
        ),
        _athleteUid,
      ));
      await _selectNutricionTab(tester);
      lectura.add(planWith(const [
        Meal(id: 'm1', name: 'Desayuno', groups: []),
      ]));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextFormField, 'Desayuno'),
        'Desayuno liviano',
      );
      await tester.pump();

      lectura.addError(ilegible);
      await tester.pumpAndSettle();

      // No se le tira el trabajo al PF…
      expect(
        find.widgetWithText(TextFormField, 'Desayuno liviano'),
        findsOneWidget,
      );
      // …pero tampoco se lo deja guardar encima de lo que no se pudo leer.
      expect(find.text(avisoBloqueo), findsOneWidget);
      expect(guardar(tester).onPressed, isNull);

      // Reintentar lee bien: se desbloquea y el borrador sigue.
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      lectura.add(planWith(const [
        Meal(id: 'm1', name: 'Desayuno', groups: []),
      ]));
      await tester.pumpAndSettle();

      expect(find.text(avisoBloqueo), findsNothing);
      expect(guardar(tester).onPressed, isNotNull);
      expect(
        find.widgetWithText(TextFormField, 'Desayuno liviano'),
        findsOneWidget,
      );
      expect(repo.saved, isEmpty, reason: 'nada se guardó solo');
    });
  });
}
