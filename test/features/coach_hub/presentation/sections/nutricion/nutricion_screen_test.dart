// WU-04 (Fase 6) — NutricionScreen: overview cross-alumno de Nutrición.
//
// Widget tests SOLO happy path (data) — el resto de los estados
// (loading/error) ya están cubiertos por `NutricionPlanRow`
// (nutricion_plan_row_test.dart) y el patrón compartido de
// `TreinoStateSwitcher` (invitaciones_screen_test.dart, alumnos_screen_test.dart).
// Cubre: roster poblado renderiza filas por alumno activo, el filtro
// Con plan/Sin plan particiona, y el tap navega a `/alumnos/:id` (ADR-F6-03).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/nutrition_plan_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/nutricion/nutricion_screen.dart';
import 'package:treino/features/profile/application/user_public_profile_providers.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;
import 'package:treino/l10n/app_l10n.dart';

const _trainerId = 'trainer-1';

TrainerLink _link(String athleteId, {TrainerLinkStatus? status}) => TrainerLink(
      id: 'link-$athleteId',
      trainerId: _trainerId,
      athleteId: athleteId,
      status: status ?? TrainerLinkStatus.active,
      requestedAt: DateTime.utc(2026, 1, 1),
      acceptedAt: DateTime.utc(2026, 1, 1),
    );

UserPublicProfile _prof(String uid, String name) =>
    UserPublicProfile(uid: uid, displayName: name);

NutritionPlan _plan(String athleteId, {int meals = 3}) => NutritionPlan(
      id: '${_trainerId}_$athleteId',
      trainerId: _trainerId,
      athleteId: athleteId,
      title: 'Plan de $athleteId',
      updatedAt: DateTime.utc(2026, 1, 5),
      meals: List.generate(
        meals,
        (i) => Meal(id: 'meal-$i', name: 'Comida $i', groups: const []),
      ),
    );

/// Pumpea `NutricionScreen` detrás de un `GoRouter` (para que el tap de fila
/// → `context.go('/alumnos/:id')` tenga a dónde ir) con providers stub —
/// mismo patrón que `alumnos_screen_test.dart`.
Future<void> _pump(
  WidgetTester tester, {
  required List<TrainerLink> links,
  List<UserPublicProfile> profiles = const [],
  Map<String, NutritionPlan?> plans = const {},
}) async {
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final profileByUid = {for (final p in profiles) p.uid: p};

  final router = GoRouter(
    initialLocation: '/nutricion',
    routes: [
      GoRoute(
        path: '/nutricion',
        builder: (_, __) => const Scaffold(body: NutricionScreen()),
      ),
      GoRoute(
        path: '/alumnos/:id',
        builder: (_, state) =>
            Scaffold(body: Text('DETALLE ${state.pathParameters['id']}')),
      ),
    ],
  );

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        currentUidProvider.overrideWithValue(_trainerId),
        trainerLinksStreamProvider.overrideWith(
          (ref) => Stream.value(links),
        ),
        userPublicProfileProvider.overrideWith(
          (ref, uid) => Stream.value(profileByUid[uid]),
        ),
        for (final entry in plans.entries)
          nutritionPlanProvider(
            (trainerId: _trainerId, athleteId: entry.key),
          ).overrideWith((ref) => Stream.value(entry.value)),
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
}

void main() {
  group('NutricionScreen — roster', () {
    testWidgets('roster poblado renderiza una fila por alumno activo',
        (tester) async {
      await _pump(
        tester,
        links: [
          _link('a1'),
          _link('a2'),
          _link('a3', status: TrainerLinkStatus.paused),
        ],
        profiles: [
          _prof('a1', 'Ana García'),
          _prof('a2', 'Beto López'),
          _prof('a3', 'Caro Díaz'),
        ],
        plans: {'a1': _plan('a1'), 'a2': null},
      );

      // Solo los links `active` entran al overview (a3 está paused).
      expect(find.text('Ana García'), findsOneWidget);
      expect(find.text('Beto López'), findsOneWidget);
      expect(find.text('Caro Díaz'), findsNothing);
    });
  });

  group('NutricionScreen — filtro', () {
    testWidgets('chip "Con plan" muestra solo alumnos con plan',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1'), _link('a2')],
        profiles: [_prof('a1', 'Ana García'), _prof('a2', 'Beto López')],
        plans: {'a1': _plan('a1'), 'a2': null},
      );

      await tester.tap(find.byKey(const Key('filter_chip_Con plan')));
      await tester.pumpAndSettle();

      expect(find.text('Ana García'), findsOneWidget);
      expect(find.text('Beto López'), findsNothing);
    });

    testWidgets('chip "Sin plan" muestra solo alumnos sin plan',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1'), _link('a2')],
        profiles: [_prof('a1', 'Ana García'), _prof('a2', 'Beto López')],
        plans: {'a1': _plan('a1'), 'a2': null},
      );

      await tester.tap(find.byKey(const Key('filter_chip_Sin plan')));
      await tester.pumpAndSettle();

      expect(find.text('Ana García'), findsNothing);
      expect(find.text('Beto López'), findsOneWidget);
    });
  });

  group('NutricionScreen — navegación', () {
    testWidgets('tap en una fila navega a /alumnos/:id (ADR-F6-03)',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1')],
        profiles: [_prof('a1', 'Ana García')],
        plans: {'a1': _plan('a1')},
      );

      await tester.tap(find.text('Ana García'));
      await tester.pumpAndSettle();

      expect(find.text('DETALLE a1'), findsOneWidget);
    });
  });
}
