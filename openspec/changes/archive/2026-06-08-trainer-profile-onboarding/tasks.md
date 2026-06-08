# Tasks: trainer-profile-onboarding

**Change**: trainer-profile-onboarding
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-09
**PRs**: 2 chained PRs against `main` (stacked-to-main)
**Artifact store**: hybrid (file `openspec/changes/trainer-profile-onboarding/tasks.md` + Engram `sdd/trainer-profile-onboarding/tasks`)
**Phase**: Fase 6 Etapa 1

---

## Summary

34 tasks across 2 chained PRs. Total estimated ~250 LOC additions (tests included). Chain strategy: stacked-to-main — each PR targets `main` directly, PR#2 rebases after PR#1 merges. Strict TDD throughout: every production change is preceded by a RED task (failing test commit) followed by a GREEN task (passing implementation commit).

---

## Review Workload Forecast

| Field | PR#1 | PR#2 |
|---|---|---|
| Estimated changed lines | ~150 | ~100 |
| 400-line budget risk | Low | Low |
| Chained PRs recommended | Yes | Yes |
| Decision needed before apply | No (already decided) | No |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: Low

Chained PRs recommended: Yes. Chain strategy: stacked-to-main. Delivery strategy: chained-pr (user signed off 2 PRs). PR#1 estimated ~313 LOC including tests; PR#2 ~200 LOC net additions with ~143 LOC deletion; both comfortably sub-400-line budget.

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|---|---|---|---|
| PR#1 | `uid` fix + `trainerProfileComplete` getter + provider + `authRedirect` gate + tests | PR#1 | Base: `main`; standalone mergeable; exercises bug fix end-to-end |
| PR#2 | `ProfileEditTrainerMode` enum + onboarding-mode behaviors + router query-param mapping + promote script + delete legacy script + `scripts/README.md` + widget tests | PR#2 | Base: `main`, rebase after PR#1 merges |

---

## Risk Resolutions (pre-verified)

| Risk | Resolution |
|---|---|
| `_trainerPublicSubsetFromPartial` signature change (breaking) | Only ONE caller: `update()`. Verified in design §4. Cost: 1 call-site update. |
| `authRedirect` regression on new branch | ADR-TPO-003: strict insertion point (after `displayName == null`, before public-route → `/home`). All 8 existing + new branches tested. |
| `router_auth_redirect_test.dart` does not exist | Confirmed missing — T-TPO-014 CREATES it from scratch using `ProviderContainer` pattern. |
| `profile_edit_trainer_screen_edit_test.dart` does not exist | Confirmed missing — T-TPO-027 CREATES it from scratch. |
| `profile_edit_trainer_screen_onboarding_test.dart` does not exist | Confirmed missing — T-TPO-025 CREATES it from scratch. |
| `PopScope` API | Flutter 3.22+ confirmed in project (`AGENTS.md`). `WillPopScope` is deprecated. Use `PopScope(canPop: false)`. |
| Widget tests need GoRouter harness | Use existing `GoRouter` test patterns from current widget tests. Verify patterns before RED tasks in T-TPO-025. |
| Whitelist ADR-RV-005 preserved | SCENARIO-691 regression test asserts `averageRating` absent from subset. |
| `SetOptions(merge: true)` idempotency | Already in code — uid re-write on existing docs is a no-op. |
| Loop guard via `startsWith('/profile/edit-trainer')` | Covers `?mode=onboarding` AND bare route — defensive against future query-param shapes. |

---

## Branch + Base per PR

| PR | Branch | Base |
|---|---|---|
| PR#1 | `feat/trainer-profile-onboarding-pr1-data-gate` | `main` |
| PR#2 | `feat/trainer-profile-onboarding-pr2-onboarding-mode` | `main` (rebase after PR#1 merges) |

---

## PR#1 — Data Layer Fix + Onboarding Gate (~150 LOC + ~270 LOC tests)

**REQs covered**: REQ-TPO-DATA-001, REQ-TPO-DATA-002, REQ-TPO-DATA-003, REQ-TPO-DATA-004, REQ-TPO-GATE-001, REQ-TPO-GATE-002, REQ-TPO-GATE-003, REQ-TPO-GATE-004, REQ-TPO-CX-001, REQ-TPO-CX-002, REQ-TPO-CX-005
**SCENARIOs covered**: 688, 689, 690, 691, 692, 693, 694, 695, 696, 697, 698, 699, 700, 701, 702, 703, 704, 705, 706, 707, 708

### Phase 1.1: Branch setup

- [x] T-TPO-001 — SETUP: create branch `feat/trainer-profile-onboarding-pr1-data-gate` from `main`; confirm clean working tree; verify `lib/features/profile/data/user_repository.dart` lines 30-39 contain the deferred-fix comment and that `_trainerPublicSubsetFromPartial` currently takes only `(Map partial)`.

### Phase 1.2: `_trainerPublicSubsetFromPartial` uid fix (ADR-TPO-001)

- [x] T-TPO-002 — RED: CREATE `test/features/profile/data/user_repository_trainer_uid_test.dart`; add failing test `SCENARIO-688`: `UserRepository.update(uid: 'user_a', partial: {trainerBio: 'hello', trainerSpecialty: 'crossfit', trainerOffersOnline: true})` → `fakeStore.collection('trainerPublicProfiles').doc('user_a').get()` has `data()['uid'] == 'user_a'` and `data()['trainerBio'] == 'hello'`. Use `fake_cloud_firestore`. Test MUST fail (red).
- [x] T-TPO-003 — GREEN: edit `lib/features/profile/data/user_repository.dart`: change `_trainerPublicSubsetFromPartial(Map partial)` signature to `_trainerPublicSubsetFromPartial(Map partial, {required String uid})`; inside the helper, after building the subset, when `result.isNotEmpty` add `result['uid'] = uid`; update the one `update()` callsite to pass `uid: uid`; replace lines 30-39 deferred comment with single-line ADR-TPO-001 reference. SCENARIO-688 must pass.
- [x] T-TPO-004 — RED: in `user_repository_trainer_uid_test.dart` add failing tests for SCENARIO-689 (re-save idempotent: uid unchanged after second call), SCENARIO-690 (athlete-only partial `{weight: 70}` → no `trainerPublicProfiles` write), SCENARIO-691 (partial containing hypothetical `averageRating` → subset map does NOT include `averageRating`), SCENARIO-692 (partial with `trainerLocations: []` and `trainerOffersOnline: false` → exception thrown before any write), SCENARIO-693 (`trainerOffersOnline: true` with empty locations → no exception, batch proceeds). Tests MUST fail (red).
- [x] T-TPO-005 — GREEN: run `flutter test test/features/profile/data/user_repository_trainer_uid_test.dart`; all 6 scenarios (688-693) must pass with no production-code changes beyond T-TPO-003 (the fix already covers these scenarios). If any fail, identify the gap and patch only the minimal production code to make them pass. REQ-TPO-DATA-001, REQ-TPO-DATA-002, REQ-TPO-DATA-003 satisfied.

### Phase 1.3: `trainerProfileComplete` extension getter (ADR-TPO-004)

- [x] T-TPO-006 — RED: CREATE `test/features/profile/domain/trainer_profile_complete_test.dart`; add failing pure-Dart tests for SCENARIO-694 (`trainerBio: null` → `false`), SCENARIO-695 (`trainerSpecialty: null` → `false`), SCENARIO-696 (`trainerMonthlyRate: null` → `false`), SCENARIO-697 (all fields set, `trainerLocations: []`, `trainerOffersOnline: false` → `false`), SCENARIO-698 (all fields set, `trainerOffersOnline: true` → `true`), SCENARIO-699 (all fields set, one location, `trainerOffersOnline: false` → `true`), SCENARIO-700 (all trainer fields null → `false`). No Riverpod container — construct `UserProfile` directly and assert `profile.trainerProfileComplete`. Tests MUST fail (red).
- [x] T-TPO-007 — GREEN: CREATE `lib/features/profile/domain/user_profile_trainer_completeness.dart` — extension `UserProfileTrainerCompleteness on UserProfile` with getter `bool get trainerProfileComplete` using formula: `trainerBio != null && trainerSpecialty != null && trainerMonthlyRate != null && (trainerLocations.isNotEmpty || trainerOffersOnline == true)`. All 7 scenarios (694-700) must pass. No Freezed regen. No new field on model. REQ-TPO-DATA-004 satisfied.

### Phase 1.4: `trainerProfileCompleteProvider` thin provider (ADR-TPO-004)

- [x] T-TPO-008 — RED: in `test/features/profile/domain/trainer_profile_complete_test.dart` add a Riverpod provider test: override `userProfileProvider` with a complete profile → `container.read(trainerProfileCompleteProvider)` returns `true`; override with incomplete profile → returns `false`; override with null profile → returns `false`. Tests MUST fail (red).
- [x] T-TPO-009 — GREEN: edit `lib/features/profile/application/user_providers.dart` — add import for the new extension file; add `final trainerProfileCompleteProvider = Provider<bool>((ref) { final profile = ref.watch(userProfileProvider).valueOrNull; return profile?.trainerProfileComplete ?? false; });`. All provider tests must pass. REQ-TPO-DATA-004 provider aspect satisfied.

### Phase 1.5: `authRedirect` trainer-incomplete gate (ADR-TPO-003)

- [x] T-TPO-010 — SETUP: verify whether `lib/app/router.dart` already imports `user_profile_trainer_completeness.dart` (it won't — confirm); note the exact line number of the `displayName == null` check and the `loggedIn && isPublic` check so the insertion point is unambiguous.
- [x] T-TPO-011 — RED: CREATE `test/app/router_auth_redirect_test.dart`; add failing tests for all 8 branches using `ProviderContainer` overrides — SCENARIO-701 (incomplete trainer → returns `/profile/edit-trainer?mode=onboarding`), SCENARIO-702 (complete trainer → returns `null`), SCENARIO-703 (location already `/profile/edit-trainer` → returns `null`, no loop), SCENARIO-704 (athlete, any completeness → returns `null`), SCENARIO-705 (unauthenticated → returns sign-in route), SCENARIO-706 (`displayName == null` → returns `/profile-setup`, NOT trainer gate), SCENARIO-707 (account-deletion in-flight → existing behavior preserved), SCENARIO-708 (public route + incomplete trainer → trainer gate does NOT fire). Tests MUST fail (red).
- [x] T-TPO-012 — GREEN: edit `lib/app/router.dart` — add import for `user_profile_trainer_completeness.dart`; inside `authRedirect`, after the `profile.displayName == null` return-`/profile-setup` branch and BEFORE the `loggedIn && isPublic && !isSplash` branch, add: `if (profile.role == UserRole.trainer && !profile.trainerProfileComplete && !location.startsWith('/profile/edit-trainer')) { return '/profile/edit-trainer?mode=onboarding'; }`. Use the getter directly on `profile` (NOT via provider — `profile` is already in scope). All 8 SCENARIO tests (701-708) must pass. REQ-TPO-GATE-001, REQ-TPO-GATE-002, REQ-TPO-GATE-003, REQ-TPO-GATE-004 satisfied.

### Phase 1.6: PR#1 quality gates

- [x] T-TPO-013 — GATE: run `flutter analyze`; confirm 0 issues. Run `dart format --output=none --set-exit-if-changed .`; confirm 0 changed files in touched paths. Fix any issues before proceeding.
- [x] T-TPO-014 — GATE: run `flutter test test/features/profile/data/user_repository_trainer_uid_test.dart test/features/profile/domain/trainer_profile_complete_test.dart test/app/router_auth_redirect_test.dart`; confirm all pass; delta ≥ +21 new tests (6 repo + 7 domain + 8 router).
- [x] T-TPO-015 — VERIFY: `grep -r "averageRating\|reviewCount" lib/features/profile/data/user_repository.dart` must show the ADR-RV-005 comment but NOT these fields inside `_trainerPublicFields` list. No `pubspec.yaml` changes. No `firestore.rules` changes. No `storage.rules` changes. No CF changes. Conventional commits only, no `Co-Authored-By` in any commit in the branch.

---

## PR#2 — Onboarding Mode UI + Promote Script (~100 LOC net)

**REQs covered**: REQ-TPO-UI-001, REQ-TPO-UI-002, REQ-TPO-UI-003, REQ-TPO-UI-004, REQ-TPO-UI-005, REQ-TPO-UI-006, REQ-TPO-UI-007, REQ-TPO-UI-008, REQ-TPO-SCRIPT-001, REQ-TPO-SCRIPT-002, REQ-TPO-SCRIPT-003, REQ-TPO-SCRIPT-004, REQ-TPO-SCRIPT-005, REQ-TPO-SCRIPT-006, REQ-TPO-CX-001, REQ-TPO-CX-002, REQ-TPO-CX-003, REQ-TPO-CX-004, REQ-TPO-CX-005
**SCENARIOs covered**: 709, 710, 711, 712, 713, 714, 715, 716, 717, 718, 719, 720 (documented constraint), 721-726 (manual smoke)

### Phase 2.1: Branch setup

- [x] T-TPO-016 — SETUP: create branch `feat/trainer-profile-onboarding-pr2-onboarding-mode` from `main` (rebase on `main` after PR#1 merges if applicable); confirm clean working tree; verify `lib/features/profile/presentation/profile_edit_trainer_screen.dart` does NOT yet have `ProfileEditTrainerMode` enum or `mode` constructor arg; inspect existing GoRouter test helper patterns in the project (search `test/` for existing GoRouter widget test harness) and note the pattern to use in RED tasks.

### Phase 2.2: `ProfileEditTrainerMode` enum + screen constructor (ADR-TPO-005)

- [x] T-TPO-017 — RED: CREATE `test/features/profile/presentation/profile_edit_trainer_screen_edit_test.dart`; add failing test SCENARIO-709: pump `ProfileEditTrainerScreen()` with no `mode` arg inside minimal GoRouter harness → effective mode is `ProfileEditTrainerMode.edit` (assert AppBar title is `"Editá tu perfil profesional"` as proxy). Test MUST fail because enum and arg do not exist yet (red).
- [x] T-TPO-018 — GREEN: edit `lib/features/profile/presentation/profile_edit_trainer_screen.dart` — add `enum ProfileEditTrainerMode { edit, onboarding }` inline at top of file, above the class declaration; add `final ProfileEditTrainerMode mode;` field + update constructor to accept `mode = ProfileEditTrainerMode.edit`; keep ALL existing behavior unchanged (no title branching yet — just the enum and the field). SCENARIO-709 must pass with the AppBar title still being the existing string. REQ-TPO-UI-001 satisfied.

### Phase 2.3: AppBar title branching on mode (ADR-TPO-006)

- [x] T-TPO-019 — RED: in `profile_edit_trainer_screen_edit_test.dart` add SCENARIO-712 (edit mode title `"Editá tu perfil profesional"`); CREATE `test/features/profile/presentation/profile_edit_trainer_screen_onboarding_test.dart`; add SCENARIO-713 (onboarding mode title `"Completá tu perfil profesional"`). Both tests MUST fail (red — no branching implemented yet).
- [x] T-TPO-020 — GREEN: in `lib/features/profile/presentation/profile_edit_trainer_screen.dart`, replace the static AppBar title string with: `final title = mode == ProfileEditTrainerMode.onboarding ? 'Completá tu perfil profesional' // i18n: Fase 6 Etapa 1 : 'Editá tu perfil profesional'; // i18n: Fase 6 Etapa 1`. Apply `title` as the AppBar title `Text`. SCENARIO-712 and SCENARIO-713 must pass. REQ-TPO-UI-003, REQ-TPO-CX-003 satisfied.

### Phase 2.4: Back navigation blocking in onboarding mode (ADR-TPO-006)

- [x] T-TPO-021 — RED: in `profile_edit_trainer_screen_onboarding_test.dart` add SCENARIO-714 (no back button in AppBar + `PopScope(canPop: false)` in tree); in `profile_edit_trainer_screen_edit_test.dart` add SCENARIO-715 (back button present in AppBar). Tests MUST fail (red).
- [x] T-TPO-022 — GREEN: in `lib/features/profile/presentation/profile_edit_trainer_screen.dart`, when `mode == ProfileEditTrainerMode.onboarding`: set `AppBar(automaticallyImplyLeading: false, ...)`; wrap the screen body in `PopScope(canPop: false, onPopInvokedWithResult: (_, __) {})`. In edit mode: no changes (defaults preserve existing back behavior). SCENARIO-714 and SCENARIO-715 must pass. REQ-TPO-UI-004 satisfied.

### Phase 2.5: Post-save navigation branching (ADR-TPO-006)

- [x] T-TPO-023 — RED: in `profile_edit_trainer_screen_onboarding_test.dart` add SCENARIO-716 (after save → GoRouter location is `/home`); in `profile_edit_trainer_screen_onboarding_test.dart` add SCENARIO-718 (save with invalid location invariant → repo exception surfaced, no navigation to `/home`); in `profile_edit_trainer_screen_onboarding_test.dart` add SCENARIO-719 (bio shorter than minimum → same validation error in onboarding mode as in edit mode); in `profile_edit_trainer_screen_edit_test.dart` add SCENARIO-717 (save in edit mode → `context.pop()` called). Tests MUST fail (red). Use `fake_cloud_firestore` or mock `userRepositoryProvider` for save outcomes.
- [x] T-TPO-024 — GREEN: in `lib/features/profile/presentation/profile_edit_trainer_screen.dart`, inside the save success callback, branch: `if (mode == ProfileEditTrainerMode.onboarding) { context.go('/home'); } else { context.pop(); }`. Error/validation paths are mode-independent (no change). SCENARIO-716, SCENARIO-717, SCENARIO-718, SCENARIO-719 must pass. REQ-TPO-UI-005, REQ-TPO-UI-006, REQ-TPO-UI-007 satisfied.

### Phase 2.6: Router `?mode=onboarding` query-param mapping (ADR-TPO-005)

- [x] T-TPO-025 — RED: in `profile_edit_trainer_screen_onboarding_test.dart` add SCENARIO-710 (navigate to `/profile/edit-trainer?mode=onboarding` via GoRouter test harness → screen pumped with `mode == ProfileEditTrainerMode.onboarding`); in `profile_edit_trainer_screen_edit_test.dart` add SCENARIO-711 (navigate to `/profile/edit-trainer` with no param → screen pumped with `mode == ProfileEditTrainerMode.edit`). Tests MUST fail (red — router not yet updated).
- [x] T-TPO-026 — GREEN: edit `lib/app/router.dart` — find `GoRoute(path: 'edit-trainer', ...)` (lines ~375-379); update `pageBuilder` to read `final mode = state.uri.queryParameters['mode'] == 'onboarding' ? ProfileEditTrainerMode.onboarding : ProfileEditTrainerMode.edit;` and pass `mode: mode` to `ProfileEditTrainerScreen(mode: mode)`. Add import for `profile_edit_trainer_screen.dart` if not already imported there. SCENARIO-710 and SCENARIO-711 must pass. REQ-TPO-UI-002 satisfied.

### Phase 2.7: `promote_user_to_trainer.js` script + `scripts/README.md` (ADR-TPO-007, ADR-TPO-011)

- [x] T-TPO-027 — CREATE `scripts/promote_user_to_trainer.js` (~30 LOC) per ADR-TPO-007 skeleton: `'use strict'`; `admin.initializeApp()`; CLI reads `process.argv[2]` → exit 1 with USAGE if falsy; `db.collection('users').doc(uid).get()` → exit 1 with error if `!snap.exists`; log `email` and `displayName || '(no displayName)'`; `await db.collection('users').doc(uid).update({ role: 'trainer' })`; `console.log('Done.')` + `process.exit(0)`; `.catch` handler exits 1. No geohash, no seeding. REQ-TPO-SCRIPT-001 through REQ-TPO-SCRIPT-005 (manual smoke verification per ADR-TPO-009).
- [x] T-TPO-028 — CREATE `scripts/README.md` per ADR-TPO-011: sections — Prerequisites (service-account JSON path, `GOOGLE_APPLICATION_CREDENTIALS`, `npm install firebase-admin`), `## promote_user_to_trainer.js` with usage, behavior list (validate → log → update → exit 0), post-promotion flow description. REQ-TPO-SCRIPT-006 documentation aspect satisfied.

### Phase 2.8: Delete legacy script (ADR-TPO-008)

- [x] T-TPO-029 — DELETE `scripts/promote_mateo_to_public_trainer.js`. Commit message MUST include `BREAKING: scripts/promote_mateo_to_public_trainer.js removed — use scripts/promote_user_to_trainer.js <uid>`. Verify file is absent from working tree. SCENARIO-726 satisfied. REQ-TPO-SCRIPT-006 deletion aspect satisfied.

### Phase 2.9: PR#2 quality gates

- [x] T-TPO-030 — GATE: run `flutter analyze`; confirm 0 issues. Run `dart format --output=none --set-exit-if-changed .`; confirm 0 changed files on touched paths.
- [x] T-TPO-031 — GATE: run `flutter test test/features/profile/presentation/profile_edit_trainer_screen_edit_test.dart test/features/profile/presentation/profile_edit_trainer_screen_onboarding_test.dart`; confirm all pass; delta ≥ +11 new widget tests (5 edit mode + 6 onboarding mode including 710-719 scenarios covered by widget tests).
- [x] T-TPO-032 — VERIFY: no `pubspec.yaml` changes. No `firestore.rules`, `storage.rules`, or CF changes. All es-AR strings tagged `// i18n: Fase 6 Etapa 1`. No `AppPalette`-violating hex literals. No direct `PhosphorIcons.X` references. `scripts/promote_mateo_to_public_trainer.js` absent. `scripts/promote_user_to_trainer.js` present. `scripts/README.md` present. Conventional commits only, no `Co-Authored-By`.
- [ ] T-TPO-033 — MANUAL SMOKE (post-merge, against `treino-dev`): run `node scripts/promote_user_to_trainer.js` (no arg → exit 1); run with non-existent uid → exit 1; run with valid dev uid → logs email + displayName → exits 0; verify `users/{uid}.role == 'trainer'`, `trainerBio` absent; re-run → exits 0 (idempotent). Check SCENARIO-721 through SCENARIO-725.

### Phase 2.10: Post-archive step

- [ ] T-TPO-034 — POST-MERGE: after PR#2 merges to `main`, update `docs/roadmap.md` line 414 (Etapa 1 entry) to ✅ and append PR hashes. This is an archive-phase step, not a code-review blocker.

---

## Coverage Matrix

| REQ | Tasks | SCENARIOs |
|---|---|---|
| REQ-TPO-DATA-001 | T-TPO-002, T-TPO-003, T-TPO-004, T-TPO-005 | 688, 689, 690 |
| REQ-TPO-DATA-002 | T-TPO-004, T-TPO-005 | 691 |
| REQ-TPO-DATA-003 | T-TPO-004, T-TPO-005 | 692, 693 |
| REQ-TPO-DATA-004 | T-TPO-006, T-TPO-007, T-TPO-008, T-TPO-009 | 694, 695, 696, 697, 698, 699, 700 |
| REQ-TPO-GATE-001 | T-TPO-011, T-TPO-012 | 701, 702 |
| REQ-TPO-GATE-002 | T-TPO-011, T-TPO-012 | 703 |
| REQ-TPO-GATE-003 | T-TPO-011, T-TPO-012 | 704 |
| REQ-TPO-GATE-004 | T-TPO-011, T-TPO-012 | 705, 706, 707, 708 |
| REQ-TPO-UI-001 | T-TPO-017, T-TPO-018 | 709 |
| REQ-TPO-UI-002 | T-TPO-025, T-TPO-026 | 710, 711 |
| REQ-TPO-UI-003 | T-TPO-019, T-TPO-020 | 712, 713 |
| REQ-TPO-UI-004 | T-TPO-021, T-TPO-022 | 714, 715 |
| REQ-TPO-UI-005 | T-TPO-023, T-TPO-024 | 716, 717 |
| REQ-TPO-UI-006 | T-TPO-023, T-TPO-024 | 718 |
| REQ-TPO-UI-007 | T-TPO-023, T-TPO-024 | 719 |
| REQ-TPO-UI-008 | (documented constraint — no code) | 720 |
| REQ-TPO-SCRIPT-001 | T-TPO-027 | 721 (manual) |
| REQ-TPO-SCRIPT-002 | T-TPO-027 | 722 (manual) |
| REQ-TPO-SCRIPT-003 | T-TPO-027 | 723 (manual) |
| REQ-TPO-SCRIPT-004 | T-TPO-027 | 724 (manual) |
| REQ-TPO-SCRIPT-005 | T-TPO-027 | 725 (manual) |
| REQ-TPO-SCRIPT-006 | T-TPO-028, T-TPO-029 | 726 |
| REQ-TPO-CX-001 | All RED/GREEN pairs (T-TPO-002..024) | (structural) |
| REQ-TPO-CX-002 | T-TPO-015, T-TPO-032 | (structural) |
| REQ-TPO-CX-003 | T-TPO-020 | (es-AR tags) |
| REQ-TPO-CX-004 | T-TPO-032 | (AppPalette/TreinoIcon) |
| REQ-TPO-CX-005 | T-TPO-015, T-TPO-032 | (structural) |

---

## Pre-PR Checklist

### PR#1

- [ ] All 21 new tests pass (`flutter test` for the 3 new test files)
- [ ] `flutter analyze` 0 issues
- [ ] `dart format` 0 changes on touched files
- [ ] `_trainerPublicSubsetFromPartial` signature updated; only one callsite (`update()`) — confirmed
- [ ] `_trainerPublicFields` whitelist unchanged (rg check passes)
- [ ] No `pubspec.yaml`, `firestore.rules`, `storage.rules`, or CF changes
- [ ] All commits conventional, no `Co-Authored-By`
- [ ] Extension file `lib/features/profile/domain/user_profile_trainer_completeness.dart` created
- [ ] `trainerProfileCompleteProvider` added to `lib/features/profile/application/user_providers.dart`
- [ ] `authRedirect` loop guard uses `startsWith('/profile/edit-trainer')` (not exact match)

### PR#2

- [ ] Rebased on `main` after PR#1 merges
- [ ] All ≥11 new widget tests pass (`flutter test` for the 2 new widget test files)
- [ ] `flutter analyze` 0 issues
- [ ] `dart format` 0 changes on touched files
- [ ] `enum ProfileEditTrainerMode` inline at top of `profile_edit_trainer_screen.dart`
- [ ] Both AppBar title strings tagged `// i18n: Fase 6 Etapa 1`
- [ ] `PopScope(canPop: false)` present in onboarding mode; absent in edit mode
- [ ] Post-save branches: `context.go('/home')` for onboarding, `context.pop()` for edit
- [ ] Router builder reads `state.uri.queryParameters['mode']`; any non-`'onboarding'` value → `edit`
- [ ] `scripts/promote_user_to_trainer.js` created; ~30 LOC; no field seeding
- [ ] `scripts/README.md` created; documents prerequisites + usage + post-promotion flow
- [ ] `scripts/promote_mateo_to_public_trainer.js` DELETED; absent from `git status`
- [ ] BREAKING commit message for deletion included
- [ ] No `pubspec.yaml`, `firestore.rules`, `storage.rules`, or CF changes
- [ ] No hex literals; no direct `PhosphorIcons.X` references
- [ ] All commits conventional, no `Co-Authored-By`
- [ ] Manual smoke checklist (T-TPO-033) passed against `treino-dev`

---

## Hard Constraints

- 2 PRs chained-to-main, stacked-to-main chain strategy
- Strict TDD: RED commit (failing test) BEFORE GREEN commit (passing implementation) for every task pair
- `averageRating` and `reviewCount` MUST NOT appear in `_trainerPublicFields` whitelist (ADR-RV-005)
- NO `pubspec.yaml` changes
- NO `firestore.rules` changes
- NO `storage.rules` changes
- NO Cloud Function changes
- All es-AR strings tagged `// i18n: Fase 6 Etapa 1`
- All colors via `AppPalette.of(context)` — no hex literals
- All icons via `TreinoIcon.X` — no `PhosphorIcons.X` direct references
- Conventional commits only — NO `Co-Authored-By`, no AI attribution
- DELETE `scripts/promote_mateo_to_public_trainer.js` (not deprecate — delete)
- CREATE `scripts/README.md`
- `ProfileEditTrainerScreen` onboarding mode: `automaticallyImplyLeading: false` + `PopScope(canPop: false)` — both required
- Post-save in onboarding mode: `context.go('/home')` — not `pop()`

---

## Final Deliverables Beyond Code

- Update `docs/roadmap.md` line 414 (Etapa 1) to ✅ with PR hashes after PR#2 merges (T-TPO-034, post-archive step).

---

## Artifacts

- File: `openspec/changes/trainer-profile-onboarding/tasks.md`
- Engram: `sdd/trainer-profile-onboarding/tasks`
