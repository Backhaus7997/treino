import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/custom_exercise.dart';
import 'package:treino/features/workout/domain/equipment_type.dart';

void main() {
  // Use Firestore Timestamps as required by @TimestampConverter.
  final createdAt = Timestamp.fromDate(DateTime.utc(2024, 1, 1));
  final updatedAt = Timestamp.fromDate(DateTime.utc(2024, 1, 2));

  Map<String, dynamic> baseMap({String? equipment}) => {
        'id': 'ce-1',
        'ownerId': 'trainer-1',
        'name': 'Curl con mancuerna',
        if (equipment != null) 'equipment': equipment,
        'createdAt': createdAt,
        'updatedAt': updatedAt,
      };

  group('CustomExercise — equipment field (REQ-RER-015, T-RER-007)', () {
    test('fromJson with equipment "mancuerna" → EquipmentType.mancuerna', () {
      final exercise = CustomExercise.fromJson(baseMap(equipment: 'mancuerna'));
      expect(exercise.equipment, equals(EquipmentType.mancuerna));
    });

    test('fromJson without equipment key → equipment is null', () {
      final exercise = CustomExercise.fromJson(baseMap());
      expect(exercise.equipment, isNull);
    });

    test('toJson emits equipment jsonValue string for non-null', () {
      final exercise = CustomExercise(
        id: 'ce-3',
        ownerId: 'trainer-1',
        name: 'Ejercicio con cable',
        equipment: EquipmentType.cable,
        createdAt: createdAt.toDate(),
        updatedAt: updatedAt.toDate(),
      );
      final json = exercise.toJson();
      expect(json['equipment'], equals('cable'));
    });

    test('toJson emits null for null equipment', () {
      final exercise = CustomExercise(
        id: 'ce-4',
        ownerId: 'trainer-1',
        name: 'Ejercicio sin equipo',
        createdAt: createdAt.toDate(),
        updatedAt: updatedAt.toDate(),
      );
      final json = exercise.toJson();
      expect(json['equipment'], isNull);
    });

    test('equipment field round-trip via toJson → fromJson preserves value',
        () {
      final original = CustomExercise(
        id: 'ce-5',
        ownerId: 'trainer-1',
        name: 'Dominadas',
        equipment: EquipmentType.pesoCorporal,
        createdAt: createdAt.toDate(),
        updatedAt: updatedAt.toDate(),
      );
      // toJson emits a Timestamp for the date fields; re-parse from map
      final json = original.toJson();
      final decoded = CustomExercise.fromJson(json);
      expect(decoded.equipment, equals(EquipmentType.pesoCorporal));
    });
  });
}
