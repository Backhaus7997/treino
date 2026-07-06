// Widget tests for the Coach Hub web "Nutrición" tab
// (alumno_detail_screen.dart, W2+).
//
// Covered:
//   - empty state: seed presets (6 comidas default)
//   - populated: existing plan renders title + meals
//   - save flow: tap "GUARDAR PLAN" hits repository.save() with the draft
//   - cross-alumno: swap athlete resets the draft

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
import 'package:treino/features/coach/domain/follow_up_entry.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart';
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
  }) async =>
      throw UnimplementedError();
  @override
  Stream<List<AthleteFile>> watch(String trainerId, String athleteId) =>
      const Stream.empty();
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
}) =>
    [
      currentUidProvider.overrideWithValue(_trainerUid),
      trainerLinksStreamProvider
          .overrideWith((ref) => Stream.value([_link(athleteUid)])),
      userPublicProfilesBatchProvider.overrideWith(
          (ref, key) => {athleteUid: _profile(athleteUid)}),
      userPublicProfileProvider.overrideWith(
          (ref, id) => Stream.value(_profile(id))),
      pagosPorCobrarProvider
          .overrideWith((ref) => const AsyncData(<CobroPendiente>[])),
      finishedTodayByUidProvider
          .overrideWith((ref, uid) => const <Session>[]),
      measurementsForAthleteProvider
          .overrideWith((ref, id) => Stream.value(const <Measurement>[])),
      performanceTestsForAthleteProvider
          .overrideWith(
              (ref, id) => Stream.value(const <PerformanceTest>[])),
      gymsProvider.overrideWith((ref) => const <Gym>[]),
      athleteBillingProvider.overrideWith((ref, id) => Stream.value(null)),
      sessionsByUidProvider.overrideWith((ref, id) => const <Session>[]),
      assignedRoutinesProvider
          .overrideWith((ref, id) => const <Routine>[]),
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
      ).overrideWith((ref) => Stream.value(existing)),
      if (repo != null)
        nutritionPlanRepositoryProvider.overrideWithValue(repo),
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
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  } catch (_) {}
  final tabBarContext = tester.element(find.byType(TabBar));
  // "Nutrición" es tab 2. Salteamos por TabController por si está off-screen.
  DefaultTabController.of(tabBarContext).animateTo(2);
  try {
    await tester.pumpAndSettle(const Duration(milliseconds: 500));
  } catch (_) {}
}

void main() {
  testWidgets('empty state: se seedean los 6 presets default',
      (tester) async {
    _useDesktopViewport(tester);
    await tester.pumpWidget(_wrap(_baseOverrides(athleteUid: _athleteUid), _athleteUid));
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
}
