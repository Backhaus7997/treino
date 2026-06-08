# Design: trainer-profile-onboarding

**Change**: trainer-profile-onboarding
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-08
**Phase**: Fase 6 Etapa 1
**Artifact store**: hybrid (file + Engram `sdd/trainer-profile-onboarding/design`)
**Proposal ref**: `openspec/changes/trainer-profile-onboarding/proposal.md` (+ Engram `sdd/trainer-profile-onboarding/proposal` #150)
**Spec ref**: `openspec/changes/trainer-profile-onboarding/spec.md` (+ Engram `sdd/trainer-profile-onboarding/spec` #151)
**Exploration ref**: `openspec/changes/trainer-profile-onboarding/explore.md` (+ Engram `sdd/trainer-profile-onboarding/explore` #149)
**ADR range**: ADR-TPO-001 .. ADR-TPO-011

---

## 1. Scope Summary

This design locks the architecture for the trainer-profile onboarding flow. Four small surfaces change, with ADRs picking the cheapest viable shape for each: (1) `UserRepository._trainerPublicSubsetFromPartial` is fixed to thread `uid` so Firestore create rules accept the first dual-write; (2) a `trainerProfileComplete` getter lives on `UserProfile` and is exposed via a thin derived provider so both router redirect logic and widgets consume a single source of truth; (3) `authRedirect` gains a new branch positioned strictly after the `displayName == null` gate and the account-deletion in-flight gate, with a self-skip guard to prevent loops; (4) `ProfileEditTrainerScreen` accepts a `ProfileEditTrainerMode` enum (inline) that drives AppBar title, back-navigation blocking, and post-save destination. The legacy Mateo-specific seed script is replaced by a generic `scripts/promote_user_to_trainer.js` and a new `scripts/README.md` documents the team workflow. No new collections, no Cloud Functions, no Firestore/storage rules changes, no `pubspec.yaml` additions.

---

## 2. Architecture Overview

### High-level flow (cold start of a freshly-promoted trainer)

```
Team operator
   │ node scripts/promote_user_to_trainer.js <uid>
   ▼
Firestore: users/{uid}.role = 'trainer'  ← Admin SDK bypasses role-immutability rule
   │
   ▼
Trainer reopens the app
   │
   ▼
SplashScreen → authStateChanges → userProfileProvider (StreamProvider)
   │
   ▼
GoRouter.redirect → authRedirect(read, location)
   │
   ├─ auth loading                                 → null
   ├─ !loggedIn && !isPublic                       → '/welcome'
   ├─ accountDeletionInFlight                      → null
   ├─ profile loading                              → null
   ├─ profile == null || displayName == null       → '/profile-setup'
   ├─ role == trainer && !trainerProfileComplete   ◄── NEW BRANCH (ADR-TPO-003)
   │    && !location.startsWith('/profile/edit-trainer')
   │                                                  → '/profile/edit-trainer?mode=onboarding'
   └─ loggedIn && isPublic && !splash              → '/home'
   │
   ▼
GoRoute('/profile/edit-trainer') reads ?mode=onboarding (ADR-TPO-005)
   │
   ▼
ProfileEditTrainerScreen(mode: ProfileEditTrainerMode.onboarding)
   │ AppBar.title = "Completá tu perfil profesional"  (ADR-TPO-006)
   │ AppBar.automaticallyImplyLeading = false
   │ PopScope(canPop: false)                          (ADR-TPO-006)
   │
   │ user fills bio + specialty + monthlyRate + (locations || online)
   │ taps SAVE
   ▼
UserRepository.update(uid, partial)
   │ _assertTrainerLocationStateIsValid(partial)
   │ _trainerPublicSubsetFromPartial(partial, uid: uid)  ← uid threaded (ADR-TPO-001)
   │ batch.set(users/{uid}, sanitized, merge: true)
   │ batch.set(userPublicProfiles/{uid}, publicSubset, merge: true)
   │ batch.set(trainerPublicProfiles/{uid}, trainerPublicSubset, merge: true)
   │   ▲ now includes uid → firestore.rules create passes
   │ batch.commit()
   ▼
Save callback branches on mode (ADR-TPO-006)
   │ mode == onboarding ? context.go('/home') : context.pop()
   ▼
HomeScreen
```

### Component / module table

| Component | File | Role |
|---|---|---|
| `UserRepository._trainerPublicSubsetFromPartial` | `lib/features/profile/data/user_repository.dart` | Pure mapper — accepts `uid` + `partial`, returns subset with `uid` field included whenever any trainer field is present. |
| `UserProfile.trainerProfileComplete` (extension getter) | `lib/features/profile/domain/user_profile_trainer_completeness.dart` (NEW) | Pure synchronous boolean derived from existing fields. Single source of truth. |
| `trainerProfileCompleteProvider` | `lib/features/profile/application/user_providers.dart` | Thin `Provider<bool>` wrapping `userProfileProvider.valueOrNull?.trainerProfileComplete ?? false`. Consumed by `authRedirect` and any future widget. |
| `authRedirect` | `lib/app/router.dart` | Pure function — adds trainer-incomplete branch with loop guard. |
| `ProfileEditTrainerMode` enum | `lib/features/profile/presentation/profile_edit_trainer_screen.dart` (inline) | View-only mode marker. No other consumer. |
| `ProfileEditTrainerScreen` | `lib/features/profile/presentation/profile_edit_trainer_screen.dart` | Adds `mode` ctor arg, drives title/back-block/post-save. |
| `/profile/edit-trainer` route | `lib/app/router.dart` | Reads `?mode=` query param, maps to enum. |
| `scripts/promote_user_to_trainer.js` | `scripts/` (NEW) | Generic CLI: validate doc exists → log identity → `update({role:'trainer'})` → exit 0/1. |
| `scripts/README.md` | `scripts/` (NEW) | Documents the promote workflow + future operator scripts. |

---

## 3. Architecture Decision Records

ADRs are grouped by surface. Status legend: ACCEPTED = locked for this change; SUPERSEDED = replaced by a later ADR in this document; DEPRECATED = removed.

---

### ADR-TPO-001 — Thread `uid` into `_trainerPublicSubsetFromPartial`

**Status**: ACCEPTED

**Context**: `firestore.rules` for `trainerPublicProfiles/{uid}` on create requires `request.resource.data.uid == uid`. Today `_trainerPublicSubsetFromPartial(Map partial)` builds the body from `partial` only, and `partial` never contains `uid` because `UserRepository.update()` filters `uid` out via `_immutableFields`. Every first-time trainer save from the app will fail permission-denied. The existing seed script (`promote_mateo_to_public_trainer.js`) bypasses this only because it manually includes `uid` and runs as Admin SDK. The code comment at lines 30-39 of `user_repository.dart` already describes the fix as "Approach E" and explicitly defers it.

**Decision**: Change the helper signature from `(Map partial)` to `(Map partial, {required String uid})`. When any trainer-specific field is present in `partial`, the returned subset map MUST include `result['uid'] = uid`. The caller (`update()`) already receives `uid` as its first positional argument — pass it through. `SetOptions(merge: true)` on the batch write (already in code) makes re-writing `uid` on existing docs a no-op, so the fix is fully idempotent.

**Consequences**:
- Pros: 2-line change in production code. Unblocks every future trainer save. No rules change required. Idempotent for legacy seeded trainer docs that already contain `uid`.
- Pros: Eliminates the latent regression-bait described in the existing code comment — the comment can be replaced with a single line pointing at ADR-TPO-001.
- Cons: Helper signature change — all callers must be updated (there is only ONE caller, `update()`, so cost is trivial).
- Follow-up: regression test in `test/features/profile/data/user_repository_trainer_uid_test.dart` that verifies `trainerPublicProfiles/{uid}.uid == uid` after a first-time save via `fake_cloud_firestore`.

---

### ADR-TPO-002 — Preserve `_trainerPublicFields` whitelist verbatim (ADR-RV-005)

**Status**: ACCEPTED

**Context**: `_trainerPublicFields` is the authoritative set of fields that get dual-written to `trainerPublicProfiles/{uid}`. The trainer-reviews SDD locked ADR-RV-005: `averageRating` and `reviewCount` are CF-write-only and MUST NOT be added to this whitelist. The bug fix in ADR-TPO-001 must not piggy-back any whitelist mutation.

**Decision**: This change MUST NOT add, remove, or reorder any entry in `_trainerPublicFields`. The fix is strictly limited to threading `uid` into the helper. Any whitelist evolution is a separate SDD.

**Consequences**:
- Pros: Honors ADR-RV-005 invariant. Keeps the diff narrow and focused.
- Pros: A scenario (SCENARIO-691) asserts `averageRating` does NOT appear in the subset — gives a regression test for the invariant.
- Cons: None.

---

### ADR-TPO-003 — `authRedirect` ordering, loop guard, and athlete bypass

**Status**: ACCEPTED

**Context**: `authRedirect` is a pure function in `lib/app/router.dart` (line 78) that currently runs these checks in order: (1) auth loading → null, (2) anonymous on protected route → `/welcome`, (3) authenticated and not on profile-setup → account-deletion-in-flight gate, profile-loading gate, `displayName == null` → `/profile-setup`, (4) authenticated on public route (except splash) → `/home`. The new trainer-incomplete gate MUST integrate without regressing any existing branch (REQ-TPO-GATE-004), without redirect-looping on the onboarding route itself (REQ-TPO-GATE-002), and without firing for athletes (REQ-TPO-GATE-003).

**Decision**: Insert the new branch INSIDE the `if (loggedIn && !isProfileSetup)` block, AFTER the `profile.displayName == null` check that returns `/profile-setup`. The branch fires only when ALL of the following are true:
1. `profile != null && profile.displayName != null` (already guaranteed by reaching this code path).
2. `profile.role == UserRole.trainer`.
3. `!profile.trainerProfileComplete` (read directly via the getter — see ADR-TPO-004).
4. `!location.startsWith('/profile/edit-trainer')` — self-skip loop guard.

On match, return `'/profile/edit-trainer?mode=onboarding'`. The public-route → `/home` redirect at line 130 is unchanged and continues to run AFTER the new branch.

The branch uses the model getter directly (`profile.trainerProfileComplete`) rather than `read(trainerProfileCompleteProvider)` because `profile` is already in scope inside `authRedirect` and a second `read` call would be wasted indirection. The provider exists for widget consumers, not for the router (see ADR-TPO-004 rationale).

**Consequences**:
- Pros: Strict insertion point — every existing branch keeps identical semantics. Account-deletion-in-flight gate runs first and short-circuits before the trainer check, so a trainer mid-deletion is not redirected.
- Pros: Loop guard uses `startsWith('/profile/edit-trainer')` so both `?mode=onboarding` and the bare `/profile/edit-trainer` route are skipped — defensive against future query-param shapes.
- Pros: Athletes naturally bypass the branch via the `role == trainer` check.
- Cons: Adds a fifth check inside an already-branchy function. Mitigated by extracting nothing — readability wins from keeping the logic inline.
- Follow-up: spec lists 8 mandatory test branches in `test/app/router_auth_redirect_test.dart`; all 8 are non-negotiable in PR#1.

---

### ADR-TPO-004 — `trainerProfileComplete` shape: hybrid (model getter + thin provider)

**Status**: ACCEPTED — resolves spec Q1

**Context**: Spec phase passed forward three shape options for the completeness check: (a) getter on `UserProfile`, (b) derived `Provider<bool>`, (c) both. The check is consumed in TWO distinct contexts: (1) `authRedirect` which already holds a `UserProfile` instance in scope after reading `userProfileProvider`, and (2) potential future widgets that want to react to completeness changes without unpacking the `AsyncValue<UserProfile?>` themselves. The logic itself is pure boolean algebra over four fields and belongs in the domain layer.

Verified: `userProfileProvider` (in `lib/features/profile/application/user_providers.dart`) is a `StreamProvider<UserProfile?>` that streams via `userRepositoryProvider.watch(uid)`. The `read(userProfileProvider)` pattern in `authRedirect` already unwraps to `profile` — adding a separate `Provider<bool>` for this consumer would be wasted indirection.

**Decision**: Option (c) HYBRID.

1. Add a `bool get trainerProfileComplete` as an EXTENSION on `UserProfile` in a new file `lib/features/profile/domain/user_profile_trainer_completeness.dart`. The extension keeps the logic out of the Freezed-generated class (no regen, no schema impact) while still being a synchronous method on the model. Formula:
   ```dart
   extension UserProfileTrainerCompleteness on UserProfile {
     bool get trainerProfileComplete {
       return trainerBio != null
           && trainerSpecialty != null
           && trainerMonthlyRate != null
           && (trainerLocations.isNotEmpty || trainerOffersOnline);
     }
   }
   ```
2. Add a `final trainerProfileCompleteProvider = Provider<bool>((ref) { ... })` in `lib/features/profile/application/user_providers.dart`. The provider reads `userProfileProvider`, returns `valueOrNull?.trainerProfileComplete ?? false`. This is the consumer-facing API for widgets that want a reactive boolean without `AsyncValue` ceremony.
3. `authRedirect` consumes the GETTER directly via the already-in-scope `profile` instance (see ADR-TPO-003). The provider is NOT used in `authRedirect`.

**Consequences**:
- Pros: Single source of truth — the formula lives ONCE in the extension getter; the provider is a 3-line wrapper.
- Pros: Unit tests on the model (`test/features/profile/domain/trainer_profile_complete_test.dart`) cover all combinations without spinning up Riverpod containers — the spec's 7 scenarios (694-700) are pure model tests.
- Pros: Future widget consumers get a clean `ref.watch(trainerProfileCompleteProvider)` API.
- Pros: NO new field on `UserProfile`, NO Freezed regen, NO migration. Extension is invisible to JSON serialization.
- Cons: Two artifacts (extension + provider) for one concept. Mitigated by the provider being trivial and the extension being the canonical source.
- Follow-up: if a future SDD needs to invalidate completeness from a side effect, the provider can switch to `Provider.autoDispose` without touching consumers.

---

### ADR-TPO-005 — `ProfileEditTrainerMode` enum location and router query-param mapping

**Status**: ACCEPTED — resolves spec Q2

**Context**: The mode enum is consumed by exactly two sites: the screen constructor and the route builder. Project convention (cf. `ReviewTriggerVariant` inlined in `ReviewBottomSheet` during the trainer-reviews SDD) is to co-locate view-only enums with their single screen consumer. Extracting to a dedicated file adds a third file with no benefit.

**Decision**:
1. Define `enum ProfileEditTrainerMode { edit, onboarding }` INLINE at the top of `lib/features/profile/presentation/profile_edit_trainer_screen.dart`, immediately above the `ProfileEditTrainerScreen` class declaration.
2. The screen constructor accepts `ProfileEditTrainerMode mode = ProfileEditTrainerMode.edit` (defaults to edit for safety — any code path that forgets to pass the mode degrades to current behavior).
3. The router `GoRoute(path: 'edit-trainer', ...)` in `lib/app/router.dart` (currently lines 375-379) is updated to read `state.uri.queryParameters['mode']` and pass `ProfileEditTrainerMode.onboarding` when the value is exactly `'onboarding'`, otherwise `ProfileEditTrainerMode.edit`. Any other value (`?mode=xyz`, missing param, empty string) defaults to `edit` — strict allow-list behavior.

Concrete router snippet (illustrative — final form lives in PR#2):
```dart
GoRoute(
  path: 'edit-trainer',
  pageBuilder: (context, state) {
    final mode = state.uri.queryParameters['mode'] == 'onboarding'
        ? ProfileEditTrainerMode.onboarding
        : ProfileEditTrainerMode.edit;
    return _noAnim(ProfileEditTrainerScreen(mode: mode));
  },
),
```

**Consequences**:
- Pros: One enum, one consumer, one file. Matches existing project pattern.
- Pros: Default-to-edit means partial regressions land safely — even if a future caller forgets the mode, the screen stays in edit mode (back works, post-save pops).
- Pros: Strict allow-list on the query param prevents typo-based bugs (`?mode=Onboarding` does NOT enter onboarding mode).
- Cons: Future cross-file consumer would need extraction. Acceptable — extraction is a 3-minute refactor when (if) that day comes.

---

### ADR-TPO-006 — Onboarding-mode behavior: AppBar, back navigation, post-save

**Status**: ACCEPTED

**Context**: Spec REQ-TPO-UI-003, REQ-TPO-UI-004, REQ-TPO-UI-005 require three behaviors to branch on `mode`. The onboarding gate is a "forcing function" — the user MUST complete or close the app. Partial saves are explicitly out of scope (REQ-TPO-UI-008, locked decision #8). Post-save `pop()` from a gate-redirected screen has no underlying route to pop to, so `context.go('/home')` is the only correct destination (locked decision #9, mirrors ProfileSetup submit).

**Decision**: Three mode-driven branches inside `ProfileEditTrainerScreen.build`:

1. **AppBar title** — derived from `mode`:
   ```dart
   final title = mode == ProfileEditTrainerMode.onboarding
       ? 'Completá tu perfil profesional' // i18n: Fase 6 Etapa 1
       : 'Editá tu perfil profesional';   // i18n: Fase 6 Etapa 1
   ```
   Both strings carry the `// i18n: Fase 6 Etapa 1` marker per REQ-TPO-CX-003.

2. **Back navigation blocking (onboarding mode only)** — defense in depth:
   - `AppBar(automaticallyImplyLeading: false, ...)` removes the visual back button.
   - The body is wrapped in `PopScope(canPop: false, onPopInvokedWithResult: (_, __) {})` so the OS back gesture (iOS swipe-back, Android back button) is blocked too. (`PopScope` is the current Flutter 3.22 API; `WillPopScope` is deprecated. Project is on Flutter 3.22+ per `AGENTS.md`.)
   - In edit mode, neither override applies — `automaticallyImplyLeading` defaults to `true` and `PopScope` is not in the tree.

3. **Post-save navigation** — branch inside the save success callback:
   ```dart
   if (mode == ProfileEditTrainerMode.onboarding) {
     context.go('/home');
   } else {
     context.pop();
   }
   ```
   Error paths (validation failure, repo invariant violation) are mode-INDEPENDENT — the same error UI/snackbar shows in both modes (REQ-TPO-UI-006, REQ-TPO-UI-007). The branch is strictly on the post-save SUCCESS path.

**Consequences**:
- Pros: All three behaviors are ~5 lines each, all driven from the same `mode` field. Easy to audit.
- Pros: `PopScope` + `automaticallyImplyLeading: false` is belt-and-suspenders — covers both visual back button and OS gesture in a single onboarding-mode block.
- Pros: Post-save branching keeps the edit-mode flow exactly as today (no regression).
- Cons: Three branches in the screen body mean the screen now carries mode-conditional logic. Mitigated by all three branches being TINY and adjacent in the source.
- Follow-up: widget tests in `test/features/profile/presentation/profile_edit_trainer_screen_onboarding_test.dart` cover title, back-button absence, and post-save navigation via `GoRouter` test helpers.

---

### ADR-TPO-007 — `scripts/promote_user_to_trainer.js` contract

**Status**: ACCEPTED

**Context**: Spec REQ-TPO-SCRIPT-001 through REQ-TPO-SCRIPT-005 pin the CLI contract. The existing `promote_mateo_to_public_trainer.js` is over-engineered for the new flow (it seeds an entire trainer profile, computes a geohash, dual-writes to `trainerPublicProfiles`). The new script is intentionally minimal: it flips `role` and nothing else. Trainer-specific fields are populated exclusively via the app's onboarding flow — that separation enforces that `trainerPublicProfiles/{uid}` is always created via the app's dual-write path (which exercises the ADR-TPO-001 fix end-to-end on first save).

**Decision**: Create `scripts/promote_user_to_trainer.js` as a ~30-LOC Admin SDK utility with the following contract:

1. **Initialization**: `admin.initializeApp()` — relies on `GOOGLE_APPLICATION_CREDENTIALS` env var pointing at `scripts/treino-dev-service-account.json` (existing pattern, same as the Mateo script and the account-deletion scripts).
2. **CLI**: single positional arg `<uid>`. If `process.argv[2]` is falsy → print `USAGE: node scripts/promote_user_to_trainer.js <uid>` to stderr, `process.exit(1)`.
3. **Validation**: `await db.collection('users').doc(uid).get()`. If `!snap.exists` → log `User document users/{uid} not found.` to stderr, `process.exit(1)`. The script MUST NOT create or seed the user doc — that's a signup-flow concern.
4. **Identity log**: read `email` and `displayName` from the snapshot, log `Promoting {email} ({displayName || '(no displayName)'}) → role: trainer` to stdout for human verification.
5. **Update**: `await db.collection('users').doc(uid).update({ role: 'trainer' })`. Admin SDK bypasses the user-side role-immutability rule. NO other fields are written. Update (not set+merge) is intentional — if `users/{uid}` somehow doesn't exist between steps 3 and 5, `update` throws and the catch handler exits 1 (race protection).
6. **Idempotency**: Firestore `update({role: 'trainer'})` on a doc where `role` already equals `'trainer'` is a no-op write that succeeds with code 0. No special branch needed.
7. **Error handling**: top-level `.catch((err) => { console.error('FAILED:', err); process.exit(1); })`.
8. **Success exit**: `console.log('Done.')` + `process.exit(0)`.

Skeleton:
```js
'use strict';
const admin = require('firebase-admin');
admin.initializeApp();
const db = admin.firestore();

async function run() {
  const uid = process.argv[2];
  if (!uid) {
    console.error('USAGE: node scripts/promote_user_to_trainer.js <uid>');
    process.exit(1);
  }
  const snap = await db.collection('users').doc(uid).get();
  if (!snap.exists) {
    console.error(`User document users/${uid} not found.`);
    process.exit(1);
  }
  const { email, displayName } = snap.data();
  console.log(`Promoting ${email} (${displayName || '(no displayName)'}) → role: trainer`);
  await db.collection('users').doc(uid).update({ role: 'trainer' });
  console.log('Done.');
  process.exit(0);
}

run().catch((err) => { console.error('FAILED:', err); process.exit(1); });
```

**Consequences**:
- Pros: ~30 LOC, no geohash logic, no dual-write, no model knowledge. The script is a thin role-flipper — easy to read, easy to audit, easy to maintain.
- Pros: Forcing trainer fields to flow through the app's onboarding exercises ADR-TPO-001 on every new trainer (a real regression-test surface).
- Pros: Idempotent by default — no special handling required for re-runs.
- Cons: No automated test. Acceptable per ADR-TPO-009 (testing strategy) — a 30-LOC Admin SDK script doesn't warrant a Jest harness in `functions/` (the script lives outside `functions/`).
- Follow-up: manual smoke verification documented in `scripts/README.md` (see ADR-TPO-011).

---

### ADR-TPO-008 — Delete `scripts/promote_mateo_to_public_trainer.js`

**Status**: ACCEPTED

**Context**: The legacy Mateo script (143 LOC) seeds a hard-coded trainer profile, including a custom geohash5 implementation, manual dual-writes to `users/{uid}` and `trainerPublicProfiles/{uid}`, and Mateo-specific defaults. The generic `promote_user_to_trainer.js` (ADR-TPO-007) supersedes its useful behavior (flipping `role`) and removes the seeding side effects, which now belong exclusively to the app's onboarding flow.

**Decision**: DELETE the file outright in PR#2 along with the new script. Git history preserves the prior implementation if anyone needs to reference the geohash5 algorithm or the Mateo defaults. No deprecation stub — a deprecation file would be one more thing to clean up later and risks operators running it by muscle memory.

**Consequences**:
- Pros: Cleaner repo state. One promote script with one clear contract.
- Pros: Removes a script that writes legacy singular fields (`trainerGeohash`, `trainerLatitude`, `trainerLongitude`) which the new model treats as `// DEPRECATED`.
- Pros: REQ-TPO-SCRIPT-006 ships with a verifiable "file does not exist" check at PR#2 merge.
- Cons: Operators with shell history pointing at the old script will get "file not found" until they update muscle memory. Mitigated by `scripts/README.md` (ADR-TPO-011) documenting the new entry point prominently.
- Follow-up: PR#2 commit message includes `BREAKING: scripts/promote_mateo_to_public_trainer.js removed — use scripts/promote_user_to_trainer.js <uid>`.

---

### ADR-TPO-009 — Testing strategy: layered coverage with explicit non-targets

**Status**: ACCEPTED

**Context**: Spec defines 39 scenarios (688-726). Coverage needs to span four code surfaces (repo, router, screen, script) and TWO PRs. Strict TDD mode is active for this project — every task pair is RED → GREEN. The script (ADR-TPO-007) is the one surface where automated tests are NOT warranted.

**Decision**:

1. **Repository layer** (`test/features/profile/data/user_repository_trainer_uid_test.dart`):
   - Framework: `fake_cloud_firestore` (already in dev_dependencies for this project).
   - Covers: SCENARIO-688 (first-time create includes `uid`), SCENARIO-689 (re-save idempotent), SCENARIO-690 (athlete-only partial does not touch `trainerPublicProfiles`), SCENARIO-691 (whitelist preserved — `averageRating` absent), SCENARIO-692 (location guard rejects), SCENARIO-693 (online=true accepts).
   - Pattern: build `UserRepository(firestore: FakeFirebaseFirestore())`, call `update()`, assert against `fakeStore.collection('trainerPublicProfiles').doc(uid).get()`.

2. **Domain getter** (`test/features/profile/domain/trainer_profile_complete_test.dart`):
   - Framework: pure Dart unit tests, no Riverpod, no Firestore.
   - Covers: SCENARIO-694 through SCENARIO-700 — all 7 combinations of the boolean formula.
   - Pattern: construct `UserProfile` instances directly, assert `profile.trainerProfileComplete == expected`.

3. **Router `authRedirect`** (`test/app/router_auth_redirect_test.dart` — extend if exists, else create):
   - Framework: `ProviderContainer` from `flutter_riverpod` for the `read` function; no widget tree.
   - Covers ALL 8 spec branches: SCENARIO-701 (trainer incomplete redirects), SCENARIO-702 (trainer complete does not), SCENARIO-703 (loop guard), SCENARIO-704 (athlete bypass), SCENARIO-705 (unauth → welcome — existing, preserved), SCENARIO-706 (`displayName == null` → `/profile-setup`), SCENARIO-707 (account-deletion in-flight preserved), SCENARIO-708 (public routes accessible).
   - Pattern: override providers (`authNotifierProvider`, `userProfileProvider`, `accountDeletionInFlightProvider`) in a `ProviderContainer`, call `authRedirect(container.read, location)`, assert returned redirect string.

4. **Widget tests for `ProfileEditTrainerScreen`**:
   - Onboarding mode (`test/features/profile/presentation/profile_edit_trainer_screen_onboarding_test.dart`): SCENARIO-713 (title), SCENARIO-714 (back button absent + PopScope present), SCENARIO-716 (post-save navigates to `/home`), SCENARIO-718 (location invariant error surfaces, no navigation), SCENARIO-719 (validation rules mode-independent).
   - Edit mode (`test/features/profile/presentation/profile_edit_trainer_screen_edit_test.dart` — create if missing): SCENARIO-709 (default mode), SCENARIO-711 (no query param → edit), SCENARIO-712 (title), SCENARIO-715 (back button present), SCENARIO-717 (post-save pops).
   - Pattern: pump the screen inside a minimal `GoRouter` test harness (cf. `goRouterTestHelpers` patterns used in past widget tests for navigation assertions), override `userRepositoryProvider` with a mock that returns deterministic save outcomes.

5. **Script** (`scripts/promote_user_to_trainer.js`):
   - NO automated test. Acceptance is manual smoke against `treino-dev`: SCENARIO-721 (no arg → exit 1), SCENARIO-722 (missing user → exit 1), SCENARIO-723 (logs email + displayName), SCENARIO-724 (only `role` written), SCENARIO-725 (idempotent re-run), SCENARIO-726 (Mateo script absent from repo).
   - Rationale: the script is 30 LOC of Admin SDK glue with no business logic. A Jest harness in `functions/` would be disproportionate (the script lives OUTSIDE `functions/`). The contract is enforced by `scripts/README.md` checklist + manual smoke per PR#2 merge.

**Consequences**:
- Pros: Every spec scenario has an explicit test target. Coverage matrix in spec maps 1:1 to test files.
- Pros: Layered (model → repo → router → widget) keeps each test fast and focused.
- Pros: Strict TDD enforceable — each task pair has a RED commit (test failing) before GREEN.
- Cons: Script has no automated coverage. Mitigated by manual smoke being trivial (`node scripts/promote_user_to_trainer.js <uid>` against `treino-dev`) and documented.
- Follow-up: tasks phase produces one task pair per scenario group, ensuring the RED commit lands first.

---

### ADR-TPO-010 — Mateo's pre-seeded doc and legacy singular fields

**Status**: ACCEPTED

**Context**: Mateo's existing `users/{uid}` and `trainerPublicProfiles/{uid}` were seeded by the legacy script with singular `trainerGeohash`, `trainerLatitude`, `trainerLongitude` fields. The new model treats these as `// DEPRECATED` and the new write path uses `trainerLocations` + `trainerGeohashes` + `trainerOffersOnline`. The question: does the new save path actively null out the legacy fields, or do they persist as orphans?

Verified by reading `UserRepository.update()`: the dual-write uses `batch.set(..., SetOptions(merge: true))`. With `merge: true`, only fields PRESENT in the subset map are written; fields not in the map are LEFT UNTOUCHED. The new screen does NOT write `trainerGeohash`, `trainerLatitude`, or `trainerLongitude` (these are not on the form), so on first save from the app, Mateo's legacy fields PERSIST as orphan data on both `users/{uid}` and `trainerPublicProfiles/{uid}`.

**Decision**: ACCEPT orphan legacy fields. No active migration in this SDD. Rationale:
1. The legacy fields are marked DEPRECATED in the model but still typed as nullable `double?` / `String?`. They do not break deserialization.
2. Discovery queries already use `trainerGeohashes` (plural) per the multi-location migration; the singular `trainerGeohash` is no longer consumed by any read path.
3. Cleaning them would require either (a) extending the write path to explicitly emit `trainerGeohash: null` etc. (touches the whitelist, violates ADR-TPO-002 conceptually because it changes write semantics for the legacy fields), or (b) a one-off migration script (additional scope).
4. Mateo is a TEST account. Real PFs onboarded via the new flow never have legacy fields in the first place.

If, in a future SDD, the legacy fields need cleanup, the right place is a dedicated migration script (separate from `promote_user_to_trainer.js`) that runs once across `treino-dev` and `treino-prod`.

**Consequences**:
- Pros: Zero scope cost in this SDD. Locked decision #10 from proposal §4 is honored without any code.
- Pros: Discovery continues to work for Mateo because the new save populates `trainerLocations` + `trainerGeohashes`, which is what the query reads.
- Cons: Mateo's `trainerPublicProfiles/{uid}` doc carries orphan legacy fields indefinitely. Acceptable for a test account.
- Follow-up: file a follow-up note in the next-steps section for a future "trainer-legacy-field-cleanup" SDD if production data ever accumulates similar orphans.

---

### ADR-TPO-011 — Create `scripts/README.md` for operator documentation

**Status**: ACCEPTED — resolves spec Q3

**Context**: Spec REQ-TPO-SCRIPT-006 requires usage docs for `promote_user_to_trainer.js`. Verified: `scripts/README.md` does NOT currently exist (no file at that path). Options were (a) inline docstring at top of the script, (b) new `scripts/README.md`, (c) section in `docs/setup-notes.md`. Inline docstring is mode-locked into the file body (operators need to open the file to read it); `docs/setup-notes.md` is the wrong audience (it carries SDD tooling notes, not operator runbooks); a dedicated `scripts/README.md` is the canonical location for operator workflows on this kind of monorepo.

**Decision**: CREATE `scripts/README.md` in PR#2. Contents (initial — future scripts append sections to the same file):

```markdown
# scripts/

Admin SDK utilities operated by the team against `treino-dev` and (rarely) `treino-prod`.

## Prerequisites

- Service-account JSON at `scripts/treino-dev-service-account.json` (gitignored).
- `GOOGLE_APPLICATION_CREDENTIALS` env var pointing at that file.
- `npm install firebase-admin` (one-time, repo root).

## promote_user_to_trainer.js

Flips `users/{uid}.role` to `'trainer'`. Trainer fields are NOT seeded — the user
must complete the in-app onboarding flow to populate them (`trainerBio`,
`trainerSpecialty`, `trainerMonthlyRate`, `trainerLocations` / `trainerOffersOnline`).

### Usage

```
node scripts/promote_user_to_trainer.js <uid>
```

### Behavior

1. Validates that `users/{uid}` exists. Exits 1 with an error if not.
2. Logs the user's `email` and `displayName` for human verification.
3. Calls `users/{uid}.update({ role: 'trainer' })`.
4. Exits 0 on success. Idempotent — re-running on an already-promoted user is a no-op.

### Post-promotion flow

The user reopens the app → `authRedirect` detects `role == trainer && !trainerProfileComplete`
and routes them to `/profile/edit-trainer?mode=onboarding`. Back navigation is blocked
until the form is submitted. On save, they land on `/home` as a discoverable trainer.
```

The Markdown chosen is deliberately operator-focused: prerequisites, usage, behavior, what-happens-next. Future scripts add sections under their own `##` heading.

**Consequences**:
- Pros: One canonical location for operator runbooks. Discoverable via `ls scripts/` (or `eza scripts/`).
- Pros: Operators don't need to open the script body to understand usage — README is the entry point.
- Pros: Future scripts (e.g., a hypothetical legacy-field-cleanup migration) extend the same file.
- Cons: Mild duplication between README and the script's own header comment. Mitigated by keeping the script's header comment to a 1-line summary that points at `scripts/README.md` for full details.
- Follow-up: PR#2 includes both the README and the script in the same commit so they ship atomically.

---

## 4. File-by-File Structure

### PR#1 — Data layer fix + onboarding gate

**Production code:**

| File | Action | Lines (est.) | ADR |
|---|---|---|---|
| `lib/features/profile/data/user_repository.dart` | EDIT — change `_trainerPublicSubsetFromPartial` signature to `(Map partial, {required String uid})`, set `result['uid'] = uid` when any trainer field present; update `update()` to pass `uid` through; update lines 30-39 comment to reflect ADR-TPO-001 applied | ~15 | ADR-TPO-001, ADR-TPO-002 |
| `lib/features/profile/domain/user_profile_trainer_completeness.dart` | NEW — extension getter `bool get trainerProfileComplete` on `UserProfile` | ~12 | ADR-TPO-004 |
| `lib/features/profile/application/user_providers.dart` | EDIT — add `trainerProfileCompleteProvider` (3-line `Provider<bool>`), add import for the new extension | ~6 | ADR-TPO-004 |
| `lib/app/router.dart` | EDIT — add `import '../features/profile/domain/user_role.dart'` if not already present; inside `authRedirect`, after the `displayName == null` branch and before the public-route → `/home` branch, add the trainer-incomplete check with loop guard | ~10 | ADR-TPO-003 |

**Tests:**

| File | Action | Lines (est.) | Scenarios covered |
|---|---|---|---|
| `test/features/profile/data/user_repository_trainer_uid_test.dart` | NEW | ~80 | 688, 689, 690, 691, 692, 693 |
| `test/features/profile/domain/trainer_profile_complete_test.dart` | NEW | ~70 | 694, 695, 696, 697, 698, 699, 700 |
| `test/app/router_auth_redirect_test.dart` | NEW (extend if exists) | ~120 | 701, 702, 703, 704, 705, 706, 707, 708 |

PR#1 total estimate: ~313 LOC including tests, well under the 400-LOC budget.

---

### PR#2 — Onboarding mode UI + promote script

**Production code:**

| File | Action | Lines (est.) | ADR |
|---|---|---|---|
| `lib/features/profile/presentation/profile_edit_trainer_screen.dart` | EDIT — add `enum ProfileEditTrainerMode { edit, onboarding }` at top of file; add `mode` ctor arg (default `edit`); branch AppBar title on mode (es-AR with i18n markers); add `automaticallyImplyLeading: false` in onboarding mode; wrap body in `PopScope(canPop: false)` in onboarding mode; branch post-save callback on mode (`context.go('/home')` vs `context.pop()`) | ~30 | ADR-TPO-005, ADR-TPO-006 |
| `lib/app/router.dart` | EDIT — update `GoRoute(path: 'edit-trainer', ...)` builder to read `state.uri.queryParameters['mode']` and pass enum to screen ctor | ~8 | ADR-TPO-005 |
| `scripts/promote_user_to_trainer.js` | NEW | ~35 | ADR-TPO-007 |
| `scripts/promote_mateo_to_public_trainer.js` | DELETE | -143 (deletion) | ADR-TPO-008 |
| `scripts/README.md` | NEW | ~45 | ADR-TPO-011 |

**Tests:**

| File | Action | Lines (est.) | Scenarios covered |
|---|---|---|---|
| `test/features/profile/presentation/profile_edit_trainer_screen_onboarding_test.dart` | NEW | ~120 | 710 (router-level via test helper), 713, 714, 716, 718, 719 |
| `test/features/profile/presentation/profile_edit_trainer_screen_edit_test.dart` | NEW (or EXTEND if exists) | ~80 | 709, 711, 712, 715, 717 |

PR#2 net code estimate: ~118 LOC additions + ~200 LOC of tests + 143-LOC deletion (net add ~175 LOC), comfortably sub-budget.

Manual verification scenarios (no automated test): 721, 722, 723, 724, 725, 726 — covered by `scripts/README.md` smoke checklist (ADR-TPO-009).

---

## 5. PR Boundary Rationale

**PR#1 = data + gate (mergeable in isolation)**: The `uid` fix has independent value as a regression fix — it would be merge-worthy even without the onboarding flow because it unblocks any first-time trainer save (including the manual one done today via the Mateo script if someone tried to re-edit through the app). The `trainerProfileComplete` helper and `authRedirect` gate are pure additions; they don't change ANY athlete behavior and the gate is inert until a user has `role == trainer`. PR#1 can ship on `main`, gather review, and be verified end-to-end with a synthetic incomplete trainer profile manually constructed in `treino-dev`.

**PR#2 = UI + ops (rebases on `main`)**: PR#2 depends on PR#1's `trainerProfileComplete` helper indirectly (the new save path in onboarding mode exercises the dual-write fix from PR#1), but the dependency is data-shape only — PR#2 doesn't import PR#1 types beyond what already exists. PR#2 is the user-facing payoff: the onboarding screen, the route mapping, the operator script, and the documentation. PR#2 lands on `main` rebased after PR#1 merges.

Both PRs target `main` directly (not stacked on each other's branch). This keeps review parallelizable if needed and avoids merge conflicts on long-lived branches.

---

## 6. Risks Resolution Matrix

| Risk (from proposal §7) | Severity | ADR(s) that mitigate | How |
|---|---|---|---|
| #1 — `uid` missing → first-time save permission-denied | CRITICAL | ADR-TPO-001 + ADR-TPO-009 | Threading fix + regression test in PR#1. |
| #2 — `authRedirect` regression on new branch | HIGH | ADR-TPO-003 + ADR-TPO-009 | Strict insertion point (after `displayName == null`, before public-route → `/home`) + loop guard + all 8 branches tested. |
| #3 — No test coverage on `UserRepository` dual-write today | MEDIUM | ADR-TPO-009 | New `user_repository_trainer_uid_test.dart` closes the gap alongside the fix. |
| #4 — Mateo's pre-seeded doc has legacy singular fields | LOW | ADR-TPO-010 | Accepted — orphan fields persist but are not consumed by discovery. Mateo is a test account. |
| #5 — `_CustomLocationSheet` requires GPS, trainer who denies cannot add custom locations | LOW | (no ADR — pre-existing) | Catalog gyms + `trainerOffersOnline` toggle remain valid completion paths. Onboarding still completes. |
| #6 — Team forgets to run promote script for a new PF | OPERATIONAL | ADR-TPO-011 | `scripts/README.md` documents the workflow as the canonical operator runbook. |
| #7 — `PopScope` blocks iOS swipe-back, could feel jarring | LOW | ADR-TPO-006 | Accepted per locked decision #8. User can quit the app; reopening returns to the gate. |
| #8 — Spec/design picks wrong shape for `trainerProfileComplete` | LOW | ADR-TPO-004 | Hybrid (getter + thin provider) — rewrite cost if wrong is <10 LOC. |

---

## 7. Open Questions for Tasks Phase

**None** — all spec-passed-forward questions are LOCKED:
- Q1 (shape of `trainerProfileComplete`) → ADR-TPO-004 (hybrid).
- Q2 (enum file location) → ADR-TPO-005 (inline).
- Q3 (`scripts/README.md` location) → ADR-TPO-011 (create the file).

Residual micro-tasks for the tasks phase to sequence (not decisions, just ordering):
1. The four ADR-driven test files MUST land BEFORE their corresponding production changes (strict TDD, REQ-TPO-CX-001).
2. PR#1 task ordering: model getter test → model getter → repo test → repo fix → provider → router test → router branch.
3. PR#2 task ordering: enum + screen ctor (no behavior change) → AppBar title test → AppBar title impl → back-block test → back-block impl → post-save test → post-save impl → router mapping test → router mapping impl → script (no test, manual smoke) → script docs → delete legacy script.

---

## 8. Hard Constraints (verbatim from proposal)

- `averageRating` and `reviewCount` MUST NOT be added to `_trainerPublicFields` whitelist (ADR-RV-005, reinforced by ADR-TPO-002).
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

## 9. Artifact References

- Design file: `openspec/changes/trainer-profile-onboarding/design.md`
- Engram: `sdd/trainer-profile-onboarding/design`
- Spec file: `openspec/changes/trainer-profile-onboarding/spec.md`
- Engram spec: `sdd/trainer-profile-onboarding/spec` (#151)
- Proposal file: `openspec/changes/trainer-profile-onboarding/proposal.md`
- Engram proposal: `sdd/trainer-profile-onboarding/proposal` (#150)
- Exploration file: `openspec/changes/trainer-profile-onboarding/explore.md`
- Engram exploration: `sdd/trainer-profile-onboarding/explore` (#149)
