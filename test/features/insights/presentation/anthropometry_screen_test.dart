import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/presentation/anthropometry_screen.dart';
import 'package:treino/features/measurements/application/measurement_providers.dart';
import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/measurements/presentation/widgets/measurement_progress_chart.dart';
import 'package:treino/l10n/app_l10n.dart';

Measurement _m(DateTime at, double kg) => Measurement(
      id: 'm-${at.millisecondsSinceEpoch}',
      athleteId: 'u1',
      recordedBy: 'trainerA',
      recordedAt: at,
      weightKg: kg,
    );

Widget _wrap({required List<Override> overrides}) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: AnthropometryScreen(uid: 'u1')),
      ),
    );

void main() {
  testWidgets('2+ mediciones → renderiza el chart de progreso', (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      ownMeasurementsProvider('u1').overrideWith(
        (ref) => Stream.value([
          _m(DateTime.utc(2026, 1, 1), 80),
          _m(DateTime.utc(2026, 2, 1), 78),
        ]),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.text('ANTROPOMETRÍA'), findsOneWidget);
    expect(find.byType(MeasurementProgressChart), findsOneWidget);
  });

  testWidgets(
      'CERO mediciones → empty state que dice QUIÉN las carga, no un chart '
      'vacío', (tester) async {
    // Un atleta sin entrenador nunca va a tener mediciones (hoy sólo un rol
    // `trainer` puede crearlas — firestore.rules AD-1). El empty state tiene
    // que explicar por qué, o la pantalla parece rota.
    await tester.pumpWidget(_wrap(overrides: [
      ownMeasurementsProvider('u1').overrideWith((ref) => Stream.value([])),
    ]));
    await tester.pumpAndSettle();

    expect(find.byType(MeasurementProgressChart), findsNothing);
    expect(
      find.text(
          'Todavía no tenés mediciones cargadas. Las registra tu entrenador.'),
      findsOneWidget,
    );
  });

  testWidgets('UNA sola medición → mensaje distinto al de cero',
      (tester) async {
    // MeasurementProgressChart exige >= 2 puntos (su contrato). "Todavía no
    // tenés nada" y "te falta una más" son situaciones distintas para el
    // usuario y no pueden compartir mensaje.
    await tester.pumpWidget(_wrap(overrides: [
      ownMeasurementsProvider('u1').overrideWith(
        (ref) => Stream.value([_m(DateTime.utc(2026, 1, 1), 80)]),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.byType(MeasurementProgressChart), findsNothing);
    expect(
      find.text(
          'Con una sola medición no hay progreso que mostrar. Falta al menos una más.'),
      findsOneWidget,
    );
    expect(
      find.text(
          'Todavía no tenés mediciones cargadas. Las registra tu entrenador.'),
      findsNothing,
    );
  });

  testWidgets('fallo de carga → error VISIBLE con retry, nunca card vacía',
      (tester) async {
    await tester.pumpWidget(_wrap(overrides: [
      ownMeasurementsProvider('u1').overrideWith(
        (ref) => Stream.error(Exception('boom')),
      ),
    ]));
    await tester.pumpAndSettle();

    expect(find.byType(MeasurementProgressChart), findsNothing);
    expect(find.text('Reintentar'), findsOneWidget);
  });
}
