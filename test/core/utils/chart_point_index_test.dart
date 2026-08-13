import 'package:flutter_test/flutter_test.dart';

import 'package:treino/core/utils/chart_point_index.dart';

void main() {
  group('exactPointIndex', () {
    test('devuelve el índice para values exactamente enteros', () {
      expect(exactPointIndex(0.0), 0);
      expect(exactPointIndex(3.0), 3);
      expect(exactPointIndex(12.0), 12);
    });

    test('tolera el residuo de floating point cerca del entero', () {
      expect(exactPointIndex(2.0000001), 2);
      expect(exactPointIndex(4.995, tolerance: 0.01), 5);
      expect(exactPointIndex(5.005, tolerance: 0.01), 5);
    });

    test('rechaza samples fraccionarios (la causa de #383/#554)', () {
      // fl_chart sin interval samplea Xs como 1.71 / 2.14 — ambos redondeaban
      // al índice 2 y duplicaban la etiqueta.
      expect(exactPointIndex(1.71), isNull);
      expect(exactPointIndex(2.14), isNull);
      expect(exactPointIndex(0.5), isNull);
      expect(exactPointIndex(3.02), isNull);
    });

    test('tolerance es configurable', () {
      expect(exactPointIndex(2.05, tolerance: 0.1), 2);
      expect(exactPointIndex(2.05, tolerance: 0.01), isNull);
    });
  });
}
