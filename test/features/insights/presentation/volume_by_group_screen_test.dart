import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/insights/application/insights_providers.dart';
import 'package:treino/features/insights/domain/muscle_group.dart';
import 'package:treino/features/insights/domain/weekly_insights.dart';
import 'package:treino/features/insights/presentation/volume_by_group_screen.dart';
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
}
