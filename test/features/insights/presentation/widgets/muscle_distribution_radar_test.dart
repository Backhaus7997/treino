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
      const insights = MuscleDistributionInsights(
        currentSetsByAxis: {
          RadarAxis.chest: 10,
          RadarAxis.back: 8,
          RadarAxis.core: 4,
          RadarAxis.shoulders: 5,
          RadarAxis.arms: 6,
          RadarAxis.legs: 12,
        },
        previousSetsByAxis: {
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
      const insights = MuscleDistributionInsights(
        currentSetsByAxis: {RadarAxis.chest: 10},
        previousSetsByAxis: {RadarAxis.chest: 6},
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

    testWidgets(
        'axis titles are horizontal — the bottom one is NOT upside down',
        (tester) async {
      // Regression: `getTitle` pasaba el ángulo del EJE a RadarChartTitle, así
      // que cada etiqueta rotaba con su eje. La de abajo (HOMBROS, a 180°)
      // salía literalmente cabeza abajo e ilegible en pantalla.
      await tester.pumpWidget(_wrap(
        MuscleDistributionRadar(insights: _sample, labels: _labels()),
      ));

      final data = tester.widget<RadarChart>(find.byType(RadarChart)).data;

      for (var i = 0; i < RadarAxis.displayOrder.length; i++) {
        final title = data.getTitle!(i, 90.0 * i); // ángulo de eje arbitrario
        expect(
          title.angle,
          0,
          reason: 'la etiqueta "${title.text}" debe quedar horizontal, '
              'no rotada con su eje',
        );
      }
    });

    testWidgets('tick labels are hidden — they overlapped the polygon',
        (tester) async {
      // fl_chart apila las etiquetas de tick sobre el eje vertical DESDE EL
      // CENTRO, o sea encima del gráfico. `tickCount` no puede ser 0 (assert
      // >= 1), así que se ocultan por estilo.
      await tester.pumpWidget(_wrap(
        MuscleDistributionRadar(insights: _sample, labels: _labels()),
      ));

      final data = tester.widget<RadarChart>(find.byType(RadarChart)).data;
      expect(data.ticksTextStyle?.color, Colors.transparent);
    });

    testWidgets(
        'a 5-digit volume stays on ONE line and cards keep equal height',
        (tester) async {
      // Regression: '20770 kg' wrappeaba a dos líneas y estiraba SOLO esa card.
      const insights = MuscleDistributionInsights(
        currentSetsByAxis: {RadarAxis.chest: 10},
        previousSetsByAxis: {RadarAxis.chest: 6},
        currentWorkouts: 4,
        previousWorkouts: 8,
        currentDurationMin: 7,
        previousDurationMin: 61,
        currentVolumeKg: 20770,
        previousVolumeKg: 20655,
        currentSets: 72,
        previousSets: 178,
      );

      await tester.pumpWidget(_wrap(
        MuscleDistributionRadar(insights: insights, labels: _labels()),
      ));

      // Formato compacto: 20770 → '20.8k', no '20770'.
      expect(find.text('20.8k kg'), findsOneWidget);
      expect(find.text('20770 kg'), findsNothing);

      // Las 4 cards comparten altura (IntrinsicHeight + CrossAxisAlignment
      // .stretch). Se miden los RenderBox reales: si una wrappeara, su altura
      // se despegaría de las otras y el Set tendría más de un valor.
      final cardHeights = tester
          .renderObjectList<RenderBox>(find.descendant(
            of: find.byType(IntrinsicHeight),
            matching: find.byType(Container),
          ))
          .map((r) => r.size.height)
          .toSet();

      expect(cardHeights.length, 1,
          reason: 'las 4 stat cards deben tener exactamente la misma altura, '
              'pero se midieron: $cardHeights');
    });
  });
}

/// Sample con las 6 axes pobladas — para los tests que sólo miran el chart.
const _sample = MuscleDistributionInsights(
  currentSetsByAxis: {
    RadarAxis.chest: 10,
    RadarAxis.back: 8,
    RadarAxis.legs: 12,
    RadarAxis.shoulders: 5,
    RadarAxis.arms: 6,
    RadarAxis.core: 4,
  },
  previousSetsByAxis: {RadarAxis.chest: 6},
  currentWorkouts: 4,
  previousWorkouts: 3,
  currentDurationMin: 180,
  previousDurationMin: 150,
  currentVolumeKg: 4000,
  previousVolumeKg: 3500,
  currentSets: 45,
  previousSets: 30,
);
