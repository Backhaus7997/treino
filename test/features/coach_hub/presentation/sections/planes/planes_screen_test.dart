// WU-03 (Fase 10) — PlanesScreen: shell + KPI strip + banner de descope.
//
// TDD: RED → GREEN. Cubre el contrato de la screen real que reemplaza al
// placeholder ProximamenteScreen en /planes (routes.dart).
//
// SCENARIO-PS-01: estado data — aparecen los 3 KpiCard (labels reales) y el
//   banner de descope honesto (ADR-F10-01), con el título de sección.
// SCENARIO-PS-02: estado loading — cada KpiCard muestra su skeleton (nunca
//   un spinner genérico ni "…" ad-hoc).
// SCENARIO-PS-03: estado vacío — resumen sin billings no rompe el render;
//   los KPI degradan a valores en cero, sin excepciones.
// SCENARIO-PS-04: contrato ADR-F10-02 — el sublabel del KPI "Precio
//   promedio" es el caveat de mezcla de cadencias (no un conteo de
//   alumnos), y el sublabel "N tarifas" del KPI "Alumnos con tarifa"
//   singulariza correctamente.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/planes/planes_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/planes/tarifas_provider.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart'
    show KpiCard;
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/l10n/app_l10n.dart';

// ─── Factories ────────────────────────────────────────────────────────────────

AthleteBilling _billing({
  required String athleteId,
  required int amountArs,
  required BillingCadence cadence,
}) =>
    AthleteBilling(
      trainerId: 'trainer-1',
      athleteId: athleteId,
      amountArs: amountArs,
      cadence: cadence,
      updatedAt: DateTime.utc(2026, 1, 5),
    );

final _billings = [
  _billing(athleteId: 'a1', amountArs: 15000, cadence: BillingCadence.mensual),
  _billing(athleteId: 'a2', amountArs: 15000, cadence: BillingCadence.mensual),
  _billing(athleteId: 'a3', amountArs: 15000, cadence: BillingCadence.mensual),
  _billing(athleteId: 'a4', amountArs: 8000, cadence: BillingCadence.semanal),
  _billing(athleteId: 'a5', amountArs: 8000, cadence: BillingCadence.semanal),
  _billing(
      athleteId: 'a6', amountArs: 30000, cadence: BillingCadence.porSesion),
];

// ─── Test helpers ─────────────────────────────────────────────────────────────

Future<void> _pump(
  WidgetTester tester, {
  required List<Override> overrides,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: PlanesScreen()),
      ),
    ),
  );
}

void main() {
  group('SCENARIO-PS-01 — PlanesScreen: data', () {
    testWidgets('muestra header, banner de descope y los 3 KPI reales',
        (tester) async {
      await _pump(tester, overrides: [
        trainerBillingsProvider.overrideWith((ref) => Stream.value(_billings)),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('PLANES COMERCIALES'), findsOneWidget);
      expect(find.byKey(const Key('planes_descope_banner')), findsOneWidget);
      expect(
        find.textContaining('planes comerciales vendibles llega más '
            'adelante'),
        findsOneWidget,
      );

      expect(find.text('Precio promedio'), findsOneWidget);
      expect(find.text('Alumnos con tarifa'), findsOneWidget);
      expect(find.text('Tarifas distintas'), findsOneWidget);

      // 6 billings, ningún KpiCard en loading.
      expect(find.byKey(const Key('kpi_card_skeleton')), findsNothing);
      expect(find.text('6'), findsOneWidget); // Alumnos con tarifa
      expect(find.text('3'), findsOneWidget); // Tarifas distintas
    });
  });

  group('SCENARIO-PS-02 — PlanesScreen: loading', () {
    testWidgets('mientras trainerBillingsProvider no resolvió → skeletons',
        (tester) async {
      final controller = StreamController<List<AthleteBilling>>();
      addTearDown(controller.close);

      await _pump(tester, overrides: [
        trainerBillingsProvider.overrideWith((ref) => controller.stream),
      ]);

      // Sin pumpAndSettle (el stream nunca emite) — un pump alcanza para que
      // Riverpod entregue AsyncLoading.
      await tester.pump();

      expect(find.byKey(const Key('kpi_card_skeleton')), findsNWidgets(3));
      // El banner de descope no depende del provider — visible igual.
      expect(find.byKey(const Key('planes_descope_banner')), findsOneWidget);
    });
  });

  group('SCENARIO-PS-03 — PlanesScreen: vacío', () {
    testWidgets('sin billings → KPIs en cero, sin romper', (tester) async {
      await _pump(tester, overrides: [
        trainerBillingsProvider.overrideWith((ref) => Stream.value(const [])),
      ]);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('kpi_card_skeleton')), findsNothing);
      expect(find.text(r'$0'), findsOneWidget); // Precio promedio
      // Alumnos con tarifa (0) y Tarifas distintas (0) comparten el mismo
      // texto de value — deben aparecer dos KpiCard con "0". Scoped a KpiCard
      // (WU-04 agregó badges "0" por cadencia en los TreinoFilterChips del
      // grid, que también matchean texto "0" — no son parte de este
      // contrato).
      expect(
        find.descendant(
          of: find.byType(KpiCard),
          matching: find.text('0'),
        ),
        findsNWidgets(2),
      );
    });
  });

  group(
      'SCENARIO-PS-04 — PlanesScreen: caveat de promedio (ADR-F10-02) + '
      'pluralización', () {
    testWidgets(
        'KPI "Precio promedio": sublabel es el caveat de cadencias, no un '
        'conteo de alumnos', (tester) async {
      await _pump(tester, overrides: [
        trainerBillingsProvider.overrideWith((ref) => Stream.value(_billings)),
      ]);
      await tester.pumpAndSettle();

      final kpiPromedio = tester.widget<KpiCard>(
        find.byWidgetPredicate(
          (w) => w is KpiCard && w.label == 'Precio promedio',
        ),
      );

      expect(kpiPromedio.sublabel, isNotNull);
      expect(kpiPromedio.sublabel, contains('cadencia'));
      expect(kpiPromedio.sublabel, isNot(contains('alumnos con tarifa')));
    });

    testWidgets(
        'KPI "Alumnos con tarifa": sublabel "N tarifas" singulariza con 1 '
        'grupo', (tester) async {
      await _pump(tester, overrides: [
        trainerBillingsProvider.overrideWith(
          (ref) => Stream.value([
            _billing(
              athleteId: 'a1',
              amountArs: 15000,
              cadence: BillingCadence.mensual,
            ),
          ]),
        ),
      ]);
      await tester.pumpAndSettle();

      expect(find.text('1 tarifa'), findsOneWidget);
      expect(find.text('1 tarifas'), findsNothing);
    });
  });
}
