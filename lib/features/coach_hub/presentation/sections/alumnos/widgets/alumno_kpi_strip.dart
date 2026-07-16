import 'package:flutter/material.dart';
import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';

/// Strip de métricas denormalizadas del header de detalle — Fase 3 WU-04.
///
/// Extraído de `_MetricChip` (`alumno_detail_screen.dart`, ADR-A3-04) y
/// migrado al kit v2 (`KpiCard`, con skeleton `loading:true` propio).
///
/// Data-honesty (ADR-A3-01): el mockup del header pide "Adherencia 30d" como
/// una de las 4 métricas, pero ese cálculo depende de 3 streams pesados
/// (sesiones + mediciones + rutinas — ver `ResumenMetrics.compute`) que hoy
/// solo se suscriben dentro del tab Resumen (WU-05). Duplicarlos acá
/// montaría esas 3 queries en TODO momento que el detalle está abierto (los
/// 11 tabs, no solo Resumen) — inventar/duplicar ese costo no es el alcance
/// de un WU de chrome. Se usan las 4 métricas REALES ya disponibles vía
/// `valueOrNull` en `AlumnoDetailScreen` (perfil/billing/cobros pendientes):
/// **Sesiones · Racha · Vencimiento · Deuda**.
class AlumnoKpiStrip extends StatelessWidget {
  const AlumnoKpiStrip({
    super.key,
    required this.sesiones,
    required this.racha,
    required this.vencimiento,
    required this.deuda,
    this.sesionesLoading = false,
    this.rachaLoading = false,
    this.vencimientoLoading = false,
    this.deudaLoading = false,
  });

  /// Cantidad de sesiones registradas (`profile?.workoutsCount ?? 0` —
  /// mismo default que el `_MetricChip` original).
  final int sesiones;

  /// Racha actual en días (`profile?.racha ?? 0`).
  final int racha;

  /// Fecha del próximo cobro ya formateada (`fmtDayMonth`), o `null` si no
  /// hay billing configurado.
  final String? vencimiento;

  /// Monto adeudado ya formateado (`fmtArs`), o `null` si el alumno está al
  /// día (sin cobros pendientes).
  final String? deuda;

  final bool sesionesLoading;
  final bool rachaLoading;
  final bool vencimientoLoading;
  final bool deudaLoading;

  @override
  Widget build(BuildContext context) {
    final cards = [
      KpiCard(
        value: '$sesiones',
        label: 'Sesiones', // i18n: Fase W2
        loading: sesionesLoading,
      ),
      KpiCard(
        value: '$racha d',
        label: 'Racha', // i18n: Fase W2
        loading: rachaLoading,
      ),
      KpiCard(
        value: vencimiento ?? '—',
        label: 'Vencimiento', // i18n: Fase W2
        loading: vencimientoLoading,
      ),
      KpiCard(
        value: deuda ?? 'Al día', // i18n: Fase W2
        label: 'Deuda', // i18n: Fase W2
        loading: deudaLoading,
      ),
    ];

    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: AppSpacing.s12),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }
}
