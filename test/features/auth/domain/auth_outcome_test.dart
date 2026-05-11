import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:treino/features/auth/domain/auth_outcome.dart';

class MockUser extends Mock implements User {}

void main() {
  late MockUser mockUser;

  setUp(() {
    mockUser = MockUser();
  });

  group('AuthOutcome', () {
    test('equality — same fields are equal', () {
      final outcome1 = AuthOutcome(user: mockUser, isNewUser: true);
      final outcome2 = AuthOutcome(user: mockUser, isNewUser: true);
      expect(outcome1, equals(outcome2));
    });

    test('equality — different isNewUser are not equal', () {
      final outcome1 = AuthOutcome(user: mockUser, isNewUser: true);
      final outcome2 = AuthOutcome(user: mockUser, isNewUser: false);
      expect(outcome1, isNot(equals(outcome2)));
    });

    test('copyWith — isNewUser can be changed', () {
      final outcome = AuthOutcome(user: mockUser, isNewUser: true);
      final copied = outcome.copyWith(isNewUser: false);
      expect(copied.isNewUser, isFalse);
      expect(copied.user, mockUser);
    });

    test('copyWith — user can be changed', () {
      final outcome = AuthOutcome(user: mockUser, isNewUser: true);
      final otherUser = MockUser();
      final copied = outcome.copyWith(user: otherUser);
      expect(copied.user, otherUser);
      expect(copied.isNewUser, isTrue);
    });
  });
}
