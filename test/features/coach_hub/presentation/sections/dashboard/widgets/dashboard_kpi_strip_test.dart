// WU-03 — KPI strip: DashboardKpiStrip (migra de KpiTile de pagos al kit
// KpiCard, ADR-D2-05 extracción incremental + ADR-D2-04 orden mockup).
//
// RED → GREEN: cubre el contrato de extracción a
// dashboard/widgets/dashboard_kpi_strip.dart. Preserva la lógica de datos
// REAL (sin inventar deltas — ADR-D2-01): alumnos activos, ingreso del mes,
// adherencia promedio (aggregateAdherenceProvider, "--" si null), por cobrar
// (vencidos reales).
//
// SCENARIO-KPI-01: 4 tiles reales con label+value correctos, vía KpiCard.
// SCENARIO-KPI-02: loading → cada card muestra el skeleton del kit (nunca
//   el "…" viejo).
// SCENARIO-KPI-03: adherencia degrada a "--" sin loading skeleton (gauge
//   determinado, no spinner — mismo criterio que DashboardAdherenceRing).
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/application/aggregate_adherence_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/dashboard/widgets/dashboard_kpi_strip.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/coach_hub/presentation/widgets/kpi_card/kpi_card.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/l10n/app_l10n.dart';

// ─── Factories ────────────────────────────────────────────────────────────────

TrainerLink _link({
  required String id,
  required TrainerLinkStatus status,
  String athleteId = 'a1',
}) =>
    TrainerLink(
      id: id,
      trainerId: 'trainer-1',
      athleteId: athleteId,
      status: status,
      requestedAt: DateTime.utc(2026, 1, 10),
      acceptedAt:
          status == TrainerLinkStatus.active ? DateTime.utc(2026, 1, 11) : null,
    );

Payment _payment({
  required String id,
  required PaymentStatus status,
  required int amountArs,
  DateTime? paidAt,
  DateTime? createdAt,
}) =>
    Payment(
      id: id,
      trainerId: 'trainer-1',
      athleteId: 'a1',
      amountArs: amountArs,
      concept: 'Mensualidad',
      status: status,
      createdAt: createdAt ?? DateTime.utc(2025, 12, 1),
      paidAt: paidAt,
    );

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
        home: const Scaffold(body: DashboardKpiStrip()),
      ),
    ),
  );
  await tester.pump();
}

List<Override> _dataOverrides({
  List<TrainerLink> links = const [],
  List<Payment> payments = const [],
  double? adherenceValue,
}) =>
    [
      trainerLinksStreamProvider.overrideWith((ref) => Stream.value(links)),
      pagosBucketsProvider.overrideWith(
        (ref) => AsyncData(PagosBuckets(
          vencidos: payments
              .where((p) =>
                  p.status == PaymentStatus.pending &&
                  p.createdAt.toUtc().isBefore(DateTime.utc(
                      DateTime.now().toUtc().year,
                      DateTime.now().toUtc().month,
                      1)))
              .toList(),
          porVencer:
              payments.where((p) => p.status == PaymentStatus.pending).toList(),
          pagados:
              payments.where((p) => p.status == PaymentStatus.paid).toList(),
          todos: payments,
        )),
      ),
      aggregateAdherenceProvider.overrideWith((ref) async => adherenceValue),
    ];

// ─── Tests ────────────────────────────────────────────────────────────────────

void main() {
  group('SCENARIO-KPI-01 — 4 tiles reales vía KpiCard', () {
    testWidgets('alumnos activos cuenta solo links con status active',
        (tester) async {
      await _pump(
        tester,
        overrides: _dataOverrides(
          links: [
            _link(id: 'a1', status: TrainerLinkStatus.active),
            _link(id: 'a2', status: TrainerLinkStatus.active, athleteId: 'a2'),
            _link(id: 'a3', status: TrainerLinkStatus.active, athleteId: 'a3'),
            _link(id: 'p1', status: TrainerLinkStatus.paused, athleteId: 'p1'),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('3'), findsOneWidget);
      expect(find.text('Alumnos activos'), findsOneWidget);
    });

    testWidgets('ingreso del mes suma pagados del mes calendario actual',
        (tester) async {
      final now = DateTime.now().toUtc();
      await _pump(
        tester,
        overrides: _dataOverrides(
          payments: [
            _payment(
              id: 'pago1',
              status: PaymentStatus.paid,
              amountArs: 15000,
              paidAt: DateTime.utc(now.year, now.month, 2),
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ingreso del mes'), findsOneWidget);
      expect(find.text(r'$15.000'), findsOneWidget);
    });

    testWidgets(
        'por cobrar suma vencidos reales — label incluye el conteo real',
        (tester) async {
      await _pump(
        tester,
        overrides: _dataOverrides(
          payments: [
            _payment(
              id: 'venc1',
              status: PaymentStatus.pending,
              amountArs: 20000,
              createdAt: DateTime.utc(2025, 1, 1), // definitely vencido
            ),
          ],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(r'$20.000'), findsOneWidget);
      expect(find.textContaining('1 vencimientos'), findsOneWidget);
    });

    testWidgets('todos los tiles son KpiCard del kit (no KpiTile de pagos)',
        (tester) async {
      await _pump(tester, overrides: _dataOverrides());
      await tester.pumpAndSettle();

      expect(find.byType(KpiCard), findsNWidgets(4));
    });
  });

  group('SCENARIO-KPI-02 — loading usa el skeleton del kit', () {
    testWidgets('bucketsAsync loading → ingreso/por cobrar muestran skeleton',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trainerLinksStreamProvider.overrideWith(
              (ref) => Stream.value(const <TrainerLink>[]),
            ),
            pagosBucketsProvider.overrideWith(
              (ref) => const AsyncLoading<PagosBuckets>(),
            ),
            aggregateAdherenceProvider.overrideWith((ref) async => null),
          ],
          child: MaterialApp(
            theme: AppTheme.dark(),
            localizationsDelegates: AppL10n.localizationsDelegates,
            supportedLocales: AppL10n.supportedLocales,
            locale: const Locale('es', 'AR'),
            home: const Scaffold(body: DashboardKpiStrip()),
          ),
        ),
      );
      await tester.pump();

      // El viejo "…" no debe existir más — se reemplaza por skeleton.
      expect(find.text('…'), findsNothing);
      expect(find.byKey(const Key('kpi_card_skeleton')), findsWidgets);
    });
  });

  group('SCENARIO-KPI-03 — adherencia degrada a "--" sin skeleton', () {
    testWidgets('adherencia null → muestra "--" (gauge, no spinner)',
        (tester) async {
      await _pump(tester, overrides: _dataOverrides(adherenceValue: null));
      await tester.pumpAndSettle();

      expect(find.text('Adherencia promedio'), findsOneWidget);
      expect(find.text('--'), findsOneWidget);
    });

    testWidgets('adherencia con dato real → muestra el porcentaje',
        (tester) async {
      await _pump(tester, overrides: _dataOverrides(adherenceValue: 74.0));
      await tester.pumpAndSettle();

      expect(find.text('74%'), findsOneWidget);
    });
  });
}
