/// KPI row de la pantalla Pagos del Coach Hub web.
///
/// Tres KpiCard del kit v2: Ingreso del mes / Pendiente cobrar / Vencido.
/// Sección: coach_hub/pagos — contrato: sin Scaffold, sin HEX,
/// es-AR + // i18n, AppPalette, sin AppL10n.
///
/// ADR-F9-01 (honestidad de datos): solo 3 KPI reales, sin "Proyectado" ni
/// deltas +%/-% inventados (no hay fuente mes-contra-mes real). Los
/// sublabels sí son honestos: derivan de conteos reales de los mismos
/// providers usados para el value.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart'
    show pagosPorCobrarProvider;

import '../../../widgets/coach_hub_widgets.dart' show KpiCard;
import 'pagos_buckets_provider.dart';
import 'payment_format.dart';

// ── PagosKpiRow ───────────────────────────────────────────────────────────────

/// Fila de 3 KpiCard: Ingreso del mes / Pendiente cobrar / Vencido.
///
/// - **Ingreso del mes**: suma de amountArs de pagos paid cuyo
///   `(paidAt ?? createdAt)` cae en el mes calendario actual (UTC).
///   Sublabel: cantidad de pagos que componen esa suma.
/// - **Pendiente cobrar**: suma de amountArs de [pagosPorCobrarProvider]
///   (cadence-aware, como en alumno_detail). Sublabel: cantidad de alumnos.
/// - **Vencido**: suma de amountArs de `pagosBucketsProvider.vencidos`.
///   Sublabel: cantidad de pagos vencidos.
///
/// Layout responsive: 3 columnas iguales (Row + Expanded) desde ~900px de
/// ancho; debajo de eso, Wrap de 2 columnas para no romper en el rango
/// 768-900 (Coach Hub es desktop-only >=768).
class PagosKpiRow extends ConsumerWidget {
  const PagosKpiRow({super.key});

  static const double _rowBreakpoint = 900;
  static const double _spacing = 12;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bucketsAsync = ref.watch(pagosBucketsProvider);
    final cobrosAsync = ref.watch(pagosPorCobrarProvider);

    final now = DateTime.now().toUtc();
    final monthStart = DateTime.utc(now.year, now.month, 1);

    // Ingreso del mes: paid && (paidAt ?? createdAt) >= firstDayOfMonth UTC.
    int ingresoMes = 0;
    int pagadosMesCount = 0;
    int vencidoTotal = 0;
    int vencidosCount = 0;
    bucketsAsync.whenData((buckets) {
      for (final p in buckets.pagados) {
        final pagoRef = (p.paidAt ?? p.createdAt).toUtc();
        if (!pagoRef.isBefore(monthStart)) {
          ingresoMes += p.amountArs;
          pagadosMesCount++;
        }
      }
      vencidoTotal = buckets.vencidos.fold(0, (sum, p) => sum + p.amountArs);
      vencidosCount = buckets.vencidos.length;
    });

    // Pendiente cobrar: suma de cobros del período actual (pagosPorCobrarProvider).
    int pendienteCobrar = 0;
    int cobrosCount = 0;
    cobrosAsync.whenData((cobros) {
      pendienteCobrar = cobros.fold(0, (sum, c) => sum + c.amountArs);
      cobrosCount = cobros.length;
    });

    final loading = bucketsAsync.isLoading;

    final cards = <KpiCard>[
      KpiCard(
        label: 'Ingreso del mes', // i18n
        value: fmtArs(ingresoMes),
        sublabel: '$pagadosMesCount cobrados', // i18n
        loading: loading,
      ),
      KpiCard(
        label: 'Pendiente cobrar', // i18n
        value: fmtArs(pendienteCobrar),
        sublabel: '$cobrosCount alumnos', // i18n
        loading: loading,
      ),
      KpiCard(
        label: 'Vencido', // i18n
        value: fmtArs(vencidoTotal),
        sublabel: '$vencidosCount vencidos', // i18n
        loading: loading,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= _rowBreakpoint) {
          return Row(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(width: _spacing),
                Expanded(child: cards[i]),
              ],
            ],
          );
        }

        final itemWidth = (constraints.maxWidth - _spacing) / 2;
        return Wrap(
          spacing: _spacing,
          runSpacing: _spacing,
          children: [
            for (final card in cards) SizedBox(width: itemWidth, child: card),
          ],
        );
      },
    );
  }
}
