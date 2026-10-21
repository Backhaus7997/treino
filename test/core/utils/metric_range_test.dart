import 'package:flutter_test/flutter_test.dart';
import 'package:treino/core/utils/metric_range.dart';
import 'package:treino/features/measurements/domain/measurement_ranges.dart';
import 'package:treino/features/performance/domain/performance_test_ranges.dart';

void main() {
  group('MetricRange.check', () {
    const grasa = MeasurementRanges.fatPercentage; // 2–70 %

    test('vacío es válido: todos los campos son opcionales', () {
      expect(grasa.check(null), MetricCheck.empty);
      expect(grasa.check('   '), MetricCheck.empty);
    });

    test('los bordes son válidos', () {
      expect(grasa.check('2'), MetricCheck.ok);
      expect(grasa.check('70'), MetricCheck.ok);
    });

    test('apenas afuera de cada borde es fuera de rango', () {
      expect(grasa.check('1,9'), MetricCheck.outOfRange);
      expect(grasa.check('70,1'), MetricCheck.outOfRange);
    });

    test('el caso del QA: 150 % de grasa', () {
      expect(grasa.check('150'), MetricCheck.outOfRange);
    });

    test('acepta coma y punto decimal', () {
      expect(grasa.check('12,5'), MetricCheck.ok);
      expect(grasa.check('12.5'), MetricCheck.ok);
    });

    test('texto que no es número es inválido, no fuera de rango', () {
      expect(grasa.check('12.x.3'), MetricCheck.invalid);
      expect(grasa.check('abc'), MetricCheck.invalid);
    });

    test('infinito y NaN son inválidos', () {
      expect(grasa.check('Infinity'), MetricCheck.invalid);
      expect(grasa.check('NaN'), MetricCheck.invalid);
    });
  });

  group('rangos de rendimiento', () {
    test('el caso del QA: CMJ de 999 cm', () {
      expect(PerformanceTestRanges.verticalJumpCm.check('999'),
          MetricCheck.outOfRange);
    });

    // Los pisos de producto, espejados en `firestore.rules` (#1485).
    test('el 0 es válido donde el rango arranca en 0', () {
      expect(PerformanceTestRanges.verticalJumpCm.check('0'), MetricCheck.ok);
      expect(PerformanceTestRanges.cooperMeters.check('0'), MetricCheck.ok);
    });

    test('sit and reach acepta negativos hasta −40', () {
      expect(PerformanceTestRanges.sitAndReachCm.check('-12'), MetricCheck.ok);
      expect(PerformanceTestRanges.sitAndReachCm.check('-40'), MetricCheck.ok);
      expect(PerformanceTestRanges.sitAndReachCm.check('-41'),
          MetricCheck.outOfRange);
    });
  });
}
