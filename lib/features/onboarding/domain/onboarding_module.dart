/// A part of the app that explains itself the first time the user opens it.
///
/// One card per module, shown once, dismissed forever. The alternative — a
/// full-screen tour up front — was built and rejected: it makes the user read
/// five screens before touching anything, and it teaches out of context.
///
/// The key deliberately does NOT carry the role. A TREINO account is an athlete
/// XOR a trainer for life (AGENTS.md rule 3), so a given user only ever sees one
/// variant of a module. The role picks the COPY; the key stays the same. That
/// halves both the enum and the persisted map.
///
/// Web modules are prefixed because they are different places, not translations
/// of the mobile ones: `webAgenda` is the Coach Hub scheduling section, while
/// mobile `coach` is a tab that contains ALUMNOS and AGENDA together.
enum OnboardingModule {
  // ── Mobile: the five bottom-bar tabs ────────────────────────────────────
  home,
  workout,
  feed,
  coach,
  profile,

  // Sub-screen modules (editar perfil, editor de rutina, player de sesión…)
  // lived here while onboarding was per-screen contextual cards. The tour is
  // a single run of slides after login now, so the section-level modules above
  // are the whole vocabulary.

  // ── Coach Hub web: the eight visible sidebar sections ───────────────────
  // Matches sidebar_registry.dart, which the "W2 reduce" cut from ~19 to 8.
  webDashboard,
  webAlumnos,
  webAgenda,
  webChat,
  webBiblioteca,
  webRutinas,
  webPagos,
  webAjustes,
}

extension OnboardingModuleX on OnboardingModule {
  /// Key under `users/{uid}.onboardingSeen`.
  ///
  /// Derived from [Enum.name] rather than a hand-written literal so a rename
  /// cannot silently orphan already-persisted flags — renaming a value here IS
  /// a wire-format change and must be treated as a version bump.
  String get wireKey => name;

  /// Version of the card currently shipped for this module.
  ///
  /// ⚠️ BLAST RADIUS: bumping this re-shows the card to EVERY user who had
  /// already dismissed it. That is a product decision wearing a constant's
  /// clothes — bump it in its own PR, never as a side effect of editing copy.
  int get currentVersion => 1;

  /// Whether the card should be shown, given the persisted map.
  ///
  /// An absent entry reads as `0`, so every existing account sees each card
  /// once — no backfill, no migration.
  ///
  /// The comparison is `<`, NOT `!=`: a client running an older build must not
  /// re-trigger a card it has no copy for. Downgrades are silent no-ops.
  bool shouldShow(Map<String, int> seen) =>
      (seen[wireKey] ?? 0) < currentVersion;

  /// The full map to persist after this card is dismissed.
  ///
  /// Returns the WHOLE map with this module's entry set — callers must write it
  /// verbatim rather than a single-key partial. See `OnboardingController` for
  /// why the nested-merge shortcut is unsafe to rely on.
  Map<String, int> markedIn(Map<String, int> seen) => <String, int>{
        ...seen,
        wireKey: currentVersion,
      };
}
