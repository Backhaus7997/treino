import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/exercise_feedback.dart';
import 'package:treino/features/workout/domain/exercise_feedback_kind.dart';

ExerciseFeedback _feedback({
  String id = 'fb-1',
  String exerciseId = 'ex-bench',
  String exerciseName = 'Press banca',
  int slotIndex = 0,
  int? setNumber,
  ExerciseFeedbackKind kind = ExerciseFeedbackKind.comment,
  String? text = 'Me tiró el hombro',
  String? photoUrl,
  String? photoPath,
}) {
  return ExerciseFeedback(
    id: id,
    exerciseId: exerciseId,
    exerciseName: exerciseName,
    slotIndex: slotIndex,
    setNumber: setNumber,
    kind: kind,
    text: text,
    photoUrl: photoUrl,
    photoPath: photoPath,
    createdAt: DateTime.utc(2026, 8, 11, 15, 30),
  );
}

void main() {
  group('ExerciseFeedbackKind', () {
    test('wire values round-trip', () {
      for (final kind in ExerciseFeedbackKind.values) {
        expect(ExerciseFeedbackKindX.fromJson(kind.toJson()), kind);
      }
    });

    test('unknown wire value throws instead of silently defaulting', () {
      // A garbage kind must never reach the trainer's screen as a valid one.
      expect(
        () => ExerciseFeedbackKindX.fromJson('sarasa'),
        throwsArgumentError,
      );
    });

    test('only discomfort notifies the trainer', () {
      // A routine comment must not buzz the trainer's phone mid-session.
      expect(ExerciseFeedbackKind.discomfort.notifiesTrainer, isTrue);
      expect(ExerciseFeedbackKind.comment.notifiesTrainer, isFalse);
    });
  });

  group('ExerciseFeedback.hasContent', () {
    test('text only → true', () {
      expect(_feedback(text: 'Molestia').hasContent, isTrue);
    });

    test('photo only → true', () {
      expect(
        _feedback(
          text: null,
          photoUrl: 'https://example.test/p.jpg',
          photoPath: 'sessionFeedback/u/s/p.jpg',
        ).hasContent,
        isTrue,
      );
    });

    test('neither → false', () {
      expect(_feedback(text: null).hasContent, isFalse);
    });

    test('whitespace-only text → false', () {
      expect(_feedback(text: '   ').hasContent, isFalse);
    });
  });

  group('ExerciseFeedback.matchesSlot', () {
    test('same exerciseId AND slotIndex → true', () {
      expect(_feedback(slotIndex: 2).matchesSlot('ex-bench', 2), isTrue);
    });

    test('same exerciseId but different slotIndex → false', () {
      // The regression this field exists for: one exercise may appear twice in
      // a day, and a comment on the second block must not surface on the first.
      expect(_feedback(slotIndex: 2).matchesSlot('ex-bench', 0), isFalse);
    });

    test('different exerciseId → false', () {
      expect(_feedback(slotIndex: 0).matchesSlot('ex-squat', 0), isFalse);
    });
  });

  group('JSON', () {
    test('round-trips through fromJson/toJson', () {
      final original = _feedback(
        setNumber: 3,
        kind: ExerciseFeedbackKind.discomfort,
      );
      final decoded = ExerciseFeedback.fromJson(original.toJson());
      expect(decoded, original);
    });

    test('setNumber null survives the round-trip as exercise-level', () {
      final decoded = ExerciseFeedback.fromJson(_feedback().toJson());
      expect(decoded.setNumber, isNull);
    });

    test('createdAt serializes as a Firestore Timestamp', () {
      expect(_feedback().toJson()['createdAt'], isA<Timestamp>());
    });

    test('kind serializes to its wire string', () {
      final json = _feedback(kind: ExerciseFeedbackKind.discomfort).toJson();
      expect(json['kind'], 'discomfort');
    });
  });
}
