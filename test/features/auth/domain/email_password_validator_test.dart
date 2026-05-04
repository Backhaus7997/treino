import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/auth/domain/email_password_validator.dart';

void main() {
  group('EmailPasswordValidator.validateEmail', () {
    test('returns null for valid email a@b.c', () {
      expect(EmailPasswordValidator.validateEmail('a@b.c'), isNull);
    });

    test('returns null for valid email martin@treino.app', () {
      expect(EmailPasswordValidator.validateEmail('martin@treino.app'), isNull);
    });

    test('returns error for empty string', () {
      expect(
        EmailPasswordValidator.validateEmail(''),
        equals('El email no es válido'),
      );
    });

    test('returns error for null value', () {
      expect(
        EmailPasswordValidator.validateEmail(null),
        equals('El email no es válido'),
      );
    });

    test('returns error for email without @ sign', () {
      expect(
        EmailPasswordValidator.validateEmail('noatsign'),
        equals('El email no es válido'),
      );
    });

    test('returns error for email starting with @', () {
      expect(
        EmailPasswordValidator.validateEmail('@x.y'),
        equals('El email no es válido'),
      );
    });

    test('returns error for email with @ but no domain', () {
      expect(
        EmailPasswordValidator.validateEmail('user@'),
        equals('El email no es válido'),
      );
    });

    test('returns error for email with @ but no TLD', () {
      expect(
        EmailPasswordValidator.validateEmail('user@x'),
        equals('El email no es válido'),
      );
    });
  });

  group('EmailPasswordValidator.validatePassword', () {
    test('returns null for valid password Pass1234', () {
      expect(EmailPasswordValidator.validatePassword('Pass1234'), isNull);
    });

    test('returns null for valid password abc12345', () {
      expect(EmailPasswordValidator.validatePassword('abc12345'), isNull);
    });

    test('returns error for empty string', () {
      expect(
        EmailPasswordValidator.validatePassword(''),
        equals(
          'La contraseña debe tener al menos 8 caracteres, una letra y un número',
        ),
      );
    });

    test('returns error for null value', () {
      expect(
        EmailPasswordValidator.validatePassword(null),
        equals(
          'La contraseña debe tener al menos 8 caracteres, una letra y un número',
        ),
      );
    });

    test('returns error for too short password abc1 (less than 8 chars)', () {
      expect(
        EmailPasswordValidator.validatePassword('abc1'),
        equals(
          'La contraseña debe tener al menos 8 caracteres, una letra y un número',
        ),
      );
    });

    test('returns error for password without numbers abcdefgh', () {
      expect(
        EmailPasswordValidator.validatePassword('abcdefgh'),
        equals(
          'La contraseña debe tener al menos 8 caracteres, una letra y un número',
        ),
      );
    });

    test('returns error for password without letters 12345678', () {
      expect(
        EmailPasswordValidator.validatePassword('12345678'),
        equals(
          'La contraseña debe tener al menos 8 caracteres, una letra y un número',
        ),
      );
    });
  });

  group('EmailPasswordValidator.validatePasswordMatch', () {
    test('returns null when passwords match', () {
      expect(
        EmailPasswordValidator.validatePasswordMatch('Pass1234', 'Pass1234'),
        isNull,
      );
    });

    test('returns error message when passwords differ', () {
      expect(
        EmailPasswordValidator.validatePasswordMatch('a', 'b'),
        equals('Las contraseñas no coinciden'),
      );
    });

    test('returns error when confirm is null', () {
      expect(
        EmailPasswordValidator.validatePasswordMatch('Pass1234', null),
        equals('Las contraseñas no coinciden'),
      );
    });

    test('returns error when password is null and confirm is not', () {
      expect(
        EmailPasswordValidator.validatePasswordMatch(null, 'Pass1234'),
        equals('Las contraseñas no coinciden'),
      );
    });
  });
}
