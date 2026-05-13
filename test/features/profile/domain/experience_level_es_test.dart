import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/experience_level.dart';

void main() {
  group('ExperienceLevelEs.displayNameEs', () {
    test('values length guard — fail when new case added without translation',
        () {
      expect(ExperienceLevel.values.length, equals(3));
    });

    test('beginner → Principiante', () {
      expect(ExperienceLevel.beginner.displayNameEs, equals('Principiante'));
    });

    test('intermediate → Intermedio', () {
      expect(ExperienceLevel.intermediate.displayNameEs, equals('Intermedio'));
    });

    test('advanced → Avanzado', () {
      expect(ExperienceLevel.advanced.displayNameEs, equals('Avanzado'));
    });
  });
}
