// WU-04/WU-05 (Fase 6) — NutricionScreen: overview cross-alumno de
// Nutrición.
//
// WU-04 cubre el happy path (data): roster poblado renderiza filas por
// alumno activo, el filtro Con plan/Sin plan particiona, y el tap navega a
// `/alumnos/:id` (ADR-F6-03).
// WU-05 cubre los estados NO-happy (ADR-F6-06): empties honestos por caso
// (sin alumnos / filtro "Con plan" vacío / filtro "Sin plan" vacío), error
// con retry, loading con shimmer (`NutricionPlanRow.loading` x N) y el
// `childKey` de `TreinoStateSwitcher` cambiando con el filtro.
import 'dart:async';

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
  List<TrainerLink>? links,
  Stream<List<TrainerLink>>? linksStream,
  List<UserPublicProfile> profiles = const [],
  Map<String, NutritionPlan?> plans = const {},
  ThemeData? theme,
  // `false` cuando el stream de links queda colgado en loading a propósito
  // (`TreinoShimmer` corre en loop infinito — `pumpAndSettle` no termina
  // nunca). Mismo patrón que `invitaciones_screen_test.dart`.
  bool settle = true,
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
        path: '/alumnos',
        builder: (_, __) => const Scaffold(body: Text('ALUMNOS')),
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
          (ref) => linksStream ?? Stream.value(links ?? const []),
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
        theme: theme ?? AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        routerConfig: router,
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
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

  group('NutricionScreen — loading (WU-05)', () {
    testWidgets('roster en loading → shimmer, NutricionPlanRow.loading x N',
        (tester) async {
      final controller = StreamController<List<TrainerLink>>();
      addTearDown(controller.close);

      await _pump(tester, linksStream: controller.stream, settle: false);

      expect(find.byKey(const Key('list_row_skeleton')), findsNWidgets(5));
      // Título UPPERCASE automático de `TreinoSectionHeader`.
      expect(find.textContaining('NUTRICIÓN'), findsOneWidget);
    });
  });

  group('NutricionScreen — error (WU-05)', () {
    testWidgets('error al cargar el roster → mensaje + retry invoca invalidate',
        (tester) async {
      await _pump(
        tester,
        linksStream: Stream<List<TrainerLink>>.error(Exception('boom')),
      );

      expect(find.byKey(const Key('nutricion_error')), findsOneWidget);
      expect(find.text('No pudimos cargar tus alumnos.'), findsOneWidget);

      final retryButton = find.widgetWithText(TextButton, 'Reintentar');
      expect(retryButton, findsOneWidget);

      // Retry invalida el provider y re-suscribe al mismo stream fallido —
      // no debe crashear ni quedar colgado.
      await tester.tap(retryButton);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('nutricion_error')), findsOneWidget);
    });
  });

  group('NutricionScreen — empties por caso (WU-05, ADR-F6-06)', () {
    testWidgets(
        'sin alumnos activos vinculados → "Todavía no tenés alumnos" + CTA a Alumnos',
        (tester) async {
      await _pump(tester, links: const []);

      expect(
        find.byKey(const Key('nutricion_empty_sin_alumnos')),
        findsOneWidget,
      );
      expect(find.text('Todavía no tenés alumnos.'), findsOneWidget);

      await tester.tap(find.widgetWithText(TextButton, 'Ir a Alumnos'));
      await tester.pumpAndSettle();

      expect(find.text('ALUMNOS'), findsOneWidget);
    });

    testWidgets(
        'filtro "Con plan" sin resultados → "Ningún alumno con plan todavía"',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1'), _link('a2')],
        profiles: [_prof('a1', 'Ana García'), _prof('a2', 'Beto López')],
        plans: {'a1': null, 'a2': null},
      );

      await tester.tap(find.byKey(const Key('filter_chip_Con plan')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('nutricion_empty_conPlan')),
        findsOneWidget,
      );
      expect(find.text('Ningún alumno con plan todavía.'), findsOneWidget);
    });

    testWidgets(
        'filtro "Sin plan" sin resultados → "Todos tus alumnos ya tienen plan"',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1'), _link('a2')],
        profiles: [_prof('a1', 'Ana García'), _prof('a2', 'Beto López')],
        plans: {'a1': _plan('a1'), 'a2': _plan('a2')},
      );

      await tester.tap(find.byKey(const Key('filter_chip_Sin plan')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('nutricion_empty_sinPlan')),
        findsOneWidget,
      );
      expect(find.text('Todos tus alumnos ya tienen plan.'), findsOneWidget);
    });
  });

  group('NutricionScreen — motion (WU-05)', () {
    testWidgets(
        'el childKey del StateSwitcher incluye el filtro activo (cross-fade)',
        (tester) async {
      await _pump(
        tester,
        links: [_link('a1')],
        profiles: [_prof('a1', 'Ana García')],
        plans: {'a1': _plan('a1')},
      );

      expect(
        find.byKey(const ValueKey('nutricion_data_todos')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('filter_chip_Con plan')));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('nutricion_data_todos')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('nutricion_data_conPlan')),
        findsOneWidget,
      );
    });

    testWidgets('dark y light: smoke sin crash en data/empty/error',
        (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await _pump(
          tester,
          theme: theme,
          links: [_link('a1')],
          profiles: [_prof('a1', 'Ana García')],
          plans: {'a1': _plan('a1')},
        );
        expect(find.text('Ana García'), findsOneWidget);
        // Reset del árbol entre escenarios: Riverpod no permite cambiar la
        // cantidad de overrides de un mismo `ProviderScope` entre rebuilds.
        await tester.pumpWidget(const SizedBox.shrink());

        await _pump(tester, theme: theme, links: const []);
        expect(
          find.byKey(const Key('nutricion_empty_sin_alumnos')),
          findsOneWidget,
        );
        await tester.pumpWidget(const SizedBox.shrink());

        await _pump(
          tester,
          theme: theme,
          linksStream: Stream<List<TrainerLink>>.error(Exception('boom')),
        );
        expect(find.byKey(const Key('nutricion_error')), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
      }
    });
  });
}
