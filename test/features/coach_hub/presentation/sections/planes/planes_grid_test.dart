// WU-04 (Fase 10) — Grid de tarifas + filtro por cadencia + estados.
//
// Cubre el contrato de la zona principal de PlanesScreen: filtro
// (TreinoFilterChips) + grid responsive de TarifaCard, con los 4 estados
// completos (data/filtrado/vacío/error) — loading ya cubierto por
// planes_screen_test.dart (SCENARIO-PS-02, KPI skeletons).
//
// SCENARIO-PG-01: data con >=2 grupos → una TarifaCard por grupo, con precio
//   y alumnosCount honestos; el chip "Más usada" solo en el grupo modal.
// SCENARIO-PG-02: filtrar por una cadencia reduce las cards visibles a solo
//   ese grupo.
// SCENARIO-PG-03: sin billings → TreinoEmptyState honesto (sin inventar
//   catálogo).
// SCENARIO-PG-04: filtro sin resultados (pero con datos en otras cadencias)
//   → TreinoEmptyState con mensaje específico del filtro.
// SCENARIO-PG-05: error del stream → mensaje + botón "Reintentar" que
//   invalida `trainerBillingsProvider`.
// SCENARIO-PG-06: loading → skeleton shimmer del grid (no rompe con el
//   shimmer del KPI strip).
// SCENARIO-PG-07: smoke dark+light (mintMagenta/mintMagentaLight) +
//   reduceMotion, sin crash.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/planes/planes_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/planes/tarifas_provider.dart';
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

/// 3 grupos: mensual $15.000 x3 (modal), semanal $8.000 x2, porSesion
/// $30.000 x1.
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
  Size surfaceSize = const Size(1400, 900),
  ThemeData? theme,
  bool reduceMotion = false,
}) async {
  tester.view.physicalSize = surfaceSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: theme ?? AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: reduceMotion),
          child: const Scaffold(body: PlanesScreen()),
        ),
      ),
    ),
  );
}

void main() {
  group('SCENARIO-PG-01 — Grid: data con múltiples grupos', () {
    testWidgets('una card por grupo, precio + alumnos honestos + Más usada',
        (tester) async {
      await _pump(tester, overrides: [
        trainerBillingsProvider.overrideWith((ref) => Stream.value(_billings)),
      ]);
      await tester.pumpAndSettle();

      expect(find.text(r'$15.000'), findsOneWidget);
      expect(find.text(r'$8.000'), findsOneWidget);
      expect(find.text(r'$30.000'), findsOneWidget);
      expect(find.text('3 alumnos'), findsOneWidget);
      expect(find.text('2 alumnos'), findsOneWidget);
      expect(find.text('1 alumno'), findsOneWidget);

      // Solo el grupo mensual (3 alumnos, la moda) tiene el chip.
      expect(find.text('Más usada'), findsOneWidget);
    });
  });

  group('SCENARIO-PG-02 — Grid: filtro por cadencia', () {
    testWidgets('filtrar por Semanal deja solo esa card', (tester) async {
      await _pump(tester, overrides: [
        trainerBillingsProvider.overrideWith((ref) => Stream.value(_billings)),
      ]);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('filter_chip_Semanal')));
      await tester.pumpAndSettle();

      expect(find.text(r'$8.000'), findsOneWidget);
      expect(find.text(r'$15.000'), findsNothing);
      expect(find.text(r'$30.000'), findsNothing);
    });
  });

  group('SCENARIO-PG-03 — Grid: vacío total', () {
    testWidgets('sin billings → TreinoEmptyState honesto', (tester) async {
      await _pump(tester, overrides: [
        trainerBillingsProvider.overrideWith((ref) => Stream.value(const [])),
      ]);
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Todavía no configuraste tarifas'),
        findsOneWidget,
      );
    });
  });

  group('SCENARIO-PG-04 — Grid: filtro sin resultados', () {
    testWidgets('filtro Suelto sin datos → empty state específico del filtro',
        (tester) async {
      await _pump(tester, overrides: [
        trainerBillingsProvider.overrideWith((ref) => Stream.value(_billings)),
      ]);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('filter_chip_Suelto')));
      await tester.pumpAndSettle();

      expect(find.text(r'$15.000'), findsNothing);
      expect(find.text(r'$8.000'), findsNothing);
      expect(find.text(r'$30.000'), findsNothing);
      expect(find.textContaining('No hay tarifas'), findsOneWidget);
    });
  });

  group('SCENARIO-PG-05 — Grid: error', () {
    testWidgets('stream con error → mensaje + Reintentar', (tester) async {
      await _pump(tester, overrides: [
        trainerBillingsProvider
            .overrideWith((ref) => Stream.error(Exception('boom'))),
      ]);
      await tester.pumpAndSettle();

      expect(find.textContaining('Error'), findsWidgets);
      expect(find.text('Reintentar'), findsOneWidget);

      // Tocar Reintentar no debe crashear (invalida el provider real).
      await tester.tap(find.text('Reintentar'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });
  });

  group('SCENARIO-PG-06 — Grid: loading', () {
    testWidgets('sin resolver el stream → skeleton shimmer del grid',
        (tester) async {
      final controller = StreamController<List<AthleteBilling>>();
      addTearDown(controller.close);

      await _pump(tester, overrides: [
        trainerBillingsProvider.overrideWith((ref) => controller.stream),
      ]);
      await tester.pump();

      expect(find.byKey(const Key('planes_tarifas_skeleton')), findsOneWidget);
    });
  });

  group('SCENARIO-PG-07 — Grid: smoke dark+light + reduceMotion', () {
    testWidgets('dark, light y reduceMotion sin crash', (tester) async {
      for (final theme in [AppTheme.dark(), AppTheme.light()]) {
        await _pump(
          tester,
          theme: theme,
          overrides: [
            trainerBillingsProvider
                .overrideWith((ref) => Stream.value(_billings)),
          ],
        );
        await tester.pumpAndSettle();
        expect(find.text(r'$15.000'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      await _pump(
        tester,
        reduceMotion: true,
        overrides: [
          trainerBillingsProvider
              .overrideWith((ref) => Stream.value(_billings)),
        ],
      );
      await tester.pumpAndSettle();
      expect(find.text(r'$15.000'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
