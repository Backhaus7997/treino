// FacturacionTab — Fase 12 WU-06.
//
// Cubre: empty state honesto vía TreinoEmptyState (sin plan/historial/PDFs
// falsos, Fase 7 pendiente de backend), el único dato real (alumnos activos)
// mostrado dentro de un KpiCard, y loading real (shimmer) mientras
// trainerLinksStreamProvider está pendiente — reemplaza el `.valueOrNull`
// seco anterior.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/facturacion_tab.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';

Widget _harness(Stream<List<TrainerLink>> stream) => ProviderScope(
      overrides: [
        trainerLinksStreamProvider.overrideWith((ref) => stream),
      ],
      child: const MaterialApp(home: Scaffold(body: FacturacionTab())),
    );

TrainerLink _activeLink(String athleteId) => TrainerLink(
      id: 'link_$athleteId',
      trainerId: 'pf1',
      athleteId: athleteId,
      status: TrainerLinkStatus.active,
      requestedAt: DateTime(2025, 1, 1),
    );

void main() {
  group('FacturacionTab — empty state honesto y KpiCard (Fase 12 WU-06)', () {
    testWidgets(
        'empty state honesto: TreinoEmptyState, sin datos falsos, avisa Fase 7',
        (tester) async {
      await tester.pumpWidget(_harness(Stream.value(const [])));
      await tester.pumpAndSettle();

      // Encabezado.
      expect(find.text('FACTURACIÓN TREINO'), findsOneWidget);

      // Empty state honesto vía el componente del kit, no armado a mano.
      expect(find.byType(TreinoEmptyState), findsOneWidget);
      expect(find.text('Facturación próximamente'), findsOneWidget);
      expect(find.textContaining('Fase 7'), findsOneWidget);

      // Ya NO quedan datos de ejemplo del mockup anterior.
      expect(find.text('TREINO Coach Solo'), findsNothing);
      expect(find.text('CAMBIAR PLAN'), findsNothing);
      expect(find.text('HISTORIAL DE FACTURACIÓN'), findsNothing);
      expect(find.textContaining('12.000'), findsNothing);
    });

    testWidgets(
        'uso real de alumnos activos (distintos) se muestra en un KpiCard',
        (tester) async {
      await tester.pumpWidget(_harness(Stream.value([
        _activeLink('a1'),
        _activeLink('a2'),
        _activeLink('a1'), // duplicado → cuenta 1 sola vez
      ])));
      await tester.pumpAndSettle();

      expect(find.byType(KpiCard), findsOneWidget);
      final kpiCard = tester.widget<KpiCard>(find.byType(KpiCard));
      expect(kpiCard.value, '2');
      expect(kpiCard.label, 'Alumnos activos');
      expect(kpiCard.loading, isFalse);
    });

    testWidgets('cuenta 1 alumno activo con un solo vínculo activo',
        (tester) async {
      await tester.pumpWidget(_harness(Stream.value([_activeLink('a1')])));
      await tester.pumpAndSettle();

      final kpiCard = tester.widget<KpiCard>(find.byType(KpiCard));
      expect(kpiCard.value, '1');
    });

    testWidgets(
        'loading: el KpiCard muestra shimmer (loading:true) mientras el stream está pendiente',
        (tester) async {
      final controller = StreamController<List<TrainerLink>>();
      addTearDown(controller.close);

      await tester.pumpWidget(_harness(controller.stream));
      await tester.pump();

      final kpiCard = tester.widget<KpiCard>(find.byType(KpiCard));
      expect(kpiCard.loading, isTrue);
      expect(find.byKey(const Key('kpi_card_skeleton')), findsOneWidget);
    });
  });
}
