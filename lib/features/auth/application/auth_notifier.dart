import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_providers.dart';

class AuthNotifier extends AsyncNotifier<User?> {
  @override
  Future<User?> build() async {
    // Listen to subsequent stream emissions imperatively (ref.listen does NOT
    // rerun build(), so in-flight imperative actions are never clobbered).
    ref.listen<AsyncValue<User?>>(authStateChangesProvider, (prev, next) {
      next.whenData((user) => state = AsyncData(user));
    });

    // Seed with the current / first emission (one-shot watch for initial value).
    return ref.watch(authStateChangesProvider.future);
  }

  Future<void> signIn({required String email, required String password}) async {
    final service = ref.read(authServiceProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final outcome = await service.signInWithEmail(
        email: email,
        password: password,
      );
      if (outcome != null) {
        ref.read(lastSignInIsNewUserProvider.notifier).state =
            outcome.isNewUser;
      }
      return outcome?.user;
    });
  }

  Future<void> signUp({
    required String email,
    required String password,
    String? displayName,
  }) async {
    final service = ref.read(authServiceProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final outcome = await service.signUpWithEmail(
        email: email,
        password: password,
        displayName: displayName,
      );
      if (outcome != null) {
        ref.read(lastSignInIsNewUserProvider.notifier).state =
            outcome.isNewUser;
      }
      return outcome?.user;
    });
  }

  /// Signs in with Apple native sheet (iOS only).
  ///
  /// When the user cancels, state is restored to the previous value
  /// (typically AsyncData(null) on the login screen) — no error emitted.
  Future<void> signInWithApple() async {
    final service = ref.read(authServiceProvider);
    final previousUser = state.valueOrNull;

    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final outcome = await service.signInWithApple();
      if (outcome == null) return previousUser; // cancel: restore prior state
      ref.read(lastSignInIsNewUserProvider.notifier).state = outcome.isNewUser;
      return outcome.user;
    });
  }

  Future<void> sendPasswordResetEmail({required String email}) async {
    final service = ref.read(authServiceProvider);
    final currentUser = state.valueOrNull;
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => service.sendPasswordResetEmail(email: email),
    );
    // Restore user value — password reset does not change auth state.
    state = AsyncData(currentUser);
    // Rethrow so screens can handle failure cases (e.g. mask userNotFound).
    if (result is AsyncError) throw result.error;
  }

  Future<void> sendEmailVerification() async {
    final service = ref.read(authServiceProvider);
    await AsyncValue.guard(() => service.sendEmailVerification());
  }

  Future<void> reloadUser() async {
    final service = ref.read(authServiceProvider);
    final user = await AsyncValue.guard(() => service.reloadUser());
    user.whenData((u) => state = AsyncData(u));
  }

  Future<void> signOut() async {
    final service = ref.read(authServiceProvider);
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await service.signOut();
      return null;
    });
  }
}
