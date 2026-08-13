// QA-WKT-004 — a day must never list the same exerciseId twice.
//
// The session player keys ALL progress by exerciseId, so two slots sharing an
// id collapse into one pool of logs (double-counted gating, the second slot's
// sets can't be logged). The editor blocks this on replace and on save; this
// pins the shared predicate that both paths use.
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/presentation/routine_editor_screen.dart';

void main() {
  group('dayHasDuplicateExerciseId', () {
    test('false for distinct ids', () {
      expect(dayHasDuplicateExerciseId(['a', 'b', 'c']), isFalse);
    });
    test('true when an id repeats (replace B -> A while A is already present)',
        () {
      expect(dayHasDuplicateExerciseId(['a', 'b', 'a']), isTrue);
    });
    test('false for a single exercise', () {
      expect(dayHasDuplicateExerciseId(['a']), isFalse);
    });
    test('false for an empty day', () {
      expect(dayHasDuplicateExerciseId(const <String>[]), isFalse);
    });
  });
}
