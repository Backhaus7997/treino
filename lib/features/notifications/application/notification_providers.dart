import 'package:cloud_firestore/cloud_firestore.dart' show FirebaseFirestore;
import 'package:firebase_auth/firebase_auth.dart' show User;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../profile/application/user_providers.dart';
import '../data/fcm_service.dart';
import '../data/fcm_token_repository.dart';

/// Provides the [FirebaseMessaging] singleton.
final firebaseMessagingProvider = Provider<FirebaseMessaging>(
  (ref) => FirebaseMessaging.instance,
);

/// Provides [FcmTokenRepository] wired with [FirebaseFirestore.instance].
final fcmTokenRepositoryProvider = Provider<FcmTokenRepository>(
  (ref) => FcmTokenRepository(firestore: ref.watch(firestoreProvider)),
);

/// Provides the [FcmService] singleton wired with messaging + repository.
///
/// ADR-PN-003. REQ-PN-CLIENT-002, REQ-PN-CLIENT-003.
final fcmServiceProvider = Provider<FcmService>(
  (ref) => FcmService(
    messaging: ref.watch(firebaseMessagingProvider),
    repository: ref.watch(fcmTokenRepositoryProvider),
  ),
);

/// Lifecycle provider that wires [FcmService] to the auth state stream.
///
/// When a user signs in (non-null uid emitted) → calls [FcmService.init].
/// When a user signs out (null emitted after non-null) → calls [FcmService.dispose].
///
/// Must be eagerly read in [TreinoApp.initState] to register the listener
/// for the app lifetime. (ADR-PN-003, REQ-PN-CLIENT-004, SCENARIO-650, 651, 683.)
final fcmLifecycleProvider = Provider<void>((ref) {
  ref.listen<AsyncValue<User?>>(
    authStateChangesProvider,
    (prev, next) {
      final fcm = ref.read(fcmServiceProvider);

      next.whenData((user) {
        if (user != null) {
          // User signed in — initialise FCM token lifecycle.
          fcm.init(user.uid);
        } else {
          // User signed out — clean up the token if we had a previous user.
          final prevUser = prev?.valueOrNull;
          if (prevUser != null) {
            fcm.dispose(prevUser.uid);
          }
        }
      });
    },
    fireImmediately: false,
  );
});
