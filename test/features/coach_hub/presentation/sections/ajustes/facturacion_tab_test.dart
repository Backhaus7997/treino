import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach_hub/presentation/sections/ajustes/tabs/facturacion_tab.dart';

Widget _harness(List<TrainerLink> links) => ProviderScope(
      overrides: [
        trainerLinksStreamProvider
            .overrideWith((ref) => Stream<List<TrainerLink>>.value(links)),
      ],
      child: const MaterialApp(home: Scaffold(body: FacturacionTab())),
    );

void main() {
  testWidgets('muestra plan + uso real + historial de ejemplo marcado',
      (tester) async {
    await tester.pumpWidget(_harness(const []));
    await tester.pump();

    // Encabezado + plan (de ejemplo).
    expect(find.text('FACTURACIÓN TREINO'), findsOneWidget);
    expect(find.text('PLAN ACTUAL'), findsOneWidget);
    expect(find.text('TREINO Coach Solo'), findsOneWidget);
    expect(find.text('CAMBIAR PLAN'), findsOneWidget);

    // Uso REAL (0 activos sin vínculos) sobre el límite de ejemplo.
    expect(find.text('0 / 40 alumnos'), findsOneWidget);

    // Historial de ejemplo.
    expect(find.text('HISTORIAL DE FACTURACIÓN'), findsOneWidget);
    expect(find.text('29 ene 2025'), findsOneWidget);

    // Marca honesta de datos de ejemplo.
    expect(find.textContaining('ejemplo'), findsOneWidget);
  });
}
