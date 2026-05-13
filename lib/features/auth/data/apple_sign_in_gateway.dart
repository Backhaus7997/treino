import 'package:sign_in_with_apple/sign_in_with_apple.dart';

/// Testable seam around [SignInWithApple.getAppleIDCredential] (a static method
/// that cannot be mocked directly with mocktail).
///
/// [RealAppleSignInGateway] is the production implementation; tests inject a
/// mock via the [AuthService] constructor.
abstract class AppleSignInGateway {
  /// Invokes the native iOS Apple Sign-In sheet.
  ///
  /// Cancellation (`AuthorizationErrorCode.canceled`) propagates as
  /// [SignInWithAppleAuthorizationException] — the gateway does NOT swallow it.
  /// [AuthService] catches and converts it to [AuthFailure.signInCancelled].
  Future<AuthorizationCredentialAppleID> getAppleIDCredential({
    required List<AppleIDAuthorizationScopes> scopes,
    required String nonce,
  });
}

class RealAppleSignInGateway implements AppleSignInGateway {
  const RealAppleSignInGateway();

  @override
  Future<AuthorizationCredentialAppleID> getAppleIDCredential({
    required List<AppleIDAuthorizationScopes> scopes,
    required String nonce,
  }) =>
      SignInWithApple.getAppleIDCredential(scopes: scopes, nonce: nonce);
}
