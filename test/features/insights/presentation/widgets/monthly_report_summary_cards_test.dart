import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/core/widgets/treino_icon.dart';
import 'package:treino/features/insights/domain/monthly_report.dart';
import 'package:treino/features/insights/presentation/widgets/monthly_report_summary_cards.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

MonthlyReportSummaryLabels _labels({
  String workoutsLabel = 'Entrenos',
  String durationLabel = 'Duración',
  String volumeLabel = 'Volumen',
  String setsLabel = 'Sets',
  String durationUnit = 'min',
  String volumeUnit = 'kg',
}) =>
    MonthlyReportSummaryLabels(
      workoutsLabel: workoutsLabel,
      durationLabel: durationLabel,
      volumeLabel: volumeLabel,
      setsLabel: setsLabel,
      durationUnit: durationUnit,
      volumeUnit: volumeUnit,
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

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('MonthlyReportSummaryCards', () {
    testWidgets('renders the 4 stats for the selected month', (tester) async {
      final selected = _pt(2026, 6,
          workoutsCount: 12, durationMin: 480, volumeKg: 12000, setsCount: 96);

      await tester.pumpWidget(_wrap(
        MonthlyReportSummaryCards(
          selectedMonth: selected,
          previousMonth: null,
          labels: _labels(),
        ),
      ));

      expect(find.text('12'), findsOneWidget);
      expect(find.text('480'), findsOneWidget);
      expect(find.text('12000'), findsOneWidget);
      expect(find.text('96'), findsOneWidget);
    });

    testWidgets('shows an up arrow when the metric increased vs previous',
        (tester) async {
      final selected = _pt(2026, 6, workoutsCount: 12);
      final previous = _pt(2026, 5, workoutsCount: 8);

      await tester.pumpWidget(_wrap(
        MonthlyReportSummaryCards(
          selectedMonth: selected,
          previousMonth: previous,
          labels: _labels(),
        ),
      ));

      expect(find.byIcon(TreinoIcon.trendUp), findsWidgets);
    });

    testWidgets('shows a down arrow when the metric decreased vs previous',
        (tester) async {
      final selected = _pt(2026, 6, workoutsCount: 4);
      final previous = _pt(2026, 5, workoutsCount: 8);

      await tester.pumpWidget(_wrap(
        MonthlyReportSummaryCards(
          selectedMonth: selected,
          previousMonth: previous,
          labels: _labels(),
        ),
      ));

      expect(find.byIcon(TreinoIcon.trendDown), findsWidgets);
    });

    testWidgets('shows no arrow when there is no previous month',
        (tester) async {
      final selected = _pt(2026, 6, workoutsCount: 12);

      await tester.pumpWidget(_wrap(
        MonthlyReportSummaryCards(
          selectedMonth: selected,
          previousMonth: null,
          labels: _labels(),
        ),
      ));

      expect(find.byIcon(TreinoIcon.trendUp), findsNothing);
      expect(find.byIcon(TreinoIcon.trendDown), findsNothing);
    });
  });
}
