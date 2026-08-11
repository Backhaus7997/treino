import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';
import 'package:treino/features/workout/domain/exercise_feedback_kind.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/presentation/widgets/athlete_feedback_note.dart';
import 'package:treino/features/workout/presentation/widgets/session_exercise_block.dart';
import 'package:treino/l10n/app_l10n.dart';

SetLog _log(int setNumber) => SetLog(
      id: 'log-$setNumber',
      exerciseId: 'ex-bench',
      exerciseName: 'Press banca',
      setNumber: setNumber,
      reps: 10,
      weightKg: 60,
      completedAt: DateTime.utc(2026, 8, 11, 15),
    );

ExerciseFeedback _feedback({
  String id = 'fb-1',
  int? setNumber,
  ExerciseFeedbackKind kind = ExerciseFeedbackKind.comment,
  String text = 'Me tiró el hombro',
}) =>
    ExerciseFeedback(
      id: id,
      exerciseId: 'ex-bench',
      exerciseName: 'Press banca',
      slotIndex: 0,
      setNumber: setNumber,
      kind: kind,
      text: text,
      createdAt: DateTime.utc(2026, 8, 11, 15, 30),
    );

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: SingleChildScrollView(child: child)),
    );

void main() {
  group('SessionExerciseBlock feedback (issue #628)', () {
    testWidgets('renders the set rows unchanged when there is no feedback',
        (tester) async {
      // Default empty list keeps every existing call site working.
      await tester.pumpWidget(_wrap(SessionExerciseBlock(
        exerciseName: 'Press banca',
        sets: [_log(1), _log(2)],
      )));
      await tester.pump();

      expect(find.text('Press banca'), findsOneWidget);
      expect(find.textContaining('10 reps'), findsNWidgets(2));
      expect(find.byType(AthleteFeedbackNote), findsNothing);
    });

    testWidgets('renders the athlete feedback under the sets', (tester) async {
      await tester.pumpWidget(_wrap(SessionExerciseBlock(
        exerciseName: 'Press banca',
        sets: [_log(1)],
        feedback: [_feedback()],
      )));
      await tester.pump();

      expect(find.byType(AthleteFeedbackNote), findsOneWidget);
      expect(find.text('Me tiró el hombro'), findsOneWidget);
    });

    testWidgets('renders every entry for the exercise', (tester) async {
      await tester.pumpWidget(_wrap(SessionExerciseBlock(
        exerciseName: 'Press banca',
        sets: [_log(1)],
        feedback: [
          _feedback(id: 'fb-1', text: 'primero'),
          _feedback(id: 'fb-2', text: 'segundo'),
        ],
      )));
      await tester.pump();

      expect(find.byType(AthleteFeedbackNote), findsNWidgets(2));
    });

    testWidgets('a discomfort entry is visually distinct', (tester) async {
      await tester.pumpWidget(_wrap(SessionExerciseBlock(
        exerciseName: 'Press banca',
        sets: [_log(1)],
        feedback: [_feedback(kind: ExerciseFeedbackKind.discomfort)],
      )));
      await tester.pump();

      expect(find.text('MOLESTIA'), findsOneWidget);
    });

    testWidgets('the trainer view offers no delete affordance', (tester) async {
      // REQ: trainers may never mutate the athlete's data — not even feedback.
      await tester.pumpWidget(_wrap(SessionExerciseBlock(
        exerciseName: 'Press banca',
        sets: [_log(1)],
        feedback: [_feedback()],
      )));
      await tester.pump();

      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('shows the set anchor when the entry has one', (tester) async {
      await tester.pumpWidget(_wrap(SessionExerciseBlock(
        exerciseName: 'Press banca',
        sets: [_log(1), _log(2), _log(3)],
        feedback: [_feedback(setNumber: 3)],
      )));
      await tester.pump();

      expect(find.textContaining('Serie 3'), findsOneWidget);
    });
  });
}
