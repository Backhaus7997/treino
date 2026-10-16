import '../../l10n/app_l10n.dart';
import 'kg_format.dart';
import 'metric_range.dart';

/// Mensaje inline para un campo validado contra [range], o null si es válido.
///
/// Fuera de rango dice el rango ("Entre 2 y 70 %") en vez de un genérico
/// "fuera de rango": quien cargó 150 % de grasa necesita saber qué escribir.
String? metricRangeError(MetricRange range, String? raw, AppL10n l10n) {
  switch (range.check(raw)) {
    case MetricCheck.empty:
    case MetricCheck.ok:
      return null;
    case MetricCheck.invalid:
      return l10n.logFieldInvalidNumber;
    case MetricCheck.outOfRange:
      String n(double v) => formatWeightKg(v).replaceAll('.', ',');
      // `unit` puede ser vacío (nivel de Course Navette): sin el trim queda un
      // espacio colgando al final.
      final text = range.minExclusive
          ? l10n.logFieldRangeAbove(n(range.min), n(range.max), range.unit)
          : l10n.logFieldRange(n(range.min), n(range.max), range.unit);
      return text.trim();
  }
}
