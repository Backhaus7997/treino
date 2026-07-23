import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import 'fcm_token_repository.dart';

/// Thin service class responsible for FCM token lifecycle management.
///
/// Holds [FirebaseMessaging] and [FcmTokenRepository]. Exposes imperative
/// [init] and [dispose] methods driven by the Riverpod auth lifecycle
/// provider. Does NOT call [requestPermission] — that is owned by PR#2b's
/// PermissionGate widget.
///
/// ADR-PN-003. REQ-PN-CLIENT-002, REQ-PN-CLIENT-003.
class FcmService {
  FcmService({
    required FirebaseMessaging messaging,
    required FcmTokenRepository repository,
  })  : _messaging = messaging,
        _repo = repository;

  final FirebaseMessaging _messaging;
  final FcmTokenRepository _repo;

  StreamSubscription<String>? _refreshSub;

  /// QA-502: monotonic guard against interleaved lifecycle calls.
  ///
  /// `fcmLifecycleProvider` dispara [init]/[dispose] fire-and-forget en cada
  /// emisión de auth, así que un sign-in→sign-out (o sign-out→sign-in) rápido
  /// los intercala a través de sus huecos `await`. Cada llamada bumpea este
  /// contador y captura su propio valor; después de cada await se retira si otra
  /// llamada MÁS NUEVA la superó. Sin esto, un `init('A')` en vuelo resucita el
  /// token que un `dispose('A')` posterior acababa de borrar, y deja un listener
  /// de onTokenRefresh atado a 'A' que termina escribiendo el token de OTRO
  /// usuario en el documento de A.
  int _generation = 0;

  /// Initialises FCM for [uid]:
  /// 1. Calls [getToken] once and persists the result via [FcmTokenRepository].
  ///    On iOS, [getToken] throws `apns-token-not-set` when APNS isn't
  ///    provisioned yet (no permission granted, or iOS Simulator). The throw
  ///    is swallowed here — the caller (lifecycle provider) MUST NOT see it,
  ///    otherwise the trace propagates to Crashlytics as noise. A later
  ///    permission grant in [PermissionGate] re-invokes [init] to register
  ///    the token once APNS provisions. (SCENARIO-685.)
  /// 2. Subscribes to [onTokenRefresh] — each new token is persisted.
  ///    The subscription is registered EVEN IF [getToken] failed in step 1,
  ///    so that a later refresh after permission grant still saves a token.
  ///
  /// Does NOT call [requestPermission] (ADR-PN-003).
  /// REQ-PN-CLIENT-002, SCENARIO-645, 646, 647, 678, 685.
  Future<void> init(String uid) async {
    // init() is called twice in the normal flow: once on sign-in and again
    // from PermissionGate after a permission grant. Cancel any existing
    // subscription first so we never leak a listener or fire saveToken twice
    // on a token refresh. Mirrors the cleanup in dispose().
    // QA-502: reclamamos esta generación ANTES del primer await.
    final generation = ++_generation;

    await _refreshSub?.cancel();
    _refreshSub = null;

    try {
      final token = await _messaging.getToken();
      // QA-502: un dispose (o un login de otro uid) corrió mientras esperábamos
      // → NO reescribir el token que ya se borró.
      if (generation != _generation) return;
      if (token != null) {
        await _repo.saveToken(uid, token);
      }
    } on FirebaseException catch (e) {
      // Expected on iOS Simulator and on real iOS device pre-permission.
      // Token will be saved later via onTokenRefresh or the PermissionGate
      // re-init after grant.
      debugPrint('[fcm] init: getToken deferred — ${e.code}');
    } catch (e) {
      debugPrint('[fcm] init: unexpected getToken error for $uid — $e');
    }

    // QA-502: si nos superaron, no dejamos un listener atado a un uid viejo.
    if (generation != _generation) return;

    _refreshSub = _messaging.onTokenRefresh.listen((newToken) {
      // QA-502: cinturón y tiradores — un refresh que llegue entre la
      // supersesión y el cancel() no debe escribir en el doc del uid viejo.
      if (generation != _generation) return;
      _repo.saveToken(uid, newToken);
    });
  }

  /// Cleans up FCM for [uid] on sign-out:
  /// 1. Cancels the [onTokenRefresh] subscription.
  /// 2. Best-effort: gets the current token and removes it from Firestore.
  ///    Errors are swallowed — on a forced sign-out the user is already
  ///    unauthenticated and the rule denies the write.
  /// 3. QA-NOT-001: deletes the registration token on the DEVICE. This is
  ///    auth-independent, so it still runs when step 2 was denied — after it the
  ///    device stops receiving pushes addressed to the signed-out account.
  ///
  /// REQ-PN-CLIENT-003, SCENARIO-648, 649, 679.
  Future<void> dispose(String uid) async {
    // QA-502: reclamamos esta generación ANTES del primer await.
    final generation = ++_generation;

    await _refreshSub?.cancel();
    _refreshSub = null;

    try {
      final token = await _messaging.getToken();
      // QA-502: si mientras esperábamos entró un login nuevo, este dispose
      // quedó viejo → no tocar el token que ya pertenece al usuario nuevo.
      if (generation != _generation) return;
      if (token != null) {
        await _repo.removeToken(uid, token);
      }
    } catch (e) {
      debugPrint('[fcm] dispose: error removing token for $uid — $e');
    }

    // QA-NOT-001: invalidate the token device-side regardless of the Firestore
    // outcome. On forced sign-outs (token revocation, password change on another
    // device, Admin-SDK disable) auth is already null so removeToken above is
    // denied and the stale token would keep delivering the closed account's
    // pushes (including chat content). deleteToken() needs no auth; the next
    // login mints a fresh token via getToken().
    //
    // QA-502: pero SOLO si este dispose sigue siendo el vigente. Si un login
    // nuevo ya corrió, el token del device es del usuario NUEVO y borrarlo lo
    // dejaría sin push hasta el próximo refresh.
    if (generation != _generation) return;

    try {
      await _messaging.deleteToken();
    } catch (e) {
      debugPrint('[fcm] dispose: error deleting device token — $e');
    }
  }

  /// Requests notification permission from the OS.
  ///
  /// Called by PR#2b's PermissionGate widget post-onboarding.
  /// REQ-PN-PERM-001, REQ-PN-PERM-002.
  Future<NotificationSettings> requestPermission() =>
      _messaging.requestPermission();

  /// Stream of foreground messages (app in focus).
  /// REQ-PN-HANDLER-001.
  Stream<RemoteMessage> get onForegroundMessage => FirebaseMessaging.onMessage;

  /// Stream of messages that opened the app from the background.
  /// REQ-PN-HANDLER-002.
  Stream<RemoteMessage> get onMessageOpenedApp =>
      FirebaseMessaging.onMessageOpenedApp;

  /// Returns the message that launched the app from a terminated state,
  /// or null if the app was opened normally.
  /// REQ-PN-HANDLER-003.
  Future<RemoteMessage?> getInitialMessage() => _messaging.getInitialMessage();
}
