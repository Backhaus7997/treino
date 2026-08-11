import 'onboarding_module.dart';

/// Where a welcome tour runs, and therefore what gets flagged as seen.
///
/// The flag is PER SURFACE, never a single global one (issue #627): a trainer
/// who already saw the mobile tour must still get the Coach Hub one — that is
/// the one they need most. A shared flag would suppress it forever.
///
/// There is no `athleteWeb` because there is no athlete web surface: the entry
/// points are `lib/main.dart` (mobile) and `lib/main_coach_hub.dart` (web,
/// trainer-only — athletes are redirected to `/not-allowed`). Adding one later
/// is a single enum value; the exhaustive `switch` in [slides] makes the
/// compiler point at every site that needs a decision.
enum OnboardingSurface {
  athleteMobile,
  trainerMobile,
  trainerWeb,
}

extension OnboardingSurfaceX on OnboardingSurface {
  /// Firestore key under `users/{uid}.onboardingSeen`.
  ///
  /// Derived from [Enum.name] rather than a literal so a rename cannot silently
  /// orphan persisted flags — renaming here IS a wire-format change and must be
  /// treated as a version bump.
  String get wireKey => name;

  /// Version of the tour currently shipped for this surface.
  ///
  /// ⚠️ BLAST RADIUS: bumping this re-shows the whole tour to EVERY user of the
  /// surface. That is a product decision wearing a constant's clothes — bump it
  /// in its own PR, never as a side effect of editing copy.
  ///
  /// All three ship at 1: the tour has never been released, so there is no
  /// installed base to re-show it to. During QA this is also the only lever that
  /// re-triggers the tour on an account that already dismissed it — the flag
  /// lives in Firestore, so reinstalling the app does NOT reset it. Bump it
  /// locally to test, and revert before committing. See docs/onboarding-tour.md.
  int get currentVersion => switch (this) {
        OnboardingSurface.athleteMobile => 1,
        OnboardingSurface.trainerMobile => 1,
        OnboardingSurface.trainerWeb => 1,
      };

  /// The slides, in order.
  ///
  /// Mobile mirrors the bottom bar so the tour matches what the user is about
  /// to see; web mirrors the eight sidebar items after the "W2 reduce" — not
  /// the ~20 directories on disk, and not the 19 the openspec doc still claims.
  List<OnboardingModule> get slides => switch (this) {
        OnboardingSurface.athleteMobile ||
        OnboardingSurface.trainerMobile =>
          const [
            OnboardingModule.home,
            OnboardingModule.workout,
            OnboardingModule.feed,
            OnboardingModule.coach,
            OnboardingModule.profile,
          ],
        OnboardingSurface.trainerWeb => const [
            OnboardingModule.webDashboard,
            OnboardingModule.webAlumnos,
            OnboardingModule.webAgenda,
            OnboardingModule.webChat,
            OnboardingModule.webBiblioteca,
            OnboardingModule.webRutinas,
            OnboardingModule.webPagos,
            OnboardingModule.webAjustes,
          ],
      };

  /// Whether the tour should run, given the persisted map.
  ///
  /// An absent entry reads as `0`, so every existing account sees it once — no
  /// backfill, no migration.
  ///
  /// The comparison is `<`, NOT `!=`: a client on an older build must not
  /// re-trigger a tour it has no copy for. Downgrades are silent no-ops.
  bool shouldShow(Map<String, int> seen) =>
      (seen[wireKey] ?? 0) < currentVersion;

  /// The full map to persist once the tour is finished or skipped.
  ///
  /// Returns the WHOLE map with this surface's entry set — callers write it
  /// verbatim rather than a single-key partial. See `OnboardingController` for
  /// why relying on nested merge is unsafe.
  Map<String, int> markedIn(Map<String, int> seen) => <String, int>{
        ...seen,
        wireKey: currentVersion,
      };
}
