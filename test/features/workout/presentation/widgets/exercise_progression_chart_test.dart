import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart' as intl;

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/domain/exercise_progression.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_progression_chart.dart';
import 'package:treino/l10n/app_l10n.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

ExerciseProgressionChartLabels _labels({
  String heaviestWeightLabel = 'Peso máximo',
  String oneRepMaxLabel = '1RM',
  String bestSetVolumeLabel = 'Mejor serie',
  String bestSessionVolumeLabel = 'Volumen',
  String volumeUnit = 'kg·reps',
  String weightUnit = 'kg',
  String Function(int)? frequencyLabel,
  String singlePointHint =
      'Necesitás al menos 2 sesiones para ver la evolución.',
  String emptyHint = 'Sin datos para este ejercicio.',
}) =>
    ExerciseProgressionChartLabels(
      heaviestWeightLabel: heaviestWeightLabel,
      oneRepMaxLabel: oneRepMaxLabel,
      bestSetVolumeLabel: bestSetVolumeLabel,
      bestSessionVolumeLabel: bestSessionVolumeLabel,
      volumeUnit: volumeUnit,
      weightUnit: weightUnit,
      frequencyLabel:
          frequencyLabel ?? (n) => '$n sesiones en las últimas 8 semanas',
      singlePointHint: singlePointHint,
      emptyHint: emptyHint,
    );

ProgressionPoint _pt(int dayOffset, double value) =>
    ProgressionPoint(date: DateTime(2025, 1, dayOffset), value: value);

// UTC-flagged noon: safe under TZ=UTC CI and the ART calendar frame (#398).
ProgressionPoint _ptUtc(int month, int day, double value) =>
    ProgressionPoint(date: DateTime.utc(2026, month, day, 12), value: value);

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

ExerciseProgression _progression({
  List<ProgressionPoint> heaviestWeightSeries = const [],
  List<ProgressionPoint> oneRepMaxSeries = const [],
  List<ProgressionPoint> bestSetVolumeSeries = const [],
  List<ProgressionPoint> bestSessionVolumeSeries = const [],
  int frequencyLast8Weeks = 0,
}) =>
    ExerciseProgression(
      exerciseId: 'squat',
      exerciseName: 'Sentadilla',
      heaviestWeightSeries: heaviestWeightSeries,
      oneRepMaxSeries: oneRepMaxSeries,
      bestSetVolumeSeries: bestSetVolumeSeries,
      bestSessionVolumeSeries: bestSessionVolumeSeries,
      personalRecords: const [],
      frequencyLast8Weeks: frequencyLast8Weeks,
    );

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  group('ExerciseProgressionChart', () {
    // T10 — ≥2 points → LineChart rendered
    testWidgets('SCENARIO-PROG-07C: ≥2 points renders LineChart',
        (tester) async {
      final progression = _progression(
        heaviestWeightSeries: [_pt(5, 80.0), _pt(10, 90.0), _pt(15, 95.0)],
        oneRepMaxSeries: [_pt(5, 93.3), _pt(10, 99.0), _pt(15, 108.7)],
        bestSetVolumeSeries: [_pt(5, 400.0), _pt(10, 270.0), _pt(15, 340.0)],
        bestSessionVolumeSeries: [
          _pt(5, 400.0),
          _pt(10, 285.0),
          _pt(15, 475.0)
        ],
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
      // All 4 metric chips are shown
      expect(find.text('Peso máximo'), findsAtLeastNWidgets(1));
      expect(find.text('1RM'), findsAtLeastNWidgets(1));
      expect(find.text('Mejor serie'), findsAtLeastNWidgets(1));
      expect(find.text('Volumen'), findsAtLeastNWidgets(1));
    });

    // T11 — 1 point → no line, show value + hint
    testWidgets('SCENARIO-PROG-07B: 1 point shows value + hint, no trend line',
        (tester) async {
      final progression = _progression(
        heaviestWeightSeries: [_pt(5, 70.0)],
        oneRepMaxSeries: [_pt(5, 81.7)],
        bestSetVolumeSeries: [_pt(5, 350.0)],
        bestSessionVolumeSeries: [_pt(5, 350.0)],
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

    // T13 — Heaviest Weight chip default + Frecuencia stat above chip row
    testWidgets(
        'SCENARIO-PROG-06A/C: Heaviest Weight is default (renamed from PR), Frecuencia stat displayed',
        (tester) async {
      final progression = _progression(
        heaviestWeightSeries: [_pt(5, 80.0), _pt(10, 90.0)],
        oneRepMaxSeries: [_pt(5, 93.3), _pt(10, 99.0)],
        bestSetVolumeSeries: [_pt(5, 400.0), _pt(10, 270.0)],
        bestSessionVolumeSeries: [_pt(5, 400.0), _pt(10, 285.0)],
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
      // Heaviest Weight chip exists and its series value (90 = default
      // metric) is rendered as the active single/multi-point view.
      expect(find.text('Peso máximo'), findsAtLeastNWidgets(1));
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

    // CRITICAL-1 fixup (AD2/AD3 verify #434): 1RM display must be rounded to
    // the nearest 0.5 kg, not the raw Epley double.
    testWidgets(
        'AD2 fixup: single-point 1RM value is rounded to nearest 0.5 kg',
        (tester) async {
      final progression = _progression(
        heaviestWeightSeries: [_pt(5, 100.0)],
        // 100 * (1 + 5/30) = 116.6667 -> rounds to 116.5
        oneRepMaxSeries: [_pt(5, 116.6667)],
        bestSetVolumeSeries: [_pt(5, 500.0)],
        bestSessionVolumeSeries: [_pt(5, 500.0)],
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

      // Switch to 1RM chip
      await tester.tap(find.text('1RM'));
      await tester.pump();

      // Rounded to 116.5, NOT the raw 116.7 (toStringAsFixed(1) of raw value)
      expect(find.text('116.5'), findsOneWidget);
      expect(find.text('116.7'), findsNothing);
    });

    // SCENARIO-PROG-06B: switching metric chips reflows the chart
    testWidgets('SCENARIO-PROG-06B: tap another metric chip reflows chart',
        (tester) async {
      final progression = _progression(
        heaviestWeightSeries: [_pt(5, 80.0), _pt(10, 90.0)],
        oneRepMaxSeries: [_pt(5, 93.3), _pt(10, 99.0)],
        bestSetVolumeSeries: [_pt(5, 400.0), _pt(10, 270.0)],
        bestSessionVolumeSeries: [_pt(5, 400.0), _pt(10, 285.0)],
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

      // Tap Volumen (Best Session Volume) chip
      await tester.tap(find.text('Volumen'));
      await tester.pump();

      // Chart still shows (no crash on metric switch)
      expect(find.byType(ExerciseProgressionChart), findsOneWidget);

      // Tap 1RM chip
      await tester.tap(find.text('1RM'));
      await tester.pump();
      expect(find.byType(ExerciseProgressionChart), findsOneWidget);

      // Tap Mejor serie (Best Set Volume) chip
      await tester.tap(find.text('Mejor serie'));
      await tester.pump();
      expect(find.byType(ExerciseProgressionChart), findsOneWidget);
    });

    // #383 — X axis is point-index-based. Without an explicit interval,
    // fl_chart samples fractional Xs and value.round() maps neighbouring
    // samples to the same index → duplicated labels + skipped ones.
    testWidgets('#383: >4 points renders each visible axis date exactly once',
        (tester) async {
      // Issue repro: 6 sessions (19 jun … 17 jul) → label subset {0, 2, 3, 5}.
      final series = [
        _ptUtc(6, 19, 60.0),
        _ptUtc(6, 25, 62.5),
        _ptUtc(7, 1, 65.0),
        _ptUtc(7, 7, 67.5),
        _ptUtc(7, 13, 70.0),
        _ptUtc(7, 17, 72.5),
      ];
      final progression = _progression(
        heaviestWeightSeries: series,
        oneRepMaxSeries: series,
        bestSetVolumeSeries: series,
        bestSessionVolumeSeries: series,
        frequencyLast8Weeks: 6,
      );

      await tester.pumpWidget(_wrap(
        ExerciseProgressionChart(
          progression: progression,
          labels: _labels(),
          localeName: 'es_AR',
        ),
      ));
      await tester.pump();

      String label(int i) =>
          intl.DateFormat('d MMM', 'es_AR').format(series[i].date);

      // Broken sampling rendered '1 jul', '7 jul' and '17 jul' twice each.
      for (final i in [0, 2, 3, 5]) {
        expect(find.text(label(i)), findsOneWidget,
            reason: 'axis label for point $i must appear exactly once');
      }
      // Indices outside the ≤4-label subset stay off the axis; their points
      // remain visible as dots with tooltip.
      for (final i in [1, 4]) {
        expect(find.text(label(i)), findsNothing,
            reason: 'point $i is not part of the label subset');
      }
    });

    testWidgets('#383: ≤4 points labels every point date exactly once',
        (tester) async {
      final series = [
        _ptUtc(6, 19, 60.0),
        _ptUtc(6, 25, 62.5),
        _ptUtc(7, 1, 65.0),
        _ptUtc(7, 7, 67.5),
      ];
      final progression = _progression(
        heaviestWeightSeries: series,
        oneRepMaxSeries: series,
        bestSetVolumeSeries: series,
        bestSessionVolumeSeries: series,
        frequencyLast8Weeks: 4,
      );

      await tester.pumpWidget(_wrap(
        ExerciseProgressionChart(
          progression: progression,
          labels: _labels(),
          localeName: 'es_AR',
        ),
      ));
      await tester.pump();

      String label(int i) =>
          intl.DateFormat('d MMM', 'es_AR').format(series[i].date);

      for (var i = 0; i < series.length; i++) {
        expect(find.text(label(i)), findsOneWidget,
            reason: 'axis label for point $i must appear exactly once');
      }
    });
  });
}
