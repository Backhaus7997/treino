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

MonthlyReportPoint _pt(
  int year,
  int month, {
  int workoutsCount = 0,
  int durationMin = 0,
  double volumeKg = 0,
  int setsCount = 0,
}) =>
    MonthlyReportPoint(
      month: DateTime(year, month, 1),
      workoutsCount: workoutsCount,
      durationMin: durationMin,
      volumeKg: volumeKg,
      setsCount: setsCount,
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
  });
}
