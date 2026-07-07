import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/domain/muscle_distribution_insights.dart';
import 'package:treino/features/insights/domain/radar_axis.dart';
import 'package:treino/features/insights/presentation/widgets/muscle_distribution_radar.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

MuscleDistributionLabels _labels({
  String currentLabel = 'Actual',
  String previousLabel = 'Anterior',
  String emptyStateText = 'Sin datos para este período.',
  String workoutsLabel = 'Entrenos',
  String durationLabel = 'Duración',
  String volumeLabel = 'Volumen',
  String setsLabel = 'Sets',
  String durationUnit = 'min',
  String volumeUnit = 'kg',
}) =>
    MuscleDistributionLabels(
      currentLabel: currentLabel,
      previousLabel: previousLabel,
      emptyStateText: emptyStateText,
      workoutsLabel: workoutsLabel,
      durationLabel: durationLabel,
      volumeLabel: volumeLabel,
      setsLabel: setsLabel,
      durationUnit: durationUnit,
      volumeUnit: volumeUnit,
    );

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('MuscleDistributionRadar', () {
    testWidgets('empty insights → shows empty state, no RadarChart',
        (tester) async {
      await tester.pumpWidget(_wrap(
        MuscleDistributionRadar(
          insights: MuscleDistributionInsights.empty,
          labels: _labels(),
        ),
      ));

      expect(find.text('Sin datos para este período.'), findsOneWidget);
      expect(find.byType(RadarChart), findsNothing);
    });

    testWidgets('non-empty insights → renders RadarChart with 2 dataSets',
        (tester) async {
      final insights = MuscleDistributionInsights(
        currentSetsByAxis: const {
          RadarAxis.chest: 10,
          RadarAxis.back: 8,
          RadarAxis.core: 4,
          RadarAxis.shoulders: 5,
          RadarAxis.arms: 6,
          RadarAxis.legs: 12,
        },
        previousSetsByAxis: const {
          RadarAxis.chest: 6,
          RadarAxis.back: 4,
        },
        currentWorkouts: 4,
        previousWorkouts: 3,
        currentDurationMin: 180,
        previousDurationMin: 150,
        currentVolumeKg: 4000,
        previousVolumeKg: 3500,
        currentSets: 45,
        previousSets: 30,
      );

      await tester.pumpWidget(_wrap(
        MuscleDistributionRadar(insights: insights, labels: _labels()),
      ));

      expect(find.byType(RadarChart), findsOneWidget);
      expect(find.text('Sin datos para este período.'), findsNothing);
      // Legend renders both series labels.
      expect(find.text('Actual'), findsOneWidget);
      expect(find.text('Anterior'), findsOneWidget);
    });

    testWidgets('stat cards render current value + previous arrow',
        (tester) async {
      final insights = MuscleDistributionInsights(
        currentSetsByAxis: const {RadarAxis.chest: 10},
        previousSetsByAxis: const {RadarAxis.chest: 6},
        currentWorkouts: 4,
        previousWorkouts: 3,
        currentDurationMin: 180,
        previousDurationMin: 150,
        currentVolumeKg: 4000,
        previousVolumeKg: 3500,
        currentSets: 45,
        previousSets: 30,
      );

      await tester.pumpWidget(_wrap(
        MuscleDistributionRadar(insights: insights, labels: _labels()),
      ));

      // Current values
      expect(find.text('4'), findsOneWidget); // workouts
      expect(find.text('45'), findsOneWidget); // sets
      // Previous-value arrows (→ prev) — at least one per stat card.
      expect(find.textContaining('→'), findsNWidgets(4));
    });
  });
}
