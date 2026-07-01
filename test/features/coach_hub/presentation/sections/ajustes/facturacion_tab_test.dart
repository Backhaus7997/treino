import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/facturacion_tab.dart';

Widget _harness(List<TrainerLink> links) => ProviderScope(
      overrides: [
        trainerLinksStreamProvider
            .overrideWith((ref) => Stream<List<TrainerLink>>.value(links)),
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
  testWidgets('empty state honesto: sin datos falsos y avisa Fase 7',
      (tester) async {
    await tester.pumpWidget(_harness(const []));
    await tester.pump();

    // Encabezado + empty state.
    expect(find.text('FACTURACIÓN TREINO'), findsOneWidget);
    expect(find.text('Facturación próximamente'), findsOneWidget);
    expect(find.textContaining('Fase 7'), findsOneWidget);

    // Uso REAL: 0 alumnos activos sin vínculos.
    expect(find.text('0 alumnos activos'), findsOneWidget);

    // Ya NO quedan datos de ejemplo del mockup anterior.
    expect(find.text('TREINO Coach Solo'), findsNothing);
    expect(find.text('CAMBIAR PLAN'), findsNothing);
    expect(find.text('HISTORIAL DE FACTURACIÓN'), findsNothing);
    expect(find.textContaining('12.000'), findsNothing);
  });

  testWidgets('muestra el uso REAL de alumnos activos (distintos)',
      (tester) async {
    await tester.pumpWidget(_harness([
      _activeLink('a1'),
      _activeLink('a2'),
      _activeLink('a1'), // duplicado → cuenta 1 sola vez
    ]));
    await tester.pump();

    expect(find.text('2 alumnos activos'), findsOneWidget);
  });

  testWidgets('singular: 1 alumno activo', (tester) async {
    await tester.pumpWidget(_harness([_activeLink('a1')]));
    await tester.pump();

    expect(find.text('1 alumno activo'), findsOneWidget);
  });
}
