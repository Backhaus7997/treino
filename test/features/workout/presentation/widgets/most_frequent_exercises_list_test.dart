import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/domain/chart_period.dart';
import 'package:treino/features/workout/domain/exercise_frequency.dart';
import 'package:treino/features/workout/presentation/widgets/exercise_progression_section.dart'
    show ChartPeriodLabels;
import 'package:treino/features/workout/presentation/widgets/most_frequent_exercises_list.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

MostFrequentExercisesListLabels _labels() => MostFrequentExercisesListLabels(
      sectionTitle: 'EJERCICIOS MÁS FRECUENTES',
      sessionCountLabel: (n) => n == 1 ? '1 sesión' : '$n sesiones',
      emptyText: 'No hay datos todavía.',
      periodLabels: const ChartPeriodLabels(
        last30dLabel: 'Últimos 30 días',
        thisWeekLabel: 'Esta semana',
        monthLabel: 'Este mes',
      ),
    );

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  testWidgets(
      'SCENARIO-FREQ-LIST-01: renders one row per entry, ordered as given',
      (tester) async {
    final entries = [
      const ExerciseFrequencyEntry(
          exerciseId: 'squat', exerciseName: 'Sentadilla', sessionCount: 8),
      const ExerciseFrequencyEntry(
          exerciseId: 'bench', exerciseName: 'Press banca', sessionCount: 5),
    ];

    await tester.pumpWidget(_wrap(MostFrequentExercisesList(
      entries: entries,
      selectedPeriod: ChartPeriod.defaultPeriod,
      labels: _labels(),
      onSelectExercise: (_) {},
      onSelectPeriod: (_) {},
    )));

    expect(find.text('EJERCICIOS MÁS FRECUENTES'), findsOneWidget);
    expect(find.text('Sentadilla'), findsOneWidget);
    expect(find.text('8 sesiones'), findsOneWidget);
    expect(find.text('Press banca'), findsOneWidget);
    expect(find.text('5 sesiones'), findsOneWidget);
  });

  testWidgets('SCENARIO-FREQ-LIST-02: empty entries shows empty state text',
      (tester) async {
    await tester.pumpWidget(_wrap(MostFrequentExercisesList(
      entries: const [],
      selectedPeriod: ChartPeriod.defaultPeriod,
      labels: _labels(),
      onSelectExercise: (_) {},
      onSelectPeriod: (_) {},
    )));

    expect(find.text('No hay datos todavía.'), findsOneWidget);
  });

  testWidgets('SCENARIO-FREQ-LIST-03: tapping a row invokes onSelectExercise',
      (tester) async {
    String? tapped;
    final entries = [
      const ExerciseFrequencyEntry(
          exerciseId: 'squat', exerciseName: 'Sentadilla', sessionCount: 8),
    ];

    await tester.pumpWidget(_wrap(MostFrequentExercisesList(
      entries: entries,
      selectedPeriod: ChartPeriod.defaultPeriod,
      labels: _labels(),
      onSelectExercise: (id) => tapped = id,
      onSelectPeriod: (_) {},
    )));

    await tester.tap(find.text('Sentadilla'));
    await tester.pump();

    expect(tapped, 'squat');
  });

  testWidgets(
      'SCENARIO-FREQ-LIST-04: renders period selector with 1 session text singular',
      (tester) async {
    final entries = [
      const ExerciseFrequencyEntry(
          exerciseId: 'squat', exerciseName: 'Sentadilla', sessionCount: 1),
    ];

    await tester.pumpWidget(_wrap(MostFrequentExercisesList(
      entries: entries,
      selectedPeriod: ChartPeriod.defaultPeriod,
      labels: _labels(),
      onSelectExercise: (_) {},
      onSelectPeriod: (_) {},
    )));

    expect(find.text('1 sesión'), findsOneWidget);
    expect(find.text('Últimos 30 días'), findsOneWidget);
  });
}
