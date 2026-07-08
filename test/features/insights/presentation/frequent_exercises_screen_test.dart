import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/presentation/frequent_exercises_screen.dart';
import 'package:treino/features/insights/domain/chart_period.dart';
import 'package:treino/features/workout/application/exercise_frequency_providers.dart';
import 'package:treino/features/workout/domain/exercise_frequency.dart';
import 'package:treino/l10n/app_l10n.dart';

/// [stats-hub] Athlete-side "Ejercicios frecuentes" screen — reuses the
/// coach-only MostFrequentExercisesList widget with the athlete's OWN uid
/// (obs #445). Mirrors (inverted) the non-current-uid test pattern used
/// elsewhere in the app: here we assert the screen's OWN uid ('me') is the
/// one whose data renders, NOT some other athlete's uid ('other-athlete').
void main() {
  Widget wrap(Widget child, {required List<Override> overrides}) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(body: FrequentExercisesScreen(uid: 'me')),
        ),
      );

  testWidgets(
      'SCENARIO-FREQ-SCREEN-01: renders the OWN uid\'s frequency data (not '
      'another athlete\'s), proving the screen queries the athlete\'s own '
      'uid rather than a hardcoded/coach-selected uid', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
        exerciseFrequencyProvider((
          athleteUid: 'me',
          period: ChartPeriod.defaultPeriod,
        )).overrideWith((ref) async => const [
              ExerciseFrequencyEntry(
                exerciseId: 'e-press',
                exerciseName: 'Press Banca',
                sessionCount: 5,
              ),
            ]),
        // Different uid's data must NOT be the one rendered — proves the
        // screen is wired to 'me', not to this other athlete.
        exerciseFrequencyProvider((
          athleteUid: 'other-athlete',
          period: ChartPeriod.defaultPeriod,
        )).overrideWith((ref) async => const [
              ExerciseFrequencyEntry(
                exerciseId: 'e-squat',
                exerciseName: 'Sentadilla',
                sessionCount: 99,
              ),
            ]),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('EJERCICIOS FRECUENTES'), findsOneWidget);
    expect(find.text('Press Banca'), findsOneWidget);
    expect(find.text('Sentadilla'), findsNothing);
  });

  testWidgets(
      'SCENARIO-FREQ-SCREEN-02: tapping a row is a no-op (no navigation) — '
      'no athlete-side exercise progression destination exists yet',
      (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
        exerciseFrequencyProvider((
          athleteUid: 'me',
          period: ChartPeriod.defaultPeriod,
        )).overrideWith((ref) async => const [
              ExerciseFrequencyEntry(
                exerciseId: 'e-press',
                exerciseName: 'Press Banca',
                sessionCount: 5,
              ),
            ]),
      ],
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Press Banca'));
    await tester.pumpAndSettle();

    // Still on the same screen — no exception, no navigation happened.
    expect(tester.takeException(), isNull);
    expect(find.text('EJERCICIOS FRECUENTES'), findsOneWidget);
    expect(find.text('Press Banca'), findsOneWidget);
  });

  testWidgets(
      'SCENARIO-FREQ-SCREEN-03: switching the period selector re-fetches '
      'for the new period', (tester) async {
    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
        exerciseFrequencyProvider((
          athleteUid: 'me',
          period: ChartPeriod.defaultPeriod,
        )).overrideWith((ref) async => const [
              ExerciseFrequencyEntry(
                exerciseId: 'e-press',
                exerciseName: 'Press Banca',
                sessionCount: 5,
              ),
            ]),
        exerciseFrequencyProvider((
          athleteUid: 'me',
          period: ChartPeriod.thisWeek,
        )).overrideWith((ref) async => const [
              ExerciseFrequencyEntry(
                exerciseId: 'e-row',
                exerciseName: 'Remo',
                sessionCount: 2,
              ),
            ]),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Últimos 30 días'), findsOneWidget);
    expect(find.text('Press Banca'), findsOneWidget);

    await tester.tap(find.text('Últimos 30 días'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Esta semana').last);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Esta semana'), findsOneWidget);
    expect(find.text('Remo'), findsOneWidget);
  });
}
