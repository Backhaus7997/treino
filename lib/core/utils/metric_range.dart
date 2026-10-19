import 'package:flutter/foundation.dart';

/// Rango válido de una métrica que carga una persona a mano (antropometría,
/// evaluaciones de rendimiento).
///
/// No es un rango fisiológico estricto: es un tope GENEROSO para atajar typos
/// —150 % de grasa, un CMJ de 999 cm— sin rechazar a un atleta real fuera de
/// lo común. Los bordes son válidos.
@immutable
class MetricRange {
  const MetricRange(this.min, this.max, this.unit)
      : assert(min < max, 'min tiene que ser menor que max');

  final double min;
  final double max;

  /// Unidad que acompaña al número en el mensaje de error ("kg", "%", "cm").
  /// Vacía para métricas adimensionales (nivel de Course Navette).
  final String unit;

  bool contains(double value) => value >= min && value <= max;

  /// Valida el texto crudo de un campo. Vacío es válido: todos los campos son
  /// opcionales. Acepta coma decimal, que es lo que tipea un teclado es-AR.
  MetricCheck check(String? raw) {
    final text = (raw ?? '').trim();
    if (text.isEmpty) return MetricCheck.empty;
    final parsed = parseMetric(text);
    if (parsed == null) return MetricCheck.invalid;
    return contains(parsed) ? MetricCheck.ok : MetricCheck.outOfRange;
  }

  @override
  bool operator ==(Object other) =>
      other is MetricRange &&
      other.min == min &&
      other.max == max &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(min, max, unit);
}

/// Resultado de [MetricRange.check].
enum MetricCheck {
  empty,
  invalid,
  outOfRange,
  ok;

  bool get isError => this == invalid || this == outOfRange;
}

/// Parsea un número tipeado a mano, con punto o coma decimal. Null si no es
/// un número finito.
double? parseMetric(String raw) {
  final parsed = double.tryParse(raw.trim().replaceAll(',', '.'));
  if (parsed == null || !parsed.isFinite) return null;
  return parsed;
}
