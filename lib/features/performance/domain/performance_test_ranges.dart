import '../../../core/utils/metric_range.dart';

/// Rangos válidos de cada métrica de [PerformanceTest], acordados con
/// producto el 2026-10-16 (#1485). Generosos a propósito: atajan typos como
/// un CMJ de 999 cm, no juzgan al atleta.
///
/// ⚠️  `performanceTestShapeOk` en `firestore.rules` espeja estos MISMOS
/// rangos (`optNumInRange`). Si se mueve uno sin el otro, el form acepta un
/// valor que Firestore rechaza con permission-denied, o al revés.
abstract final class PerformanceTestRanges {
  // ── Saltos ────────────────────────────────────────────────────────────────
  /// CMJ, squat jump y Abalakov.
  static const verticalJumpCm = MetricRange(0, 150, 'cm');
  static const broadJumpCm = MetricRange(0, 400, 'cm');

  // ── Sprints ───────────────────────────────────────────────────────────────
  static const sprint10mS = MetricRange(1, 5, 's');
  static const sprint20mS = MetricRange(2, 8, 's');
  static const sprint30mS = MetricRange(3, 10, 's');
  static const sprint40mS = MetricRange(4, 12, 's');

  // ── Fuerza (1RM) ──────────────────────────────────────────────────────────
  /// Sentadilla, press de banca, peso muerto y press militar.
  static const oneRepMaxKg = MetricRange(0, 500, 'kg');

  /// Dominada: es el LASTRE, no el peso corporal.
  static const pullUpLoadKg = MetricRange(0, 200, 'kg');

  // ── Resistencia y movilidad ───────────────────────────────────────────────
  static const vo2maxMlKgMin = MetricRange(10, 95, 'ml/kg/min');
  static const courseNavetteLevel = MetricRange(1, 21, '');
  static const cooperMeters = MetricRange(0, 5000, 'm');

  /// Puede ser negativo: no llegar a la punta del pie.
  static const sitAndReachCm = MetricRange(-40, 60, 'cm');
}
