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
///
/// ── Two kinds of surface ────────────────────────────────────────────────────
/// The first three are WELCOME TOURS: full-screen, once per role, right after
/// login. The `customExercise*` ones are FEATURE ONBOARDINGS — a modal shown the
/// first time a user opens one specific screen.
///
/// They share this enum on purpose rather than getting one of their own: the
/// flag mechanism is identical, `OnboardingController.markSeen` takes this type,
/// and `allSurfacesSeen()` in `test/helpers/onboarding_test_helpers.dart`
/// iterates [values] — so every unrelated widget test suppresses a new surface
/// automatically instead of silently rendering a modal over the screen it is
/// asserting on. A parallel enum would have to re-earn all three.
enum OnboardingSurface {
  athleteMobile,
  trainerMobile,
  trainerWeb,

  /// "Creá tus propios ejercicios", shown over the mobile routine editor.
  /// Split by role because the copy differs: the athlete builds their own
  /// library, the trainer assigns theirs to students.
  customExerciseAthleteMobile,
  customExerciseTrainerMobile,

  /// Same feature onboarding on the Coach Hub routine editor. Trainer-only by
  /// construction — `coachHubRedirect` sends everyone else to `/not-allowed`.
  customExerciseTrainerWeb,

  /// The PLANTILLAS mini-onboarding (#635): four questions asked the first time
  /// an athlete opens Entrenar → PLANTILLAS.
  ///
  /// Unlike every surface above it, this one does not just TELL — it collects
  /// answers and writes them to `users/{uid}.templatePreferences`. It still
  /// belongs in this enum because the "has this user seen it" mechanism is
  /// identical, which is the whole reason `OnboardingSurface` is shared rather
  /// than re-declared per feature.
  ///
  /// Athlete-only, and there is no trainer twin yet on purpose: the trainer
  /// half of the handoff declares `goals` / `primaryMuscleGroups` on the
  /// ROUTINE at publish time, and those fields do not exist until #635 PR#1.
  /// Shipping a trainer surface with nowhere to write would be a dead flow.
  templatesAthleteMobile,
}

/// The WELCOME tours — the surfaces that own a full-screen module tour.
///
/// Exists so callers and tests can say "the tours" without spelling out a
/// negation of the feature onboardings, and so adding a fourth tour is one edit
/// rather than a hunt through `where` clauses.
const onboardingTourSurfaces = <OnboardingSurface>[
  OnboardingSurface.athleteMobile,
  OnboardingSurface.trainerMobile,
  OnboardingSurface.trainerWeb,
];

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
        OnboardingSurface.customExerciseAthleteMobile => 1,
        OnboardingSurface.customExerciseTrainerMobile => 1,
        OnboardingSurface.customExerciseTrainerWeb => 1,
        OnboardingSurface.templatesAthleteMobile => 1,
      };

  /// The MODULE slides, in order — welcome tours only.
  ///
  /// Mobile mirrors the bottom bar so the tour matches what the user is about
  /// to see; web mirrors the eight sidebar items after the "W2 reduce" — not
  /// the ~20 directories on disk, and not the 19 the openspec doc still claims.
  ///
  /// Empty for the `customExercise*` surfaces, and not a placeholder: a feature
  /// onboarding does not tour modules at all. Its three slides are a fixed deck
  /// in `custom_exercise_onboarding_slides.dart`, keyed by role rather than by
  /// module, so there is nothing to enumerate here. `CoachHubTourGate` already
  /// bails on an empty list, which is what keeps a wrong caller from rendering
  /// a blank tour.
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
        OnboardingSurface.customExerciseAthleteMobile ||
        OnboardingSurface.customExerciseTrainerMobile ||
        OnboardingSurface.customExerciseTrainerWeb ||
        OnboardingSurface.templatesAthleteMobile =>
          const <OnboardingModule>[],
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
