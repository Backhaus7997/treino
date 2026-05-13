import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';

void main() {
  group('RoutineDay', () {
    test(
        'SCENARIO-046: empty slots and null estimatedMinutes roundtrip correctly',
        () {
      const day = RoutineDay(
        dayNumber: 1,
        name: 'Push',
        slots: [],
      );

      final json = day.toJson();
      final decoded = RoutineDay.fromJson(json);

      expect(decoded.dayNumber, equals(1));
      expect(decoded.name, equals('Push'));
      expect(decoded.slots, isEmpty);
      expect(decoded.estimatedMinutes, isNull);
      expect(decoded, equals(day));
    });

    test('SCENARIO-047: 3 slots roundtrip preserves exerciseIds', () {
      const day = RoutineDay(
        dayNumber: 2,
        name: 'Pull',
        estimatedMinutes: 60,
        slots: [
          RoutineSlot(
            exerciseId: 'deadlift',
            exerciseName: 'Deadlift',
            muscleGroup: 'back',
            targetSets: 4,
            targetRepsMin: 5,
            targetRepsMax: 5,
            restSeconds: 120,
          ),
          RoutineSlot(
            exerciseId: 'pull-up',
            exerciseName: 'Pull-Up',
            muscleGroup: 'back',
            targetSets: 3,
            targetRepsMin: 8,
            targetRepsMax: 12,
            restSeconds: 90,
          ),
          RoutineSlot(
            exerciseId: 'barbell-curl',
            exerciseName: 'Barbell Curl',
            muscleGroup: 'biceps',
            targetSets: 3,
            targetRepsMin: 10,
            targetRepsMax: 15,
            restSeconds: 60,
          ),
        ],
      );

      final json = day.toJson();
      final decoded = RoutineDay.fromJson(json);

      expect(decoded.slots, hasLength(3));
      expect(decoded.slots[0].exerciseId, equals('deadlift'));
      expect(decoded.slots[1].exerciseId, equals('pull-up'));
      expect(decoded.slots[2].exerciseId, equals('barbell-curl'));
      expect(decoded, equals(day));
    });

    test(
        'SCENARIO-048: raw Firestore wire map with List<dynamic> slots deserializes correctly',
        () {
      final rawMap = <String, dynamic>{
        'dayNumber': 1,
        'name': 'Legs',
        'estimatedMinutes': 70,
        'slots': <dynamic>[
          <String, dynamic>{
            'exerciseId': 'back-squat',
            'exerciseName': 'Back Squat',
            'muscleGroup': 'quads',
            'targetSets': 4,
            'targetRepsMin': 8,
            'targetRepsMax': 12,
            'restSeconds': 120,
          },
          <String, dynamic>{
            'exerciseId': 'romanian-deadlift',
            'exerciseName': 'Romanian Deadlift',
            'muscleGroup': 'hamstrings',
            'targetSets': 3,
            'targetRepsMin': 10,
            'targetRepsMax': 12,
            'restSeconds': 90,
          },
        ],
      };

      final day = RoutineDay.fromJson(rawMap);

      expect(day.slots, isA<List<RoutineSlot>>());
      expect(day.slots, hasLength(2));
      expect(day.slots[0].exerciseId, equals('back-squat'));
      expect(day.slots[1].exerciseId, equals('romanian-deadlift'));
      expect(day.estimatedMinutes, equals(70));
    });
  });
}
