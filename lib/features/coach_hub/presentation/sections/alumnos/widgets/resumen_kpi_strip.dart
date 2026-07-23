import 'package:flutter/material.dart';

import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';

import '../resumen_metrics.dart';

/// Entero si es redondo, un decimal si no (61 → "61", 60.5 → "60.5").
///
/// Copia local de `_trimNum` (`alumno_detail_screen.dart`) — función pura de
/// 1 línea, duplicada a propósito para no acoplar este widget extraído al
/// archivo raíz (evita import circular; ver `_fmtVolKg` abajo).
String _trimNum(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

/// Volumen compacto: kg hasta 999, toneladas con un decimal de ahí en más.
/// Copia local de `_fmtVolKg` — ver nota de [_trimNum].
String _fmtVolKg(double kg) =>
    kg >= 1000 ? '${(kg / 1000).toStringAsFixed(1)} t' : '${kg.round()} kg';

/// Strip de 4 KPI cards del tab Resumen — Fase 3 WU-05.
///
/// Extraído de `_MetricCard`×4 (`alumno_detail_screen.dart`, ADR-A3-04) y
/// migrado al kit v2 (`KpiCard`). Cálculo 100% preservado — sólo consume
/// [ResumenMetrics] ya computado por el caller (`_ResumenTab`), no recalcula
/// nada acá (single source of truth: `resumen_metrics.dart`, cálculo puro).
///
/// [metrics] `null` → 4 `KpiCard(loading: true)` (skeleton del kit).
class ResumenKpiStrip extends StatelessWidget {
  const ResumenKpiStrip({super.key, this.metrics});

  final ResumenMetrics? metrics;

  @override
  Widget build(BuildContext context) {
    final m = metrics;
    final cards = m == null
        ? List<Widget>.generate(
            4,
            (_) => const KpiCard(value: '', label: '', loading: true),
          )
        : _dataCards(m);

    // IntrinsicHeight: mismo criterio que el `_MetricCard` original — el Row
    // vive dentro de un `Column` sin altura acotada (SingleChildScrollView) y
    // ahora, además, dentro del Stack de cross-fade de `TreinoStateSwitcher`
    // (ADR-A3-04, WU-05), que también relaja la altura a infinita. Sin este
    // wrapper, `CrossAxisAlignment.stretch` intenta estirar los hijos a una
    // altura infinita → `BoxConstraints forces an infinite height`.
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: AppSpacing.s12),
            Expanded(child: cards[i]),
          ],
        ],
      ),
    );
  }

  List<Widget> _dataCards(ResumenMetrics m) {
    final adh = m.adherencia30dPct;
    final adhDelta = m.adherenciaDeltaPts;
    final volDelta = m.volumenDeltaPct;
    final peso = m.pesoActualKg;
    final pesoDelta = m.pesoDelta30dKg;

    return [
      KpiCard(
        value: adh == null ? '—' : '${adh.round()}%',
        label: 'ADHERENCIA 30D', // i18n: Fase W2
        delta: adhDelta == null
            ? null
            : '${adhDelta >= 0 ? '↑' : '↓'} ${adhDelta.abs().round()} pts',
        deltaPositive: adhDelta == null ? null : adhDelta >= 0,
        sublabel: adh == null ? 'Sin plan' : 'vs 30 días previos',
      ),
      KpiCard(
        value: m.sesionesPorSemana.toStringAsFixed(1),
        label: 'SESIONES / SEM', // i18n: Fase W2
        sublabel: m.weeklyTarget > 0 ? 'Plan: ${m.weeklyTarget}' : 'Sin plan',
      ),
      KpiCard(
        value: _fmtVolKg(m.volumenSemanaActualKg),
        label: 'VOLUMEN', // i18n: Fase W2
        delta: volDelta == null
            ? null
            : '${volDelta >= 0 ? '+' : ''}${volDelta.round()}%',
        deltaPositive: volDelta == null ? null : volDelta >= 0,
        sublabel: volDelta == null ? 'esta semana' : 'vs semana pasada',
      ),
      KpiCard(
        value: peso == null ? '—' : '${_trimNum(peso)} kg',
        label: 'PESO CORPORAL', // i18n: Fase W2
        delta: pesoDelta == null
            ? null
            : '${pesoDelta >= 0 ? '+' : ''}${pesoDelta.toStringAsFixed(1)} kg',
        deltaPositive: pesoDelta == null ? null : pesoDelta >= 0,
        sublabel: pesoDelta == null ? null : '30 días',
      ),
    ];
  }
}
