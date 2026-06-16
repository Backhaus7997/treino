import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/performance/domain/performance_test.dart';
import 'package:treino/features/performance/presentation/widgets/performance_progress_chart.dart';
import 'package:treino/l10n/app_l10n.dart';

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

PerformanceTest _test({
  required String id,
  required DateTime recordedAt,
  double? cmjCm,
  double? sprint20mS,
}) =>
    PerformanceTest(
      id: id,
      athleteId: 'athlete-1',
      recordedBy: 'trainer-1',
      recordedAt: recordedAt,
      cmjCm: cmjCm,
      sprint20mS: sprint20mS,
    );

void main() {
  group('PerformanceProgressChart — no plottable metric', () {
    testWidgets(
      'two tests filling DIFFERENT metrics → shows hint, no fake delta header',
      (tester) async {
        // tests.length == 2 (caller gate passes) but no single field has 2
        // non-null values, so no metric is plottable.
        final tests = <PerformanceTest>[
          _test(
            id: 't1',
            recordedAt: DateTime(2026, 1, 1),
            cmjCm: 32,
          ),
          _test(
            id: 't2',
            recordedAt: DateTime(2026, 2, 1),
            sprint20mS: 3.1,
          ),
        ];

        await tester.pumpWidget(_wrap(PerformanceProgressChart(tests: tests)));

        // The hint replaces the fabricated chart.
        expect(
          find.text('Cargá otra evaluación para ver el progreso.'),
          findsOneWidget,
        );

        // No fabricated "▲ 0.0 ..." delta header is rendered.
        expect(find.textContaining('▲ 0.0'), findsNothing);
        expect(find.textContaining('▼ 0.0'), findsNothing);
        // No CMJ fallback chip is shown.
        expect(find.text('CMJ'), findsNothing);
      },
    );

    testWidgets(
      'two tests with same metric ≥2 values → renders chart, no hint',
      (tester) async {
        final tests = <PerformanceTest>[
          _test(id: 't1', recordedAt: DateTime(2026, 1, 1), cmjCm: 30),
          _test(id: 't2', recordedAt: DateTime(2026, 2, 1), cmjCm: 34),
        ];

        await tester.pumpWidget(_wrap(PerformanceProgressChart(tests: tests)));

        expect(
          find.text('Cargá otra evaluación para ver el progreso.'),
          findsNothing,
        );
        // CMJ metric chip is available and selected.
        expect(find.text('CMJ'), findsOneWidget);
      },
    );
  });
}
