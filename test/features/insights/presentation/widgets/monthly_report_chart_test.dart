import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/domain/monthly_report.dart';
import 'package:treino/features/insights/presentation/widgets/monthly_report_chart.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

MonthlyReportChartLabels _labels({
  String workoutsLabel = 'Entrenos',
  String durationLabel = 'Duración',
  String volumeLabel = 'Volumen',
  String setsLabel = 'Sets',
  String emptyHint = 'Sin datos en los últimos 12 meses.',
}) =>
    MonthlyReportChartLabels(
      workoutsLabel: workoutsLabel,
      durationLabel: durationLabel,
      volumeLabel: volumeLabel,
      setsLabel: setsLabel,
      emptyHint: emptyHint,
    );

MonthlyReport _report12({int Function(int index)? workoutsCountAt}) {
  final points = List.generate(12, (i) {
    final month = DateTime(2025, 6 + i, 1);
    return MonthlyReportPoint(
      month: DateTime(month.year, month.month, 1),
      workoutsCount: workoutsCountAt != null ? workoutsCountAt(i) : 0,
      durationMin: 0,
      volumeKg: 0,
      setsCount: 0,
    );
  });
  return MonthlyReport(points: points);
}

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('MonthlyReportChart', () {
    testWidgets('renders empty hint when all 12 months are zero',
        (tester) async {
      await tester.pumpWidget(_wrap(
        MonthlyReportChart(
          report: _report12(),
          labels: _labels(),
          localeName: 'es_AR',
        ),
      ));

      expect(find.text('Sin datos en los últimos 12 meses.'), findsOneWidget);
    });

    testWidgets('renders bar chart + 4 metric chips when data exists',
        (tester) async {
      await tester.pumpWidget(_wrap(
        MonthlyReportChart(
          report: _report12(workoutsCountAt: (i) => i == 11 ? 5 : 0),
          labels: _labels(),
          localeName: 'es_AR',
        ),
      ));

      expect(find.text('Entrenos'), findsOneWidget);
      expect(find.text('Duración'), findsOneWidget);
      expect(find.text('Volumen'), findsOneWidget);
      expect(find.text('Sets'), findsOneWidget);
      expect(find.text('Sin datos en los últimos 12 meses.'), findsNothing);
    });

    testWidgets('Workouts chip selected by default', (tester) async {
      await tester.pumpWidget(_wrap(
        MonthlyReportChart(
          report: _report12(workoutsCountAt: (i) => i == 11 ? 5 : 0),
          labels: _labels(),
          localeName: 'es_AR',
        ),
      ));

      final state = tester.state<MonthlyReportChartState>(
        find.byType(MonthlyReportChart),
      );
      expect(state.selectedMetric, MonthlyReportMetric.workouts);
    });

    testWidgets('tapping a chip switches the plotted metric', (tester) async {
      await tester.pumpWidget(_wrap(
        MonthlyReportChart(
          report: _report12(workoutsCountAt: (i) => i == 11 ? 5 : 0),
          labels: _labels(),
          localeName: 'es_AR',
        ),
      ));

      await tester.tap(find.text('Volumen'));
      await tester.pump();

      final state = tester.state<MonthlyReportChartState>(
        find.byType(MonthlyReportChart),
      );
      expect(state.selectedMetric, MonthlyReportMetric.volume);
    });

    testWidgets('onMonthSelected fires with the tapped month', (tester) async {
      DateTime? tapped;
      await tester.pumpWidget(_wrap(
        MonthlyReportChart(
          report: _report12(workoutsCountAt: (i) => i == 11 ? 5 : 0),
          labels: _labels(),
          localeName: 'es_AR',
          onMonthSelected: (m) => tapped = m,
        ),
      ));

      final state = tester.state<MonthlyReportChartState>(
        find.byType(MonthlyReportChart),
      );
      // Simulate a bar-touch callback directly (fl_chart's gesture layer is
      // not easily driven from widget tests) — verify the wiring reaches
      // the widget's public callback contract.
      state.debugSelectMonth(state.widget.report.points.last.month);
      expect(tapped, state.widget.report.points.last.month);
    });

    // El CLDR de es-AR devuelve 'sept' (4 chars) para septiembre — el resto de
    // los meses da 3. En un eje de 12 barras ese label desentona, así que el
    // chart va por `monthAbbrev`, que trunca. Si alguien vuelve a un
    // `DateFormat('MMM')` pelado, este test lo frena.
    testWidgets('el eje abrevia septiembre a 3 chars', (tester) async {
      await tester.pumpWidget(_wrap(
        MonthlyReportChart(
          // _report12 arranca en junio 2025 → el índice 3 es septiembre.
          report: _report12(workoutsCountAt: (i) => i + 1),
          labels: _labels(),
          localeName: 'es_AR',
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('sep'), findsOneWidget);
      expect(find.text('sept'), findsNothing);
    });
  });

  group('DailyDurationChart', () {
    // Julio 2026 completo — 31 días, con entrenos alternados para que el
    // chart tenga barras reales (31 × 26px = 806px de contenido scrolleable).
    List<MonthlyReportDayPoint> july31() => List.generate(
          31,
          (i) => MonthlyReportDayPoint(
            day: DateTime(2026, 7, i + 1),
            durationMin: i.isEven ? 45 : 0,
          ),
        );

    Widget chart() => DailyDurationChart(
          points: july31(),
          emptyHint: 'Sin entrenos este mes.',
          dayLabel: 'Día',
          minutesUnit: 'min',
        );

    List<int> showingTooltipsAt(WidgetTester tester, int index) => tester
        .widget<BarChart>(find.byType(BarChart))
        .data
        .barGroups[index]
        .showingTooltipIndicators;

    testWidgets('el drag horizontal SOBRE las barras desplaza el scroll (#369)',
        (tester) async {
      // Viewport angosto tipo iPhone (400 lógicos) — como en el reporte del
      // bug, entran ~14 de los 31 días y el resto queda detrás del scroll.
      tester.view.physicalSize = const Size(1200, 2400);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(_wrap(chart()));
      await tester.pumpAndSettle();

      final scrollable = find.descendant(
        of: find.byType(DailyDurationChart),
        matching: find.byType(Scrollable),
      );
      final position = tester.state<ScrollableState>(scrollable).position;
      expect(position.pixels, 0);

      // Swipe real de usuario sobre el área de barras, en dos moves:
      // 1. -60px en UN evento — reproduce el bug: supera el pan slop de
      //    fl_chart (36px) en un solo move, y ese recognizer (registrado
      //    antes) acepta el arena antes de que el HorizontalDrag del
      //    SingleChildScrollView (slop 18px) vea el movimiento. `tester.drag()`
      //    cruza el slop en pasos chicos y NO reproduce la pérdida del arena.
      // 2. -140px — el desplazamiento observable: con DragStartBehavior.start
      //    el scrollable absorbe el delta previo a la aceptación, así que el
      //    scroll real lo producen los moves POSTERIORES, como en un swipe
      //    de verdad.
      // Ojo: NO usar getCenter(BarChart) — el chart mide 806px y su centro
      // (x≈417) cae fuera del viewport de 400; el pointer debe arrancar sobre
      // barras VISIBLES.
      final gesture = await tester.startGesture(
        Offset(200, tester.getCenter(find.byType(BarChart)).dy),
      );
      await gesture.moveBy(const Offset(-60, 0));
      await gesture.moveBy(const Offset(-140, 0));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(position.pixels, greaterThan(0));

      // Y el drag NO tiene que dejar un tooltip seleccionado de rebote.
      for (var i = 0; i < 31; i++) {
        expect(showingTooltipsAt(tester, i), isEmpty);
      }
    });

    testWidgets(
        'tap sobre la columna de un día muestra su tooltip y re-tap '
        'lo oculta', (tester) async {
      await tester.pumpWidget(_wrap(chart()));
      await tester.pumpAndSettle();

      // Columna del día 3 (índice 2): centro de la ranura de 26px.
      final chartTopLeft = tester.getTopLeft(find.byType(BarChart));
      final day3Column = chartTopLeft + const Offset(2 * 26 + 13, 100);

      await tester.tapAt(day3Column);
      await tester.pumpAndSettle();
      expect(showingTooltipsAt(tester, 2), const [0]);

      // Tap en OTRA columna mueve el tooltip (día 6, índice 5).
      await tester.tapAt(chartTopLeft + const Offset(5 * 26 + 13, 100));
      await tester.pumpAndSettle();
      expect(showingTooltipsAt(tester, 2), isEmpty);
      expect(showingTooltipsAt(tester, 5), const [0]);

      // Re-tap sobre la misma columna lo apaga (toggle).
      await tester.tapAt(chartTopLeft + const Offset(5 * 26 + 13, 100));
      await tester.pumpAndSettle();
      expect(showingTooltipsAt(tester, 5), isEmpty);
    });
  });
}
