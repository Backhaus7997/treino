import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/application/auth_providers.dart';
import '../../auth/domain/auth_failure.dart';
import '../../profile_setup/application/profile_setup_providers.dart';
import '../data/account_deletion_service.dart';
import '../presentation/widgets/re_auth_bottom_sheet.dart';

/// Orchestrates the full account deletion flow per ADR-ACCDEL-009:
///
///   1. Open ReAuthBottomSheet → get AuthCredential?
///   2. If null (cancelled) → stay idle
///   3. AuthService.reauthenticate(credential)
///   4. AccountDeletionService.call(uid)
///   5. On success → signOut → state = AsyncData(null)
///   6. On partial/error → state = AsyncError(AuthFailure)
///
/// Retry policy per ADR-ACCDEL-011:
///   - Within 5 min of last re-auth → skip re-auth sheet, call CF directly
///   - After 5 min → full re-auth path
class AccountDeletionNotifier extends AsyncNotifier<void> {
  AccountDeletionNotifier() : _sheetOpener = null;

  /// Constructor used by tests to inject a fake sheet opener that does not
  /// require a real BuildContext / Navigator.
  AccountDeletionNotifier.withSheetOpener(
    Future<AuthCredential?> Function() sheetOpener,
  ) : _sheetOpener = sheetOpener;

  /// Overridable sheet opener. When null, [_openReAuthSheet] uses the real
  /// showModalBottomSheet with a BuildContext.
  final Future<AuthCredential?> Function()? _sheetOpener;

  /// Timestamp of the last successful re-authentication.
  /// Used to implement the 5-minute retry window (ADR-ACCDEL-011).
  DateTime? _lastReauthAt;

  @override
  Future<void> build() async {}

  /// Initiates the full deletion flow: shows re-auth sheet, authenticates,
  /// calls CF, signs out.
  ///
  /// [context] is used to open the re-auth sheet. May be null in tests
  /// when [_sheetOpener] is injected.
  Future<void> deleteAccount([BuildContext? context]) async {
    final credential = await _openReAuthSheet(context);
    if (credential == null) {
      debugPrint('[AccountDeletion] re-auth sheet returned null — aborted');
      return;
    }

    state = const AsyncLoading();
    try {
      final authService = ref.read(authServiceProvider);
      await authService.reauthenticate(credential);
      _lastReauthAt = DateTime.now();
      await _callCfAndFinish();
    } on AuthFailure catch (e) {
      debugPrint('[AccountDeletion] AuthFailure: $e');
      state = AsyncError(e, StackTrace.current);
    } catch (e, st) {
      debugPrint('[AccountDeletion] unexpected error: $e\n$st');
      state = AsyncError(AuthFailure.deletionFailed(cause: e), st);
    }
  }

  /// Retries without re-auth if within the 5-min window (ADR-ACCDEL-011).
  Future<void> retry([BuildContext? context]) async {
    final reauthFresh = _lastReauthAt != null &&
        DateTime.now().difference(_lastReauthAt!) < const Duration(minutes: 5);
    if (!reauthFresh) {
      // Window expired — full re-auth path.
      await deleteAccount(context);
      return;
    }
    state = const AsyncLoading();
    try {
      await _callCfAndFinish();
    } catch (e, st) {
      state = AsyncError(_mapError(e), st);
    }
  }

  /// Calls the CF and, on success, signs out and emits [AsyncData(null)].
  ///
  /// Manages [accountDeletionInFlightProvider] for the full duration of the
  /// CF cascade so BOTH entry paths ([deleteAccount] and [retry]) defer the
  /// router's loggedIn=true + profile=null → /profile-setup redirect during
  /// the window where the Firestore profile is deleted before the Auth user.
  Future<void> _callCfAndFinish() async {
    ref.read(accountDeletionInFlightProvider.notifier).state = true;
    try {
      final service = ref.read(accountDeletionServiceProvider);
      final firebaseAuth = ref.read(firebaseAuthProvider);
      final uid = firebaseAuth.currentUser?.uid;
      if (uid == null) {
        state = AsyncError(
          const AuthFailure.userNotFound(),
          StackTrace.current,
        );
        return;
      }

      final result = await service.call(uid: uid);
      debugPrint(
        '[AccountDeletion] CF returned: status=${result.status}, '
        'deletedCollections=${result.deletedCollections}, errors=${result.errors}',
      );

      // The definitive signal that the account is gone: Auth user deleted.
      // CF reports 'partial' when any non-auth cascade step errors (e.g.,
      // sweeping friendships with a missing index, audit log write fails) —
      // but if Auth was deleted, the user's account is effectively gone and
      // we MUST sign out + redirect. Treating partial-with-auth-deleted as
      // failure leaves the UI stuck and confuses the user.
      final authDeleted = result.deletedCollections.contains('users-auth');

      if (!authDeleted) {
        // Real failure — Auth user still exists.
        state = AsyncError(
          const AuthFailure.deletionFailed(),
          StackTrace.current,
        );
        return;
      }

      // Order matters: sign out BEFORE flipping the deleted-flag.
      //
      // The flag listener in EliminarCuentaSheet calls context.go('/welcome')
      // when the flag becomes true. If the flag flips while the local auth
      // state is still cached (loggedIn=true) + the Firestore profile is null
      // (deleted by the CF cascade), the router's redirect logic resolves
      // /welcome → /home → /profile-setup, stranding the user mid-onboarding.
      //
      // By awaiting signOut first, authStateChanges emits null before we
      // signal the navigation, so the router sees !loggedIn and routes to
      // /welcome cleanly.
      await ref.read(authServiceProvider).signOut();

      // Reset any onboarding state from the deleted user so a follow-up
      // signup starts on a blank form (otherwise the previous user's draft
      // re-appears in profile-setup if the user creates a new account).
      ref.invalidate(profileSetupNotifierProvider);

      state = const AsyncData(null);
      ref.read(accountDeletedFlagProvider.notifier).state = true;
    } finally {
      ref.read(accountDeletionInFlightProvider.notifier).state = false;
    }
  }

  /// Opens the ReAuthBottomSheet and returns the credential or null.
  Future<AuthCredential?> _openReAuthSheet([BuildContext? context]) async {
    // Injected opener takes priority (used in tests).
    final opener = _sheetOpener;
    if (opener != null) return opener();

    if (context == null || !context.mounted) return null;

    // Detect provider from current user.
    final user = ref.read(firebaseAuthProvider).currentUser;
    final providerId = user?.providerData.isNotEmpty == true
        ? user!.providerData[0].providerId
        : 'password';

    return showModalBottomSheet<AuthCredential?>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      builder: (_) => ReAuthBottomSheet(providerId: providerId),
    );
  }

  AuthFailure _mapError(Object e) {
    if (e is FirebaseFunctionsException) {
      if (e.code == 'unauthenticated' ||
          (e.code == 'permission-denied' &&
              (e.message?.contains('recent-login') ?? false))) {
        return const AuthFailure.requiresRecentLogin();
      }
    }
    if (e is AuthFailure) return e;
    return AuthFailure.deletionFailed(cause: e);
  }
}

/// Riverpod provider for [AccountDeletionNotifier].
final accountDeletionNotifierProvider =
    AsyncNotifierProvider<AccountDeletionNotifier, void>(
  AccountDeletionNotifier.new,
);

/// Set to `true` when an account deletion succeeds. Consumed by [WelcomeScreen]
/// to show "Tu cuenta fue eliminada" SnackBar after GoRouter redirects. Resets
/// to `false` once the snackbar has been shown.
final accountDeletedFlagProvider = StateProvider<bool>((_) => false);

/// Set to `true` while the CF cascade is mid-flight (between the moment the
/// notifier kicks off the CF call and the moment signOut completes). Consumed
/// by the GoRouter redirect to suppress the loggedIn=true + profile=null →
/// /profile-setup detour during the window where the Firestore profile has
/// already been deleted but the Auth user has not. Defaults to `false`.
final accountDeletionInFlightProvider = StateProvider<bool>((_) => false);
