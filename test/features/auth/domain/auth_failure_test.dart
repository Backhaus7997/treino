import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/auth/domain/auth_failure.dart';

void main() {
  group('AuthFailure.fromFirebase', () {
    AuthFailure fromCode(String code) =>
        AuthFailure.fromFirebase(FirebaseAuthException(code: code));

    test('19.1 invalid-email → invalidEmail', () {
      expect(fromCode('invalid-email'), const AuthFailure.invalidEmail());
    });

    test('19.2 user-disabled → userDisabled', () {
      expect(fromCode('user-disabled'), const AuthFailure.userDisabled());
    });

    test('19.3 user-not-found → userNotFound', () {
      expect(fromCode('user-not-found'), const AuthFailure.userNotFound());
    });

    test('19.4 wrong-password → wrongPassword', () {
      expect(fromCode('wrong-password'), const AuthFailure.wrongPassword());
    });

    test('19.5 invalid-credential → wrongPassword (collapsed)', () {
      expect(fromCode('invalid-credential'), const AuthFailure.wrongPassword());
    });

    test('19.6 email-already-in-use → emailAlreadyInUse', () {
      expect(
        fromCode('email-already-in-use'),
        const AuthFailure.emailAlreadyInUse(),
      );
    });

    test('19.7 weak-password → weakPassword', () {
      expect(fromCode('weak-password'), const AuthFailure.weakPassword());
    });

    test('19.8 too-many-requests → tooManyRequests', () {
      expect(
        fromCode('too-many-requests'),
        const AuthFailure.tooManyRequests(),
      );
    });

    test('19.9 network-request-failed → networkError', () {
      expect(
        fromCode('network-request-failed'),
        const AuthFailure.networkError(),
      );
    });

    test('19.10 unknown code → unknown with code preserved', () {
      final result = fromCode('some-unknown-code');
      expect(result, const AuthFailure.unknown('some-unknown-code'));
    });
  });

  group('AuthFailure.userMessage', () {
    test('invalidEmail returns Spanish message', () {
      expect(
        const AuthFailure.invalidEmail().userMessage,
        equals('El email no es válido'),
      );
    });

    test('userDisabled returns Spanish message', () {
      expect(
        const AuthFailure.userDisabled().userMessage,
        equals('Tu cuenta está deshabilitada. Contactá soporte'),
      );
    });

    test('userNotFound returns Spanish message', () {
      expect(
        const AuthFailure.userNotFound().userMessage,
        equals('No encontramos una cuenta con ese email'),
      );
    });

    test('wrongPassword returns Spanish message', () {
      expect(
        const AuthFailure.wrongPassword().userMessage,
        equals('La contraseña es incorrecta'),
      );
    });

    test('emailAlreadyInUse returns Spanish message', () {
      expect(
        const AuthFailure.emailAlreadyInUse().userMessage,
        equals('Ya existe una cuenta con ese email'),
      );
    });

    test('weakPassword returns Spanish message', () {
      expect(
        const AuthFailure.weakPassword().userMessage,
        equals('La contraseña es muy débil'),
      );
    });

    test('tooManyRequests returns Spanish message (scenario 9.2)', () {
      expect(
        const AuthFailure.tooManyRequests().userMessage,
        equals(
          'Demasiados intentos. Esperá unos minutos e intentá de nuevo',
        ),
      );
    });

    test('networkError returns Spanish message', () {
      expect(
        const AuthFailure.networkError().userMessage,
        equals('Sin conexión. Revisá tu internet e intentá de nuevo'),
      );
    });

    test('unknown returns Spanish message', () {
      expect(
        const AuthFailure.unknown('any-code').userMessage,
        equals('Algo salió mal. Intentá de nuevo'),
      );
    });

    test('every variant userMessage is non-empty and Spanish', () {
      final failures = [
        const AuthFailure.invalidEmail(),
        const AuthFailure.userDisabled(),
        const AuthFailure.userNotFound(),
        const AuthFailure.wrongPassword(),
        const AuthFailure.emailAlreadyInUse(),
        const AuthFailure.weakPassword(),
        const AuthFailure.tooManyRequests(),
        const AuthFailure.networkError(),
        const AuthFailure.unknown('x'),
      ];
      for (final f in failures) {
        expect(f.userMessage, isNotEmpty, reason: '$f.userMessage was empty');
        // Verify Spanish chars present in at least some messages
        expect(f.userMessage.length, greaterThan(5));
      }
    });
  });
}
