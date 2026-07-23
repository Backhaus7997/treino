import 'package:flutter/material.dart';

import 'package:treino/app/theme/tokens/primitives.dart';
import 'package:treino/features/coach_hub/presentation/widgets/coach_hub_widgets.dart';

import '../progreso_metrics.dart';

/// Entero si es redondo, un decimal si no (61 → "61", 60.5 → "60.5").
/// Copia local de `_trimNum` (`alumno_detail_screen.dart`) — función pura de
/// 1 línea, duplicada a propósito para no acoplar este widget extraído al
/// archivo raíz (mismo criterio que `resumen_kpi_strip.dart`).
String _trimNum(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);

String? _delta(double? v, String unit, {int decimals = 1}) => v == null
    ? null
    : '${v >= 0 ? '+' : ''}${v.toStringAsFixed(decimals)}$unit';

/// Strip de 4 KPI cards del tab Progreso — Fase 3 WU-06b.
///
/// Peso / % graso / cintura / 1RM, cada uno con delta real cuando hay al
/// menos 2 mediciones/tests comparables ([ProgresoKpis], cálculo puro). El
/// 1RM es data-honest (ADR-D2-04): `sublabel` con el ejercicio SÓLO cuando
/// hay un dato real detrás.
///
/// [kpis] `null` → 4 `KpiCard(loading: true)` (skeleton del kit).
class ProgresoKpiStrip extends StatelessWidget {
  const ProgresoKpiStrip({super.key, this.kpis});

  final ProgresoKpis? kpis;

  @override
  Widget build(BuildContext context) {
    final k = kpis;
    final cards = k == null
        ? List<Widget>.generate(
            4,
            (_) => const KpiCard(value: '', label: '', loading: true),
          )
        : _dataCards(k);

    // IntrinsicHeight: mismo criterio que `ResumenKpiStrip` — vive dentro de
    // un `Column` sin altura acotada (SingleChildScrollView + cross-fade de
    // `TreinoStateSwitcher`), que relaja la altura a infinita.
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

  List<Widget> _dataCards(ProgresoKpis k) {
    return [
      KpiCard(
        value: k.pesoKg == null ? '—' : '${_trimNum(k.pesoKg!)} kg',
        label: 'Peso', // i18n: Fase W2
        delta: _delta(k.pesoDeltaKg, ' kg'),
        deltaPositive: k.pesoDeltaKg == null ? null : k.pesoDeltaKg! >= 0,
      ),
      KpiCard(
        value: k.fatPct == null ? '—' : '${_trimNum(k.fatPct!)}%',
        label: '% Graso', // i18n: Fase W2
        delta: _delta(k.fatDeltaPct, '%'),
        deltaPositive: k.fatDeltaPct == null ? null : k.fatDeltaPct! >= 0,
      ),
      KpiCard(
        value: k.waistCm == null ? '—' : '${_trimNum(k.waistCm!)} cm',
        label: 'Cintura', // i18n: Fase W2
        delta: _delta(k.waistDeltaCm, ' cm'),
        deltaPositive: k.waistDeltaCm == null ? null : k.waistDeltaCm! >= 0,
      ),
      KpiCard(
        value: k.oneRmKg == null ? '—' : '${_trimNum(k.oneRmKg!)} kg',
        label: '1RM', // i18n: Fase W2
        delta: _delta(k.oneRmDeltaKg, ' kg'),
        deltaPositive: k.oneRmDeltaKg == null ? null : k.oneRmDeltaKg! >= 0,
        sublabel: k.oneRmLabel,
      ),
    ];
  }
}
