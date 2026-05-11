import 'package:firebase_auth/firebase_auth.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' hide generateNonce;

import '../domain/auth_failure.dart';
import '../domain/auth_outcome.dart';
import 'apple_sign_in_gateway.dart';
import 'nonce_helpers.dart';

class AuthService {
  AuthService({
    required FirebaseAuth firebaseAuth,
    AppleSignInGateway appleGateway = const RealAppleSignInGateway(),
  })  : _auth = firebaseAuth,
        _appleGateway = appleGateway;

  final FirebaseAuth _auth;
  final AppleSignInGateway _appleGateway;

  /// Creates the user, optionally sets [displayName], and sends verification
  /// email automatically (REQ-AUTH-003). Throws [AuthFailure].
  ///
  /// Never returns null for the email path; nullable return type aligns with
  /// Apple's cancel contract for uniform handling across providers.
  Future<AuthOutcome?> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final fbUser = cred.user!;
      if (displayName != null) {
        await fbUser.updateDisplayName(displayName);
      }
      await fbUser.sendEmailVerification();
      return AuthOutcome(
        user: fbUser,
        isNewUser: cred.additionalUserInfo?.isNewUser ?? true,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }
  }

  /// Throws [AuthFailure] on bad credentials, missing user, etc.
  ///
  /// Never returns null for the email path; nullable return type aligns with
  /// Apple's cancel contract for uniform handling across providers.
  Future<AuthOutcome?> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return AuthOutcome(
        user: cred.user!,
        isNewUser: cred.additionalUserInfo?.isNewUser ?? false,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }
  }

  /// Returns null when the user cancels the native Apple sheet.
  /// Throws [AuthFailure] on any other Apple/Firebase failure.
  Future<AuthOutcome?> signInWithApple() async {
    final rawNonce = generateNonce();
    final hashedNonce = sha256OfString(rawNonce);

    final AuthorizationCredentialAppleID appleCred;
    try {
      appleCred = await _appleGateway.getAppleIDCredential(
        scopes: const [
          AppleIDAuthorizationScopes.email,
          AppleIDAuthorizationScopes.fullName,
        ],
        nonce: hashedNonce, // HASH to Apple
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) return null;
      throw const AuthFailure.appleSignInFailed();
    } catch (_) {
      throw const AuthFailure.appleSignInFailed();
    }

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCred.identityToken,
      rawNonce: rawNonce, // RAW to Firebase
    );

    try {
      final userCredential = await _auth.signInWithCredential(oauthCredential);
      final fbUser = userCredential.user!;
      final isNewUser = userCredential.additionalUserInfo?.isNewUser ?? false;

      if (isNewUser) {
        final fullName = [
          appleCred.givenName ?? '',
          appleCred.familyName ?? '',
        ].where((s) => s.isNotEmpty).join(' ').trim();
        if (fullName.isNotEmpty) {
          await fbUser.updateDisplayName(fullName);
        }
      }

      return AuthOutcome(user: fbUser, isNewUser: isNewUser);
    } on FirebaseAuthException catch (e) {
      // Apple's identity token rejected (audience mismatch, signature
      // failure, etc.) → surface a generic Apple failure rather than
      // the email-password "wrong password" message.
      if (e.code == 'invalid-credential') {
        throw const AuthFailure.appleSignInFailed();
      }
      throw AuthFailure.fromFirebase(e);
    }
  }

  /// Throws [AuthFailure]; the screen treats userNotFound as success (REQ-AUTH-011).
  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      await _auth.sendPasswordResetEmail(email: email);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }
  }

  /// Sends verification email for the currently signed-in user. No-op if signed out.
  Future<void> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return;
    try {
      await user.sendEmailVerification();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }
  }

  /// Forces a token refresh + reloads the user; useful after the user verifies
  /// email in another window so [User.emailVerified] flips to true on next read.
  Future<User?> reloadUser() async {
    final user = _auth.currentUser;
    if (user == null) return null;
    await user.reload();
    return user;
  }

  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }
  }

  /// Stream piped from [FirebaseAuth.authStateChanges].
  Stream<User?> authStateChanges() => _auth.authStateChanges();
}
