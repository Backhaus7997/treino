# Exploration: trainer-profile-onboarding

**Change**: trainer-profile-onboarding
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-08
**Phase**: Fase 6 Etapa 1
**Artifact store**: hybrid (openspec + engram `sdd/trainer-profile-onboarding/explore` #149)

---

## Scope Summary

Ship trainer-profile onboarding flow that turns a fresh `role: trainer` user into a complete public profile (`trainerPublicProfiles/{uid}` doc) **without manual Admin SDK scripts**. Currently the only path to create a PF is running `scripts/promote_mateo_to_public_trainer.js` — bloqueante para invitar PFs reales a TestFlight.

**Ships**:
- `authRedirect` gate that catches `role == trainer && !trainerProfileComplete` and redirects to onboarding
- Onboarding flow that reuses `ProfileEditTrainerScreen` (already 90% complete) with onboarding-mode behavior (no back nav, save → home)
- Critical fix to `_trainerPublicSubsetFromPartial` in `UserRepository` — currently doesn't include `uid`, breaks first-time creates per Firestore rules
- Test coverage for repo dual-write + authRedirect gate + form
- Deprecation of `scripts/promote_mateo_to_public_trainer.js`

**Out of scope**:
- No new Firestore collections (reuse `users/{uid}` + `trainerPublicProfiles/{uid}`)
- No CF changes
- No `pubspec.yaml` additions (`geolocator` already present, no Google Places needed)
- `averageRating` / `reviewCount` stay CF-write-only (ADR-RV-005)
- `storage.rules` unchanged
- Reviews, billing, plan catalog (separate etapas)

---

## Current State — File Inventory

### Models / Domain (all complete, no gaps)

| File | Status | Notes |
|---|---|---|
| `lib/features/coach/domain/trainer_public_profile.dart` | COMPLETE | All trainer fields + `averageRating`/`reviewCount` from trainer-reviews |
| `lib/features/coach/domain/trainer_specialty.dart` | COMPLETE | 10-value enum, ready as dropdown source |
| `lib/features/coach/domain/trainer_location.dart` | COMPLETE | `TrainerLocation` Freezed: type (gym/custom), gymId, customLabel, lat/lng/geohash |
| `lib/features/profile/domain/user_profile.dart` | COMPLETE | All trainer fields; `trainerSpecialty` stored as `String?` |

### Data Layer

| File | Status | Notes |
|---|---|---|
| `lib/features/profile/data/user_repository.dart` | **NEARLY COMPLETE — 1 BUG** | Dual-write via WriteBatch. `_trainerPublicFields` whitelist correct. `_assertTrainerLocationStateIsValid` guards. **BUG**: `_trainerPublicSubsetFromPartial` never includes `uid`. Firestore create rule requires `request.resource.data.uid == uid`. First-time trainer save WILL be permission-denied. Comment lines 36-39 already describes the "Approach E" fix. |
| `lib/features/profile/application/user_providers.dart` | COMPLETE | `userProfileProvider`, `userRepositoryProvider` |

### Screens / Presentation

| File | Status | Notes |
|---|---|---|
| `lib/features/profile/presentation/profile_edit_trainer_screen.dart` | **SUBSTANTIALLY COMPLETE** | Full form: bio (20-280 chars), specialty dropdown, monthly rate (500-999999 ARS), payment alias, gym picker (catalog + search bottom sheet), custom location (GPS via Geolocator), online toggle. Client + repo validation. Route exists. |
| `lib/features/profile/trainer_profile_view.dart` | COMPLETE | Trainer-only profile tab. Identity card, PERFIL PÚBLICO card with VISIBLE/OCULTO badge, VER PREVIEW + EDITAR CTAs |
| `lib/features/profile/presentation/widgets/profile_trainer_section.dart` | COMPLETE | Trainer tile with completeness subtitle (lists missing fields). → `/profile/edit-trainer` |
| `lib/features/coach/presentation/widgets/trainer_profile_hero.dart` | COMPLETE | Public profile hero |
| `lib/features/profile/profile_screen.dart` | COMPLETE | Role-aware: `role == trainer` → `TrainerProfileView` |

### Profile Setup

| File | Status | Notes |
|---|---|---|
| `lib/features/profile_setup/presentation/profile_setup_flow.dart` | **ATHLETE-ONLY** | 4 steps: username/avatar, gym, experience/gender, weight/height. No role selection. Submit → `/home` |
| `lib/features/profile_setup/domain/profile_setup_draft.dart` | ATHLETE-ONLY | No trainer fields, no role field |
| `lib/features/profile_setup/application/profile_setup_notifier.dart` | ATHLETE-ONLY | Submit writes athlete fields only. Role defaults to `athlete` at `getOrCreate` |

**Key finding**: There is NO mechanism in the app for a user to self-select `role: trainer`. Role is set externally via Admin SDK. This is the most impactful discovery — see Open Questions.

### Router

| File | Status | Notes |
|---|---|---|
| `lib/app/router.dart` | READY FOR EXTENSION | `/profile/edit-trainer` exists (line 375-379). `authRedirect` gates on `displayName == null` but NO trainer-incomplete gate. Comment at line 108-110 explicitly marks the injection point. |

### Firestore Rules

| Collection | Gap? |
|---|---|
| `users/{uid}` | None — owner R/W, role immutable on update |
| `trainerPublicProfiles/{uid}` | **GAP** — create requires `uid` in body. Not supplied by current `_trainerPublicSubsetFromPartial` |
| `gyms/{gymId}` | None — role-gated create validates `role == 'trainer'` |

### Storage Rules

`storage.rules`: `/avatars/{uid}.{ext}` rule is present. No changes needed.

### Scripts (to be deprecated)

- `scripts/promote_mateo_to_public_trainer.js` — sets role + trainer fields via Admin SDK. Legacy singular geohash fields.

---

## What Needs to Be Built

### 1. Data / Model Gaps

- **Fix `uid` in `_trainerPublicSubsetFromPartial`** (1-line fix logically, but needs threading): add `result['uid'] = uid;` when any trainer field is present. Requires passing `uid` into the helper (currently `partial` doesn't contain it because `_immutableFields` strips it). Pattern: pass as separate param, or extract from pre-fetched profile. Already described in the code comment.

### 2. Onboarding Gate

- **Derived completeness check** (no new field): `trainerBio != null && trainerSpecialty != null && trainerMonthlyRate != null && (trainerLocations.isNotEmpty || trainerOffersOnline)`. Same logic already in `ProfileTrainerSection`.
- **`authRedirect` extension**: after `displayName == null` check, add: if `role == trainer && !trainerProfileComplete` → redirect to `/trainer-onboarding` (or `/profile/edit-trainer?mode=onboarding`).
- **Navigation after onboarding save**: change `context.pop()` to `context.go('/home')` in onboarding mode.

### 3. Edit Screen — Remaining Gaps

- `avatarUrl` upload not included (roadmap mentions it). Decision: keep out-of-scope (trainer uses personal edit for avatar) or add a shortcut.
- Custom location shows raw lat/lng (no reverse geocoding). Acceptable for MVP.
- Missing test coverage — no test file found.

### 4. Geocoding / Location

Already solved without new deps:
- Gym catalog: `_GymPickerSheet` with search. Uses existing `gymsProvider`.
- Custom: text label + GPS detect via `Geolocator` (already in pubspec).

### 5. Validation

Fully implemented in `ProfileEditTrainerScreen`. Repo-level guard at `_assertTrainerLocationStateIsValid`. No gaps.

### 6. Profile Screen Integration

Complete. No work needed beyond confirming VISIBLE/OCULTO badge shows correctly on first-time state (profile doc doesn't exist → `trainerByIdProvider` returns null → `isVisible = false` → OCULTO badge).

### 7. Tests

Main gap. Need:
- `UserRepository` unit tests: `_trainerPublicSubsetFromPartial` with `uid`, dual-write, `_assertTrainerLocationStateIsValid`
- `authRedirect` unit tests: trainer incomplete profile → redirect to onboarding
- `ProfileEditTrainerScreen` widget tests: form validation, save success, location invariant error

---

## Approach Options

| Approach | Description | Pros | Cons | Effort |
|---|---|---|---|---|
| **A (RECOMMENDED): Single form, mode param** | `ProfileEditTrainerScreen` is canonical. Onboarding adds `mode=onboarding` query param that changes header copy, disables back nav, routes to `/home` on save. Edit just opens same screen. | One widget to maintain. No duplication. 90% already built. Minimal new code. | Slightly less wizard-y feel, but trainers are power users. | Low |
| **B: Multi-step onboarding sheets + separate edit** | Bio/specialty/location/rate as sequential modal sheets at onboarding. Dedicated edit screen. | Each onboarding step is focused. | Double surface area. Sheets and form will drift. | High |
| **C: Inline profile tile editing** | User fills sections directly by tapping profile tiles. No forced wizard. | Minimal friction. | Easy to skip required fields. No completion guidance. | Medium |

**Recommendation**: **Approach A**. Edit screen is functionally complete. Smallest delta: fix `uid` bug + add `authRedirect` trainer-incomplete gate + onboarding mode behavior + tests.

---

## Open Questions for Proposal

### 🔴 Q1 (CRITICAL — changes scope 5x): Role assignment mechanism

How does a user get `role: trainer`?

| Option | Description | Scope impact |
|---|---|---|
| **(a) Self-select in ProfileSetup** | Add role chooser at start of ProfileSetup; trainers skip athlete-specific steps; role set at CREATE time | ~5-6 PRs (ProfileSetup needs trainer branch) |
| **(b) Admin-SDK-only** ⭐ | Team sets role manually before inviting to TestFlight. Unblocks TestFlight immediately with minimal scope | **~1-2 PRs** |
| **(c) Separate trainer onboarding code/link** | Magic link that pre-sets role | Out of scope for MVP |

This decision drastically changes everything else. Lock before spec.

### Q2: Onboarding gate flag vs. derived check

Derived check from existing fields (recommended, no model change) vs new `trainerOnboardingCompleted: bool` field?

### Q3: avatarUrl in onboarding wizard

Include avatar upload step in trainer onboarding, or keep it in "Datos personales" only?

### Q4: Route shape

`/trainer-onboarding` dedicated route vs `?mode=onboarding` query param on `/profile/edit-trainer`?

### Q5: If Q1=self-select, ProfileSetup trainer branch

Should trainers skip steps 2 (gym), 3 (experience/gender), 4 (weight/height)?

### Q6: Custom location reverse geocode

Raw lat/lng display acceptable for MVP, or add reverse geocoding (new dep)?

---

## Risks

| Risk | Severity | Mitigation |
|---|---|---|
| `uid` missing from `_trainerPublicSubsetFromPartial` → first-time save permission-denied | **CRITICAL** | Fix in PR1 + unit test covering first-time create |
| Role immutability: `users/{uid}` update rule blocks changing `role`. Self-select option requires role at CREATE time, not via `update()` | HIGH (if Q1=self-select) | If self-select: modify `getOrCreate` to accept optional role param. If admin-SDK-only: non-issue |
| `authRedirect` regression: new trainer gate must not break athlete signup, account-deletion in-flight, public route redirects | MEDIUM | Unit test the 6 authRedirect branches |
| No test coverage for `UserRepository` dual-write | MEDIUM | Fix in same PR as `uid` bug |
| `_CustomLocationSheet` requires GPS permission. Trainer who denies cannot add custom locations | LOW | Catalog gyms + online toggle mitigate. Not blocker |
| Existing seeded trainers (`promote_mateo`) use legacy singular fields. New form nulls these on save | LOW | One-time: re-run script or let first save clean up |

---

## Ready for Proposal

**YES** — with prerequisite that Q1 (role assignment) is locked. All other decisions have clear defaults. The `uid` fix is the only code-level blocker and is a small change with known location.

---

## Artifacts

- File: `openspec/changes/trainer-profile-onboarding/explore.md`
- Engram: `sdd/trainer-profile-onboarding/explore` (id #149)
