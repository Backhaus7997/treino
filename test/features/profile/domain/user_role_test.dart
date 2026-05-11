import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/domain/user_role.dart';

void main() {
  group('UserRole', () {
    test('SCENARIO-005: fromJson athlete → UserRole.athlete', () {
      expect(UserRoleX.fromJson('athlete'), UserRole.athlete);
    });

    test('SCENARIO-006: fromJson trainer → UserRole.trainer', () {
      expect(UserRoleX.fromJson('trainer'), UserRole.trainer);
    });

    test('SCENARIO-007: fromJson admin → throws ArgumentError', () {
      expect(() => UserRoleX.fromJson('admin'), throwsA(isA<ArgumentError>()));
    });

    test('roundtrip athlete toJson == athlete', () {
      expect(UserRole.athlete.toJson(), equals('athlete'));
    });

    test('roundtrip trainer toJson == trainer', () {
      expect(UserRole.trainer.toJson(), equals('trainer'));
    });
  });
}
