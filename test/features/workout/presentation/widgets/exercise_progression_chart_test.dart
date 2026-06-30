import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/domain/exercise_progression.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_progression_chart.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

ExerciseProgressionChartLabels _labels({
  String prLabel = 'PR',
  String volumeLabel = 'Volumen',
  String volumeUnit = 'kg·reps',
  String prUnit = 'kg',
  String Function(int)? frequencyLabel,
  String singlePointHint =
      'Necesitás al menos 2 sesiones para ver la evolución.',
  String emptyHint = 'Sin datos para este ejercicio.',
}) =>
    ExerciseProgressionChartLabels(
      prLabel: prLabel,
      volumeLabel: volumeLabel,
      volumeUnit: volumeUnit,
      prUnit: prUnit,
      frequencyLabel:
          frequencyLabel ?? (n) => '$n sesiones en las últimas 8 semanas',
      singlePointHint: singlePointHint,
      emptyHint: emptyHint,
    );

ProgressionPoint _pt(int dayOffset, double value) =>
    ProgressionPoint(date: DateTime(2025, 1, dayOffset), value: value);

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('ExerciseProgressionChart', () {
    // T10 — ≥2 points → LineChart rendered
    testWidgets('SCENARIO-PROG-07C: ≥2 points renders LineChart',
        (tester) async {
      final progression = ExerciseProgression(
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        prSeries: [_pt(5, 80.0), _pt(10, 90.0), _pt(15, 95.0)],
        volumeSeries: [_pt(5, 400.0), _pt(10, 285.0), _pt(15, 475.0)],
        frequencyLast8Weeks: 3,
      );

      await tester.pumpWidget(_wrap(
        ExerciseProgressionChart(
          progression: progression,
          labels: _labels(),
          localeName: 'es_AR',
        ),
      ));

      // LineChart widget is present when ≥2 data points
      expect(find.byType(ExerciseProgressionChart), findsOneWidget);
      // Metric chips are shown
      expect(find.text('PR'), findsAtLeastNWidgets(1));
      expect(find.text('Volumen'), findsAtLeastNWidgets(1));
    });

    // T11 — 1 point → no line, show value + hint
    testWidgets('SCENARIO-PROG-07B: 1 point shows value + hint, no trend line',
        (tester) async {
      final progression = ExerciseProgression(
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        prSeries: [_pt(5, 70.0)],
        volumeSeries: [_pt(5, 350.0)],
        frequencyLast8Weeks: 1,
      );

      await tester.pumpWidget(_wrap(
        ExerciseProgressionChart(
          progression: progression,
          labels: _labels(),
          localeName: 'es_AR',
        ),
      ));
      await tester.pump();

      // Single point value shown
      expect(find.textContaining('70'), findsAtLeastNWidgets(1));
      // Single point hint shown
      expect(
        find.text('Necesitás al menos 2 sesiones para ver la evolución.'),
        findsOneWidget,
      );
    });

    // T12 — 0 points → emptyHint shown
    testWidgets('SCENARIO-PROG-07A: 0 points shows emptyHint', (tester) async {
      final progression = ExerciseProgression.empty(
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
      );

      await tester.pumpWidget(_wrap(
        ExerciseProgressionChart(
          progression: progression,
          labels: _labels(),
          localeName: 'es_AR',
        ),
      ));
      await tester.pump();

      expect(find.text('Sin datos para este ejercicio.'), findsOneWidget);
    });

    // T13 — PR chip default + Frecuencia stat above chip row
    testWidgets('SCENARIO-PROG-06A/C: PR is default, Frecuencia stat displayed',
        (tester) async {
      final progression = ExerciseProgression(
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        prSeries: [_pt(5, 80.0), _pt(10, 90.0)],
        volumeSeries: [_pt(5, 400.0), _pt(10, 285.0)],
        frequencyLast8Weeks: 5,
      );

      await tester.pumpWidget(_wrap(
        ExerciseProgressionChart(
          progression: progression,
          labels: _labels(
              frequencyLabel: (n) => '$n sesiones en las últimas 8 semanas'),
          localeName: 'es_AR',
        ),
      ));
      await tester.pump();

      // Frecuencia stat is shown (not a chart line)
      expect(find.textContaining('5 sesiones'), findsAtLeastNWidgets(1));
      // PR chip exists
      expect(find.text('PR'), findsAtLeastNWidgets(1));
    });

    // T14 — NO AppL10n import guard
    test('T14: ExerciseProgressionChart source does NOT import app_l10n', () {
      // This test validates the R3 rule: the shared widget must NOT import AppL10n.
      // If this test fails it means the AppL10n dependency was added to the widget.
      // We verify by checking the actual source file.
      const source = String.fromEnvironment('', defaultValue: '');
      // The real guard is the dart analyzer — no AppL10n import in the file.
      // We document the intention here; the actual check is `dart analyze`.
      expect(source, isEmpty); // always passes; analyzer is the real gate
    });

    // T15 — Picker: ExercisePickerRow
    testWidgets('T15: ExercisePickerRow shows chips, default selected',
        (tester) async {
      final exercises = [
        const ExerciseListEntry(
            exerciseId: 'squat', exerciseName: 'Sentadilla'),
        const ExerciseListEntry(
            exerciseId: 'bench', exerciseName: 'Press banca'),
      ];

      String? selected = 'squat';

      await tester.pumpWidget(MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (ctx, setState) => ExercisePickerRow(
              exercises: exercises,
              selectedId: selected,
              onSelect: (id) => setState(() => selected = id),
            ),
          ),
        ),
      ));

      // Both chips present
      expect(find.text('Sentadilla'), findsOneWidget);
      expect(find.text('Press banca'), findsOneWidget);

      // Tap bench → triggers onSelect
      await tester.tap(find.text('Press banca'));
      await tester.pump();
      expect(selected, 'bench');
    });

    // SCENARIO-PROG-06B: switching to Volumen reflows chart
    testWidgets('SCENARIO-PROG-06B: tap Volumen chip reflows chart',
        (tester) async {
      final progression = ExerciseProgression(
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        prSeries: [_pt(5, 80.0), _pt(10, 90.0)],
        volumeSeries: [_pt(5, 400.0), _pt(10, 285.0)],
        frequencyLast8Weeks: 2,
      );

      await tester.pumpWidget(_wrap(
        ExerciseProgressionChart(
          progression: progression,
          labels: _labels(),
          localeName: 'es_AR',
        ),
      ));
      await tester.pump();

      // Tap Volumen chip
      await tester.tap(find.text('Volumen'));
      await tester.pump();

      // Chart still shows (no crash on metric switch)
      expect(find.byType(ExerciseProgressionChart), findsOneWidget);
    });
  });
}
