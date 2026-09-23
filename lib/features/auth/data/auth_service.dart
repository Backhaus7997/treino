import 'dart:async';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' hide generateNonce;

import '../../../core/telemetry/non_fatal.dart';
import '../domain/auth_failure.dart';
import '../presentation/legal/legal_content.dart';
import '../../profile/data/account_deletion_service.dart';
import '../../profile/data/user_repository.dart';
import 'apple_sign_in_gateway.dart';
import 'nonce_helpers.dart';

class AuthService {
  AuthService({
    required FirebaseAuth firebaseAuth,
    required UserRepository userRepository,
    FirebaseFunctions? functions,
    GoogleSignIn? googleSignIn,
    AppleSignInGateway appleGateway = const RealAppleSignInGateway(),
    NonFatalReporter? nonFatalReporter,
  })  : _auth = firebaseAuth,
        _userRepository = userRepository,
        _injectedFunctions = functions,
        _googleSignIn = googleSignIn ?? GoogleSignIn.instance,
        _appleGateway = appleGateway,
        _reportNonFatal = nonFatalReporter ?? reportNonFatal;

  /// La misma región de todas las CFs de TREINO. Si no coincide, la llamada
  /// sale a `us-central1` y devuelve NOT_FOUND.
  static const _functionsRegion = 'southamerica-east1';

  final FirebaseFunctions? _injectedFunctions;

  /// Perezoso A PROPÓSITO. `FirebaseFunctions.instanceFor` resuelve la app
  /// `[DEFAULT]` en el acto, así que construirlo en la lista de
  /// inicialización ataba la CONSTRUCCIÓN de `AuthService` a que
  /// `Firebase.initializeApp()` ya hubiera terminado — incluso para los
  /// caminos que nunca mandan un mail (reauth, signOut).
  /// El provider de Riverpod lo arma eager, así que eso convertía un detalle
  /// del canal de mails en una precondición de toda la capa de auth.
  late final FirebaseFunctions _functions = _injectedFunctions ??
      FirebaseFunctions.instanceFor(region: _functionsRegion);

  final FirebaseAuth _auth;
  final UserRepository _userRepository;
  final GoogleSignIn _googleSignIn;
  final AppleSignInGateway _appleGateway;
  final NonFatalReporter _reportNonFatal;

  /// El `createIfAbsent` de después del login sigue siendo best-effort —el
  /// login ya salió bien y no se rompe por esto—, pero ya no en silencio.
  ///
  /// En producción, en 3 de las 5 altas con Google/Apple del 16 al 22/09,
  /// `users/{uid}` no nació en el login: apareció entre 34 y 95 s después.
  /// Mientras tanto la cuenta recorrió el alta sin documento, y el paso de
  /// gimnasio, que escribía ahí, fallaba. El `catch (_) {}` que había en los
  /// tres logins se tragó el porqué, y sin él no hay forma de saberlo.
  void _reportarAltaFallida(Object error, StackTrace stack, String camino) {
    unawaited(_reportNonFatal(
      error,
      stack,
      reason: 'AuthService.$camino: createIfAbsent falló después del login',
    ));
  }

  /// Creates the user, best-effort sends the verification email (a failure here
  /// is swallowed — it can be resent later), then atomically creates the
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
      // Verification is best-effort: a failure here must NOT orphan the
      // freshly created Auth user. The user can re-send later via
      // [sendEmailVerification] from the verify-email screen.
      //
      // El catch es a TODO a propósito, y el `on FirebaseAuthException` de
      // antes ya se quedaba corto: el `catch` de rollback vive adentro del
      // try de `getOrCreate`, así que cualquier excepción que se escape de
      // acá saltea la creación del perfil Y el rollback. El usuario queda en
      // Auth, sin doc en Firestore y sin nadie que lo limpie. Con el mail
      // saliendo por un callable la superficie se ensancha
      // (FirebaseFunctionsException, AuthFailure, red), así que el catch
      // tiene que cubrir lo que el comentario ya prometía.
      try {
        await sendEmailVerification();
      } catch (_) {
        // Swallow — signup continues; verification can be resent.
      }

      try {
        await _userRepository.getOrCreate(
          uid: user.uid,
          email: email,
          // Only signUpWithEmail reaches this line with the Register Terms
          // checkbox already accepted (register_screen.dart gates the call
          // that leads here) — so the signup itself IS the email flow's
          // consent event (QA-AUTH-001, issue #434).
          termsAcceptedAt: DateTime.now().toUtc(),
          // consentimiento-legal-versionado (R3): the same checkbox accepts
          // BOTH documents at their current text, so both versions are
          // stamped in this same call.
          acceptedTermsVersion: kTermsVersion,
          acceptedPrivacyVersion: kPrivacyVersion,
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
    } catch (e, st) {
      _reportarAltaFallida(e, st, 'signInWithEmail');
    }

    return user;
  }

  /// Traduce el fallo de un callable a un [AuthFailure] con copy accionable.
  ///
  /// ─── Por que solo `unavailable` ────────────────────────────────────────────
  ///
  /// El plugin `cloud_functions` NORMALIZA el code en el lado nativo, a
  /// proposito, para que Android, iOS y Web coincidan
  /// (FlutterFirebaseFunctionsPlugin.kt:129-141):
  ///
  ///   - `IOException` de red        -> `unavailable`
  ///   - cancel / timeout            -> `deadline-exceeded`
  ///   - la funcion corrio y fallo   -> `internal`
  ///
  /// O sea que `unavailable` ES el modo avion, y es el unico que lo es.
  /// `internal` NO: significa que el server contesto y algo se rompio adentro;
  /// mandarlo a "Sin conexion" seria mentirle al usuario en la direccion
  /// contraria, y lo dejaria mirando el wifi mientras el problema es nuestro.
  ///
  /// `deadline-exceeded` queda afuera a proposito: en `southamerica-east1` un
  /// cold start puede agotar el plazo con la conexion perfecta. "Algo salio
  /// mal, intenta de nuevo" es el consejo correcto para un timeout; "revisa tu
  /// internet" no.
  AuthFailure _failureFromCallable(FirebaseFunctionsException e) =>
      switch (e.code) {
        'unavailable' => const AuthFailure.networkError(),
        final code => AuthFailure.unknown(code),
      };

  /// Pide el mail de reseteo a la CF `requestPasswordReset`.
  ///
  /// Ya NO llama a `FirebaseAuth.sendPasswordResetEmail`. El servidor manda el
  /// mail por Resend, con el dominio de TREINO — el de Firebase salía de
  /// `noreply@treino-dev.firebaseapp.com` y caía en spam.
  ///
  /// Y hace algo que el SDK no puede: si la cuenta no tiene contraseña porque
  /// se creó con Google o Apple, manda un mail distinto explicando cómo entrar,
  /// en vez de un link de reseteo que no aplica. Antes ese caso no producía
  /// NADA — ni mail ni error — y el usuario quedaba sin salida ni señal.
  ///
  /// La respuesta es uniforme para las tres ramas (existe con contraseña,
  /// existe federada, no existe), así que la anti-enumeración de REQ-AUTH-011
  /// se sostiene del lado del servidor y no depende de esta pantalla.
  ///
  /// Throws [AuthFailure] sólo si la llamada misma falla (red, backend caído).
  /// Nunca por el estado de la cuenta.
  Future<void> sendPasswordResetEmail({required String email}) async {
    try {
      final callable = _functions.httpsCallable('requestPasswordReset');
      await callable.call<Map<String, dynamic>>({'email': email});
    } on FirebaseFunctionsException catch (e) {
      throw _failureFromCallable(e);
    } catch (e) {
      throw const AuthFailure.unknown('reset-request-failed');
    }
  }

  /// Pide el mail de verificación a la CF `requestEmailVerification`.
  ///
  /// No-op si no hay sesión: el callable exige `request.auth`, así que sin
  /// usuario la llamada moriría con `unauthenticated`. Se corta antes.
  ///
  /// Igual que el reseteo, el mail sale por Resend con el dominio propio en
  /// vez de las plantillas de Firebase.
  Future<void> sendEmailVerification() async {
    if (_auth.currentUser == null) return;
    try {
      final callable = _functions.httpsCallable('requestEmailVerification');
      await callable.call<Map<String, dynamic>>(<String, dynamic>{});
    } on FirebaseFunctionsException catch (e) {
      throw _failureFromCallable(e);
    } catch (e) {
      throw const AuthFailure.unknown('verification-request-failed');
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
    } catch (e, st) {
      _reportarAltaFallida(e, st, 'signInWithGoogle');
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
    } catch (e, st) {
      _reportarAltaFallida(e, st, 'signInWithApple');
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
  /// Sentinel providerId used by [getAppleCredential] to signal that the
  /// re-authentication was already performed by Firebase's
  /// `reauthenticateWithProvider` flow (which bypasses the nonce-cache
  /// quirks of sign_in_with_apple's native iOS sheet on re-auth). When
  /// [reauthenticate] sees this providerId, it short-circuits since the
  /// re-auth has already happened server-side.
  static const String _appleReauthDoneSentinelProviderId =
      '__apple_reauth_done_sentinel__';

  Future<void> reauthenticate(AuthCredential credential) async {
    // Apple re-auth already completed by getAppleCredential. See sentinel doc.
    if (credential.providerId == _appleReauthDoneSentinelProviderId) return;

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

  /// Triggers Apple re-authentication via Firebase's
  /// `reauthenticateWithProvider` flow. Returns a SENTINEL credential that
  /// [reauthenticate] recognizes as "already done, skip" — because the
  /// actual re-auth is performed server-side by Firebase inside this method,
  /// not separately as in the email/password / Google paths.
  ///
  /// Why not the same shape as [signInWithApple] / [getGoogleCredential]?
  /// On iOS, `sign_in_with_apple`'s native sheet on RE-auth (after a prior
  /// successful Apple sign-in) tends to return a cached identityToken whose
  /// embedded nonce no longer matches the fresh rawNonce we generate, and
  /// Firebase rejects the credential with `missing-or-invalid-nonce`.
  /// Firebase's `reauthenticateWithProvider(OAuthProvider('apple.com'))`
  /// drives the OAuth dance internally and handles the nonce correctly.
  ///
  /// Throws [AuthFailure.signInCancelled] on user-cancel.
  /// Throws [AuthFailure.reAuthFailed] on other Apple errors.
  // i18n: Fase 6 Etapa 3
  Future<AuthCredential> getAppleCredential() async {
    final user = _auth.currentUser;
    if (user == null) {
      throw const AuthFailure.userNotFound();
    }

    try {
      await user.reauthenticateWithProvider(OAuthProvider('apple.com'));
    } on FirebaseAuthException catch (e) {
      // iOS surfaces user-cancel via several codes depending on iOS version
      // and which native sheet was active.
      const cancelCodes = {
        'cancelled-popup-request',
        'web-context-cancelled',
        'web-context-canceled',
        'user-cancelled',
        'popup-closed-by-user',
      };
      if (cancelCodes.contains(e.code)) {
        throw const AuthFailure.signInCancelled();
      }
      throw const AuthFailure.reAuthFailed(provider: 'apple.com');
    } catch (_) {
      throw const AuthFailure.reAuthFailed(provider: 'apple.com');
    }

    // Sentinel — reauthenticate() short-circuits on this providerId.
    return OAuthProvider(_appleReauthDoneSentinelProviderId)
        .credential(accessToken: 'sentinel');
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
  /// from ProfileSetup step 0. Va por el MISMO camino que «Eliminar cuenta» de
  /// Ajustes: el callable `deleteAccount`, que corre la cascada completa y
  /// borra la cuenta de Auth al final. Acá sólo queda cerrar la sesión local,
  /// y la de Google para que el próximo picker salga limpio.
  ///
  /// Throws [AuthFailure.deletionFailed] si el callable falla o si la cuenta
  /// de Auth sigue existiendo. En ese caso no toca la sesión: la cuenta sigue
  /// viva y entera, y la persona puede reintentar.
  Future<void> cancelOnboarding() async {
    final user = _auth.currentUser;
    if (user == null) return;

    // Acá antes estaba `UserRepository.delete`, que tira SIEMPRE (las reglas
    // le niegan el delete al cliente): el catch se lo tragaba, `user.delete()`
    // borraba sólo la cuenta de Auth, y `users/{uid}` y
    // `userPublicProfiles/{uid}` quedaban para siempre, con el mail de alguien
    // que pidió no tener cuenta.
    //
    // La cascada es la COMPLETA y no una corta del alta: el alta sin terminar
    // se reconoce por `displayName == null`, y ese campo el dueño lo puede
    // volver a null (las reglas no lo pinean). Una cascada corta sobre una
    // cuenta establecida le dejaba huérfanos los posts, rutinas y vínculos.
    final DeletionResult resultado;
    try {
      resultado = await AccountDeletionService(functions: _functions)
          .call(uid: user.uid);
    } catch (e) {
      // Un error no prueba que el servidor no haya borrado: la respuesta se
      // puede perder con la cascada ya hecha. Si Auth confirma que la cuenta
      // no existe, la baja salió, y tirar acá restauraría la sesión en la
      // pantalla y reactivaría los reintentos del alta sobre una cuenta
      // borrada.
      if (await _laCuentaYaNoExiste(user)) {
        await _cerrarSesionDeCuentaBorrada();
        return;
      }
      // Viva, o sin forma de saberlo: no se sigue. Borrar Auth sin la cascada
      // es exactamente lo que dejaba los docs sin dueño.
      throw AuthFailure.deletionFailed(cause: e);
    }

    // La misma señal que usa Ajustes (`AccountDeletionNotifier`): la cuenta se
    // fue si y sólo si el servidor llegó a borrar Auth. Un `partial` sin eso es
    // una cuenta viva, y se reintenta.
    if (!resultado.deletedCollections.contains('users-auth')) {
      throw AuthFailure.deletionFailed(cause: resultado.errors);
    }

    await _cerrarSesionDeCuentaBorrada();
  }

  /// Lo que contesta Auth sobre una cuenta que ya no existe del lado del
  /// servidor aunque este cliente todavía tenga su token.
  static const _codigosDeCuentaInexistente = {
    'user-not-found',
    'user-token-expired',
    'invalid-user-token',
  };

  /// `true` sólo si Auth CONFIRMA que la cuenta ya no existe. Sin red, o ante
  /// cualquier otra respuesta, `false`: se la trata como viva.
  Future<bool> _laCuentaYaNoExiste(User user) async {
    try {
      await user.reload();
      return false;
    } on FirebaseAuthException catch (e) {
      return _codigosDeCuentaInexistente.contains(e.code);
    } catch (_) {
      return false;
    }
  }

  /// La cuenta ya no existe: queda la sesión local. NO tira. Si tirara,
  /// `AuthNotifier` restauraría el usuario y la pantalla reactivaría los
  /// reintentos del alta sobre una cuenta borrada.
  Future<void> _cerrarSesionDeCuentaBorrada() async {
    try {
      await _auth.signOut();
    } catch (e, st) {
      unawaited(_reportNonFatal(
        e,
        st,
        reason: 'AuthService.cancelOnboarding: signOut falló con la cuenta '
            'ya borrada',
      ));
    }

    // Cleanup Google session cache. Only matters if the user signed up with
    // Google.
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Ignore — best-effort cleanup.
    }
  }

  /// Stream piped from [FirebaseAuth.authStateChanges].
  Stream<User?> authStateChanges() => _auth.authStateChanges();
}
