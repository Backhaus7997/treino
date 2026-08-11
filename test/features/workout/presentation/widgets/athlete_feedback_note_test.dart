import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/app/theme/app_theme.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';
import 'package:treino/features/workout/domain/exercise_feedback_kind.dart';
import 'package:treino/features/workout/presentation/widgets/athlete_feedback_note.dart';
import 'package:treino/l10n/app_l10n.dart';

ExerciseFeedback _feedback({
  int? setNumber,
  ExerciseFeedbackKind kind = ExerciseFeedbackKind.comment,
  String? text = 'Me tiró el hombro derecho',
  String? photoUrl,
}) {
  return ExerciseFeedback(
    id: 'fb-1',
    exerciseId: 'ex-bench',
    exerciseName: 'Press banca',
    slotIndex: 0,
    setNumber: setNumber,
    kind: kind,
    text: text,
    photoUrl: photoUrl,
    photoPath: photoUrl == null ? null : 'sessionFeedback/u/s/p.jpg',
    createdAt: DateTime.utc(2026, 8, 11, 15, 30),
  );
}

Widget _wrap(Widget child) => MaterialApp(
      theme: AppTheme.dark(),
      localizationsDelegates: AppL10n.localizationsDelegates,
      supportedLocales: AppL10n.supportedLocales,
      locale: const Locale('es', 'AR'),
      home: Scaffold(body: child),
    );

void main() {
  group('AthleteFeedbackNote', () {
    testWidgets('renders the athlete text', (tester) async {
      await tester
          .pumpWidget(_wrap(AthleteFeedbackNote(feedback: _feedback())));
      await tester.pump();

      expect(find.text('Me tiró el hombro derecho'), findsOneWidget);
    });

    testWidgets('a comment carries the DEL ALUMNO tag', (tester) async {
      await tester
          .pumpWidget(_wrap(AthleteFeedbackNote(feedback: _feedback())));
      await tester.pump();

      expect(find.text('DEL ALUMNO'), findsOneWidget);
      expect(find.text('MOLESTIA'), findsNothing);
    });

    testWidgets('discomfort is tagged distinctly from a comment',
        (tester) async {
      // The trainer scans a long session; a pain report has to stand out.
      await tester.pumpWidget(_wrap(AthleteFeedbackNote(
        feedback: _feedback(kind: ExerciseFeedbackKind.discomfort),
      )));
      await tester.pump();

      expect(find.text('MOLESTIA'), findsOneWidget);
      expect(find.text('DEL ALUMNO'), findsNothing);
    });

    testWidgets('anchors to the set when setNumber is present', (tester) async {
      // "Serie 3" is exactly what the chat cannot express.
      await tester.pumpWidget(_wrap(AthleteFeedbackNote(
        feedback: _feedback(setNumber: 3),
      )));
      await tester.pump();

      expect(find.textContaining('Serie 3'), findsOneWidget);
    });

    testWidgets('exercise-level entry shows no set label', (tester) async {
      await tester
          .pumpWidget(_wrap(AthleteFeedbackNote(feedback: _feedback())));
      await tester.pump();

      expect(find.textContaining('Serie'), findsNothing);
    });

    testWidgets('renders nothing when the entry has no content',
        (tester) async {
      // A malformed doc that slipped past the rules degrades to absence, not an
      // empty card.
      await tester.pumpWidget(_wrap(AthleteFeedbackNote(
        feedback: _feedback(text: null),
      )));
      await tester.pump();

      expect(find.byType(SizedBox), findsWidgets);
      expect(find.text('DEL ALUMNO'), findsNothing);
    });

    testWidgets('no delete affordance when onDelete is null', (tester) async {
      // The trainer's view is strictly read-only.
      await tester
          .pumpWidget(_wrap(AthleteFeedbackNote(feedback: _feedback())));
      await tester.pump();

      expect(find.byIcon(Icons.close), findsNothing);
    });

    testWidgets('delete affordance fires the callback', (tester) async {
      var deleted = false;
      await tester.pumpWidget(_wrap(AthleteFeedbackNote(
        feedback: _feedback(),
        onDelete: () => deleted = true,
      )));
      await tester.pump();

      await tester.tap(find.byIcon(Icons.close));
      await tester.pump();

      expect(deleted, isTrue);
    });

    testWidgets('delete target meets the 44pt a11y floor', (tester) async {
      await tester.pumpWidget(_wrap(AthleteFeedbackNote(
        feedback: _feedback(),
        onDelete: () {},
      )));
      await tester.pump();

      final size = tester.getSize(find
          .ancestor(
            of: find.byIcon(Icons.close),
            matching: find.byType(SizedBox),
          )
          .first);
      expect(size.width, greaterThanOrEqualTo(44));
      expect(size.height, greaterThanOrEqualTo(44));
    });
  });
}
