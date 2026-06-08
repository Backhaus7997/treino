# Proposal: trainer-profile-onboarding

**Change**: trainer-profile-onboarding
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-08
**Phase**: Fase 6 Etapa 1
**Artifact store**: hybrid (file + Engram `sdd/trainer-profile-onboarding/proposal`)
**Exploration**: `openspec/changes/trainer-profile-onboarding/explore.md` + Engram `sdd/trainer-profile-onboarding/explore` (#149)

---

## 1. TL;DR

Ship the path that turns a freshly-promoted `role: trainer` user into a complete public profile end-to-end from the app, removing the manual Admin SDK seed scripts as a blocker for inviting real personal trainers to TestFlight. Scope is intentionally minimal: fix a latent `uid` bug in `UserRepository._trainerPublicSubsetFromPartial` that would otherwise permission-deny the first save, add a derived `trainerProfileComplete` check, gate `authRedirect` on that check, reuse the already-built `ProfileEditTrainerScreen` under a new `?mode=onboarding` query param, and replace the Mateo-specific seed script with a generic `scripts/promote_user_to_trainer.js`. Two stacked-to-main PRs, ~250 LOC total, no new collections, no CF changes, no `pubspec.yaml` additions, no Firestore-rules changes. Blast radius: additive for trainers; zero behaviour change for athletes.

---

## 2. Motivation

Current state: the only path to create a personal-trainer (PF) public profile is running `scripts/promote_mateo_to_public_trainer.js`, a hard-coded Admin SDK seed for one specific account. Every new PF requires a manual Admin SDK invocation by the team. This is a hard blocker for the TestFlight beta and for inviting real PFs at scale — exactly the audience Fase 6 Etapa 1 needs to validate the Coach module.

Critical latent bug discovered during exploration: `UserRepository._trainerPublicSubsetFromPartial` never threads `uid` into the subset written to `trainerPublicProfiles/{uid}`. The `firestore.rules` create rule requires `request.resource.data.uid == uid`. The seed scripts work because they include `uid` manually. **The first time any trainer saves their profile from the app, the dual-write batch WILL fail permission-denied.** This is a code-level blocker; the onboarding flow cannot ship without fixing it. The fix is intentionally bundled with this SDD because the onboarding gate is the surface that will exercise it for the first time.

The infrastructure is in place: `ProfileEditTrainerScreen` is ~90% complete (bio, specialty dropdown, monthly rate, gym catalog picker, custom location with GPS, online toggle, client-side validation, repo-level invariants). The `/profile/edit-trainer` route is wired. `authRedirect` has a clear extension point right after the existing `displayName == null` gate. The delta is small and surgical.

---

## 3. Scope

### In Scope (v1)

- **`uid` bug fix** in `UserRepository._trainerPublicSubsetFromPartial` — thread `uid` from `update()` into the helper and include it in the subset when any trainer field is present.
- **Derived `trainerProfileComplete` helper** — either as an extension on `UserProfile` or as a derived Riverpod provider (`trainerProfileCompleteProvider`), computed from `trainerBio != null && trainerSpecialty != null && trainerMonthlyRate != null && (trainerLocations.isNotEmpty || trainerOffersOnline == true)`. NO new model field, NO Freezed regen, NO migration.
- **`authRedirect` trainer-incomplete gate** — extend `lib/app/router.dart` so that `role == trainer && !trainerProfileComplete` redirects to `/profile/edit-trainer?mode=onboarding`. Insertion point is AFTER the `displayName == null` check and BEFORE the public-route → `/home` redirect; ordering must not regress athlete signup, account-deletion in-flight handling, or public-route behaviour.
- **`?mode=onboarding` query param** on `ProfileEditTrainerScreen`. Edit mode keeps existing behaviour (back button enabled, save → `context.pop()`, current header copy). Onboarding mode: header reads "Completá tu perfil profesional" (es-AR, `// i18n: Fase 6 Etapa 1`), back navigation disabled, save → `context.go('/home')`.
- **`scripts/promote_user_to_trainer.js`** — generic CLI (`node scripts/promote_user_to_trainer.js <uid>`) that flips `role: 'trainer'` on `users/{uid}` via Admin SDK, replacing the Mateo-specific script. Validates the doc exists, logs the affected email + displayName, exits 0/1 appropriately.
- **Test coverage** for all four items: regression test for the `uid` fix, derived-helper combinations, `authRedirect` branches (including the new trainer-incomplete branch), and `ProfileEditTrainerScreen` onboarding-vs-edit mode behaviour.
- **Deprecate or delete** `scripts/promote_mateo_to_public_trainer.js` (the generic script subsumes it).

### Out of Scope (deferred, v1 does NOT ship)

- **Self-select role UI** (athlete vs trainer chooser in ProfileSetup). Admin-SDK-only flip is intentional for v1 — unblocks TestFlight with ~5x less scope. Future SDD can add self-select if user volume warrants it.
- **`avatarUrl` in onboarding wizard** — avatar stays editable in "Datos personales" only.
- **Reverse geocoding** for custom locations — raw lat/lng acceptable for MVP; would require new dep + paid API.
- **Bulk migration** of legacy seeded trainer docs (Mateo etc. with singular `trainerGeohash/Latitude/Longitude`). The dual-write helper clean-writes on first save from the app, so legacy singular fields get nulled out naturally.
- **ProfileSetup trainer branch** — ProfileSetup remains athlete-only because v1 is admin-SDK-only.
- **Magic-link / invite-code trainer registration.**
- **Partial save / draft persistence** — draft is local-only; reopening sends user back to the gate, no progress lost beyond what they typed in the session.
- **New Firestore collections, CF changes, rules changes, storage rules changes, or `pubspec.yaml` additions.**

---

## 4. Locked Decisions

The exploration phase surfaced 10 open questions. All are LOCKED below with rationale (user signed off 2026-06-08).

| # | Decision | Locked Choice | Rationale |
|---|----------|---------------|-----------|
| 1 | Role assignment mechanism | **Admin-SDK-only (Option B)**. Team runs `scripts/promote_user_to_trainer.js <uid>`; app does NOT add self-select UI. | Unblocks TestFlight with ~5x less scope than a self-select branch in ProfileSetup. Self-select can be a future SDD once the audience grows beyond a curated invite list. |
| 2 | Onboarding gate flag | **Derived check** from existing fields: `trainerBio != null && trainerSpecialty != null && trainerMonthlyRate != null && (trainerLocations.isNotEmpty || trainerOffersOnline == true)`. | Same logic already lives in `ProfileTrainerSection`. NO new boolean field, NO Freezed regen, NO migration. Single source of truth derived from data we already trust. |
| 3 | `avatarUrl` in onboarding wizard | **Out** — avatar stays in "Datos personales" edit. | Trainer doesn't need a separate avatar surface for onboarding; the existing personal-edit screen already handles upload + storage rules. Keeps the wizard focused on PF-specific fields. |
| 4 | Route shape | **`?mode=onboarding` query param** on existing `/profile/edit-trainer` route. NOT a dedicated `/trainer-onboarding` route. | Simpler — one route registration, one screen widget, one set of tests. Mode behaviour is a small enum-driven branch inside the screen. |
| 5 | ProfileSetup trainer branch | **N/A** — not needed since v1 is admin-SDK-only. ProfileSetup stays athlete-only. | Direct consequence of decision #1. Removes the role-immutability complication around `getOrCreate`. |
| 6 | Custom location reverse geocode | **Out** — raw lat/lng acceptable for MVP. | Reverse geocoding requires a new dep (`geocoding` package) or a paid API (Google Places). Trainer already types a manual label per location; coordinates are functional even if not human-pretty. |
| 7 | PR delivery strategy | **2 chained-to-main PRs.** PR#1 data layer fix + onboarding gate (~150 LOC). PR#2 onboarding mode UI + promote script (~100 LOC). Total ~250 LOC. | Each PR well under the 400-line budget. PR#1 stands alone (the `uid` fix has independent value as a regression fix). PR#2 is the user-facing payoff. |
| 8 | Onboarding back navigation | **Disabled in onboarding mode** — user must complete or close the app. Reopening sends them back to the gate. NO partial save. | Local-only draft means no progress is lost on Firestore. The gate is idempotent — repeated re-entries are fine. Avoids the half-state where a user backs out of onboarding and then can't get back in. |
| 9 | Post-save navigation in onboarding mode | **`context.go('/home')`** (replaces the stack, avoids loop). Edit mode keeps existing `context.pop()`. | `pop()` from a gate-redirected screen has no underlying route to pop to. `go('/home')` is the canonical "I'm done, go to the app" semantic — same pattern ProfileSetup already uses on submit. |
| 10 | Existing seeded trainers (Mateo etc.) with legacy singular fields | **One-time data migration happens implicitly on first save from app** — dual-write helper clean-writes, so legacy `trainerGeohash`, `trainerLatitude`, `trainerLongitude` get nulled out. NO bulk migration. | New `TrainerLocation[]` model replaces the singular fields; the form writes the full new shape on save. Seeded accounts heal themselves the first time the trainer edits anything. |

---

## 5. Approach Summary

**Approach A confirmed from explore.md** — single form + mode param. `ProfileEditTrainerScreen` is the canonical surface for both onboarding and edit; mode behaviour is a thin branch inside the screen.

Architecture sketch:

1. **`UserRepository.update()`** receives `uid` (it already does, via the auth-scoped repository). The fix threads `uid` into the helper signature so `_trainerPublicSubsetFromPartial(uid: uid, partial: partial)` includes `result['uid'] = uid` whenever any trainer-specific field is being written. `SetOptions(merge: true)` keeps the call idempotent — re-writing `uid` on existing docs is a no-op.
2. **Derived `trainerProfileComplete`** lives as either a getter on `UserProfile` or a `Provider<bool>` derived from `userProfileProvider`. Pattern matches the existing `missing`-fields computation in `ProfileTrainerSection`.
3. **`authRedirect`** gains a new branch after the `displayName == null` check: if the user has a profile, is signed in, role is `trainer`, and `trainerProfileComplete == false`, and the current location is NOT already `/profile/edit-trainer?mode=onboarding`, redirect there. Existing branches (account-deletion in-flight, public-route → home) are unchanged.
4. **`ProfileEditTrainerScreen`** takes an optional `mode` constructor arg (default `edit`). The router maps the `?mode=onboarding` query param to `ProfileEditTrainerMode.onboarding`. Mode drives three things: AppBar title (`"Completá tu perfil profesional"` vs `"Editá tu perfil profesional"`), back navigation (disabled vs enabled — `automaticallyImplyLeading: false` + `WillPopScope`/`PopScope` block), and post-save destination (`go('/home')` vs `pop()`).
5. **`scripts/promote_user_to_trainer.js`** initializes the Admin SDK from existing `firebase-adminsdk-fbsvc` credentials, validates the target `users/{uid}` doc exists, reads email + displayName for the log line, calls `.update({role: 'trainer'})` (bypasses the user-side immutability rule because Admin SDK runs as service account), exits 0 on success / 1 on error.

Rejected alternatives stay rejected: Approach B (multi-step bottom sheets + separate edit) doubles the surface area and guarantees drift; Approach C (inline tile editing on profile screen) loses completion guidance and provides no forcing function for the gate.

---

## 6. Deliverable Surface

Grouped by PR. Total estimate ~250 LOC across two stacked-to-main PRs.

### PR#1 — Data layer fix + onboarding gate (~150 LOC)

**Code:**
- Edit `lib/features/profile/data/user_repository.dart` — fix `_trainerPublicSubsetFromPartial` to thread `uid` through `update()` and include `result['uid'] = uid` when any trainer-specific field is present in the partial. Update `update()` to pass `uid` to the helper. Keep the existing comment at lines 30-39 honest (or update it to reflect the now-applied "Approach E" fix).
- Add `trainerProfileComplete` derived helper. Two acceptable shapes (spec phase resolves which): (a) `bool get trainerProfileComplete` extension/getter on `UserProfile`, or (b) `final trainerProfileCompleteProvider = Provider<bool>((ref) { ... })` in `user_providers.dart`. Decision criterion: pick whichever the `authRedirect` consumer (which reads via `ref.read(userProfileProvider)`) integrates with most cleanly.
- Edit `lib/app/router.dart` — extend `authRedirect` with the trainer-incomplete gate AFTER the existing `displayName == null` check, BEFORE the public-route → `/home` redirect. Loop-guard: do NOT redirect if `state.matchedLocation` already starts with `/profile/edit-trainer`.

**Tests:**
- `test/features/profile/data/user_repository_trainer_uid_test.dart` — first-time trainer save creates `trainerPublicProfiles/{uid}` with `uid` in the body (regression for the bug). Verify via `fake_cloud_firestore` that the write succeeds and `uid` field is set.
- `test/features/profile/domain/trainer_profile_complete_test.dart` (or `..._provider_test.dart` depending on shape chosen) — all combinations of the derived helper: only-bio, only-specialty, only-rate, only-locations, only-online, full, mixed, all-null.
- `test/app/router_auth_redirect_test.dart` (extend if exists, else create) — ALL `authRedirect` branches including: unauthenticated → login, authenticated + no displayName → profile-setup, authenticated + displayName + trainer + incomplete → onboarding, authenticated + displayName + trainer + complete → no redirect, authenticated + displayName + athlete → no redirect, account-deletion-in-flight → existing behaviour preserved.

### PR#2 — Onboarding mode UI + promote script (~100 LOC)

**Code:**
- Edit `lib/features/profile/presentation/profile_edit_trainer_screen.dart` — add `enum ProfileEditTrainerMode { edit, onboarding }` (location: top of file or co-located in a small `profile_edit_trainer_mode.dart` — spec to decide). Constructor accepts `ProfileEditTrainerMode mode = ProfileEditTrainerMode.edit`. AppBar title branches on mode (es-AR copy with `// i18n: Fase 6 Etapa 1` marker). Back navigation disabled in onboarding mode (`automaticallyImplyLeading: false` + `PopScope(canPop: false)`). Save callback branches: onboarding → `context.go('/home')`, edit → `context.pop()`.
- Edit `lib/app/router.dart` — route mapping for `/profile/edit-trainer` reads the `mode` query param: `state.uri.queryParameters['mode'] == 'onboarding' ? ProfileEditTrainerMode.onboarding : ProfileEditTrainerMode.edit`.
- New `scripts/promote_user_to_trainer.js` (~30 LOC):
  - CLI args: `<uid>` (positional, required). Error with usage message if missing.
  - Initializes Admin SDK from existing `firebase-adminsdk-fbsvc-*.json` credentials (same pattern as `promote_mateo_to_public_trainer.js` and the `account-deletion` scripts).
  - Reads `users/{uid}` doc; if it doesn't exist, logs an error and exits 1.
  - Logs current `email` and `displayName` for human verification.
  - Calls `firestore.collection('users').doc(uid).update({ role: 'trainer' })` (Admin SDK bypasses the user-side role-immutability rule).
  - Logs success line including `email` and `displayName`.
  - Exits 0 on success, 1 on any error.
- Deprecate or delete `scripts/promote_mateo_to_public_trainer.js` — spec phase to decide whether to delete outright or leave with a deprecation comment pointing at the generic script. Recommend delete (one less stale script).

**Tests:**
- `test/features/profile/presentation/profile_edit_trainer_screen_onboarding_test.dart` — widget test: pump screen in onboarding mode, verify AppBar title is "Completá tu perfil profesional", verify back button is absent / system-back is blocked, simulate successful save and verify `GoRouter` location becomes `/home`.
- `test/features/profile/presentation/profile_edit_trainer_screen_edit_test.dart` (create if missing; extend if already exists) — widget test: pump screen in edit mode, verify AppBar title is "Editá tu perfil profesional", verify back works, simulate successful save and verify `pop()` is called.

### Out-of-code

- PR#2 description updates `scripts/README.md` (or `docs/setup-notes.md` if that's where script docs live — explore didn't pin this; spec resolves) with the promote-user usage line.

---

## 7. Risks & Mitigations

Carried from exploration + design-phase refinements.

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| 1 | `uid` missing in `_trainerPublicSubsetFromPartial` → first-time save permission-denied | **CRITICAL** | Fix in PR#1 + regression test (`user_repository_trainer_uid_test.dart`) that asserts the body contains `uid` and the create succeeds against `fake_cloud_firestore`. |
| 2 | `authRedirect` regression — new branch could loop, break athlete signup, or break account-deletion in-flight | **HIGH** | Unit-test ALL branches before merge. Order new branch carefully: after `displayName == null`, before public-route → `/home`. Loop-guard: skip redirect when already at `/profile/edit-trainer`. |
| 3 | No test coverage on `UserRepository` dual-write today | MEDIUM | Same PR (PR#1) as the `uid` fix adds the missing repo tests, closing the gap simultaneously. |
| 4 | Mateo's pre-seeded doc has legacy singular fields (`trainerGeohash/Latitude/Longitude`) | LOW | First save from the app clean-writes via the dual-write helper; legacy fields get nulled. Verified manually on first dev-account save. |
| 5 | `_CustomLocationSheet` requires GPS permission; trainer who denies cannot add custom locations | LOW | Catalog gyms + `trainerOffersOnline` toggle remain fallback paths. Onboarding completes successfully via either path. |
| 6 | Team forgets to run promote script for a new PF and the PF lands as athlete | OPERATIONAL | Document the promote workflow in `scripts/README.md` (or equivalent). Eventual self-select SDD is the long-term fix once pain grows. |
| 7 | Onboarding mode `PopScope` blocks system back gesture on iOS — could feel jarring | LOW | Acceptable per locked decision #8. Alternative is partial-save (deferred). User can quit the app; reopening returns to the gate. |
| 8 | Spec/design picks the wrong shape for `trainerProfileComplete` (extension vs provider) | LOW | Decision is local to two files. Spec phase to lock; rewrite cost if wrong is <10 LOC. |

---

## 8. Out-of-band Prerequisites (NON-CODE blockers)

1. Team must have access to `treino-dev` Firebase credentials with Admin SDK auth — already true since the `account-deletion` SDD shipped.
2. Team must have a documented process for running `node scripts/promote_user_to_trainer.js <uid>` — covered by the `scripts/README.md` (or `docs/setup-notes.md`) addition in PR#2.

No APNs, no third-party API keys, no Firebase Console configuration. The Admin SDK script reuses the existing service-account JSON.

---

## 9. Success Criteria

- [ ] A fresh user signs up and completes ProfileSetup as an athlete normally — zero change to the athlete flow.
- [ ] Team runs `node scripts/promote_user_to_trainer.js <uid>`; the script logs the affected email + displayName, updates `users/{uid}.role` to `trainer`, and exits 0.
- [ ] That user reopens the app, is redirected by `authRedirect` to `/profile/edit-trainer?mode=onboarding`, the AppBar reads "Completá tu perfil profesional", system back is blocked.
- [ ] User completes the form (bio + specialty + monthly rate + at least one of gym/custom location/online toggle) and saves.
- [ ] After save: `users/{uid}` contains all trainer fields; `trainerPublicProfiles/{uid}` is created with at minimum `uid + displayName + trainerBio + trainerSpecialty + trainerMonthlyRate + trainerLocations + trainerOffersOnline`. NO permission-denied error.
- [ ] User is navigated to `/home` via `context.go('/home')` — no stack loop.
- [ ] User is discoverable in `TrainersListScreen` after the save.
- [ ] User re-entering the edit screen via the profile tab (edit mode) sees the existing header "Editá tu perfil profesional", back works normally, save pops.
- [ ] `flutter analyze` reports 0 issues. `dart format .` is clean. `flutter test` is green including the new tests.
- [ ] No regression on: athlete signup, athlete ProfileSetup, account-deletion in-flight detection, existing trainer profile edit, public-route → `/home` redirect.
- [ ] All new copy in es-AR with `// i18n: Fase 6 Etapa 1` markers.
- [ ] Strict TDD: every task pair has a RED commit before the GREEN commit.
- [ ] Conventional commits, NO `Co-Authored-By`, NO AI attribution.
- [ ] PR diffs ≤ 400 LOC each.

---

## 10. Open Questions Carrying to Spec

All 10 exploration questions are LOCKED in §4. Residual micro-decisions for spec:

1. **Shape of `trainerProfileComplete`** — extension getter on `UserProfile` vs derived `Provider<bool>` in `user_providers.dart`. Pick whichever the `authRedirect` consumer integrates with most cleanly. Likely the provider given `authRedirect` already does `ref.read` patterns.
2. **Exact enum name & location** for `ProfileEditTrainerMode` — keep inside `profile_edit_trainer_screen.dart` vs extract to its own file. Recommend co-located unless other consumers appear.
3. **Exact es-AR copy** for the onboarding-mode AppBar title (proposal locks `"Completá tu perfil profesional"`; spec may refine punctuation/voice but the shape is locked). Edit-mode title stays `"Editá tu perfil profesional"` (existing).
4. **Disposition of `scripts/promote_mateo_to_public_trainer.js`** — delete vs deprecate-with-comment. Recommend delete.
5. **Where the promote-user usage docs live** — `scripts/README.md` vs `docs/setup-notes.md` vs `AGENTS.md`. Spec resolves; recommend `scripts/README.md` if it exists, otherwise add a short section to `docs/setup-notes.md`.

---

## 11. PR Plan

**2 stacked-to-main PRs.** Each independently mergeable; PR#2 is rebased on `main` after PR#1 lands (NOT stacked on PR#1's branch — both target `main` directly to keep review parallelizable if needed).

| PR | Branch | Base | Scope | LOC est. | Verification |
|----|--------|------|-------|----------|--------------|
| **PR#1 — Data layer fix + onboarding gate** | `feat/trainer-profile-onboarding-pr1-data-gate` | `main` | `uid` fix in `UserRepository._trainerPublicSubsetFromPartial`, derived `trainerProfileComplete` helper, `authRedirect` trainer-incomplete gate, full test coverage (repo + helper + all router branches). | ~150 | `flutter analyze` 0 issues. `dart format .` clean. `flutter test` green (+~10 new tests). Manual: create a synthetic incomplete-trainer profile in dev, confirm app boots into onboarding redirect. |
| **PR#2 — Onboarding mode UI + promote script** | `feat/trainer-profile-onboarding-pr2-onboarding-mode` | `main` (rebased after PR#1 merges) | `mode` enum + behaviour branching on `ProfileEditTrainerScreen`, router query-param mapping, `scripts/promote_user_to_trainer.js`, deprecation/deletion of `promote_mateo_to_public_trainer.js`, docs update, widget tests for both modes. | ~100 | `flutter analyze` 0 issues. `dart format .` clean. `flutter test` green (+~4 new tests). Manual smoke: run promote script against a real test account in `treino-dev`, complete onboarding end-to-end, verify discovery in `TrainersListScreen`. |

**Risk mitigation rationale:** PR#1 isolates the critical bug fix and the routing change — both are reviewable in isolation against the existing edit screen. The bug fix has independent value (it's a regression bait). PR#2 is the user-facing payoff and is purely additive on a verified data layer. If PR#2 surfaces issues during smoke, PR#1 stays merged because it's a strict improvement over the current state.

**Review Workload Forecast (carry to `sdd-tasks`):**
- Estimated changed lines: ~250 across both PRs.
- 400-line budget risk: **Low** (both PRs comfortably sub-budget).
- Chained PRs recommended: **Yes** (stacked-to-main pattern).
- Decision needed before apply: **No** — falls under standard `ask-on-risk` thresholds without triggering any.

---

## 12. Artifact References

- File: `openspec/changes/trainer-profile-onboarding/proposal.md`
- Engram: `sdd/trainer-profile-onboarding/proposal`
- Predecessor (exploration): `openspec/changes/trainer-profile-onboarding/explore.md` + Engram `sdd/trainer-profile-onboarding/explore` (#149)

**Status**: Ready for `sdd-spec` and `sdd-design` (can run in parallel).
