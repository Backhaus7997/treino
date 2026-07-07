import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/exercise_progression.dart';

void main() {
  group('ExerciseProgression', () {
    // [AD3] value object now carries 4 distinct client-computed series +
    // personalRecords, replacing the old prSeries/volumeSeries pair.
    test('SCENARIO-PROG-12A: value object is immutable and typed', () {
      final now = DateTime(2025, 1, 15);
      final progression = ExerciseProgression(
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        heaviestWeightSeries: [ProgressionPoint(date: now, value: 90.0)],
        oneRepMaxSeries: [ProgressionPoint(date: now, value: 103.0)],
        bestSetVolumeSeries: [ProgressionPoint(date: now, value: 450.0)],
        bestSessionVolumeSeries: [ProgressionPoint(date: now, value: 670.0)],
        personalRecords: [
          PersonalRecord(
            recordType: ProgressionRecordType.heaviestWeight,
            value: 90.0,
            achievedAt: now,
          ),
        ],
        frequencyLast8Weeks: 3,
      );

      // Typed access — no casting
      expect(progression.exerciseId, 'squat');
      expect(progression.exerciseName, 'Sentadilla');
      expect(progression.heaviestWeightSeries, isA<List<ProgressionPoint>>());
      expect(progression.oneRepMaxSeries, isA<List<ProgressionPoint>>());
      expect(progression.bestSetVolumeSeries, isA<List<ProgressionPoint>>());
      expect(
          progression.bestSessionVolumeSeries, isA<List<ProgressionPoint>>());
      expect(progression.personalRecords, isA<List<PersonalRecord>>());
      expect(progression.frequencyLast8Weeks, isA<int>());
      expect(progression.frequencyLast8Weeks, 3);
      expect(progression.heaviestWeightSeries.first.value, 90.0);
      expect(progression.oneRepMaxSeries.first.value, 103.0);
      expect(progression.bestSetVolumeSeries.first.value, 450.0);
      expect(progression.bestSessionVolumeSeries.first.value, 670.0);
      expect(progression.personalRecords.first.recordType,
          ProgressionRecordType.heaviestWeight);
    });

    test('ExerciseProgression.empty returns zeroed fields', () {
      final empty = ExerciseProgression.empty(
        exerciseId: 'bench',
        exerciseName: 'Press de banca',
      );
      expect(empty.heaviestWeightSeries, isEmpty);
      expect(empty.oneRepMaxSeries, isEmpty);
      expect(empty.bestSetVolumeSeries, isEmpty);
      expect(empty.bestSessionVolumeSeries, isEmpty);
      expect(empty.personalRecords, isEmpty);
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

    test('PersonalRecord carries recordType, value and achievedAt', () {
      final dt = DateTime(2025, 3, 1);
      final record = PersonalRecord(
        recordType: ProgressionRecordType.oneRepMax,
        value: 103.5,
        achievedAt: dt,
      );
      expect(record.recordType, ProgressionRecordType.oneRepMax);
      expect(record.value, 103.5);
      expect(record.achievedAt, dt);
    });

    test('copyWith produces distinct instance with updated fields', () {
      final now = DateTime(2025, 1, 15);
      final original = ExerciseProgression(
        exerciseId: 'squat',
        exerciseName: 'Sentadilla',
        heaviestWeightSeries: [ProgressionPoint(date: now, value: 90.0)],
        oneRepMaxSeries: const [],
        bestSetVolumeSeries: const [],
        bestSessionVolumeSeries: const [],
        personalRecords: const [],
        frequencyLast8Weeks: 2,
      );
      final updated = original.copyWith(frequencyLast8Weeks: 5);
      expect(updated.frequencyLast8Weeks, 5);
      expect(original.frequencyLast8Weeks, 2); // immutable
    });
  });
}
