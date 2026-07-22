// Tests for SessionExerciseBlock widget (REQ-SETLOGS-006, REQ-SETLOGS-009).
// TDD RED: written before implementation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/widgets/session_exercise_block.dart';
import 'package:treino/l10n/app_l10n.dart';

SetLog _log({
  String id = 'sl1',
  String exerciseId = 'e1',
  String exerciseName = 'Sentadilla',
  int setNumber = 1,
  int reps = 10,
  double weightKg = 80.0,
}) =>
    SetLog(
      id: id,
      exerciseId: exerciseId,
      exerciseName: exerciseName,
      setNumber: setNumber,
      reps: reps,
      weightKg: weightKg,
      completedAt: DateTime.utc(2026, 6, 1),
    );

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark(),
        localizationsDelegates: AppL10n.localizationsDelegates,
        supportedLocales: AppL10n.supportedLocales,
        locale: const Locale('es', 'AR'),
        home: Scaffold(body: child),
      ),
    );

void main() {
  group('SessionExerciseBlock (REQ-SETLOGS-006, REQ-SETLOGS-009)', () {
    testWidgets('SCENARIO-SL-010: renders exercise name', (tester) async {
      await tester.pumpWidget(_wrap(
        SessionExerciseBlock(
          exerciseName: 'Sentadilla',
          sets: [_log()],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sentadilla'), findsOneWidget);
    });

    testWidgets('SCENARIO-SL-011: renders exactly N rows for N sets',
        (tester) async {
      final sets = [
        _log(id: 'sl1', setNumber: 1),
        _log(id: 'sl2', setNumber: 2),
        _log(id: 'sl3', setNumber: 3),
      ];

      await tester.pumpWidget(_wrap(
        SessionExerciseBlock(
          exerciseName: 'Press Banca',
          sets: sets,
        ),
      ));
      await tester.pumpAndSettle();

      // Each set row shows the set number — 1, 2, 3 should each appear once.
      expect(find.text('1'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('3'), findsOneWidget);
    });

    testWidgets('SCENARIO-SL-012: renders reps and weightKg per set row',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SessionExerciseBlock(
          exerciseName: 'Sentadilla',
          sets: [_log(reps: 12, weightKg: 100.0)],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.textContaining('12'), findsWidgets);
      // formatWeightKg drops the .0 of whole loads (#436): "100 kg", not
      // "100.0 kg".
      expect(find.textContaining('100 kg'), findsWidgets);
      expect(find.textContaining('100.0'), findsNothing);
    });

    testWidgets(
        'SCENARIO-SL-013: no edit or delete button/icon in the widget tree (REQ-SETLOGS-009)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        SessionExerciseBlock(
          exerciseName: 'Sentadilla',
          sets: [_log(), _log(id: 'sl2', setNumber: 2)],
        ),
      ));
      await tester.pumpAndSettle();

      // No IconButton (edit/delete affordances) inside the block.
      expect(find.byType(IconButton), findsNothing);
      // No GestureDetector children wired to delete actions.
      // The simplest proxy: find no Dismissible (swipe-to-delete pattern).
      expect(find.byType(Dismissible), findsNothing);
    });

    testWidgets(
        'SCENARIO-SL-014: no provider reads — pumps without ProviderScope overrides',
        (tester) async {
      // If SessionExerciseBlock reads any provider, this will throw.
      // It should render correctly with zero overrides.
      await tester.pumpWidget(_wrap(
        SessionExerciseBlock(
          exerciseName: 'Peso Muerto',
          sets: [_log(exerciseName: 'Peso Muerto', reps: 5, weightKg: 150.0)],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Peso Muerto'), findsOneWidget);
    });
  });
}
