import 'package:firebase_auth/firebase_auth.dart';

import '../domain/auth_failure.dart';

class AuthService {
  AuthService({required FirebaseAuth firebaseAuth}) : _auth = firebaseAuth;

  final FirebaseAuth _auth;

  /// Creates the user, optionally sets [displayName], and sends verification
  /// email automatically (REQ-AUTH-003). Throws [AuthFailure].
  Future<User> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    try {
      final cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final user = cred.user!;
      if (displayName != null) {
        await user.updateDisplayName(displayName);
      }
      await user.sendEmailVerification();
      return user;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }
  }

  /// Throws [AuthFailure] on bad credentials, missing user, etc.
  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async {
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      return cred.user!;
    } on FirebaseAuthException catch (e) {
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
