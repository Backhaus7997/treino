import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/performance/domain/performance_test.dart';
import 'package:treino/features/performance/presentation/widgets/performance_progress_chart.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

PerformanceTest _t(
  DateTime recordedAt, {
  double? cmjCm,
  double? squat1rmKg,
  double? sprint10mS,
}) =>
    PerformanceTest(
      id: 't_${recordedAt.millisecondsSinceEpoch}',
      athleteId: 'a1',
      recordedBy: 'coach1',
      recordedAt: recordedAt,
      cmjCm: cmjCm,
      squat1rmKg: squat1rmKg,
      sprint10mS: sprint10mS,
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
  group('PerformanceProgressChart', () {
    testWidgets(
        'renders the metric chip selector + line chart with ≥2 '
        'tests for the first plottable metric (CMJ)', (tester) async {
      final tests = [
        _t(DateTime(2026, 1, 1), cmjCm: 30),
        _t(DateTime(2026, 2, 1), cmjCm: 32),
      ];

      await tester.pumpWidget(_wrap(
        PerformanceProgressChart(tests: tests),
      ));
      await tester.pumpAndSettle();

      expect(find.text('PROGRESO'), findsOneWidget);
      expect(find.text('CMJ'), findsOneWidget);
      expect(find.byType(LineChart), findsOneWidget);
    });

    testWidgets('only offers metrics with ≥2 non-null data points as chips',
        (tester) async {
      final tests = [
        // cmjCm has 2 points, squat1rmKg only 1 → CMJ chip only.
        _t(DateTime(2026, 1, 1), cmjCm: 30, squat1rmKg: 100),
        _t(DateTime(2026, 2, 1), cmjCm: 32),
      ];

      await tester.pumpWidget(_wrap(
        PerformanceProgressChart(tests: tests),
      ));
      await tester.pumpAndSettle();

      expect(find.text('CMJ'), findsOneWidget);
      expect(find.text('Sentadilla 1RM'), findsNothing);
    });

    testWidgets('tapping a chip switches the plotted metric + header value',
        (tester) async {
      final tests = [
        _t(DateTime(2026, 1, 1), cmjCm: 30, squat1rmKg: 100),
        _t(DateTime(2026, 2, 1), cmjCm: 32, squat1rmKg: 105),
      ];

      await tester.pumpWidget(_wrap(
        PerformanceProgressChart(tests: tests),
      ));
      await tester.pumpAndSettle();

      // Default metric is the first plottable in preferred order (CMJ).
      expect(find.text('32'), findsOneWidget);

      await tester.tap(find.text('Sentadilla 1RM'));
      await tester.pumpAndSettle();

      expect(find.text('105'), findsOneWidget);
      expect(find.text('32'), findsNothing);
    });

    testWidgets(
        'shows the empty hint (not a crash) when no metric has ≥2 '
        'same-field values', (tester) async {
      final tests = [
        _t(DateTime(2026, 1, 1), cmjCm: 30),
        _t(DateTime(2026, 2, 1), squat1rmKg: 100),
      ];

      await tester.pumpWidget(_wrap(
        PerformanceProgressChart(tests: tests),
      ));
      await tester.pumpAndSettle();

      expect(find.text('PROGRESO'), findsOneWidget);
      expect(
        find.text('Cargá otra evaluación para ver el progreso.'),
        findsOneWidget,
      );
      expect(find.byType(LineChart), findsNothing);
    });

    testWidgets(
        'switching to a widget with different tests (didUpdateWidget) '
        'resets to a still-valid selection or falls back to the first metric',
        (tester) async {
      final first = [
        _t(DateTime(2026, 1, 1), cmjCm: 30, sprint10mS: 2.4),
        _t(DateTime(2026, 2, 1), cmjCm: 32, sprint10mS: 2.1),
      ];
      // New test set no longer has sprint10m data at all.
      final second = [
        _t(DateTime(2026, 3, 1), cmjCm: 34),
        _t(DateTime(2026, 4, 1), cmjCm: 35),
      ];

      await tester.pumpWidget(_wrap(
        PerformanceProgressChart(tests: first),
      ));
      await tester.pumpAndSettle();

      // CMJ's header value ('32') must be gone once Sprint 10m is selected.
      expect(find.text('32'), findsOneWidget);
      await tester.tap(find.text('Sprint 10m'));
      await tester.pumpAndSettle();
      expect(find.text('32'), findsNothing);

      await tester.pumpWidget(_wrap(
        PerformanceProgressChart(tests: second),
      ));
      await tester.pumpAndSettle();

      // 'Sprint 10m' chip is gone (no sprint10m data in the new set) —
      // selection must have reset to the first available metric (CMJ), not
      // crash.
      expect(find.text('Sprint 10m'), findsNothing);
      expect(find.text('CMJ'), findsOneWidget);
      expect(find.text('35'), findsOneWidget);
    });
  });
}
