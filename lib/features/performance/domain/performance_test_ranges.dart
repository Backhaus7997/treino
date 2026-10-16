import '../../../core/utils/metric_range.dart';

/// Rangos válidos de cada métrica de [PerformanceTest], acordados con
/// producto el 2026-10-16 (#1485). Generosos a propósito: atajan typos como
/// un CMJ de 999 cm, no juzgan al atleta.
///
/// ⚠️  El piso es el de `firestore.rules` (`performanceTestShapeOk` →
/// `optPositiveNum`, estrictamente `> 0`), no el de producto: donde producto
/// pidió 0 va `minExclusive`, y sit and reach no admite negativos. Bajar un
/// piso acá sin tocar la regla hace que el form acepte un valor que Firestore
/// rechaza. Aceptar 0 y negativos es un follow-up que empieza por la regla.
abstract final class PerformanceTestRanges {
  // ── Saltos ────────────────────────────────────────────────────────────────
  /// CMJ, squat jump y Abalakov.
  static const verticalJumpCm = MetricRange(0, 150, 'cm', minExclusive: true);
  static const broadJumpCm = MetricRange(0, 400, 'cm', minExclusive: true);

  // ── Sprints ───────────────────────────────────────────────────────────────
  static const sprint10mS = MetricRange(1, 5, 's');
  static const sprint20mS = MetricRange(2, 8, 's');
  static const sprint30mS = MetricRange(3, 10, 's');
  static const sprint40mS = MetricRange(4, 12, 's');

  // ── Fuerza (1RM) ──────────────────────────────────────────────────────────
  /// Sentadilla, press de banca, peso muerto y press militar.
  static const oneRepMaxKg = MetricRange(0, 500, 'kg', minExclusive: true);

  /// Dominada: es el LASTRE, no el peso corporal.
  static const pullUpLoadKg = MetricRange(0, 200, 'kg', minExclusive: true);

  // ── Resistencia y movilidad ───────────────────────────────────────────────
  static const vo2maxMlKgMin = MetricRange(10, 95, 'ml/kg/min');
  static const courseNavetteLevel = MetricRange(1, 21, '');
  static const cooperMeters = MetricRange(0, 5000, 'm', minExclusive: true);

  /// Producto pidió −40 a 60 (no llegar a la punta del pie es negativo), pero
  /// la regla exige `> 0`: hasta cambiarla, sólo positivos.
  static const sitAndReachCm = MetricRange(0, 60, 'cm', minExclusive: true);
}
