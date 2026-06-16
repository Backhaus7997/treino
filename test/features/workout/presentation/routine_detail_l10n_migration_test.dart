import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/l10n/app_l10n.dart';
import 'package:treino/features/workout/application/routine_providers.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/presentation/routine_detail_screen.dart';

// Guards the AppL10n migration of RoutineDetailScreen: the screen must render
// the localized strings resolved from AppL10n — NOT hardcoded Spanish literals.
// Asserting against the l10n getters (rather than fixed text) means these tests
// keep passing if the copy is reworded in the ARB, but fail if a literal is
// reintroduced or a key is wired wrong.

/// Resolves AppL10n from the pumped tree so assertions use the same instance
/// the screen renders with (es-AR, the locale the app is locked to).
AppL10n _l10n(WidgetTester tester) =>
    AppL10n.of(tester.element(find.byType(RoutineDetailScreen)));

RoutineSlot _slot({String exerciseId = 'bench', int? supersetGroup}) =>
    RoutineSlot(
      exerciseId: exerciseId,
      exerciseName: 'Bench Press',
      muscleGroup: 'chest',
      targetSets: 4,
      targetRepsMin: 8,
      targetRepsMax: 12,
      restSeconds: 90,
      supersetGroup: supersetGroup,
    );

Routine _routine({List<RoutineDay>? days, String split = 'PPL'}) => Routine(
      id: 'rt',
      name: 'Plan',
      split: split,
      level: ExperienceLevel.beginner,
      days: days ??
          [
            RoutineDay(
              dayNumber: 1,
              name: 'Push',
              slots: [_slot()],
              estimatedMinutes: 45,
            ),
          ],
    );

Widget _wrap(List<Override> overrides) => ProviderScope(
      overrides: overrides,
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: const Scaffold(body: RoutineDetailScreen(routineId: 'rt')),
      ),
    );

void main() {
  group('RoutineDetailScreen AppL10n migration', () {
    testWidgets('badge uses routineDetailDayLabel + stat labels from AppL10n',
        (tester) async {
      await tester.pumpWidget(_wrap([
        routineByIdProvider('rt').overrideWith((ref) async => _routine()),
      ]));
      await tester.pump(const Duration(milliseconds: 50));
      final l10n = _l10n(tester);

      // Badge: "<SPLIT> · DÍA 1" composed from the localized day label.
      expect(
        find.text('PPL · ${l10n.routineDetailDayLabel(1)}'),
        findsOneWidget,
      );
      // Stat labels come from AppL10n, not literals.
      expect(find.text(l10n.routineDetailStatExercises),
          findsAtLeastNWidgets(1));
      expect(find.text(l10n.routineDetailStatSets), findsOneWidget);
      expect(find.text(l10n.routineDetailStatMinutes), findsOneWidget);
      // CTA label from AppL10n.
      expect(find.text(l10n.routineDetailStart), findsOneWidget);
    });

    testWidgets('not-found state uses routineDetailNotFound', (tester) async {
      await tester.pumpWidget(_wrap([
        routineByIdProvider('rt').overrideWith((ref) async => null),
      ]));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text(_l10n(tester).routineDetailNotFound), findsOneWidget);
    });

    testWidgets('empty-day state uses routineDetailNoExercisesThisDay',
        (tester) async {
      await tester.pumpWidget(_wrap([
        routineByIdProvider('rt').overrideWith(
          (ref) async => _routine(
            days: [const RoutineDay(dayNumber: 1, name: 'Push', slots: [])],
          ),
        ),
      ]));
      await tester.pump(const Duration(milliseconds: 50));
      expect(
        find.text(_l10n(tester).routineDetailNoExercisesThisDay),
        findsOneWidget,
      );
    });

    testWidgets('superset block header uses routineDetailSuperset',
        (tester) async {
      await tester.pumpWidget(_wrap([
        routineByIdProvider('rt').overrideWith(
          (ref) async => _routine(
            days: [
              RoutineDay(
                dayNumber: 1,
                name: 'Push',
                slots: [
                  _slot(exerciseId: 'bench', supersetGroup: 1),
                  _slot(exerciseId: 'fly', supersetGroup: 1),
                ],
                estimatedMinutes: 45,
              ),
            ],
          ),
        ),
      ]));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text(_l10n(tester).routineDetailSuperset), findsOneWidget);
    });
  });
}
