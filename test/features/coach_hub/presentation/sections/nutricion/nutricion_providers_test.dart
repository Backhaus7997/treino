// WU-02 (Fase 6) — Providers y filtro del overview de Nutrición
// (`nutricion_providers.dart`, agregado cross-alumno x plan).
//
// RED → GREEN: cubre `matchesNutricionFiltro` (predicado puro),
// `nutricionEntriesProvider` (combina `trainerLinksStreamProvider` activos
// con `nutritionPlanProvider` por alumno) y el helper de conteos por chip.
//
// Sin UI — solo lógica/providers (ver instrucciones WU-02).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/nutrition_plan_providers.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/nutrition_plan.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/nutricion/nutricion_providers.dart';
import 'package:treino/features/workout/application/session_providers.dart'
    show currentUidProvider;

const _trainerId = 'trainer-1';

TrainerLink _link({
  required String id,
  required String athleteId,
  required TrainerLinkStatus status,
}) =>
    TrainerLink(
      id: id,
      trainerId: _trainerId,
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 1, 10),
    );

NutritionPlan _plan(String athleteId) => NutritionPlan(
      id: '${_trainerId}_$athleteId',
      trainerId: _trainerId,
      athleteId: athleteId,
      title: 'Plan de $athleteId',
      updatedAt: DateTime.utc(2026, 1, 5),
      meals: const [],
    );

NutricionEntry _entry({
  required TrainerLink link,
  NutritionPlan? plan,
  bool planLoading = false,
}) =>
    (link: link, plan: plan, planLoading: planLoading);

void main() {
  group('SCENARIO-NP-01 — matchesNutricionFiltro', () {
    final withPlan = _entry(
      link: _link(id: 'l1', athleteId: 'a1', status: TrainerLinkStatus.active),
      plan: _plan('a1'),
    );
    final withoutPlan = _entry(
      link: _link(id: 'l2', athleteId: 'a2', status: TrainerLinkStatus.active),
    );
    final loading = _entry(
      link: _link(id: 'l3', athleteId: 'a3', status: TrainerLinkStatus.active),
      planLoading: true,
    );

    test('todos → siempre true, sin importar plan/loading', () {
      expect(matchesNutricionFiltro(withPlan, NutricionFiltro.todos), isTrue);
      expect(
        matchesNutricionFiltro(withoutPlan, NutricionFiltro.todos),
        isTrue,
      );
      expect(matchesNutricionFiltro(loading, NutricionFiltro.todos), isTrue);
    });

    test('conPlan → true solo si plan != null', () {
      expect(
        matchesNutricionFiltro(withPlan, NutricionFiltro.conPlan),
        isTrue,
      );
      expect(
        matchesNutricionFiltro(withoutPlan, NutricionFiltro.conPlan),
        isFalse,
      );
    });

    test('sinPlan → true solo si plan == null', () {
      expect(
        matchesNutricionFiltro(withPlan, NutricionFiltro.sinPlan),
        isFalse,
      );
      expect(
        matchesNutricionFiltro(withoutPlan, NutricionFiltro.sinPlan),
        isTrue,
      );
    });

    test(
        'planLoading → excluido de conPlan y sinPlan (plan == null mientras carga)',
        () {
      expect(
        matchesNutricionFiltro(loading, NutricionFiltro.conPlan),
        isFalse,
      );
      expect(
        matchesNutricionFiltro(loading, NutricionFiltro.sinPlan),
        isFalse,
      );
    });
  });

  group('SCENARIO-NP-02 — nutricionFiltroProvider default', () {
    test('valor inicial es NutricionFiltro.todos', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(nutricionFiltroProvider),
        NutricionFiltro.todos,
      );
    });
  });

  group('SCENARIO-NP-03 — nutricionEntriesProvider', () {
    test('combina links activos (excluye paused/terminated) x plan por alumno',
        () async {
      final links = [
        _link(id: 'l1', athleteId: 'a1', status: TrainerLinkStatus.active),
        _link(id: 'l2', athleteId: 'a2', status: TrainerLinkStatus.active),
        _link(id: 'l3', athleteId: 'a3', status: TrainerLinkStatus.active),
        _link(id: 'l4', athleteId: 'a4', status: TrainerLinkStatus.paused),
        _link(
          id: 'l5',
          athleteId: 'a5',
          status: TrainerLinkStatus.terminated,
        ),
      ];
      final plans = <String, NutritionPlan?>{
        'a1': _plan('a1'),
        'a2': null,
        'a3': _plan('a3'),
      };

      final container = ProviderContainer(
        overrides: [
          currentUidProvider.overrideWithValue(_trainerId),
          trainerLinksStreamProvider.overrideWith(
            (ref) => Stream.value(links),
          ),
          for (final entry in plans.entries)
            nutritionPlanProvider(
              (trainerId: _trainerId, athleteId: entry.key),
            ).overrideWith((ref) => Stream.value(entry.value)),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        nutricionEntriesProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final result = container.read(nutricionEntriesProvider);
      expect(result.hasValue, isTrue);
      final entries = result.value!;

      // Solo los 3 links `active` entran — paused/terminated quedan fuera.
      expect(entries.length, 3);
      expect(entries.map((e) => e.link.athleteId), ['a1', 'a2', 'a3']);
      expect(entries[0].plan?.id, 'trainer-1_a1');
      expect(entries[1].plan, isNull);
      expect(entries[2].plan?.id, 'trainer-1_a3');
    });

    test('loading de trainerLinksStreamProvider → AsyncValue.loading', () {
      final controller = StreamController<List<TrainerLink>>();
      addTearDown(controller.close);
      final container = ProviderContainer(
        overrides: [
          currentUidProvider.overrideWithValue(_trainerId),
          trainerLinksStreamProvider.overrideWith(
            (ref) => controller.stream,
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(nutricionEntriesProvider).isLoading, isTrue);
    });
  });

  group('SCENARIO-NP-04 — counts por chip', () {
    test('cuenta todos/conPlan/sinPlan sobre una lista de entries', () {
      final entries = [
        _entry(
          link: _link(
            id: 'l1',
            athleteId: 'a1',
            status: TrainerLinkStatus.active,
          ),
          plan: _plan('a1'),
        ),
        _entry(
          link: _link(
            id: 'l2',
            athleteId: 'a2',
            status: TrainerLinkStatus.active,
          ),
        ),
        _entry(
          link: _link(
            id: 'l3',
            athleteId: 'a3',
            status: TrainerLinkStatus.active,
          ),
        ),
      ];

      final counts = nutricionFiltroCounts(entries);

      expect(counts[NutricionFiltro.todos], 3);
      expect(counts[NutricionFiltro.conPlan], 1);
      expect(counts[NutricionFiltro.sinPlan], 2);
    });

    test('lista vacía → todos los counts en 0', () {
      final counts = nutricionFiltroCounts(const []);

      expect(counts[NutricionFiltro.todos], 0);
      expect(counts[NutricionFiltro.conPlan], 0);
      expect(counts[NutricionFiltro.sinPlan], 0);
    });
  });
}
