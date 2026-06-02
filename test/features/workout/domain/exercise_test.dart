import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/equipment_type.dart';
import 'package:treino/features/workout/domain/exercise.dart';

void main() {
  group('Exercise', () {
    test('SCENARIO-020: required-only roundtrip, all nullable fields null', () {
      const exercise = Exercise(
        id: 'bench-press',
        name: 'Bench Press',
        muscleGroup: 'chest',
        category: 'compound',
      );

      final json = exercise.toJson();
      final decoded = Exercise.fromJson(json);

      expect(decoded.id, equals('bench-press'));
      expect(decoded.name, equals('Bench Press'));
      expect(decoded.muscleGroup, equals('chest'));
      expect(decoded.category, equals('compound'));
      expect(decoded.techniqueInstructions, isNull);
      expect(decoded.videoUrl, isNull);
      expect(decoded.defaultRestSeconds, isNull);
      expect(decoded, equals(exercise));
    });

    test('SCENARIO-021: all 7 fields populated roundtrip', () {
      const exercise = Exercise(
        id: 'squat',
        name: 'Back Squat',
        muscleGroup: 'quads',
        category: 'compound',
        techniqueInstructions: ['cue1', 'cue2'],
        videoUrl: 'https://v.example.com/1',
        defaultRestSeconds: 90,
      );

      final json = exercise.toJson();
      final decoded = Exercise.fromJson(json);

      expect(decoded, equals(exercise));
      expect(decoded.techniqueInstructions, hasLength(2));
      expect(decoded.techniqueInstructions, orderedEquals(['cue1', 'cue2']));
      expect(decoded.videoUrl, equals('https://v.example.com/1'));
      expect(decoded.defaultRestSeconds, equals(90));
    });

    test(
        'SCENARIO-022: raw Firestore wire map with List<dynamic> techniqueInstructions',
        () {
      final rawMap = <String, dynamic>{
        'id': 'deadlift',
        'name': 'Deadlift',
        'muscleGroup': 'back',
        'category': 'compound',
        'techniqueInstructions': <dynamic>[
          'Pies al ancho de caderas.',
          'Espalda neutra.'
        ],
      };

      final exercise = Exercise.fromJson(rawMap);

      expect(exercise.techniqueInstructions, isA<List<String>>());
      expect(exercise.techniqueInstructions, hasLength(2));
      expect(exercise.techniqueInstructions![0],
          equals('Pies al ancho de caderas.'));
      expect(exercise.techniqueInstructions![1], equals('Espalda neutra.'));
    });

    test(
        'SCENARIO-023: raw map missing techniqueInstructions, videoUrl, defaultRestSeconds',
        () {
      final rawMap = <String, dynamic>{
        'id': 'push-up',
        'name': 'Push-Up',
        'muscleGroup': 'chest',
        'category': 'compound',
      };

      final exercise = Exercise.fromJson(rawMap);

      expect(exercise.techniqueInstructions, isNull);
      expect(exercise.videoUrl, isNull);
      expect(exercise.defaultRestSeconds, isNull);
    });

    test('SCENARIO-024: fromJson with all fields does not throw', () {
      // This test verifies that the model is properly generated and functions
      // without runtime errors. The actual flutter analyze check is a quality
      // gate run outside the test suite.
      expect(
        () => Exercise.fromJson({
          'id': 'pull-up',
          'name': 'Pull-Up',
          'muscleGroup': 'back',
          'category': 'compound',
          'techniqueInstructions': ['Agarre supino.'],
          'videoUrl': 'https://v.example.com/pull-up',
          'defaultRestSeconds': 60,
        }),
        returnsNormally,
      );
    });

    // ── REQ-RER-015: equipment field round-trip (T-RER-007) ─────────────────

    test('REQ-RER-015: fromJson with equipment "barra" → EquipmentType.barra',
        () {
      final exercise = Exercise.fromJson({
        'id': 'bench-press',
        'name': 'Press de banca',
        'muscleGroup': 'chest',
        'category': 'compound',
        'equipment': 'barra',
      });
      expect(exercise.equipment, equals(EquipmentType.barra));
    });

    test('REQ-RER-015: fromJson without equipment key → equipment is null', () {
      final exercise = Exercise.fromJson({
        'id': 'bench-press',
        'name': 'Press de banca',
        'muscleGroup': 'chest',
        'category': 'compound',
      });
      expect(exercise.equipment, isNull);
    });

    test('REQ-RER-015: toJson emits equipment jsonValue string for non-null',
        () {
      const exercise = Exercise(
        id: 'bench-press',
        name: 'Press de banca',
        muscleGroup: 'chest',
        category: 'compound',
        equipment: EquipmentType.barra,
      );
      final json = exercise.toJson();
      expect(json['equipment'], equals('barra'));
    });

    test('REQ-RER-015: toJson emits null for null equipment', () {
      const exercise = Exercise(
        id: 'pull-up',
        name: 'Dominadas',
        muscleGroup: 'back',
        category: 'compound',
      );
      final json = exercise.toJson();
      expect(json['equipment'], isNull);
    });

    test('REQ-RER-015: full round-trip with equipment pesoCorporal', () {
      const original = Exercise(
        id: 'pull-up',
        name: 'Dominadas',
        muscleGroup: 'back',
        category: 'compound',
        equipment: EquipmentType.pesoCorporal,
      );
      final decoded = Exercise.fromJson(original.toJson());
      expect(decoded.equipment, equals(EquipmentType.pesoCorporal));
      expect(decoded, equals(original));
    });
  });
}
