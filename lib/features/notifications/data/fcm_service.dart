import 'dart:async';

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

  /// Initialises FCM for [uid]:
  /// 1. Calls [getToken] once and persists the result via [FcmTokenRepository].
  /// 2. Subscribes to [onTokenRefresh] — each new token is persisted.
  ///
  /// Does NOT call [requestPermission] (ADR-PN-003).
  /// REQ-PN-CLIENT-002, SCENARIO-645, 646, 647, 678.
  Future<void> init(String uid) async {
    final token = await _messaging.getToken();
    if (token != null) {
      await _repo.saveToken(uid, token);
    }

    _refreshSub = _messaging.onTokenRefresh.listen((newToken) {
      _repo.saveToken(uid, newToken);
    });
  }

  /// Cleans up FCM for [uid] on sign-out:
  /// 1. Cancels the [onTokenRefresh] subscription.
  /// 2. Best-effort: gets the current token and removes it.
  ///    Errors are swallowed — user may already be signed out from Firestore.
  ///
  /// REQ-PN-CLIENT-003, SCENARIO-648, 649, 679.
  Future<void> dispose(String uid) async {
    await _refreshSub?.cancel();
    _refreshSub = null;

    try {
      final token = await _messaging.getToken();
      if (token != null) {
        await _repo.removeToken(uid, token);
      }
    } catch (e) {
      debugPrint('[fcm] dispose: error removing token for $uid — $e');
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
