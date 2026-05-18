import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/set_log.dart';

void main() {
  group('SetLog', () {
    test('SCENARIO-237: SetLog JSON round-trip with optional rpe null', () {
      final completedAt = DateTime.utc(2026, 5, 18, 10, 5, 0);

      final setLog = SetLog(
        id: 'set-001',
        exerciseId: 'bench-press',
        exerciseName: 'Bench Press',
        setNumber: 1,
        reps: 10,
        weightKg: 80.0,
        rpe: null,
        completedAt: completedAt,
      );

      final json = setLog.toJson();
      final decoded = SetLog.fromJson(json);

      expect(decoded.id, equals('set-001'));
      expect(decoded.exerciseId, equals('bench-press'));
      expect(decoded.exerciseName, equals('Bench Press'));
      expect(decoded.setNumber, equals(1));
      expect(decoded.reps, equals(10));
      expect(decoded.weightKg, equals(80.0));
      expect(decoded.rpe, isNull);
      expect(decoded.completedAt, equals(completedAt));
      expect(decoded, equals(setLog));
    });

    test('SCENARIO-238: SetLog JSON round-trip with rpe present', () {
      final completedAt = DateTime.utc(2026, 5, 18, 10, 10, 0);

      final setLog = SetLog(
        id: 'set-002',
        exerciseId: 'back-squat',
        exerciseName: 'Back Squat',
        setNumber: 2,
        reps: 8,
        weightKg: 120.0,
        rpe: 8,
        completedAt: completedAt,
      );

      final json = setLog.toJson();
      final decoded = SetLog.fromJson(json);

      expect(decoded.rpe, equals(8));
      expect(decoded, equals(setLog));
    });

    test('SCENARIO-237b: weightKg fractional value round-trips correctly', () {
      final completedAt = DateTime.utc(2026, 5, 18, 10, 15, 0);

      final setLog = SetLog(
        id: 'set-003',
        exerciseId: 'deadlift',
        exerciseName: 'Deadlift',
        setNumber: 1,
        reps: 5,
        weightKg: 142.5,
        completedAt: completedAt,
      );

      final json = setLog.toJson();
      final decoded = SetLog.fromJson(json);

      expect(decoded.weightKg, equals(142.5));
    });

    test(
        'SCENARIO-237c: fromJson with Timestamp completedAt deserializes correctly',
        () {
      final completedAt = DateTime.utc(2026, 5, 18, 10, 20, 0);
      final rawMap = <String, dynamic>{
        'id': 'set-004',
        'exerciseId': 'overhead-press',
        'exerciseName': 'Overhead Press',
        'setNumber': 3,
        'reps': 8,
        'weightKg': 60.0,
        'rpe': null,
        'completedAt': Timestamp.fromDate(completedAt),
      };

      final decoded = SetLog.fromJson(rawMap);

      expect(decoded.id, equals('set-004'));
      expect(decoded.completedAt, equals(completedAt));
      expect(decoded.rpe, isNull);
    });
  });
}
