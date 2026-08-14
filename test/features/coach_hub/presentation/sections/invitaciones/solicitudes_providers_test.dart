// WU-02 (Fase 4) — Providers y filtros de la bandeja de Solicitudes.
//
// RED → GREEN: cubre `matchesSolicitudTab` (predicado puro, ADR-F4-02),
// `solicitudTabProvider` (default Pendientes) e
// `invitacionesPendingCountProvider` (badge del sidebar, ADR-F4-04).
//
// Sin UI — solo lógica/providers (ver plan-fase4.md §7, WU-02).
import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/invitaciones/solicitudes_providers.dart';

TrainerLink _link({required String id, required TrainerLinkStatus status}) =>
    TrainerLink(
      id: id,
      trainerId: 'trainer-1',
      athleteId: 'athlete-$id',
      status: status,
      requestedAt: DateTime.utc(2026, 1, 10),
    );

void main() {
  group('SCENARIO-SP-01 — matchesSolicitudTab (ADR-F4-02, tabla 4x3)', () {
    // status x tab -> match esperado.
    final cases = <(TrainerLinkStatus, SolicitudTab, bool)>[
      // Pendientes: solo status==pending.
      (TrainerLinkStatus.pending, SolicitudTab.pendientes, true),
      (TrainerLinkStatus.active, SolicitudTab.pendientes, false),
      (TrainerLinkStatus.paused, SolicitudTab.pendientes, false),
      (TrainerLinkStatus.terminated, SolicitudTab.pendientes, false),
      // Aceptadas: active || paused (nació de un accept).
      (TrainerLinkStatus.pending, SolicitudTab.aceptadas, false),
      (TrainerLinkStatus.active, SolicitudTab.aceptadas, true),
      (TrainerLinkStatus.paused, SolicitudTab.aceptadas, true),
      (TrainerLinkStatus.terminated, SolicitudTab.aceptadas, false),
      // Rechazadas: solo status==terminated.
      (TrainerLinkStatus.pending, SolicitudTab.rechazadas, false),
      (TrainerLinkStatus.active, SolicitudTab.rechazadas, false),
      (TrainerLinkStatus.paused, SolicitudTab.rechazadas, false),
      (TrainerLinkStatus.terminated, SolicitudTab.rechazadas, true),
    ];

    for (final (status, tab, expected) in cases) {
      test('$status × $tab → $expected', () {
        final link = _link(id: 'x', status: status);
        expect(matchesSolicitudTab(link, tab), expected);
      });
    }
  });

  group('SCENARIO-SP-02 — solicitudTabProvider default', () {
    test('valor inicial es SolicitudTab.pendientes', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(
        container.read(solicitudTabProvider),
        SolicitudTab.pendientes,
      );
    });
  });

  group('SCENARIO-SP-03 — invitacionesPendingCountProvider', () {
    test('loading → null (badge no renderiza)', () {
      final controller = StreamController<List<TrainerLink>>();
      addTearDown(controller.close);
      final container = ProviderContainer(
        overrides: [
          trainerLinksStreamProvider.overrideWith((ref) => controller.stream),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(invitacionesPendingCountProvider), isNull);
    });

    test('error → null (badge no renderiza)', () async {
      final container = ProviderContainer(
        overrides: [
          trainerLinksStreamProvider.overrideWith(
            (ref) => Stream<List<TrainerLink>>.error(Exception('boom')),
          ),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        trainerLinksStreamProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(invitacionesPendingCountProvider), isNull);
    });

    test('data → cuenta solo status==pending', () async {
      final links = [
        _link(id: 'a', status: TrainerLinkStatus.pending),
        _link(id: 'b', status: TrainerLinkStatus.pending),
        _link(id: 'c', status: TrainerLinkStatus.active),
        _link(id: 'd', status: TrainerLinkStatus.terminated),
      ];
      final container = ProviderContainer(
        overrides: [
          trainerLinksStreamProvider.overrideWith(
            (ref) => Stream.value(links),
          ),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        trainerLinksStreamProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(invitacionesPendingCountProvider), 2);
    });

    test('data vacía → 0 (no null)', () async {
      final container = ProviderContainer(
        overrides: [
          trainerLinksStreamProvider.overrideWith(
            (ref) => Stream.value(const <TrainerLink>[]),
          ),
        ],
      );
      addTearDown(container.dispose);

      final sub = container.listen(
        trainerLinksStreamProvider,
        (_, __) {},
        fireImmediately: true,
      );
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      expect(container.read(invitacionesPendingCountProvider), 0);
    });
  });
}
