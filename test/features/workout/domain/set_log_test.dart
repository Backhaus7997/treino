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

    // ── #1701: métrica de las series por tiempo / distancia ────────────────
    group('durationSeconds / distanceMeters (#1701)', () {
      SetLog base({int? durationSeconds, double? distanceMeters}) => SetLog(
            id: 'set-010',
            exerciseId: 'plank',
            exerciseName: 'Plancha',
            setNumber: 1,
            reps: 0,
            weightKg: 0,
            completedAt: DateTime.utc(2026, 5, 18, 10, 30),
            durationSeconds: durationSeconds,
            distanceMeters: distanceMeters,
          );

      test('omite AMBAS claves cuando son null (la serie por reps no cambia)',
          () {
        final json = base().toJson();

        expect(json.containsKey('durationSeconds'), isFalse);
        expect(json.containsKey('distanceMeters'), isFalse);
      });

      test('no toca la serialización de rpe: sigue escribiendo rpe: null', () {
        final json = base().toJson();

        expect(json.containsKey('rpe'), isTrue);
        expect(json['rpe'], isNull);
      });

      test(
          'el documento de una serie por reps queda con las mismas claves de '
          'antes', () {
        final json = SetLog(
          id: 'set-011',
          exerciseId: 'bench',
          exerciseName: 'Press banca',
          setNumber: 1,
          reps: 8,
          weightKg: 80,
          completedAt: DateTime.utc(2026, 5, 18),
        ).toJson();

        expect(json.keys.toSet(), {
          'id',
          'exerciseId',
          'exerciseName',
          'setNumber',
          'reps',
          'weightKg',
          'rpe',
          'completedAt',
        });
      });

      test('escribe durationSeconds y round-tripea', () {
        final setLog = base(durationSeconds: 90);

        final json = setLog.toJson();
        expect(json['durationSeconds'], 90);
        expect(json.containsKey('distanceMeters'), isFalse);

        final decoded = SetLog.fromJson(json);
        expect(decoded.durationSeconds, 90);
        expect(decoded.distanceMeters, isNull);
        expect(decoded, equals(setLog));
      });

      test('escribe distanceMeters y round-tripea (también fraccionario)', () {
        final setLog = base(distanceMeters: 37.5);

        final json = setLog.toJson();
        expect(json['distanceMeters'], 37.5);
        expect(json.containsKey('durationSeconds'), isFalse);

        final decoded = SetLog.fromJson(json);
        expect(decoded.distanceMeters, 37.5);
        expect(decoded.durationSeconds, isNull);
        expect(decoded, equals(setLog));
      });

      test('un documento viejo (sin las claves) se lee con ambos null', () {
        final decoded = SetLog.fromJson(<String, dynamic>{
          'id': 'set-legacy',
          'exerciseId': 'plank',
          'exerciseName': 'Plancha',
          'setNumber': 1,
          'reps': 0,
          'weightKg': 0.0,
          'rpe': null,
          'completedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 18)),
        });

        expect(decoded.durationSeconds, isNull);
        expect(decoded.distanceMeters, isNull);
      });

      test(
          'Firestore devuelve num: un entero para distanceMeters se lee '
          'como double', () {
        final decoded = SetLog.fromJson(<String, dynamic>{
          'id': 'set-sled',
          'exerciseId': 'sled',
          'exerciseName': 'Trineo',
          'setNumber': 1,
          'reps': 0,
          'weightKg': 0,
          'completedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 18)),
          'durationSeconds': 60,
          'distanceMeters': 40,
        });

        expect(decoded.distanceMeters, 40.0);
        expect(decoded.durationSeconds, 60);
      });

      test('copyWith conserva la métrica (updateSet no la pierde)', () {
        final edited = base(durationSeconds: 45).copyWith(id: 'otro');

        expect(edited.durationSeconds, 45);
      });
    });
  });
}
