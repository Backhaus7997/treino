import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/gender.dart';

void main() {
  group('Gender', () {
    test('SCENARIO-008: fromJson non_binary → Gender.nonBinary', () {
      expect(GenderX.fromJson('non_binary'), Gender.nonBinary);
    });

    test('roundtrip male', () {
      expect(GenderX.fromJson('male'), Gender.male);
      expect(Gender.male.toJson(), equals('male'));
    });

    test('roundtrip female', () {
      expect(GenderX.fromJson('female'), Gender.female);
      expect(Gender.female.toJson(), equals('female'));
    });

    test('roundtrip undisclosed', () {
      expect(GenderX.fromJson('undisclosed'), Gender.undisclosed);
      expect(Gender.undisclosed.toJson(), equals('undisclosed'));
    });

    test('roundtrip non_binary', () {
      expect(Gender.nonBinary.toJson(), equals('non_binary'));
    });

    test('unknown value throws ArgumentError', () {
      expect(
        () => GenderX.fromJson('unknown'),
        throwsA(isA<ArgumentError>()),
      );
    });
  });
}
