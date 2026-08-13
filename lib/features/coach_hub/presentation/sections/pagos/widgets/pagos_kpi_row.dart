/// KPI row de la pantalla Pagos del Coach Hub web.
///
/// Tres tiles: Ingreso del mes / Pendiente cobrar / Vencido.
/// Nuevo en PR2a. Sección: coach_hub/pagos — contrato: sin Scaffold, sin HEX,
/// es-AR + // i18n, AppPalette, sin AppL10n.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:treino/app/theme/app_palette.dart';
import 'package:treino/core/widgets/motion/treino_count_up.dart';
import 'package:treino/features/payments/application/pagos_por_cobrar_provider.dart'
    show pagosPorCobrarProvider;

import 'pagos_buckets_provider.dart';
import 'payment_format.dart';

// ── KpiTile ───────────────────────────────────────────────────────────────────

/// Tile individual de KPI (etiqueta + monto animado). El monto cuenta desde
/// el valor previamente mostrado hacia [value] (TreinoCountUp no reinicia en
/// 0 entre rebuilds), consistente con el resto de las cifras "hero" de la app.
class KpiTile extends StatelessWidget {
  const KpiTile({
    super.key,
    required this.label,
    required this.value,
  });

  final String label;

  /// Monto en ARS (entero, sin formatear — [TreinoCountUp] formatea vía
  /// [fmtArs] en cada frame de la animación).
  final int value;

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      decoration: BoxDecoration(
        color: palette.bgCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: palette.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 6),
          TreinoCountUp(
            value: value,
            formatter: (v) => fmtArs(v.round()),
            style: TextStyle(
              color: palette.textPrimary,
              fontSize: 22,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ── PagosKpiRow ───────────────────────────────────────────────────────────────

/// Fila de 3 KPI tiles: Ingreso del mes / Pendiente cobrar / Vencido.
///
/// - **Ingreso del mes**: suma de amountArs de pagos paid cuyo
///   `(paidAt ?? createdAt)` cae en el mes calendario actual (UTC).
/// - **Pendiente cobrar**: suma de amountArs de [pagosPorCobrarProvider]
///   (cadence-aware, como en alumno_detail).
/// - **Vencido**: suma de amountArs de `pagosBucketsProvider.vencidos`.
class PagosKpiRow extends ConsumerWidget {
  const PagosKpiRow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final bucketsAsync = ref.watch(pagosBucketsProvider);
    final cobrosAsync = ref.watch(pagosPorCobrarProvider);

    final now = DateTime.now().toUtc();
    final monthStart = DateTime.utc(now.year, now.month, 1);

    // Ingreso del mes: paid && (paidAt ?? createdAt) >= firstDayOfMonth UTC.
    int ingresoMes = 0;
    int vencidoTotal = 0;
    bucketsAsync.whenData((buckets) {
      final allPaid = buckets.pagados;
      for (final p in allPaid) {
        final pagoRef = (p.paidAt ?? p.createdAt).toUtc();
        if (!pagoRef.isBefore(monthStart)) {
          ingresoMes += p.amountArs;
        }
      }
      vencidoTotal = buckets.vencidos.fold(0, (sum, p) => sum + p.amountArs);
    });

    // Pendiente cobrar: suma de cobros del período actual (pagosPorCobrarProvider).
    int pendienteCobrar = 0;
    cobrosAsync.whenData((cobros) {
      pendienteCobrar = cobros.fold(0, (sum, c) => sum + c.amountArs);
    });

    return Row(
      children: [
        KpiTile(
          label: 'Ingreso del mes', // i18n
          value: ingresoMes,
        ),
        const SizedBox(width: 12),
        KpiTile(
          label: 'Pendiente cobrar', // i18n
          value: pendienteCobrar,
        ),
        const SizedBox(width: 12),
        KpiTile(
          label: 'Vencido', // i18n
          value: vencidoTotal,
        ),
      ],
    );
  }
}
