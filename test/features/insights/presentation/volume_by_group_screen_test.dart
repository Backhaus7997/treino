import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/application/insights_providers.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';
import 'package:treino/features/insights/domain/weekly_insights.dart';
import 'package:treino/features/insights/presentation/volume_by_group_screen.dart';
import 'package:treino/features/workout/application/exercise_providers.dart';
import 'package:treino/features/workout/domain/exercise.dart';
import 'package:treino/l10n/app_l10n.dart';

/// [stats-hub] Dedicated "Volumen por grupo" screen — promoted from
/// InsightsScreen's inline `_VolumeBarCard` (obs #445). Same data
/// semantics: current week only, via [athleteWeekInsightsProvider].
void main() {
  Widget wrap(Widget child, {required List<Override> overrides}) =>
      ProviderScope(
        overrides: overrides,
        child: MaterialApp(
          theme: AppTheme.dark(),
          localizationsDelegates: AppL10n.localizationsDelegates,
          supportedLocales: AppL10n.supportedLocales,
          locale: const Locale('es', 'AR'),
          home: const Scaffold(body: VolumeByGroupScreen(uid: 'u1')),
        ),
      );

  testWidgets(
      'SCENARIO-VOLUME-SCREEN-01: renders per-group progress bars vs. '
      'target for the current week', (tester) async {
    final weekStart = mondayOfWeek(DateTime.now().toLocal());
    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
        athleteWeekInsightsProvider((uid: 'u1', weekStart: weekStart))
            .overrideWith((ref) async => WeeklyInsights(
                  weekStart: weekStart,
                  weekEnd: weekStart.add(const Duration(days: 6)),
                  daysTrained: List<bool>.filled(7, false),
                  sessionsCount: 2,
                  plannedSessionsCount: 5,
                  setsByGroup: const {MuscleGroupDisplay.pecho: 6},
                  targetByGroup: const {MuscleGroupDisplay.pecho: 10},
                )),
      ],
    ));
    await tester.pumpAndSettle();

    // Both the header title and the card's section title read
    // "VOLUMEN POR GRUPO" (same label bag) — 2 matches, not 1.
    expect(find.text('VOLUMEN POR GRUPO'), findsNWidgets(2));
    expect(find.text('PECHO'), findsOneWidget);
    expect(find.text('6 / 10 sets'), findsOneWidget);
  });

  testWidgets(
      'SCENARIO-VOLUME-SCREEN-02: shows the no-target hint when the '
      'athlete has no assigned routine target', (tester) async {
    final weekStart = mondayOfWeek(DateTime.now().toLocal());
    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
        athleteWeekInsightsProvider((uid: 'u1', weekStart: weekStart))
            .overrideWith((ref) async => WeeklyInsights(
                  weekStart: weekStart,
                  weekEnd: weekStart.add(const Duration(days: 6)),
                  daysTrained: List<bool>.filled(7, false),
                  sessionsCount: 0,
                  plannedSessionsCount: 5,
                  setsByGroup: const {},
                  targetByGroup: const {},
                )),
      ],
    ));
    await tester.pumpAndSettle();

    expect(
      find.text('Necesitás una rutina asignada para ver tu volumen objetivo.'),
      findsOneWidget,
    );
  });

  // QA-498 / #1825: `ref.invalidate` NO cascada, y `exercisesProvider` no es
  // autoDispose: invalidar solo la semana re-leía el MISMO error cacheado del
  // catálogo y el reintento no recuperaba nunca. El reintento tiene que
  // invalidar también el catálogo (`retryWeekInsights`).
  testWidgets(
      'el reintento invalida el catálogo: se recupera de un fallo en frío',
      (tester) async {
    final weekStart = mondayOfWeek(DateTime.now().toLocal());
    var lecturasDelCatalogo = 0;
    await tester.pumpWidget(wrap(
      const SizedBox.shrink(),
      overrides: [
        exercisesProvider.overrideWith((ref) async {
          lecturasDelCatalogo++;
          if (lecturasDelCatalogo == 1) throw StateError('catálogo sin red');
          return const <Exercise>[];
        }),
        // La semana depende del catálogo, como la real.
        athleteWeekInsightsProvider((uid: 'u1', weekStart: weekStart))
            .overrideWith((ref) async {
          await ref.watch(exercisesProvider.future);
          return WeeklyInsights(
            weekStart: weekStart,
            weekEnd: weekStart.add(const Duration(days: 6)),
            daysTrained: List<bool>.filled(7, false),
            sessionsCount: 2,
            plannedSessionsCount: 5,
            setsByGroup: const {MuscleGroupDisplay.pecho: 6},
            targetByGroup: const {MuscleGroupDisplay.pecho: 10},
          );
        }),
      ],
    ));
    await tester.pumpAndSettle();

    expect(find.text('Reintentar'), findsOneWidget);
    expect(find.text('6 / 10 sets'), findsNothing);

    await tester.tap(find.text('Reintentar'));
    await tester.pumpAndSettle();

    expect(lecturasDelCatalogo, 2,
        reason: 'reintentar tiene que volver a leer el catálogo');
    expect(find.text('Reintentar'), findsNothing);
    expect(find.text('6 / 10 sets'), findsOneWidget);
  });
}
