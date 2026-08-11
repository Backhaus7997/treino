import 'dart:developer' as developer;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart';
import '../../profile/domain/user_role.dart';
import '../domain/onboarding_surface.dart';

/// Surfaces whose tour has already been dismissed in THIS app session.
///
/// Consulted BEFORE the persisted flag, for two reasons:
///
///  1. Race guard. `userProfileProvider` is a stream: between `markSeen` and the
///     arrival of the updated snapshot the persisted map still says "not seen"
///     and the tour would be pushed on top of itself.
///  2. Failure guard. If the write never lands (offline, quota), the tour does
///     not reappear within one session — it simply retries on the next cold
///     start.
///
/// Lives at the root [ProviderScope] so widget re-mounts do not resurrect it.
/// Resets only on cold start. Mirrors `permissionGateAttemptedProvider`
/// (ADR-PN-012).
final onboardingDismissedProvider =
    StateProvider<Set<OnboardingSurface>>((ref) => <OnboardingSurface>{});

/// True while the tour is on screen.
final onboardingTourOpenProvider = StateProvider<bool>((ref) => false);

final onboardingControllerProvider = Provider<OnboardingController>(
  (ref) => OnboardingController(ref),
);

/// Persists "this user has seen the tour for this surface".
class OnboardingController {
  OnboardingController(this._ref);

  final Ref _ref;

  /// Marks [surface] as seen, for this session and in Firestore.
  ///
  /// The session flag is set FIRST and unconditionally, so the tour stays gone
  /// even if the network write fails. Nobody is held behind a welcome screen
  /// because Firestore is unreachable — that is the dead-end class of bug #429.
  ///
  /// ⚠️ The payload is the WHOLE `onboardingSeen` map with one entry replaced,
  /// never a single-key partial. Real Firestore deep-merges nested maps under
  /// `SetOptions(merge: true)`, but `fake_cloud_firestore` 3.1.0 replaces the
  /// top-level key outright (`mock_document_reference.dart` `_setRawData`).
  /// Depending on backend merge semantics would make every test against the
  /// fake lie — in both directions.
  Future<void> markSeen(OnboardingSurface surface) async {
    _ref.read(onboardingDismissedProvider.notifier).update(
          (dismissed) => {...dismissed, surface},
        );

    final profile = _ref.read(userProfileProvider).valueOrNull;
    if (profile == null) return;

    try {
      await _ref.read(userRepositoryProvider).update(
        profile.uid,
        {'onboardingSeen': surface.markedIn(profile.onboardingSeen)},
      );
    } catch (e) {
      // Swallowed on purpose — the session flag already prevents a re-show and
      // the next cold start retries.
      developer.log(
        'markSeen(${surface.wireKey}) failed: $e',
        name: 'onboarding',
      );
    }
  }
}

/// Whether [surface]'s tour should run right now.
///
/// Composes the conditions in precedence order:
///
///  1. Session dismissal wins over everything.
///  2. The profile must be RESOLVED with setup complete. Loading and error
///     states yield `false` — an errored profile stream is already routed to
///     `/profile-unavailable` by the router (#544), and a tour must not flicker
///     on top of that.
///  3. The persisted version must be older than the shipped one.
final shouldShowTourProvider =
    Provider.family<bool, OnboardingSurface>((ref, surface) {
  if (ref.watch(onboardingDismissedProvider).contains(surface)) return false;

  final profile = ref.watch(userProfileProvider).valueOrNull;
  if (profile == null) return false;

  // `displayName != null` is the app-wide signal for "profile setup complete"
  // (router.dart:164-166). The tour runs strictly after it, never during.
  if (profile.displayName == null) return false;

  return surface.shouldShow(profile.onboardingSeen);
});

/// The mobile tour this user should see right now, or `null`.
///
/// This is where the ROLE decision lives, so no caller makes it twice.
///
/// Two role-specific guards beyond the version check:
///
///  - The role must be RESOLVED. `HomeScreen` renders the athlete home while
///    the profile loads (home_screen.dart:41-45), so keying off a defaulted
///    role would flash the athlete tour at a trainer.
///  - A trainer whose professional profile is incomplete belongs to the
///    `/profile/edit-trainer` gate (ADR-TPO-003). A tour pointing at Alumnos
///    and Agenda before they can reach either is worse than silence.
final pendingMobileTourProvider = Provider<OnboardingSurface?>((ref) {
  final profile = ref.watch(userProfileProvider).valueOrNull;
  if (profile == null) return null;

  final surface = switch (profile.role) {
    UserRole.athlete => OnboardingSurface.athleteMobile,
    UserRole.trainer => OnboardingSurface.trainerMobile,
  };

  if (surface == OnboardingSurface.trainerMobile &&
      !ref.watch(trainerProfileCompleteProvider)) {
    return null;
  }

  return ref.watch(shouldShowTourProvider(surface)) ? surface : null;
});

/// Whether onboarding owns the screen — open, or about to open.
///
/// Anything that presents its own prompt on first render must wait on this.
/// Two already do, and both were found on a device rather than in a test,
/// because a widget test happily renders stacked modals and reports success:
///
///  - `PermissionGate` on `/home` (push notifications).
///  - `TrainersListScreen` on `/coach` (location rationale).
final onboardingBlocksProvider = Provider<bool>((ref) {
  return ref.watch(onboardingTourOpenProvider) ||
      ref.watch(pendingMobileTourProvider) != null;
});
