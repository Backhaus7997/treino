import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/auth_failure.dart';
import '../../profile/data/user_repository.dart';

class AuthService {
  AuthService({
    required FirebaseAuth firebaseAuth,
    required UserRepository userRepository,
    GoogleSignIn? googleSignIn,
  })  : _auth = firebaseAuth,
        _userRepository = userRepository,
        _googleSignIn = googleSignIn ?? GoogleSignIn();

  final FirebaseAuth _auth;
  final UserRepository _userRepository;
  final GoogleSignIn _googleSignIn;

  /// Creates the user, sends verification email, then atomically creates the
  /// Firestore profile doc with `displayName: null` (REQ-PROF-033, REQ-AUTH-002).
  /// `displayName` is intentionally NOT collected at signup — ProfileSetup
  /// (Etapa 6) is the single owner of that field.
  /// On Firestore failure: best-effort deletes the orphan Auth user and throws
  /// [AuthFailure.profileCreateFailed] (REQ-PROF-034 / REQ-PROF-035).
  Future<User> signUpWithEmail({
    required String email,
    required String password,
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

    try {
      await user.sendEmailVerification();

      try {
        await _userRepository.getOrCreate(
          uid: user.uid,
          email: email,
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
    // Always writes `displayName: null` — ProfileSetup (Etapa 6) populates it.
    try {
      await _userRepository.createIfAbsent(
        uid: user.uid,
        email: email,
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

  /// Launches the native Google account picker and exchanges the OAuth
  /// credential with Firebase Auth. Firebase resolves new vs existing users
  /// transparently — this matches the standard one-button-fits-all UX of
  /// modern apps (Spotify, Notion, etc.).
  ///
  /// Throws [AuthFailure.signInCancelled] when the user dismisses the picker
  /// without selecting an account, [AuthFailure.networkError] on connectivity
  /// issues, and [AuthFailure.fromFirebase] for any FirebaseAuthException
  /// (e.g. account-exists-with-different-credential when the same email is
  /// already registered with a different provider).
  Future<User> signInWithGoogle() async {
    GoogleSignInAccount? googleUser;
    try {
      googleUser = await _googleSignIn.signIn();
    } catch (_) {
      // google_sign_in surfaces platform errors as PlatformException; we
      // surface them as a generic network failure to keep the domain clean.
      throw const AuthFailure.networkError();
    }
    if (googleUser == null) {
      // User dismissed the account picker.
      throw const AuthFailure.signInCancelled();
    }

    final googleAuth = await googleUser.authentication;
    final credential = GoogleAuthProvider.credential(
      idToken: googleAuth.idToken,
      accessToken: googleAuth.accessToken,
    );

    try {
      final cred = await _auth.signInWithCredential(credential);
      return cred.user!;
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }
  }

  Future<void> signOut() async {
    try {
      // Disconnect Google session too — otherwise a subsequent signIn() would
      // silently re-use the cached account without showing the picker.
      await _googleSignIn.signOut();
      await _auth.signOut();
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }
  }

  /// Stream piped from [FirebaseAuth.authStateChanges].
  Stream<User?> authStateChanges() => _auth.authStateChanges();
}
