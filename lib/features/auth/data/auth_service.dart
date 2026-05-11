import 'package:firebase_auth/firebase_auth.dart';

import '../domain/auth_failure.dart';
import '../../profile/data/user_repository.dart';

class AuthService {
  AuthService({
    required FirebaseAuth firebaseAuth,
    required UserRepository userRepository,
  })  : _auth = firebaseAuth,
        _userRepository = userRepository;

  final FirebaseAuth _auth;
  final UserRepository _userRepository;

  /// Creates the user, optionally sets [displayName], sends verification email,
  /// then atomically creates the Firestore profile doc (REQ-PROF-033).
  /// On Firestore failure: best-effort deletes the orphan Auth user and throws
  /// [AuthFailure.profileCreateFailed] (REQ-PROF-034 / REQ-PROF-035).
  Future<User> signUpWithEmail({
    required String email,
    required String password,
    String? displayName,
  }) async {
    late final UserCredential cred;
    try {
      cred = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }

    final user = cred.user!;
    final effectiveDisplayName = displayName ?? email.split('@').first;

    try {
      if (displayName != null) {
        await user.updateDisplayName(displayName);
      }
      await user.sendEmailVerification();

      try {
        await _userRepository.getOrCreate(
          uid: user.uid,
          email: email,
          displayName: effectiveDisplayName,
        );
      } catch (firestoreError) {
        // Rollback: best-effort delete the orphan Auth user.
        try {
          await user.delete();
        } catch (_) {
          // Swallow — profileCreateFailed is thrown regardless.
        }
        throw AuthFailure.profileCreateFailed(cause: firestoreError);
      }

      return user;
    } on AuthFailure {
      rethrow;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }
  }

  /// Throws [AuthFailure] on bad credentials, missing user, etc.
  /// After successful sign-in, best-effort backfills the Firestore doc for
  /// Etapa 2 users who do not yet have one (REQ-PROF-036 / REQ-PROF-037).
  Future<User> signInWithEmail({
    required String email,
    required String password,
  }) async {
    final User user;
    try {
      final cred = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      user = cred.user!;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }

    // Etapa 2 backfill — opportunistic, never blocks sign-in (REQ-PROF-037).
    try {
      await _userRepository.createIfAbsent(
        uid: user.uid,
        email: email,
        displayName: user.displayName ?? email.split('@').first,
      );
    } catch (_) {
      // Swallow — auth already succeeded; createIfAbsent is best-effort.
    }

    return user;
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
