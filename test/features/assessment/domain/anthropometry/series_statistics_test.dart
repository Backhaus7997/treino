import 'dart:math' show sqrt;

import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/assessment/domain/anthropometry/series_statistics.dart';

void main() {
  group('summarizeSeries', () {
    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO-460: Median of odd-count list
    // values = [3.0, 1.0, 5.0, 2.0, 4.0] → sorted = [1,2,3,4,5] → median=3
    // mean = (1+2+3+4+5)/5 = 3.0
    // var = ((1-3)²+(2-3)²+(3-3)²+(4-3)²+(5-3)²)/5 = (4+1+0+1+4)/5 = 2.0
    // sd = √2 ≈ 1.4142
    // errorPct = (1.4142/3.0)*100 ≈ 47.14
    // ─────────────────────────────────────────────────────────────────────────
    test('SCENARIO-460: odd-count list → correct median, sd, errorPct', () {
      final result = summarizeSeries([3.0, 1.0, 5.0, 2.0, 4.0]);
      expect(result.median, closeTo(3.0, 0.001));
      expect(result.sd, closeTo(sqrt(2.0), 0.001));
      expect(result.errorPct, closeTo((sqrt(2.0) / 3.0) * 100, 0.01));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO-461: Median of even-count list = mean of two middle values
    // values = [4.0, 1.0, 3.0, 2.0] → sorted = [1,2,3,4] → median=(2+3)/2=2.5
    // mean = (1+2+3+4)/4 = 2.5
    // var = ((1-2.5)²+(2-2.5)²+(3-2.5)²+(4-2.5)²)/4
    //     = (2.25+0.25+0.25+2.25)/4 = 5.0/4 = 1.25
    // sd = √1.25 = 1.11803
    // errorPct = (1.11803/2.5)*100 ≈ 44.72
    // ─────────────────────────────────────────────────────────────────────────
    test('SCENARIO-461: even-count list → median = mean of two middle values',
        () {
      final result = summarizeSeries([4.0, 1.0, 3.0, 2.0]);
      expect(result.median, closeTo(2.5, 0.001));
      expect(result.sd, closeTo(sqrt(1.25), 0.001));
      expect(result.errorPct, closeTo((sqrt(1.25) / 2.5) * 100, 0.01));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO-462: Single value → errorPct = defaultErrorPct
    // ─────────────────────────────────────────────────────────────────────────
    test('SCENARIO-462: single value → errorPct = defaultErrorPct (2.0)', () {
      final result = summarizeSeries([10.0]);
      expect(result.median, closeTo(10.0, 0.001));
      expect(result.sd, closeTo(0.0, 0.001));
      expect(result.errorPct, closeTo(2.0, 0.001));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO-463: Empty list → errorPct = defaultErrorPct, median=0
    // ─────────────────────────────────────────────────────────────────────────
    test('SCENARIO-463: empty list → median=0, errorPct=defaultErrorPct', () {
      final result = summarizeSeries([]);
      expect(result.median, closeTo(0.0, 0.001));
      expect(result.errorPct, closeTo(2.0, 0.001));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO-464: Custom defaultErrorPct
    // ─────────────────────────────────────────────────────────────────────────
    test('SCENARIO-464: custom defaultErrorPct=5.0 used when single value', () {
      final result = summarizeSeries([7.0], defaultErrorPct: 5.0);
      expect(result.errorPct, closeTo(5.0, 0.001));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO-465: Median=0 guard → errorPct falls back to defaultErrorPct
    // values = [0.0, 0.0, 0.0]
    // ─────────────────────────────────────────────────────────────────────────
    test('SCENARIO-465: median=0 → errorPct = defaultErrorPct', () {
      final result = summarizeSeries([0.0, 0.0, 0.0]);
      expect(result.median, closeTo(0.0, 0.001));
      expect(result.errorPct, closeTo(2.0, 0.001));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO-466: SeriesSummary equality
    // ─────────────────────────────────────────────────────────────────────────
    test('SCENARIO-466: SeriesSummary equality', () {
      const s1 = SeriesSummary(median: 3.0, sd: 1.0, errorPct: 33.33);
      const s2 = SeriesSummary(median: 3.0, sd: 1.0, errorPct: 33.33);
      expect(s1, equals(s2));
    });

    // ─────────────────────────────────────────────────────────────────────────
    // SCENARIO-467: Two identical values → sd=0, errorPct=0 (not default)
    // values = [5.0, 5.0]
    // median = 5.0, mean=5.0, var=0, sd=0
    // median != 0, n >= 2 → errorPct = (0/5)*100 = 0
    // ─────────────────────────────────────────────────────────────────────────
    test('SCENARIO-467: two identical values → sd=0, errorPct=0', () {
      final result = summarizeSeries([5.0, 5.0]);
      expect(result.sd, closeTo(0.0, 0.001));
      expect(result.errorPct, closeTo(0.0, 0.001));
    });
  });
}
