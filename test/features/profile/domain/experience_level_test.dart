import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';

void main() {
  group('ExperienceLevel', () {
    test('SCENARIO-009: fromJson intermediate → ExperienceLevel.intermediate',
        () {
      expect(
        ExperienceLevelX.fromJson('intermediate'),
        ExperienceLevel.intermediate,
      );
    });

    test('roundtrip beginner', () {
      expect(ExperienceLevelX.fromJson('beginner'), ExperienceLevel.beginner);
      expect(ExperienceLevel.beginner.toJson(), equals('beginner'));
    });

    test('roundtrip advanced', () {
      expect(ExperienceLevelX.fromJson('advanced'), ExperienceLevel.advanced);
      expect(ExperienceLevel.advanced.toJson(), equals('advanced'));
    });

    test('roundtrip intermediate', () {
      expect(ExperienceLevel.intermediate.toJson(), equals('intermediate'));
    });

    test('unknown value throws ArgumentError', () {
      expect(
        () => ExperienceLevelX.fromJson('expert'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
