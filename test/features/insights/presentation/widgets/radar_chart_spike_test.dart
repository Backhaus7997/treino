import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// SPIKE (design risk-2): fl_chart 1.2.0's RadarChart is net-new with no
/// in-repo example. This throwaway test proves it renders synthetic 6-axis
/// data (2 overlaid dataSets, like the Current/Previous radar we're about to
/// build) inside a widget test BEFORE any real wiring — de-risks the AD4
/// implementation below. Kept (not deleted) as basic regression coverage for
/// the fl_chart API surface this feature depends on.
void main() {
  testWidgets('RadarChart renders 6-axis synthetic data with 2 dataSets',
      (tester) async {
    const axisLabels = [
      'Back',
      'Chest',
      'Core',
      'Shoulders',
      'Arms',
      'Legs',
    ];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 300,
            height: 300,
            child: RadarChart(
              RadarChartData(
                radarShape: RadarShape.polygon,
                tickCount: 4,
                dataSets: [
                  RadarDataSet(
                    fillColor: Colors.blue.withValues(alpha: 0.2),
                    borderColor: Colors.blue,
                    dataEntries: const [
                      RadarEntry(value: 10),
                      RadarEntry(value: 8),
                      RadarEntry(value: 5),
                      RadarEntry(value: 6),
                      RadarEntry(value: 7),
                      RadarEntry(value: 9),
                    ],
                  ),
                  RadarDataSet(
                    fillColor: Colors.grey.withValues(alpha: 0.2),
                    borderColor: Colors.grey,
                    dataEntries: const [
                      RadarEntry(value: 6),
                      RadarEntry(value: 4),
                      RadarEntry(value: 3),
                      RadarEntry(value: 4),
                      RadarEntry(value: 5),
                      RadarEntry(value: 6),
                    ],
                  ),
                ],
                getTitle: (index, angle) =>
                    RadarChartTitle(text: axisLabels[index], angle: angle),
              ),
            ),
          ),
        ),
      ),
    );

    expect(find.byType(RadarChart), findsOneWidget);
    // Axis title text is painted via CustomPainter, not Text widgets — the
    // absence of an exception during pump/build is the actual proof the
    // synthetic 2-dataSet/6-axis shape is accepted by fl_chart's asserts
    // (hasEqualDataEntriesLength, dataEntries.length >= 3).
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.takeException(), isNull);
  });
}
