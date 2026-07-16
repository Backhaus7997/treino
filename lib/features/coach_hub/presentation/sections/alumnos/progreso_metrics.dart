import 'package:treino/features/measurements/domain/measurement.dart';
import 'package:treino/features/performance/domain/performance_test.dart';

/// Métricas del strip de KPIs del tab «Progreso» (Fase 3 WU-06b).
///
/// Cálculo PURO y testeable: no toca Flutter ni providers, recibe las listas
/// ya resueltas (ASC por `recordedAt`, mismo contrato que
/// `measurementsForAthleteProvider`/`performanceTestsForAthleteProvider`).
///
/// Delta = último valor menos el anterior no-null del MISMO campo — sin
/// ventana de tiempo (a diferencia de `ResumenMetrics.pesoDelta30dKg`, que sí
/// usa un corte de 30 días). Acá el foco es "cambio desde la última carga",
/// mismo criterio que `PerformanceProgressChart._ChartHeader` (delta entre
/// el primer y último punto graficable).
///
/// Honestidad de datos (ADR-D2, Fase 2): cada campo es `null` si no hay
/// medición real detrás — nunca se fabrica. El 1RM elige el PRIMER ejercicio
/// (orden fijo) que tenga al menos un valor cargado; `oneRmLabel` sólo se
/// completa junto con `oneRmKg` (honestidad del sublabel, ADR-D2-04).
class ProgresoKpis {
  const ProgresoKpis({
    this.pesoKg,
    this.pesoDeltaKg,
    this.fatPct,
    this.fatDeltaPct,
    this.waistCm,
    this.waistDeltaCm,
    this.oneRmLabel,
    this.oneRmKg,
    this.oneRmDeltaKg,
  });

  /// Peso corporal más reciente (kg). `null` sin mediciones con peso.
  final double? pesoKg;

  /// Variación (kg) vs la medición de peso anterior. `null` con <2 valores.
  final double? pesoDeltaKg;

  /// % graso más reciente. `null` sin mediciones con % graso.
  final double? fatPct;

  /// Variación (pts) vs la medición de % graso anterior. `null` con <2.
  final double? fatDeltaPct;

  /// Cintura más reciente (cm). `null` sin mediciones con cintura.
  final double? waistCm;

  /// Variación (cm) vs la medición de cintura anterior. `null` con <2.
  final double? waistDeltaCm;

  /// Nombre del ejercicio del 1RM mostrado (ej. "Sentadilla"). `null` si no
  /// hay ningún 1RM cargado.
  final String? oneRmLabel;

  /// 1RM más reciente (kg) del ejercicio elegido. `null` si no hay ninguno.
  final double? oneRmKg;

  /// Variación (kg) vs el 1RM anterior del mismo ejercicio. `null` con <2.
  final double? oneRmDeltaKg;

  factory ProgresoKpis.compute({
    required List<Measurement> measurements,
    required List<PerformanceTest> tests,
  }) {
    final peso = _lastAndDelta(measurements, (m) => m.weightKg);
    final fat = _lastAndDelta(measurements, (m) => m.fatPercentage);
    final waist = _lastAndDelta(measurements, (m) => m.waistCm);
    final oneRm = _bestOneRm(tests);

    return ProgresoKpis(
      pesoKg: peso.$1,
      pesoDeltaKg: peso.$2,
      fatPct: fat.$1,
      fatDeltaPct: fat.$2,
      waistCm: waist.$1,
      waistDeltaCm: waist.$2,
      oneRmLabel: oneRm.$1,
      oneRmKg: oneRm.$2,
      oneRmDeltaKg: oneRm.$3,
    );
  }
}

/// Último valor no-null de [field] + delta vs el anterior no-null.
/// `(null, null)` sin valores; delta `null` con exactamente 1 valor.
(double?, double?) _lastAndDelta(
  List<Measurement> measurements,
  double? Function(Measurement) field,
) {
  final values =
      [for (final m in measurements) field(m)].whereType<double>().toList();
  if (values.isEmpty) return (null, null);
  if (values.length == 1) return (values.last, null);
  return (values.last, values.last - values[values.length - 2]);
}

/// Ejercicios 1RM en orden de prioridad (primero con dato real gana).
const _oneRmFields = <(String, double? Function(PerformanceTest))>[
  ('Sentadilla', _squat1rm), // i18n: Fase W2
  ('Banca', _bench1rm), // i18n: Fase W2
  ('Peso muerto', _deadlift1rm), // i18n: Fase W2
  ('Press militar', _overheadPress1rm), // i18n: Fase W2
  ('Dominada', _pullUp1rm), // i18n: Fase W2
];

double? _squat1rm(PerformanceTest t) => t.squat1rmKg;
double? _bench1rm(PerformanceTest t) => t.benchPress1rmKg;
double? _deadlift1rm(PerformanceTest t) => t.deadlift1rmKg;
double? _overheadPress1rm(PerformanceTest t) => t.overheadPress1rmKg;
double? _pullUp1rm(PerformanceTest t) => t.pullUp1rmKg;

/// Primer campo 1RM (orden fijo arriba) con al menos un valor cargado.
(String?, double?, double?) _bestOneRm(List<PerformanceTest> tests) {
  for (final (label, field) in _oneRmFields) {
    final values =
        [for (final t in tests) field(t)].whereType<double>().toList();
    if (values.isEmpty) continue;
    final delta =
        values.length >= 2 ? values.last - values[values.length - 2] : null;
    return (label, values.last, delta);
  }
  return (null, null, null);
}
