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
      // Ambos períodos tienen ejes → ambos polígonos presentes.
      final data = tester.widget<RadarChart>(find.byType(RadarChart)).data;
      expect(data.dataSets.length, 2);
      // Legend renders both series labels.
      expect(find.text('Actual'), findsOneWidget);
      expect(find.text('Anterior'), findsOneWidget);
    });

    testWidgets(
        'previous period without axis data → its dataSet is omitted '
        '(no ghost hexagon), legend stays', (tester) async {
      // Regression #382: fl_chart normaliza contra el mínimo de TODOS los
      // datasets y ubica el centro en (min − tickSpace), así que el dataset
      // "Anterior" todo-en-cero se dibujaba como un hexágono chico sobre el
      // primer anillo — sugiriendo "un poco de todo" en un período que fue
      // cero entrenos.
      const insights = MuscleDistributionInsights(
        currentSetsByAxis: {
          RadarAxis.back: 8,
          RadarAxis.chest: 10,
          RadarAxis.core: 4,
          RadarAxis.shoulders: 5,
          RadarAxis.arms: 6,
          RadarAxis.legs: 12,
        },
        previousSetsByAxis: {},
        currentWorkouts: 4,
        previousWorkouts: 0,
        currentDurationMin: 180,
        previousDurationMin: 0,
        currentVolumeKg: 4000,
        previousVolumeKg: 0,
        currentSets: 45,
        previousSets: 0,
      );

      await tester.pumpWidget(_wrap(
        MuscleDistributionRadar(insights: insights, labels: _labels()),
      ));

      final data = tester.widget<RadarChart>(find.byType(RadarChart)).data;
      expect(data.dataSets.length, 1);
      // El dataset sobreviviente es el ACTUAL (borde 2.5, no el 2 del previo)
      // con los valores actuales en displayOrder.
      final survivor = data.dataSets.single;
      expect(survivor.borderWidth, 2.5);
      expect(
        survivor.dataEntries.map((e) => e.value).toList(),
        [8, 10, 4, 5, 6, 12],
      );
      // La leyenda "Anterior" queda (apagada) — el issue pide omitir el
      // polígono, no la referencia; las stat cards siguen mostrando "→ 0".
      expect(find.text('Anterior'), findsOneWidget);
    });

    testWidgets(
        'current period without axis data → its dataSet is omitted '
        '(mirrored ghost)', (tester) async {
      // Espejo de #382: usuario que entrenó el período pasado y dejó — el
      // dataset actual todo-en-cero dibujaba el mismo hexágono fantasma en
      // color accent.
      const insights = MuscleDistributionInsights(
        currentSetsByAxis: {},
        previousSetsByAxis: {RadarAxis.chest: 6, RadarAxis.legs: 3},
        currentWorkouts: 0,
        previousWorkouts: 2,
        currentDurationMin: 0,
        previousDurationMin: 90,
        currentVolumeKg: 0,
        previousVolumeKg: 1500,
        currentSets: 0,
        previousSets: 15,
      );

      await tester.pumpWidget(_wrap(
        MuscleDistributionRadar(insights: insights, labels: _labels()),
      ));

      final data = tester.widget<RadarChart>(find.byType(RadarChart)).data;
      expect(data.dataSets.length, 1);
      // Sobrevive el PREVIO (borde 2) con sus valores sparse → 0 en los ejes
      // ausentes, en displayOrder (back, chest, core, shoulders, arms, legs).
      final survivor = data.dataSets.single;
      expect(survivor.borderWidth, 2);
      expect(
        survivor.dataEntries.map((e) => e.value).toList(),
        [0, 6, 0, 0, 0, 3],
      );
    });

    testWidgets(
        'workouts but zero axis data in BOTH periods → single all-zero '
        'dataSet, chart survives a tap', (tester) async {
      // Edge cardio-only: cardio/full_body nunca llegan a MuscleGroupDisplay,
      // así que puede haber entrenos (isEmpty == false → el chart se muestra)
      // con ambos mapas byAxis vacíos. `dataSets: []` está prohibido: fl_chart
      // no pinta nada y su touch handler crashea (titleCount indexa
      // dataSets[0]) — se conserva el dataset actual todo-en-cero, que con
      // max == min == 0 sí colapsa al centro (sin hexágono fantasma).
      const insights = MuscleDistributionInsights(
        currentSetsByAxis: {},
        previousSetsByAxis: {},
        currentWorkouts: 2,
        previousWorkouts: 1,
        currentDurationMin: 60,
        previousDurationMin: 30,
        currentVolumeKg: 0,
        previousVolumeKg: 0,
        currentSets: 0,
        previousSets: 0,
      );

      await tester.pumpWidget(_wrap(
        MuscleDistributionRadar(insights: insights, labels: _labels()),
      ));

      final data = tester.widget<RadarChart>(find.byType(RadarChart)).data;
      expect(data.dataSets.length, 1);
      expect(
        data.dataSets.single.dataEntries.map((e) => e.value).toList(),
        [0, 0, 0, 0, 0, 0],
      );

      await tester.tap(find.byType(RadarChart), warnIfMissed: false);
      await tester.pump();
      expect(tester.takeException(), isNull);
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

      // Formato compacto compartido (formatVolumeKg): 20770 → '20.7k' —
      // floored, nunca redondea para arriba (#378).
      expect(find.text('20.7k kg'), findsOneWidget);
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

    testWidgets(
        'QA #370: la unidad del volumen queda visible en ancho de iPhone — '
        'el valor se achica, no se recorta', (tester) async {
      // 49 480 kg en "Últimos 30 días" (mesociclo normal de un intermedio):
      // con el ellipsis anterior la card mostraba "49.5k …" sin unidad.
      const insights = MuscleDistributionInsights(
        currentSetsByAxis: {RadarAxis.chest: 10},
        previousSetsByAxis: {RadarAxis.chest: 6},
        currentWorkouts: 22,
        previousWorkouts: 20,
        currentDurationMin: 1440,
        previousDurationMin: 1380,
        currentVolumeKg: 49480,
        previousVolumeKg: 13900,
        currentSets: 480,
        previousSets: 450,
      );

      // Ancho lógico de iPhone 14 Pro (393pt) — el device del reporte de QA.
      tester.view.physicalSize = const Size(393 * 3, 852 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(
        MuscleDistributionRadar(insights: insights, labels: _labels()),
      ));

      // Floored: 49 480 → '49.4k kg', y el string llega ENTERO al widget.
      final value = find.text('49.4k kg');
      expect(value, findsOneWidget);
      // El valor vive dentro de un FittedBox(scaleDown): si no entra en la
      // card se achica el font — un ellipsis acá volvía a comerse la unidad.
      expect(
        find.ancestor(of: value, matching: find.byType(FittedBox)),
        findsOneWidget,
      );
      expect(find.textContaining('→ 13.9k kg'), findsOneWidget);
      expect(tester.takeException(), isNull);
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
