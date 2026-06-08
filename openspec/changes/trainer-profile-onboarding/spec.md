# Spec: trainer-profile-onboarding

**Change**: trainer-profile-onboarding
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-08
**Phase**: Fase 6 Etapa 1
**Artifact store**: hybrid (file + Engram `sdd/trainer-profile-onboarding/spec`)
**Proposal ref**: `openspec/changes/trainer-profile-onboarding/proposal.md`
**Scenario range**: SCENARIO-688..SCENARIO-726

---

## Overview

This change ships the complete end-to-end path that turns a freshly-promoted `role: trainer` user into a public coach profile discoverable in `TrainersListScreen`. It is entirely additive for the trainer surface and a strict no-op for athletes. Four surfaces are touched: (1) `UserRepository._trainerPublicSubsetFromPartial` receives a critical `uid` bug fix that unblocks first-time creates against Firestore rules; (2) a derived `trainerProfileComplete` completeness helper is added with no model field and no Freezed regen; (3) `authRedirect` in `router.dart` gains a trainer-incomplete gate that redirects to the onboarding surface; (4) `ProfileEditTrainerScreen` accepts a `?mode=onboarding` query param that locks back navigation and routes post-save to `/home`. A generic `scripts/promote_user_to_trainer.js` replaces the Mateo-specific seed script. No new collections, no CF changes, no Firestore/storage rules changes, no `pubspec.yaml` additions.

Delivered in 2 chained PRs targeting `main`. Total scope ~250 LOC.

---

## Requirements

---

### REQ-TPO-DATA-001 — uid Threaded Into trainerPublicSubsetFromPartial

`UserRepository._trainerPublicSubsetFromPartial` MUST receive `uid` as an explicit parameter and MUST include `result['uid'] = uid` in the returned map whenever at least one trainer-specific field is present in the partial. The `update()` method MUST pass its authenticated `uid` argument into the helper. `SetOptions(merge: true)` on the batch write ensures the operation is idempotent — re-writing `uid` on an existing `trainerPublicProfiles/{uid}` doc MUST NOT overwrite other fields.

#### SCENARIO-688: First-time trainer save writes uid to public profile document
- **Given** an authenticated trainer `user_a` with no existing `trainerPublicProfiles/user_a` document
- **When** `UserRepository.update(uid: user_a, partial: {trainerBio: 'hello', trainerSpecialty: 'crossfit'})` is called
- **Then** `trainerPublicProfiles/user_a` is created
- **And** `trainerPublicProfiles/user_a.uid == 'user_a'`
- **And** `trainerPublicProfiles/user_a.trainerBio == 'hello'`
- **Test target**: `test/features/profile/data/user_repository_trainer_uid_test.dart`
- **REQ**: REQ-TPO-DATA-001

#### SCENARIO-689: Re-saving trainer profile is idempotent (uid already present)
- **Given** an existing `trainerPublicProfiles/user_a` doc with `uid == 'user_a'` and `trainerBio == 'hello'`
- **When** `UserRepository.update(uid: user_a, partial: {trainerBio: 'updated'})` is called
- **Then** `trainerPublicProfiles/user_a.uid` is still `'user_a'` (not overwritten or duplicated)
- **And** `trainerPublicProfiles/user_a.trainerBio == 'updated'`
- **Test target**: `test/features/profile/data/user_repository_trainer_uid_test.dart`
- **REQ**: REQ-TPO-DATA-001

#### SCENARIO-690: Partial with no trainer-specific fields does not touch trainerPublicProfiles
- **Given** a partial containing only athlete fields (e.g., `weight`, `height`)
- **When** `UserRepository.update(uid: user_a, partial: {weight: 70})` is called
- **Then** no write operation targets `trainerPublicProfiles/user_a`
- **Test target**: `test/features/profile/data/user_repository_trainer_uid_test.dart`
- **REQ**: REQ-TPO-DATA-001

---

### REQ-TPO-DATA-002 — Dual-Write Whitelist Preserved (ADR-RV-005)

The `_trainerPublicFields` whitelist in `UserRepository` MUST remain unchanged. `averageRating` and `reviewCount` MUST NOT be added to the whitelist. These fields are CF-write-only per ADR-RV-005 and MUST NOT be written by client-side dual-write operations.

#### SCENARIO-691: averageRating is not included in public profile dual-write
- **Given** a partial containing a hypothetical `averageRating` field
- **When** `_trainerPublicSubsetFromPartial` processes the partial
- **Then** the resulting subset map does not include `averageRating`
- **Test target**: `test/features/profile/data/user_repository_trainer_uid_test.dart`
- **REQ**: REQ-TPO-DATA-002

---

### REQ-TPO-DATA-003 — Repo-Level Location Guard Preserved

`UserRepository._assertTrainerLocationStateIsValid` MUST remain intact and MUST be called on every trainer profile save. The invariant is: at least one `TrainerLocation` in `trainerLocations` OR `trainerOffersOnline == true`. Saves that violate this invariant MUST throw before any Firestore write occurs.

#### SCENARIO-692: Save with no locations and online=false is rejected
- **Given** a partial with `trainerLocations: []` and `trainerOffersOnline: false`
- **When** `UserRepository.update()` is called
- **Then** an exception is thrown before any Firestore batch write executes
- **Test target**: `test/features/profile/data/user_repository_trainer_uid_test.dart`
- **REQ**: REQ-TPO-DATA-003

#### SCENARIO-693: Save with trainerOffersOnline=true and empty locations is accepted
- **Given** a partial with `trainerLocations: []` and `trainerOffersOnline: true`
- **When** `UserRepository.update()` is called with valid required fields
- **Then** no exception is thrown and the Firestore batch write proceeds
- **Test target**: `test/features/profile/data/user_repository_trainer_uid_test.dart`
- **REQ**: REQ-TPO-DATA-003

---

### REQ-TPO-DATA-004 — Derived trainerProfileComplete Helper

A `trainerProfileComplete` helper MUST be added computing from existing `UserProfile` fields using the formula: `trainerBio != null && trainerSpecialty != null && trainerMonthlyRate != null && (trainerLocations.isNotEmpty || trainerOffersOnline == true)`. This helper MUST NOT add any new field to the `UserProfile` Freezed model, MUST NOT trigger Freezed code generation, and MUST NOT require a Firestore migration. Acceptable shapes: a `bool get trainerProfileComplete` getter on `UserProfile` (via extension or direct addition to the class), or a `Provider<bool>` derived from `userProfileProvider` in `user_providers.dart`.

#### SCENARIO-694: trainerProfileComplete is false when bio is null
- **Given** a UserProfile with `trainerBio: null`, all other trainer fields set
- **When** `trainerProfileComplete` is evaluated
- **Then** it returns `false`
- **Test target**: `test/features/profile/domain/trainer_profile_complete_test.dart`
- **REQ**: REQ-TPO-DATA-004

#### SCENARIO-695: trainerProfileComplete is false when specialty is null
- **Given** a UserProfile with `trainerSpecialty: null`, all other trainer fields set
- **When** `trainerProfileComplete` is evaluated
- **Then** it returns `false`
- **Test target**: `test/features/profile/domain/trainer_profile_complete_test.dart`
- **REQ**: REQ-TPO-DATA-004

#### SCENARIO-696: trainerProfileComplete is false when monthlyRate is null
- **Given** a UserProfile with `trainerMonthlyRate: null`, all other trainer fields set
- **When** `trainerProfileComplete` is evaluated
- **Then** it returns `false`
- **Test target**: `test/features/profile/domain/trainer_profile_complete_test.dart`
- **REQ**: REQ-TPO-DATA-004

#### SCENARIO-697: trainerProfileComplete is false when locations empty and online=false
- **Given** a UserProfile with `trainerBio` set, `trainerSpecialty` set, `trainerMonthlyRate` set, `trainerLocations: []`, `trainerOffersOnline: false`
- **When** `trainerProfileComplete` is evaluated
- **Then** it returns `false`
- **Test target**: `test/features/profile/domain/trainer_profile_complete_test.dart`
- **REQ**: REQ-TPO-DATA-004

#### SCENARIO-698: trainerProfileComplete is true when all required fields set and online=true
- **Given** a UserProfile with `trainerBio` set, `trainerSpecialty` set, `trainerMonthlyRate` set, `trainerLocations: []`, `trainerOffersOnline: true`
- **When** `trainerProfileComplete` is evaluated
- **Then** it returns `true`
- **Test target**: `test/features/profile/domain/trainer_profile_complete_test.dart`
- **REQ**: REQ-TPO-DATA-004

#### SCENARIO-699: trainerProfileComplete is true when all required fields set and locations non-empty
- **Given** a UserProfile with `trainerBio` set, `trainerSpecialty` set, `trainerMonthlyRate` set, `trainerLocations: [<one location>]`, `trainerOffersOnline: false`
- **When** `trainerProfileComplete` is evaluated
- **Then** it returns `true`
- **Test target**: `test/features/profile/domain/trainer_profile_complete_test.dart`
- **REQ**: REQ-TPO-DATA-004

#### SCENARIO-700: trainerProfileComplete is false when all fields null (fresh trainer)
- **Given** a UserProfile with all trainer-specific fields null/empty (freshly promoted)
- **When** `trainerProfileComplete` is evaluated
- **Then** it returns `false`
- **Test target**: `test/features/profile/domain/trainer_profile_complete_test.dart`
- **REQ**: REQ-TPO-DATA-004

---

### REQ-TPO-GATE-001 — authRedirect Trainer-Incomplete Branch

`authRedirect` in `lib/app/router.dart` MUST add a new branch that fires AFTER the existing `displayName == null` redirect and BEFORE the public-route → `/home` redirect. The branch MUST redirect to `/profile/edit-trainer?mode=onboarding` when all of the following are true: the user is authenticated, `displayName` is not null, `role == 'trainer'`, and `trainerProfileComplete == false`.

#### SCENARIO-701: Trainer with incomplete profile is redirected to onboarding
- **Given** an authenticated user with `role: 'trainer'`, `displayName` set, and `trainerProfileComplete == false`
- **When** `authRedirect` is called for any non-public route (e.g., `/home`)
- **Then** `authRedirect` returns `/profile/edit-trainer?mode=onboarding`
- **Test target**: `test/app/router_auth_redirect_test.dart`
- **REQ**: REQ-TPO-GATE-001

#### SCENARIO-702: Trainer with complete profile is not redirected
- **Given** an authenticated user with `role: 'trainer'`, `displayName` set, and `trainerProfileComplete == true`
- **When** `authRedirect` is called for `/home`
- **Then** `authRedirect` returns `null` (no redirect)
- **Test target**: `test/app/router_auth_redirect_test.dart`
- **REQ**: REQ-TPO-GATE-001

---

### REQ-TPO-GATE-002 — authRedirect Loop Guard

The trainer-incomplete redirect MUST be a no-op when the current router location already starts with `/profile/edit-trainer`. This MUST prevent infinite redirect loops.

#### SCENARIO-703: No redirect loop when already on onboarding screen
- **Given** an authenticated trainer with `trainerProfileComplete == false`
- **When** `authRedirect` is called with `state.matchedLocation == '/profile/edit-trainer'`
- **Then** `authRedirect` returns `null` (no redirect)
- **Test target**: `test/app/router_auth_redirect_test.dart`
- **REQ**: REQ-TPO-GATE-002

---

### REQ-TPO-GATE-003 — authRedirect Does Not Fire for Athletes

The trainer-incomplete gate MUST NOT affect users with `role == 'athlete'`. Athletes MUST bypass this gate entirely.

#### SCENARIO-704: Athlete with incomplete trainer fields is not redirected
- **Given** an authenticated user with `role: 'athlete'`, `displayName` set
- **When** `authRedirect` is called for `/home`
- **Then** `authRedirect` returns `null` (athlete gate not triggered)
- **Test target**: `test/app/router_auth_redirect_test.dart`
- **REQ**: REQ-TPO-GATE-003

---

### REQ-TPO-GATE-004 — Existing authRedirect Branches Preserved

The `displayName == null` redirect, the account-deletion in-flight gate, and the public-route accessibility MUST remain behaviorally identical after the trainer-incomplete branch is added. The insertion point is strictly AFTER `displayName == null` and BEFORE public-route checks.

#### SCENARIO-705: Unauthenticated user is redirected to sign-in
- **Given** no authenticated user
- **When** `authRedirect` is called for `/home`
- **Then** `authRedirect` returns the sign-in route
- **Test target**: `test/app/router_auth_redirect_test.dart`
- **REQ**: REQ-TPO-GATE-004

#### SCENARIO-706: Authenticated user with null displayName is redirected to profile-setup
- **Given** an authenticated user with `displayName == null` (any role)
- **When** `authRedirect` is called for `/home`
- **Then** `authRedirect` returns the profile-setup route (not the trainer onboarding route)
- **Test target**: `test/app/router_auth_redirect_test.dart`
- **REQ**: REQ-TPO-GATE-004

#### SCENARIO-707: Account-deletion in-flight gate is not disturbed
- **Given** an authenticated user in the account-deletion in-flight state
- **When** `authRedirect` is called
- **Then** the existing in-flight gate behavior fires (trainer gate does not override it)
- **Test target**: `test/app/router_auth_redirect_test.dart`
- **REQ**: REQ-TPO-GATE-004

#### SCENARIO-708: Public routes remain accessible before trainer gate
- **Given** an authenticated trainer with `trainerProfileComplete == false`
- **When** `authRedirect` is called for a public route (sign-in, sign-up, profile-setup paths)
- **Then** `authRedirect` does not redirect to the trainer onboarding gate
- **Test target**: `test/app/router_auth_redirect_test.dart`
- **REQ**: REQ-TPO-GATE-004

---

### REQ-TPO-UI-001 — ProfileEditTrainerMode Enum

`ProfileEditTrainerScreen` MUST define or import `enum ProfileEditTrainerMode { edit, onboarding }`. The constructor MUST accept `ProfileEditTrainerMode mode` defaulting to `ProfileEditTrainerMode.edit`. The enum MUST be co-located in `profile_edit_trainer_screen.dart` unless another consumer requires it to be extracted.

#### SCENARIO-709: Screen defaults to edit mode when no mode is provided
- **Given** `ProfileEditTrainerScreen` is constructed without a `mode` argument
- **When** the widget is pumped in a test
- **Then** the effective mode is `ProfileEditTrainerMode.edit`
- **Test target**: `test/features/profile/presentation/profile_edit_trainer_screen_edit_test.dart`
- **REQ**: REQ-TPO-UI-001

---

### REQ-TPO-UI-002 — Router Maps ?mode=onboarding Query Param

The route registration for `/profile/edit-trainer` in `lib/app/router.dart` MUST read `state.uri.queryParameters['mode']` and pass `ProfileEditTrainerMode.onboarding` to the screen constructor when the value equals `'onboarding'`, otherwise `ProfileEditTrainerMode.edit`.

#### SCENARIO-710: Route with ?mode=onboarding creates screen in onboarding mode
- **Given** the router handles a navigation to `/profile/edit-trainer?mode=onboarding`
- **When** the route builder executes
- **Then** `ProfileEditTrainerScreen` is constructed with `mode == ProfileEditTrainerMode.onboarding`
- **Test target**: `test/app/router_auth_redirect_test.dart` (router-level) or widget test via `GoRouter` test helpers
- **REQ**: REQ-TPO-UI-002

#### SCENARIO-711: Route without query param creates screen in edit mode
- **Given** the router handles a navigation to `/profile/edit-trainer` (no query param)
- **When** the route builder executes
- **Then** `ProfileEditTrainerScreen` is constructed with `mode == ProfileEditTrainerMode.edit`
- **Test target**: same as SCENARIO-710
- **REQ**: REQ-TPO-UI-002

---

### REQ-TPO-UI-003 — AppBar Title Branches on Mode

In **edit mode** the AppBar title MUST display `"Editá tu perfil profesional"` (es-AR, tagged `// i18n: Fase 6 Etapa 1`). In **onboarding mode** the AppBar title MUST display `"Completá tu perfil profesional"` (es-AR, tagged `// i18n: Fase 6 Etapa 1`).

#### SCENARIO-712: Edit mode AppBar title is correct
- **Given** `ProfileEditTrainerScreen` is pumped in edit mode
- **When** the widget renders
- **Then** the AppBar title text is `"Editá tu perfil profesional"`
- **Test target**: `test/features/profile/presentation/profile_edit_trainer_screen_edit_test.dart`
- **REQ**: REQ-TPO-UI-003

#### SCENARIO-713: Onboarding mode AppBar title is correct
- **Given** `ProfileEditTrainerScreen` is pumped in onboarding mode
- **When** the widget renders
- **Then** the AppBar title text is `"Completá tu perfil profesional"`
- **Test target**: `test/features/profile/presentation/profile_edit_trainer_screen_onboarding_test.dart`
- **REQ**: REQ-TPO-UI-003

---

### REQ-TPO-UI-004 — Back Navigation Disabled in Onboarding Mode

In **onboarding mode** the AppBar MUST set `automaticallyImplyLeading: false` and the screen MUST wrap content in `PopScope(canPop: false)` (or `WillPopScope` on older Flutter targets) so that both the AppBar back button and the OS back gesture/button are blocked.

In **edit mode** back navigation MUST function normally (no PopScope blocking, leading button present).

#### SCENARIO-714: Back button absent in onboarding mode
- **Given** `ProfileEditTrainerScreen` is pumped in onboarding mode
- **When** the widget renders
- **Then** no back button is present in the AppBar
- **And** a `PopScope(canPop: false)` (or equivalent) is in the widget tree
- **Test target**: `test/features/profile/presentation/profile_edit_trainer_screen_onboarding_test.dart`
- **REQ**: REQ-TPO-UI-004

#### SCENARIO-715: Back button present in edit mode
- **Given** `ProfileEditTrainerScreen` is pumped in edit mode
- **When** the widget renders
- **Then** the AppBar back button is present and enabled
- **Test target**: `test/features/profile/presentation/profile_edit_trainer_screen_edit_test.dart`
- **REQ**: REQ-TPO-UI-004

---

### REQ-TPO-UI-005 — Post-Save Navigation Branches on Mode

After a successful save, **onboarding mode** MUST navigate via `context.go('/home')` (replaces the stack). **Edit mode** MUST navigate via `context.pop()`.

#### SCENARIO-716: Onboarding mode navigates to /home after save
- **Given** `ProfileEditTrainerScreen` is pumped in onboarding mode with a `GoRouter` test setup
- **When** the user fills in all required fields and taps save
- **Then** the GoRouter current location becomes `/home`
- **Test target**: `test/features/profile/presentation/profile_edit_trainer_screen_onboarding_test.dart`
- **REQ**: REQ-TPO-UI-005

#### SCENARIO-717: Edit mode pops after save
- **Given** `ProfileEditTrainerScreen` is pumped in edit mode with a `GoRouter` test setup with a prior route on the stack
- **When** the user fills in all required fields and taps save
- **Then** `context.pop()` is called and the screen is dismissed
- **Test target**: `test/features/profile/presentation/profile_edit_trainer_screen_edit_test.dart`
- **REQ**: REQ-TPO-UI-005

---

### REQ-TPO-UI-006 — Save Path Uses Existing Dual-Write

Both onboarding mode and edit mode MUST invoke the same `UserRepository.update()` dual-write path on save. No new write path, no skip of client-side validation or the `_assertTrainerLocationStateIsValid` repo-level guard.

#### SCENARIO-718: Onboarding mode save fails with location invariant violation
- **Given** `ProfileEditTrainerScreen` is pumped in onboarding mode
- **When** the user submits with `trainerLocations: []` and `trainerOffersOnline: false`
- **Then** the repository guard throws and no Firestore write occurs
- **And** the screen displays an error state (does not navigate to `/home`)
- **Test target**: `test/features/profile/presentation/profile_edit_trainer_screen_onboarding_test.dart`
- **REQ**: REQ-TPO-UI-006

---

### REQ-TPO-UI-007 — Form Validation Identical Across Modes

Bio length, monthly rate range, specialty selection, and location invariant validation rules MUST be identical between edit mode and onboarding mode.

#### SCENARIO-719: Form validation rules are mode-independent
- **Given** `ProfileEditTrainerScreen` is pumped in onboarding mode
- **When** the user submits with `trainerBio` shorter than the minimum allowed length
- **Then** the same validation error is shown as in edit mode for the same input
- **Test target**: `test/features/profile/presentation/profile_edit_trainer_screen_onboarding_test.dart`
- **REQ**: REQ-TPO-UI-007

---

### REQ-TPO-UI-008 — No Partial Save (Local Draft Only)

Unsaved input MUST remain local-only. Closing the app or being sent back to the gate by `authRedirect` after back navigation (if somehow triggered) MUST NOT persist a partial profile to Firestore. The user re-entering via the gate starts with the last-saved state from Firestore.

#### SCENARIO-720: Unsaved input is discarded when app is restarted
- **Given** a trainer has entered some text in onboarding mode but has NOT tapped save
- **When** the app is restarted
- **Then** the form shows the last Firestore-persisted state (empty for a fresh trainer)
- **Test target**: Documented constraint — no direct automated test needed; covered by the absence of any draft persistence code
- **REQ**: REQ-TPO-UI-008

---

### REQ-TPO-SCRIPT-001 — promote_user_to_trainer.js CLI Contract

`scripts/promote_user_to_trainer.js` MUST accept a single positional CLI argument `<uid>`. If no argument is provided, the script MUST print a usage error message and exit with code 1.

#### SCENARIO-721: Script exits 1 with usage message when uid is missing
- **Given** the script is invoked as `node scripts/promote_user_to_trainer.js` (no arguments)
- **When** the process starts
- **Then** a usage error message is printed to stderr
- **And** the process exits with code 1
- **Test target**: Manual / shell integration test in `scripts/` directory
- **REQ**: REQ-TPO-SCRIPT-001

---

### REQ-TPO-SCRIPT-002 — Script Validates User Document Existence

Before applying any update, the script MUST read `users/{uid}` from Firestore. If the document does not exist, the script MUST log a clear error and exit with code 1. It MUST NOT create or seed any `trainerPublicProfiles/{uid}` document.

#### SCENARIO-722: Script exits 1 when users/{uid} does not exist
- **Given** Firestore has no document at `users/nonexistent-uid`
- **When** `node scripts/promote_user_to_trainer.js nonexistent-uid` is invoked
- **Then** an error message is printed identifying the missing document
- **And** the process exits with code 1
- **Test target**: Manual test against `treino-dev` Firebase project
- **REQ**: REQ-TPO-SCRIPT-002

---

### REQ-TPO-SCRIPT-003 — Script Logs Affected User Before Update

Before calling `.update({role: 'trainer'})`, the script MUST read and log the affected user's `email` and `displayName` for human verification.

#### SCENARIO-723: Script logs email and displayName before updating
- **Given** a valid `users/{uid}` doc with `email: 'pf@example.com'` and `displayName: 'Carlos'`
- **When** `node scripts/promote_user_to_trainer.js uid` is invoked
- **Then** the script prints a log line containing `pf@example.com` and `Carlos` before writing
- **And** the process exits with code 0
- **Test target**: Manual test against `treino-dev` Firebase project
- **REQ**: REQ-TPO-SCRIPT-003

---

### REQ-TPO-SCRIPT-004 — Script Updates Only role Field

The script MUST call `users/{uid}.update({role: 'trainer'})` ONLY. It MUST NOT seed any trainer-specific fields (`trainerBio`, `trainerSpecialty`, `trainerMonthlyRate`, `trainerLocations`, etc.). Trainer fields are populated exclusively via the app's onboarding flow.

#### SCENARIO-724: Script writes only role field to users document
- **Given** a valid `users/{uid}` doc with no trainer fields
- **When** `node scripts/promote_user_to_trainer.js uid` completes
- **Then** `users/{uid}.role == 'trainer'`
- **And** `users/{uid}.trainerBio` is absent/null (not seeded by the script)
- **Test target**: Manual test against `treino-dev` Firebase project
- **REQ**: REQ-TPO-SCRIPT-004

---

### REQ-TPO-SCRIPT-005 — Script is Idempotent

Running the script twice on the same uid MUST succeed on both runs. The second run MUST update `role` to the same value without error and exit with code 0.

#### SCENARIO-725: Script re-run on already-trainer user exits 0
- **Given** `users/{uid}.role == 'trainer'` (script has already been run)
- **When** `node scripts/promote_user_to_trainer.js uid` is invoked again
- **Then** `users/{uid}.role` is still `'trainer'`
- **And** the process exits with code 0
- **Test target**: Manual test against `treino-dev` Firebase project
- **REQ**: REQ-TPO-SCRIPT-005

---

### REQ-TPO-SCRIPT-006 — Legacy Script Deprecated (Deleted)

`scripts/promote_mateo_to_public_trainer.js` MUST be deleted from the repository. The generic `scripts/promote_user_to_trainer.js` fully supersedes it. A usage note for the new script MUST be added to `scripts/README.md` (creating the file if it does not exist) or `docs/setup-notes.md` if that is the established location.

#### SCENARIO-726: promote_mateo_to_public_trainer.js is absent from repo after PR#2
- **Given** PR#2 is applied
- **When** the repository is inspected
- **Then** `scripts/promote_mateo_to_public_trainer.js` does not exist
- **And** `scripts/promote_user_to_trainer.js` exists with documented usage
- **Test target**: CI / manual repo inspection at PR#2 merge
- **REQ**: REQ-TPO-SCRIPT-006

---

### REQ-TPO-CX-001 — Strict TDD Enforcement

Every task pair MUST have a RED commit (failing test) before the GREEN commit (passing implementation). This applies to all four surfaces: repository uid fix, derived helper, authRedirect gate, and ProfileEditTrainerScreen mode branching.

---

### REQ-TPO-CX-002 — Conventional Commits, No AI Attribution

All commits MUST follow the Conventional Commits specification. No `Co-Authored-By` trailer and no AI attribution MUST appear in any commit message.

---

### REQ-TPO-CX-003 — es-AR i18n Markers

All new user-facing strings in Spanish MUST be tagged with the inline comment `// i18n: Fase 6 Etapa 1`. This applies to at minimum: the two AppBar title strings in `ProfileEditTrainerScreen`.

---

### REQ-TPO-CX-004 — AppPalette and TreinoIcon Conventions

All color references in new or modified UI code MUST use `AppPalette.of(context)`. No hex literals MUST appear. All icon references MUST use `TreinoIcon.X`. No `PhosphorIcons.X` references MUST appear directly.

---

### REQ-TPO-CX-005 — No pubspec, Firestore Rules, Storage Rules, or CF Changes

This change MUST NOT add or modify any entry in `pubspec.yaml`. It MUST NOT modify `firestore.rules`, `storage.rules`, or any Cloud Function. The existing rules already cover the `trainerPublicProfiles/{uid}` path once the `uid` field is correctly included in the write.

---

## Coverage Matrix

| REQ ID | Description | SCENARIOs | PR |
|---|---|---|---|
| REQ-TPO-DATA-001 | uid threaded into subset helper | 688, 689, 690 | PR#1 |
| REQ-TPO-DATA-002 | Dual-write whitelist preserved (ADR-RV-005) | 691 | PR#1 |
| REQ-TPO-DATA-003 | Location guard preserved | 692, 693 | PR#1 |
| REQ-TPO-DATA-004 | Derived trainerProfileComplete helper | 694, 695, 696, 697, 698, 699, 700 | PR#1 |
| REQ-TPO-GATE-001 | authRedirect trainer-incomplete branch | 701, 702 | PR#1 |
| REQ-TPO-GATE-002 | authRedirect loop guard | 703 | PR#1 |
| REQ-TPO-GATE-003 | Gate does not fire for athletes | 704 | PR#1 |
| REQ-TPO-GATE-004 | Existing authRedirect branches preserved | 705, 706, 707, 708 | PR#1 |
| REQ-TPO-UI-001 | ProfileEditTrainerMode enum | 709 | PR#2 |
| REQ-TPO-UI-002 | Router maps ?mode=onboarding query param | 710, 711 | PR#2 |
| REQ-TPO-UI-003 | AppBar title branches on mode | 712, 713 | PR#2 |
| REQ-TPO-UI-004 | Back navigation disabled in onboarding mode | 714, 715 | PR#2 |
| REQ-TPO-UI-005 | Post-save navigation branches on mode | 716, 717 | PR#2 |
| REQ-TPO-UI-006 | Save path uses existing dual-write | 718 | PR#2 |
| REQ-TPO-UI-007 | Form validation identical across modes | 719 | PR#2 |
| REQ-TPO-UI-008 | No partial save | 720 | PR#2 |
| REQ-TPO-SCRIPT-001 | promote script CLI contract | 721 | PR#2 |
| REQ-TPO-SCRIPT-002 | Script validates user doc existence | 722 | PR#2 |
| REQ-TPO-SCRIPT-003 | Script logs email + displayName | 723 | PR#2 |
| REQ-TPO-SCRIPT-004 | Script updates only role field | 724 | PR#2 |
| REQ-TPO-SCRIPT-005 | Script is idempotent | 725 | PR#2 |
| REQ-TPO-SCRIPT-006 | Legacy script deleted | 726 | PR#2 |
| REQ-TPO-CX-001 | Strict TDD enforcement | (all RED/GREEN pairs) | PR#1 + PR#2 |
| REQ-TPO-CX-002 | Conventional commits, no AI attribution | (all commits) | PR#1 + PR#2 |
| REQ-TPO-CX-003 | es-AR i18n markers | (see UI REQs) | PR#2 |
| REQ-TPO-CX-004 | AppPalette / TreinoIcon | (see UI REQs) | PR#2 |
| REQ-TPO-CX-005 | No pubspec / rules / CF changes | (structural constraint) | PR#1 + PR#2 |

---

## Open Questions for Design

1. **Shape of `trainerProfileComplete`** — getter on `UserProfile` vs derived `Provider<bool>` in `user_providers.dart`. Design phase MUST lock this. Criterion: pick whichever the `authRedirect` consumer integrates with most cleanly given the existing `ref.read` patterns.
2. **Exact enum file location** for `ProfileEditTrainerMode` — co-located in `profile_edit_trainer_screen.dart` vs extracted to `profile_edit_trainer_mode.dart`. Low risk; co-located is the default unless another consumer appears.
3. **Usage docs location** — `scripts/README.md` (create if absent) vs `docs/setup-notes.md`. Design resolves; recommend `scripts/README.md`.

---

## Hard Constraints (verbatim from proposal §Hard Constraints, as enforceable requirements)

- `averageRating` and `reviewCount` MUST NOT be added to `_trainerPublicFields` whitelist (ADR-RV-005).
- `firestore.rules` MUST NOT be modified.
- `storage.rules` MUST NOT be modified.
- No Cloud Function MUST be added or modified.
- `pubspec.yaml` MUST NOT be modified.
- No new Firestore collection MUST be created.
- Strict TDD: RED commit before GREEN commit for every task pair.
- Conventional commits. No `Co-Authored-By`. No AI attribution.
- All es-AR strings tagged `// i18n: Fase 6 Etapa 1`.
- All colors via `AppPalette.of(context)`. No hex literals.
- All icons via `TreinoIcon.X`. No `PhosphorIcons.X` direct references.
- `ProfileEditTrainerScreen` onboarding mode back navigation MUST be fully blocked (OS gesture + AppBar button).
- `context.go('/home')` MUST be used (not `pop()`) post-save in onboarding mode.

---

## Artifact References

- Spec file: `openspec/changes/trainer-profile-onboarding/spec.md`
- Engram: `sdd/trainer-profile-onboarding/spec`
- Proposal file: `openspec/changes/trainer-profile-onboarding/proposal.md`
- Engram proposal: `sdd/trainer-profile-onboarding/proposal` (#150)
- Exploration file: `openspec/changes/trainer-profile-onboarding/explore.md`
- Engram exploration: `sdd/trainer-profile-onboarding/explore` (#149)
