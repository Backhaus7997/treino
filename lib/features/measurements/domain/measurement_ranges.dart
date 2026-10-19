import '../../../core/utils/metric_range.dart';

/// Rangos válidos de cada campo de [Measurement], acordados con producto el
/// 2026-10-16 (#1483). Generosos a propósito: atajan typos, no juzgan cuerpos.
///
/// Los bilaterales (izquierdo/derecho) comparten rango.
abstract final class MeasurementRanges {
  // ── Composición corporal ──────────────────────────────────────────────────
  static const weightKg = MetricRange(20, 400, 'kg');
  static const fatPercentage = MetricRange(2, 70, '%');
  static const muscleMassKg = MetricRange(5, 150, 'kg');

  // ── Tronco ────────────────────────────────────────────────────────────────
  static const shouldersCm = MetricRange(50, 200, 'cm');
  static const chestCm = MetricRange(50, 200, 'cm');
  static const waistCm = MetricRange(40, 250, 'cm');
  static const hipsCm = MetricRange(40, 250, 'cm');
  static const glutesCm = MetricRange(40, 250, 'cm');

  // ── Brazos ────────────────────────────────────────────────────────────────
  /// Relajado y flexionado.
  static const bicepsCm = MetricRange(10, 80, 'cm');
  static const forearmCm = MetricRange(10, 60, 'cm');

  // ── Piernas ───────────────────────────────────────────────────────────────
  /// Muslo superior y medio.
  static const thighCm = MetricRange(20, 120, 'cm');
  static const calfCm = MetricRange(15, 70, 'cm');
}
