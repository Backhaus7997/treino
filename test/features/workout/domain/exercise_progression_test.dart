import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/exercise_progression.dart';

void main() {
  group('ExerciseProgression', () {
    test('SCENARIO-PROG-12A: value object is immutable and typed', () {
      final now = DateTime(2025, 1, 15);
      final progression = ExerciseProgression(
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        prSeries: [ProgressionPoint(date: now, value: 90.0)],
        volumeSeries: [ProgressionPoint(date: now, value: 670.0)],
        frequencyLast8Weeks: 3,
      );

      // Typed access — no casting
      expect(progression.exerciseId, 'squat');
      expect(progression.exerciseName, 'Sentadilla');
      expect(progression.prSeries, isA<List<ProgressionPoint>>());
      expect(progression.volumeSeries, isA<List<ProgressionPoint>>());
      expect(progression.frequencyLast8Weeks, isA<int>());
      expect(progression.frequencyLast8Weeks, 3);
      expect(progression.prSeries.first.value, 90.0);
      expect(progression.volumeSeries.first.value, 670.0);
    });

    test('ExerciseProgression.empty returns zeroed fields', () {
      final empty = ExerciseProgression.empty(
        exerciseId: 'bench',
        exerciseName: 'Press de banca',
      );
      expect(empty.prSeries, isEmpty);
      expect(empty.volumeSeries, isEmpty);
      expect(empty.frequencyLast8Weeks, 0);
    });

    test('ProgressionPoint preserves date and value', () {
      final dt = DateTime(2025, 6, 1);
      final pt = ProgressionPoint(date: dt, value: 42.5);
      expect(pt.date, dt);
      expect(pt.value, 42.5);
    });

    test('ExerciseListEntry carries exerciseId and exerciseName', () {
      const entry = ExerciseListEntry(
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
      );
      expect(entry.exerciseId, 'squat');
      expect(entry.exerciseName, 'Sentadilla');
    });

    test('copyWith produces distinct instance with updated fields', () {
      final now = DateTime(2025, 1, 15);
      final original = ExerciseProgression(
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        prSeries: [ProgressionPoint(date: now, value: 90.0)],
        volumeSeries: [],
        frequencyLast8Weeks: 2,
      );
      final updated = original.copyWith(frequencyLast8Weeks: 5);
      expect(updated.frequencyLast8Weeks, 5);
      expect(original.frequencyLast8Weeks, 2); // immutable
    });
  });
}
