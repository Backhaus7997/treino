import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/workout/domain/set_enums.dart';
import 'package:treino/features/workout/domain/set_spec.dart';

void main() {
  group('SetSpec JSON round-trips', () {
    test('SCENARIO-SET-01: reps set (single weight+reps)', () {
      const spec = SetSpec(
        type: SetType.normal,
        weightKg: 80.0,
        reps: 10,
      );

      final json = spec.toJson();
      final decoded = SetSpec.fromJson(json);

      expect(decoded.type, equals(SetType.normal));
      expect(decoded.weightKg, closeTo(80.0, 0.001));
      expect(decoded.reps, equals(10));
      expect(decoded.repsMin, isNull);
      expect(decoded.repsMax, isNull);
      expect(decoded.durationSeconds, isNull);
      expect(decoded, equals(spec));
    });

    test('SCENARIO-SET-02: range set (repsMin + repsMax)', () {
      const spec = SetSpec(
        type: SetType.normal,
        weightKg: 60.0,
        repsMin: 8,
        repsMax: 12,
      );

      final json = spec.toJson();
      final decoded = SetSpec.fromJson(json);

      expect(decoded.weightKg, closeTo(60.0, 0.001));
      expect(decoded.repsMin, equals(8));
      expect(decoded.repsMax, equals(12));
      expect(decoded.reps, isNull);
      expect(decoded, equals(spec));
    });

    test('SCENARIO-SET-03: duration set (time-based, no weight/reps)', () {
      const spec = SetSpec(
        type: SetType.normal,
        durationSeconds: 45,
      );

      final json = spec.toJson();
      final decoded = SetSpec.fromJson(json);

      expect(decoded.durationSeconds, equals(45));
      expect(decoded.weightKg, isNull);
      expect(decoded.reps, isNull);
      expect(decoded, equals(spec));
    });

    test('SCENARIO-SET-04: warmup set type round-trips', () {
      const spec = SetSpec(
        type: SetType.warmup,
        weightKg: 40.0,
        reps: 15,
      );

      final json = spec.toJson();
      final decoded = SetSpec.fromJson(json);

      expect(decoded.type, equals(SetType.warmup));
      expect(decoded, equals(spec));
    });

    test('SCENARIO-SET-05: drop set type round-trips', () {
      const spec = SetSpec(type: SetType.drop, weightKg: 50.0, reps: 8);
      final json = spec.toJson();
      expect(SetSpec.fromJson(json).type, equals(SetType.drop));
    });

    test('SCENARIO-SET-06: failure set type round-trips', () {
      const spec = SetSpec(type: SetType.failure, weightKg: 70.0, reps: 6);
      final json = spec.toJson();
      expect(SetSpec.fromJson(json).type, equals(SetType.failure));
    });

    test(
        'SCENARIO-SET-07: unknown SetType string falls back to normal (no throw)',
        () {
      final json = <String, Object?>{
        'type': 'UNKNOWN_FUTURE_TYPE',
        'reps': 10,
      };

      // Must not throw — unknown enum value → default (normal).
      final decoded = SetSpec.fromJson(json);
      expect(decoded.type, equals(SetType.normal));
      expect(decoded.reps, equals(10));
    });

    test('SCENARIO-SET-08: missing type key uses default (normal)', () {
      final json = <String, Object?>{'reps': 5};
      final decoded = SetSpec.fromJson(json);
      expect(decoded.type, equals(SetType.normal));
    });

    test('SCENARIO-SET-09: type is serialized as enum name string', () {
      const spec = SetSpec(type: SetType.warmup);
      final json = spec.toJson();
      expect(json['type'], equals('warmup'));
    });
  });
}
