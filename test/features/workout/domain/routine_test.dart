import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';
import 'package:treino/features/workout/domain/routine.dart';
import 'package:treino/features/workout/domain/routine_day.dart';
import 'package:treino/features/workout/domain/routine_slot.dart';

void main() {
  group('Routine', () {
    test('SCENARIO-049: required-only roundtrip, nullable fields null', () {
      const routine = Routine(
        id: 'ppl-beginner',
        name: 'Push Pull Legs — Principiante',
        split: 'PPL',
        level: ExperienceLevel.beginner,
        days: [],
      );

      final json = routine.toJson();
      final decoded = Routine.fromJson(json);

      expect(decoded.id, equals('ppl-beginner'));
      expect(decoded.name, equals('Push Pull Legs — Principiante'));
      expect(decoded.split, equals('PPL'));
      expect(decoded.level, equals(ExperienceLevel.beginner));
      expect(decoded.days, isEmpty);
      expect(decoded.estimatedMinutesPerDay, isNull);
      expect(decoded.imageUrl, isNull);
      expect(decoded, equals(routine));
    });

    test('SCENARIO-050: imageUrl and estimatedMinutesPerDay are preserved', () {
      const routine = Routine(
        id: 'upper-lower',
        name: 'Upper/Lower',
        split: 'Upper/Lower',
        level: ExperienceLevel.intermediate,
        days: [],
        imageUrl: 'https://img.example.com/r.jpg',
        estimatedMinutesPerDay: 60,
      );

      final json = routine.toJson();
      final decoded = Routine.fromJson(json);

      expect(decoded.imageUrl, equals('https://img.example.com/r.jpg'));
      expect(decoded.estimatedMinutesPerDay, equals(60));
      expect(decoded, equals(routine));
    });

    test(
        'SCENARIO-051: fully-nested Firestore wire map deserializes correctly (2 days × 3 slots)',
        () {
      final rawMap = <String, dynamic>{
        'id': 'full-body-beginner',
        'name': 'Full Body Principiante',
        'split': 'Full Body',
        'level': 'beginner',
        'days': <dynamic>[
          <String, dynamic>{
            'dayNumber': 1,
            'name': 'Día 1',
            'estimatedMinutes': 60,
            'slots': <dynamic>[
              <String, dynamic>{
                'exerciseId': 'bench-press',
                'exerciseName': 'Bench Press',
                'muscleGroup': 'chest',
                'targetSets': 3,
                'targetRepsMin': 8,
                'targetRepsMax': 12,
                'restSeconds': 90,
              },
              <String, dynamic>{
                'exerciseId': 'back-squat',
                'exerciseName': 'Back Squat',
                'muscleGroup': 'quads',
                'targetSets': 3,
                'targetRepsMin': 8,
                'targetRepsMax': 12,
                'restSeconds': 120,
              },
              <String, dynamic>{
                'exerciseId': 'deadlift',
                'exerciseName': 'Deadlift',
                'muscleGroup': 'back',
                'targetSets': 3,
                'targetRepsMin': 5,
                'targetRepsMax': 5,
                'restSeconds': 120,
              },
            ],
          },
          <String, dynamic>{
            'dayNumber': 2,
            'name': 'Día 2',
            'estimatedMinutes': 55,
            'slots': <dynamic>[
              <String, dynamic>{
                'exerciseId': 'overhead-press',
                'exerciseName': 'Overhead Press',
                'muscleGroup': 'shoulders',
                'targetSets': 3,
                'targetRepsMin': 8,
                'targetRepsMax': 12,
                'restSeconds': 90,
              },
              <String, dynamic>{
                'exerciseId': 'pull-up',
                'exerciseName': 'Pull-Up',
                'muscleGroup': 'back',
                'targetSets': 3,
                'targetRepsMin': 6,
                'targetRepsMax': 10,
                'restSeconds': 90,
              },
              <String, dynamic>{
                'exerciseId': 'hip-thrust',
                'exerciseName': 'Hip Thrust',
                'muscleGroup': 'glutes',
                'targetSets': 3,
                'targetRepsMin': 10,
                'targetRepsMax': 15,
                'restSeconds': 90,
              },
            ],
          },
        ],
        'estimatedMinutesPerDay': null,
        'imageUrl': null,
      };

      final routine = Routine.fromJson(rawMap);

      expect(routine.days.length, equals(2));
      expect(routine.days[0].slots.length, equals(3));
      expect(routine.days[1].slots.length, equals(3));
      expect(routine.days[0].slots[0].exerciseId, equals('bench-press'));
      expect(routine.days[0].slots[1].exerciseId, equals('back-squat'));
      expect(routine.days[0].slots[2].exerciseId, equals('deadlift'));
      expect(routine.days[1].slots[0].exerciseId, equals('overhead-press'));
    });

    test('SCENARIO-052: days: [] roundtrip gives empty list without error', () {
      const routine = Routine(
        id: 'empty-template',
        name: 'Empty',
        split: 'PPL',
        level: ExperienceLevel.advanced,
        days: [],
      );

      final json = routine.toJson();
      final decoded = Routine.fromJson(json);

      expect(decoded.days, isEmpty);
    });

    test('SCENARIO-053: level beginner serializes to "beginner"', () {
      const routine = Routine(
        id: 'r1',
        name: 'Test',
        split: 'PPL',
        level: ExperienceLevel.beginner,
        days: [],
      );

      final json = routine.toJson();

      expect(json['level'], equals('beginner'));
    });

    test(
        'SCENARIO-054: level intermediate roundtrip preserves ExperienceLevel.intermediate',
        () {
      const routine = Routine(
        id: 'r2',
        name: 'Test',
        split: 'Full Body',
        level: ExperienceLevel.intermediate,
        days: [],
      );

      final json = routine.toJson();
      final decoded = Routine.fromJson(json);

      expect(decoded.level, equals(ExperienceLevel.intermediate));
    });

    test('SCENARIO-055: raw map with level "advanced" deserializes correctly',
        () {
      final rawMap = <String, dynamic>{
        'id': 'r3',
        'name': 'Test',
        'split': 'Upper/Lower',
        'level': 'advanced',
        'days': <dynamic>[],
      };

      final routine = Routine.fromJson(rawMap);

      expect(routine.level, equals(ExperienceLevel.advanced));
    });

    test(
        'SCENARIO-056: raw map with unknown level "elite" throws ArgumentError',
        () {
      final rawMap = <String, dynamic>{
        'id': 'r4',
        'name': 'Test',
        'split': 'PPL',
        'level': 'elite',
        'days': <dynamic>[],
      };

      expect(
        () => Routine.fromJson(rawMap),
        throwsA(isA<ArgumentError>()),
      );
    });

    // SCENARIO-057: build_runner sanity — verified by the presence of the 8
    // generated files after running build_runner. This is not a Dart test() call
    // but a checklist item confirmed when TASK-012b completes successfully.
    // Files expected: exercise.freezed.dart, exercise.g.dart,
    // routine_slot.freezed.dart, routine_slot.g.dart,
    // routine_day.freezed.dart, routine_day.g.dart,
    // routine.freezed.dart, routine.g.dart
  });
}
