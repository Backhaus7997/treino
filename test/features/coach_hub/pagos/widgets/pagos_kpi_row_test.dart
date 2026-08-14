import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_kpi_row.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart'
    show KpiCard;
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart'
    show CobroPendiente, pagosPorCobrarProvider;
import 'package:treino/features/payments/application/payment_providers.dart'
    show trainerPaymentsProvider;
import 'package:treino/features/payments/domain/athlete_billing.dart';
import 'package:treino/features/payments/domain/payment.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

final _now = DateTime.now().toUtc();
final _firstOfMonth = DateTime.utc(_now.year, _now.month, 1);
final _lastMonth = DateTime.utc(_now.year, _now.month - 1, 15);

Payment _payment({
  required String id,
  required PaymentStatus status,
  required DateTime createdAt,
  required int amountArs,
}) =>
    Payment(
      id: id,
      trainerId: 'trainer-1',
      athleteId: 'athlete-1',
      amountArs: amountArs,
      concept: 'Test $id',
      status: status,
      createdAt: createdAt,
      paidAt: status == PaymentStatus.paid ? createdAt : null,
    );

Widget _wrap(Widget child, {List<Override> overrides = const []}) =>
    ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        home: Scaffold(body: child),
      ),
    );

List<Override> _overrides({
  List<Payment> payments = const [],
  List<CobroPendiente> cobros = const [],
}) =>
    [
      trainerPaymentsProvider.overrideWith(
        (ref) => Stream.value(payments),
      ),
      pagosPorCobrarProvider.overrideWith(
        (ref) => AsyncValue.data(cobros),
      ),
    ];

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('PagosKpiRow (REQ-PAGW-KPI-001)', () {
    // SCENARIO 1: mixed payments → correct tile values
    testWidgets(
        'SCENARIO 1 — paid this month \$10.000, por vencer \$8.000, '
        'vencido \$3.000', (tester) async {
      final paidThisMonth = _payment(
        id: 'pm1',
        status: PaymentStatus.paid,
        createdAt: _firstOfMonth.add(const Duration(days: 1)),
        amountArs: 10000,
      );
      final paidLastMonth = _payment(
        id: 'pm2',
        status: PaymentStatus.paid,
        createdAt: _lastMonth,
        amountArs: 5000,
      );
      final vencido = _payment(
        id: 'v1',
        status: PaymentStatus.pending,
        createdAt: _firstOfMonth.subtract(const Duration(days: 1)),
        amountArs: 3000,
      );

      final cobros = [
        const CobroPendiente(
          athleteId: 'athlete-1',
          amountArs: 8000,
          cadence: BillingCadence.suelto,
          concept: 'Plan',
        ),
      ];

      await tester.pumpWidget(
        _wrap(
          const PagosKpiRow(),
          overrides: _overrides(
            payments: [paidThisMonth, paidLastMonth, vencido],
            cobros: cobros,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text(r'$10.000'), findsOneWidget,
          reason: 'Ingreso del mes debe ser \$10.000 (solo pagado este mes)');
      expect(find.text(r'$8.000'), findsOneWidget,
          reason:
              'Pendiente cobrar debe ser \$8.000 (de pagosPorCobrarProvider)');
      expect(find.text(r'$3.000'), findsOneWidget,
          reason: 'Vencido debe ser \$3.000');
    });

    // SCENARIO 2: empty provider → all tiles show \$0
    testWidgets('SCENARIO 2 — empty provider → all tiles show \$0',
        (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PagosKpiRow(),
          overrides: _overrides(),
        ),
      );
      await tester.pumpAndSettle();

      // Find all occurrences of '$0'
      expect(find.text(r'$0'), findsNWidgets(3),
          reason: 'All three KPI tiles must show \$0 when provider is empty');
    });

    // SCENARIO: exactly 3 KpiCard widgets rendered (kit v2), no ad-hoc tile
    testWidgets('SCENARIO — exactly 3 KpiCard widgets rendered', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          const PagosKpiRow(),
          overrides: _overrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(KpiCard), findsNWidgets(3));
    });

    // Tile labels present
    testWidgets('tile labels are present', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PagosKpiRow(),
          overrides: _overrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ingreso del mes'), findsOneWidget); // i18n
      expect(find.text('Pendiente cobrar'), findsOneWidget); // i18n
      expect(find.text('Vencido'), findsOneWidget); // i18n
    });

    // ADR-F9-01: honestidad — sin KPI proyectado ni deltas inventados
    testWidgets('no Proyectado KPI is ever rendered', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const PagosKpiRow(),
          overrides: _overrides(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Proyectado'), findsNothing);
    });

    // Sublabels honestos derivados de conteos reales
    testWidgets('sublabels show honest counts derived from real data', (
      tester,
    ) async {
      final paidThisMonth = _payment(
        id: 'pm1',
        status: PaymentStatus.paid,
        createdAt: _firstOfMonth.add(const Duration(days: 1)),
        amountArs: 10000,
      );
      final vencido = _payment(
        id: 'v1',
        status: PaymentStatus.pending,
        createdAt: _firstOfMonth.subtract(const Duration(days: 1)),
        amountArs: 3000,
      );
      final cobros = [
        const CobroPendiente(
          athleteId: 'athlete-1',
          amountArs: 8000,
          cadence: BillingCadence.suelto,
          concept: 'Plan',
        ),
      ];

      await tester.pumpWidget(
        _wrap(
          const PagosKpiRow(),
          overrides: _overrides(
            payments: [paidThisMonth, vencido],
            cobros: cobros,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 cobrados'), findsOneWidget); // i18n
      expect(find.text('1 alumnos'), findsOneWidget); // i18n
      expect(find.text('1 vencidos'), findsOneWidget); // i18n
    });
  });
}
