import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/router/router_refresh_notifier.dart';
import '../data/apple_sign_in_gateway.dart';
import '../data/auth_service.dart';
import 'auth_notifier.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

/// Provider for the Apple Sign-In gateway (defaulted to the real implementation).
final appleSignInGatewayProvider = Provider<AppleSignInGateway>(
  (ref) => const RealAppleSignInGateway(),
);

final authServiceProvider = Provider<AuthService>(
  (ref) => AuthService(
    firebaseAuth: ref.watch(firebaseAuthProvider),
    appleGateway: ref.watch(appleSignInGatewayProvider),
  ),
);

/// Tracks whether the most recent sign-in created a new user account.
///
/// Etapa 6 (ProfileSetup) reads this to decide whether to route to the
/// profile-setup screen. Reset to false after routing.
// TODO(etapa-6): retire this provider once ProfileSetup routing
// consumes AuthOutcome.isNewUser directly from the notifier.
final lastSignInIsNewUserProvider = StateProvider<bool>((ref) => false);

final authStateChangesProvider = StreamProvider<User?>(
  (ref) => ref.watch(authServiceProvider).authStateChanges(),
);

final authNotifierProvider =
    AsyncNotifierProvider<AuthNotifier, User?>(AuthNotifier.new);

final routerRefreshNotifierProvider = Provider<RouterRefreshNotifier>((ref) {
  final notifier = RouterRefreshNotifier(ref);
  ref.onDispose(notifier.dispose);
  return notifier;
});
