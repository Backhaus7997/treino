// KPI strip del Dashboard ("Hoy") — DashboardKpiStrip.
//
// Extraído de `coach_hub_dashboard_screen.dart` (ADR-D2-05, extracción
// incremental) y migrado de `KpiTile` (importado de pagos) al kit
// `KpiCard` (ADR-D2-02: reuso del kit, elimina el acople dashboard->pagos).
// Sigue el contrato de sección: sin Scaffold/SafeArea, AppPalette/AppL10n
// (ADR-CHW-005).
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach/application/trainer_link_providers.dart';
import 'package:treino/features/coach/domain/trainer_link_status.dart';
import 'package:treino/features/coach_hub/application/aggregate_adherence_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart';
import 'package:treino/features/coach_hub/presentation/sections/pagos/widgets/payment_format.dart'
    show fmtArs;
import 'package:treino/features/coach_hub/presentation/widgets/kpi_card/kpi_card.dart';
import 'package:treino/l10n/app_l10n.dart';

/// 4-tile KPI strip: Alumnos activos / Ingreso del mes / Adherencia
/// promedio / Por cobrar. REQ-HOY-05.
///
/// Cada tile es un [KpiCard] del kit v2 (ADR-D2-02). Sin deltas — ninguna de
/// las 4 métricas tiene una fuente de dato histórico real para calcular una
/// variación honesta (ADR-D2-01, no se inventan "+3"/"+18%").
///
/// - **Alumnos activos**: cuenta de [TrainerLink] con status active.
/// - **Ingreso del mes**: suma de pagos `paid` cuyo `(paidAt ?? createdAt)`
///   cae en el mes calendario actual (UTC).
/// - **Adherencia promedio**: [aggregateAdherenceProvider] — degrada a "--"
///   cuando es null (gauge determinado, no spinner — mismo criterio que
///   [DashboardAdherenceRing] en `dashboard_hero.dart`, ADR-D2-07). No usa
///   skeleton de loading: el placeholder "--" ya comunica "sin dato".
/// - **Por cobrar**: suma de `pagosBucketsProvider.vencidos`. El label ya
///   incluye el conteo real de vencimientos (l10n congelado, ADR-D2-03 — no
///   hay key separada para un sublabel "{n} vencidos" aislado sin hacer
///   cirugía de string sobre el mensaje compuesto del alert banner, así que
///   se mantiene el label combinado existente en vez de forzar el kit
///   `sublabel`).
class DashboardKpiStrip extends ConsumerWidget {
  const DashboardKpiStrip({super.key, this.wide = true});

  /// `true` (default) = tira horizontal scrolleable (desktop, sobra ancho).
  /// `false` = [Wrap] sin scroll — evita el scroll horizontal en narrow
  /// (WU-06 fase-2), donde las 4 cards no entran en una fila.
  final bool wide;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppL10n.of(context);
    final linksAsync = ref.watch(trainerLinksStreamProvider);
    final bucketsAsync = ref.watch(pagosBucketsProvider);

    // Alumnos activos.
    final activeCount = linksAsync.valueOrNull
            ?.where((l) => l.status == TrainerLinkStatus.active)
            .length ??
        0;

    // Ingreso del mes + Por cobrar from pagosBuckets.
    int ingresoMes = 0;
    int porCobrarTotal = 0;
    int vencidosCount = 0;
    bucketsAsync.whenData((buckets) {
      final now = DateTime.now().toUtc();
      final monthStart = DateTime.utc(now.year, now.month, 1);
      for (final p in buckets.pagados) {
        final paidRef = (p.paidAt ?? p.createdAt).toUtc();
        if (!paidRef.isBefore(monthStart)) {
          ingresoMes += p.amountArs;
        }
      }
      porCobrarTotal = buckets.vencidos.fold(0, (sum, p) => sum + p.amountArs);
      vencidosCount = buckets.vencidos.length;
    });

    // Adherencia aggregate — valueOrNull degrades to null (no spinner hang).
    final adherenceAsync = ref.watch(aggregateAdherenceProvider);
    final adherenceValue = adherenceAsync.valueOrNull;
    final adherenceLabel = adherenceValue == null
        ? l10n.dashboardAdherenceRingPlaceholder // "--"
        : l10n.dashboardAdherenceValue(adherenceValue.round());

    final linksLoading = linksAsync.isLoading;
    final bucketsLoading = bucketsAsync.isLoading;

    final cards = [
      KpiCard(
        value: activeCount.toString(),
        label: l10n.dashboardKpiAlumnosActivos,
        loading: linksLoading,
      ),
      KpiCard(
        value: fmtArs(ingresoMes),
        label: l10n.dashboardKpiIngresoMes,
        loading: bucketsLoading,
      ),
      // Adherencia: nunca skeleton — degrada a "--" (ADR-D2-07).
      KpiCard(
        value: adherenceLabel,
        label: l10n.dashboardKpiAdherencia,
      ),
      KpiCard(
        value: fmtArs(porCobrarTotal),
        label: l10n.dashboardKpiPorCobrar(vencidosCount),
        loading: bucketsLoading,
      ),
    ];

    if (!wide) {
      // Narrow: Wrap en vez de scroll horizontal — las 4 cards no entran en
      // una fila, pero no hace falta el gesto de scroll extra (WU-06).
      return Wrap(
        spacing: AppSpacing.s12,
        runSpacing: AppSpacing.s12,
        children: cards,
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.s12),
            cards[i],
          ],
        ],
      ),
    );
  }
}
