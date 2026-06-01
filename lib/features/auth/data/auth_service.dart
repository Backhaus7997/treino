import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' hide generateNonce;

import '../domain/auth_failure.dart';
import '../../profile/data/user_repository.dart';
import 'apple_sign_in_gateway.dart';
import 'nonce_helpers.dart';

class AuthService {
  AuthService({
    required FirebaseAuth firebaseAuth,
    required UserRepository userRepository,
    GoogleSignIn? googleSignIn,
    AppleSignInGateway appleGateway = const RealAppleSignInGateway(),
  })  : _auth = firebaseAuth,
        _userRepository = userRepository,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
        _appleGateway = appleGateway;

  final FirebaseAuth _auth;
  final UserRepository _userRepository;
  final GoogleSignIn _googleSignIn;
  final AppleSignInGateway _appleGateway;

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
  /// without selecting an account, [AuthFailure.unknown] with the underlying
  /// provider/platform code for any other non-cancel failure (interrupted,
  /// config errors, platform exceptions, etc.), and [AuthFailure.fromFirebase]
  /// for any FirebaseAuthException (e.g. account-exists-with-different-credential
  /// when the same email is already registered with a different provider).
  ///
  /// google_sign_in 7.x splits authentication and authorization:
  /// `authenticate()` returns an idToken-only account; the accessToken needed
  /// by [GoogleAuthProvider.credential] comes from a separate authorization
  /// flow via [GoogleSignInAccount.authorizationClient.authorizeScopes].
  Future<User> signInWithGoogle() async {
    final GoogleSignInAccount googleUser;
    try {
      googleUser = await _googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthFailure.signInCancelled();
      }
      throw AuthFailure.unknown(e.code.name);
    } on PlatformException catch (e) {
      throw AuthFailure.unknown(e.code);
    }

    final GoogleSignInClientAuthorization authorization;
    try {
      authorization = await googleUser.authorizationClient
          .authorizeScopes(const <String>['email']);
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthFailure.signInCancelled();
      }
      throw AuthFailure.unknown(e.code.name);
    } on PlatformException catch (e) {
      throw AuthFailure.unknown(e.code);
    }

    final credential = GoogleAuthProvider.credential(
      idToken: googleUser.authentication.idToken,
      accessToken: authorization.accessToken,
    );

    final UserCredential cred;
    try {
      cred = await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }

    // Etapa 2 backfill — opportunistic, never blocks sign-in (REQ-PROF-036 / REQ-PROF-037).
    // Always writes `displayName: null` — ProfileSetup (Etapa 6) populates it.
    // Defensive `?? ''` on email: Firebase Auth's User.email is nullable even
    // though Google always provides one.
    try {
      await _userRepository.createIfAbsent(
        uid: cred.user!.uid,
        email: cred.user!.email ?? '',
      );
    } catch (_) {
      // Swallow — auth already succeeded; createIfAbsent is best-effort.
    }

    return cred.user!;
  }

  /// Launches the native Apple Sign-In sheet and exchanges the OAuth
  /// credential with Firebase Auth. Mirrors [signInWithGoogle] — Firebase
  /// resolves new vs existing users transparently; ProfileSetup (Etapa 6)
  /// owns the displayName, so we never call [User.updateDisplayName] here.
  ///
  /// Throws [AuthFailure.signInCancelled] when the user dismisses the native
  /// sheet, [AuthFailure.unknown] with the Apple authorization code for any
  /// other Apple-side failure, and [AuthFailure.fromFirebase] for any
  /// FirebaseAuthException.
  ///
  /// Crucial: passes the Apple `authorizationCode` as `accessToken` to
  /// [OAuthProvider.credential] — without it, Firebase fails to validate the
  /// identity token server-side and returns `invalid-credential`.
  Future<User> signInWithApple() async {
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
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AuthFailure.signInCancelled();
      }
      throw AuthFailure.unknown(e.code.name);
    } catch (_) {
      throw const AuthFailure.unknown('apple-unknown');
    }

    final oauthCredential = OAuthProvider('apple.com').credential(
      idToken: appleCred.identityToken,
      rawNonce: rawNonce, // RAW to Firebase
      accessToken: appleCred.authorizationCode,
    );

    final UserCredential cred;
    try {
      cred = await _auth.signInWithCredential(oauthCredential);
    } on FirebaseAuthException catch (e) {
      throw AuthFailure.fromFirebase(e);
    }

    // Etapa 2 backfill — mirrors Google flow (REQ-PROF-036 / REQ-PROF-037).
    // Apple may not return an email after the first sign-in; defensive `?? ''`.
    try {
      await _userRepository.createIfAbsent(
        uid: cred.user!.uid,
        email: cred.user!.email ?? '',
      );
    } catch (_) {
      // Swallow — auth already succeeded; createIfAbsent is best-effort.
    }

    return cred.user!;
  }

  // ── Re-auth helpers (Fase 6 Etapa 3 — account-deletion PR#3) ────────────────
  //
  // Per ADR-ACCDEL-009: AuthService stays thin. These methods expose Firebase
  // re-auth and per-provider credential builders. ALL orchestration lives in
  // AccountDeletionNotifier.

  /// Re-authenticates the current user with [credential].
  ///
  /// Throws [AuthFailure.userNotFound] when there is no signed-in user.
  /// Throws [AuthFailure.reAuthFailed] on wrong-password / invalid-credential.
  /// Throws [AuthFailure.fromFirebase] for any other FirebaseAuthException.
  Future<void> reauthenticate(AuthCredential credential) async {
    final user = _auth.currentUser;
    if (user == null) throw const AuthFailure.userNotFound();
    try {
      await user.reauthenticateWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
        throw const AuthFailure.reAuthFailed();
      }
      throw AuthFailure.fromFirebase(e);
    }
  }

  /// Returns an [EmailAuthProvider] credential for the current user.
  ///
  /// Throws [AuthFailure.reAuthFailed] when there is no signed-in user or
  /// the current user has no email.
  // i18n: Fase 6 Etapa 3
  Future<AuthCredential> getPasswordCredential({
    required String password,
  }) async {
    final user = _auth.currentUser;
    if (user == null || user.email == null) {
      throw const AuthFailure.reAuthFailed(provider: 'password');
    }
    return EmailAuthProvider.credential(
      email: user.email!,
      password: password,
    );
  }

  /// Triggers the Google sign-in flow and returns a [GoogleAuthProvider]
  /// credential suitable for re-authentication.
  ///
  /// Unlike [signInWithGoogle], this re-auth helper does NOT call
  /// `authorizationClient.authorizeScopes(...)`. On iOS each OAuth-style
  /// call opens its own ASWebAuthenticationSession, which surfaces the
  /// system "treino quiere utilizar google.com" sheet — so requesting
  /// scopes in addition to authenticate() would surface that sheet TWICE
  /// in a row (poor UX during a deletion confirmation). Firebase's
  /// `reauthenticateWithCredential` only needs the `idToken` to verify
  /// identity; the accessToken is optional and unused for re-auth.
  ///
  /// Throws [AuthFailure.signInCancelled] on user-cancel.
  /// Throws [AuthFailure.reAuthFailed] on other Google errors.
  // i18n: Fase 6 Etapa 3
  Future<AuthCredential> getGoogleCredential() async {
    final GoogleSignInAccount googleUser;
    try {
      googleUser = await _googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        throw const AuthFailure.signInCancelled();
      }
      throw const AuthFailure.reAuthFailed(provider: 'google.com');
    }

    return GoogleAuthProvider.credential(
      idToken: googleUser.authentication.idToken,
    );
  }

  /// Triggers Apple Sign-In and returns an [OAuthProvider] credential
  /// suitable for re-authentication.
  ///
  /// Throws [AuthFailure.signInCancelled] on user-cancel.
  /// Throws [AuthFailure.reAuthFailed] on other Apple errors.
  // i18n: Fase 6 Etapa 3
  Future<AuthCredential> getAppleCredential() async {
    final rawNonce = generateNonce();
    final hashedNonce = sha256OfString(rawNonce);

    final AuthorizationCredentialAppleID appleCred;
    try {
      appleCred = await _appleGateway.getAppleIDCredential(
        scopes: const [AppleIDAuthorizationScopes.email],
        nonce: hashedNonce,
      );
    } on SignInWithAppleAuthorizationException catch (e) {
      if (e.code == AuthorizationErrorCode.canceled) {
        throw const AuthFailure.signInCancelled();
      }
      throw const AuthFailure.reAuthFailed(provider: 'apple.com');
    } catch (_) {
      throw const AuthFailure.reAuthFailed(provider: 'apple.com');
    }

    return OAuthProvider('apple.com').credential(
      idToken: appleCred.identityToken,
      rawNonce: rawNonce,
      accessToken: appleCred.authorizationCode,
    );
  }

  // ── End re-auth helpers ────────────────────────────────────────────────────

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

  /// Hard-cancel onboarding for a user who just signed up and wants to bail
  /// from ProfileSetup step 0. Deletes the Firestore profile doc (best-effort)
  /// and then the Firebase Auth user (mandatory). The Auth delete auto-signs
  /// the user out; we still clean the Google session cache so the next picker
  /// shows fresh.
  ///
  /// Throws [AuthFailure] on Firebase Auth delete failure (e.g.
  /// `requires-recent-login` on stale tokens). On Firestore delete failure
  /// we swallow and proceed — the Auth delete is the source of truth for
  /// account existence.
  Future<void> cancelOnboarding() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Best-effort delete of the Firestore profile doc.
    try {
      await _userRepository.delete(user.uid);
    } catch (_) {
      // Continue — Auth delete is what removes the account from Firebase.
    }

    // Mandatory delete of the Firebase Auth user.
    try {
      await user.delete();
    } on FirebaseAuthException catch (e) {
      // Stale-auth escape hatch: if the user no longer exists server-side
      // (e.g., previously deleted by the account-deletion Cloud Function or
      // by Firebase Console while this client still had a cached token),
      // user.delete() returns user-not-found / token-expired. The local
      // session is the only thing left to clean up — force-sign-out so the
      // user is not stuck in a phantom auth state on profile-setup.
      const staleAuthCodes = {
        'user-not-found',
        'user-token-expired',
        'invalid-user-token',
      };
      if (staleAuthCodes.contains(e.code)) {
        await _auth.signOut();
      } else {
        throw AuthFailure.fromFirebase(e);
      }
    }

    // Cleanup Google session cache. Firebase Auth is already cleared by
    // user.delete(); this only matters if the user used Google to sign up.
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Ignore — best-effort cleanup.
    }
  }

  /// Stream piped from [FirebaseAuth.authStateChanges].
  Stream<User?> authStateChanges() => _auth.authStateChanges();
}
