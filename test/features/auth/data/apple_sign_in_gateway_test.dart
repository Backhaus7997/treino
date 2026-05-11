// `RealAppleSignInGateway` wraps `SignInWithApple.getAppleIDCredential`,
// which is a static method and cannot be unit-tested without a real
// Apple Sign-In flow on a physical device. Coverage of the gateway's
// `getAppleIDCredential` method lives at the integration-test layer
// (out of scope for this PR — Etapa 5 ships unit + widget tests only).

import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart';
import 'package:treino/features/auth/data/apple_sign_in_gateway.dart';

class MockAppleSignInGateway extends Mock implements AppleSignInGateway {}

void main() {
  group('AppleSignInGateway', () {
    test('MockAppleSignInGateway can be instantiated', () {
      final mock = MockAppleSignInGateway();
      expect(mock, isA<AppleSignInGateway>());
    });

    test('MockAppleSignInGateway has correct method signature — returns Future',
        () {
      final mock = MockAppleSignInGateway();
      when(
        () => mock.getAppleIDCredential(
          scopes: any(named: 'scopes'),
          nonce: any(named: 'nonce'),
        ),
      ).thenAnswer(
        (_) async => const AuthorizationCredentialAppleID(
          userIdentifier: 'user_id',
          givenName: 'Test',
          familyName: 'User',
          email: 'test@apple.com',
          authorizationCode: 'auth_code',
          identityToken: 'id_token',
          state: null,
        ),
      );

      expect(
        () => mock.getAppleIDCredential(
          scopes: const [AppleIDAuthorizationScopes.email],
          nonce: 'test_nonce',
        ),
        returnsNormally,
      );
    });
  });
}
