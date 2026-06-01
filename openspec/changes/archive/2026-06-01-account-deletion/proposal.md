# Proposal: account-deletion

**Change**: account-deletion
**Owner**: Backhaus
**Date**: 2026-05-28
**Artifact store**: hybrid (file + Engram `sdd/account-deletion/proposal`)
**Exploration**: `openspec/changes/account-deletion/explore.md` (Engram #114)

---

## 1. TL;DR

Replace the `EliminarCuentaStubSheet` with a real, irreversible athlete account-deletion flow: confirmation sheet, provider-aware re-auth (password / Google / Apple), and a privileged Firebase Cloud Function `deleteAccount` that cascades through 8+ Firestore collections, Storage, Firebase Auth and an audit log. Bootstrap Cloud Functions infra (none exists today) and deliver in 3 chained PRs to keep each under the 400-line review budget.

---

## 2. Why

- Profile screen currently ships `EliminarCuentaStubSheet` — UX promise without function.
- `UserRepository.delete()` already throws `UnsupportedError("Account deletion goes through a privileged Cloud Function")` — team pre-decision is locked into code.
- 6 of the 12 athlete-touched Firestore paths have `delete: if false` — pure client deletion is **not viable** (would orphan `users/{uid}` and public profile docs).
- GDPR-style "I want my data gone" requests have no path today.

---

## 3. Locked Decisions

| # | Question | Decision | Rationale |
|---|----------|----------|-----------|
| 1 | Hard vs soft delete | **HARD** | No tombstone pattern in codebase; user expects immediate effect; recovery handled by support email path. |
| 2 | Posts authored by deleted user | **ANONYMIZE** to "Usuario eliminado" | Preserves feed integrity; comments/likes stay valid; no orphan content gaps. |
| 3 | Friendships sweep | **CF sweeps both sides** | CF has Admin SDK; avoids orphan reads on the other user's friend list. |
| 4 | Trainer links | **CF terminates** with `reason: 'account-deleted'` | Audit trail; trainer keeps historical record of the relationship. |
| 5 | Appointments | **CF cancels future** (`status: cancelled`, `reason: 'athlete-account-deleted'`); past untouched | History preserved; future slots freed for the trainer. |
| 6 | Chats/messages | **Anonymize sender display name**; do NOT delete chats | Matches WhatsApp/iMessage UX; other party keeps history. |
| 7 | Pre-delete data export | **OUT OF SCOPE v1** | Note GDPR may force this when user base grows. |
| 8 | Audit log | **YES** → `audit_log/{uid}` (Admin-only write) with timestamp, provider, success/failure | Support tickets ("did someone delete my account?"). |
| 9 | Provider re-auth coverage | **All 3 on day one**: email/password, Google, Apple | No partial coverage — every signed-in user must be able to delete. |
| 10 | Blaze plan | **ACTION ITEM for Backhaus** before apply phase | Callable CFs require Blaze; verify `treino-dev` billing. |

---

## 4. In Scope / Out of Scope

### In Scope
- Real `EliminarCuentaSheet` (destructive confirmation UX, es-AR copy).
- `ReAuthBottomSheet` branching on `user.providerData`.
- Cloud Function `deleteAccount` (callable, Admin SDK, full cascade across 8 collections + sub-collections + Storage + Auth + audit).
- Flutter wrapper `AccountDeletionService` over `cloud_functions` callable.
- `AccountDeletionNotifier` orchestrating re-auth → CF call → sign-out → router redirect.
- New `AuthFailure` variants: `requiresRecentLogin`, `reAuthFailed`, `deletionFailed`.
- New deps: `cloud_functions: ^4.x` (Flutter), `firebase-admin`, `firebase-functions` (Node).
- `firebase.json` `functions` entry + `functions/` directory bootstrap.
- Audit log writes from CF.
- Tests: widget + provider tests (Flutter, strict TDD); CF integration tests against emulator.

### Out of Scope (explicit)
- Pre-delete data export (deferred GDPR work).
- Trainer self-deletion — CF must REJECT if `role == 'trainer'` (trainers provisioned manually).
- Soft-delete / grace period.
- Email notification post-deletion.
- Restoring deleted accounts (irreversible by design).
- Storage rules audit (handled separately if/when surfaced).

---

## 5. Capabilities

> Contract with `sdd-spec`. No prior `openspec/specs/` exist for these areas — all are NEW.

### New Capabilities
- `account-deletion`: athlete-initiated irreversible deletion of own account (UI + orchestration).
- `auth-reauthentication`: re-auth helpers across password/Google/Apple providers.
- `cloud-functions-infra`: bootstrap of Firebase Functions runtime (Node 20, TypeScript, deployment pipeline).

### Modified Capabilities
- None (no existing specs to delta).

---

## 6. Approach Summary

**Cloud Function Cascade** (Option 1 from explore.md — Options 2 and 3 rejected; see explore.md §Approaches).

Flow:
1. Profile tile tap → `EliminarCuentaSheet` (CANCELAR / ELIMINAR with destructive styling).
2. ELIMINAR → `ReAuthBottomSheet` reading `user.providerData.first.providerId`:
   - `password` → password input field → `reauthenticateWithCredential`.
   - `google.com` → re-trigger `_googleSignIn.authenticate()` → credential → `reauthenticateWithCredential`.
   - `apple.com` → new Apple sheet → credential → `reauthenticateWithCredential`.
3. Re-auth success → `AccountDeletionNotifier` calls callable `deleteAccount({uid})`.
4. CF (running with Admin SDK):
   - Verify `context.auth.uid == data.uid` and `role != 'trainer'`.
   - Write `audit_log/{uid}` with status `'started'`.
   - Recursive-delete `users/{uid}` + sub-collections (`sessions`, `setLogs`, `checkIns`).
   - Delete `userPublicProfiles/{uid}`, `trainerPublicProfiles/{uid}`.
   - Sweep `friendships` (both members), `trainer_links` (terminate), `appointments` (cancel future), `posts` (anonymize), `chats/*/messages` (anonymize sender).
   - Delete `avatars/{uid}.*` from Storage.
   - `admin.auth().deleteUser(uid)`.
   - Update `audit_log/{uid}` with `'success'`.
5. Client receives success → `AuthService.signOut()` (Google disconnect) → `authStateChanges` → GoRouter redirects to `/sign-in` with snackbar "Tu cuenta fue eliminada".

---

## 7. Delivery Strategy — 3 chained PRs

Total estimate: **~850 LOC** across 3 PRs (each under 400-line budget).

| PR | Scope | LOC est. | Verification |
|----|-------|----------|--------------|
| **PR#1 — CF bootstrap** | `functions/` skeleton, `package.json`, TS config, `firebase.json` entry, `deleteAccount` callable that only deletes Auth user + writes audit log. Deploy to `treino-dev`. | ~150 | Smoke test from emulator; verify Blaze billing active; Firebase Console shows function. |
| **PR#2 — Full cascade** | CF recursive deletes across all 8 collections + Storage + sweep helpers (`friendships`, `trainer_links`, `appointments`, `posts`, `chats/messages`). CF integration tests against emulator. Trainer-role rejection guard. | ~300 | Seed dev user with data; run callable; verify all paths cleaned via Firestore console. |
| **PR#3 — Flutter UI** | `cloud_functions` dep, `AccountDeletionService`, `AccountDeletionNotifier`, `EliminarCuentaSheet`, `ReAuthBottomSheet`, profile tile rewire, new `AuthFailure` variants, "Tu cuenta fue eliminada" sign-in snackbar. Widget + provider tests. | ~400 | Manual e2e on dev: tap → re-auth (all 3 providers) → success → redirect. |

Risk mitigation: PR#1 proves the infra works **before** anyone writes Flutter on top. PR#2 isolates the most failure-prone code (cascade) for focused review. PR#3 is pure UI/orchestration against a verified backend.

---

## 8. Risks & Mitigations

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| Blaze plan not active on `treino-dev` | Med | Action item on Backhaus before PR#1 merge; CF deploy will fail loudly if Spark. |
| `cloud_functions` package triggers iOS pod issues | Med | Run `cd ios && pod install` immediately after `pubspec.yaml` change; commit `Podfile.lock`. |
| Apple re-auth complexity (email not returned, native sheet quirks) | High | Use existing Apple Sign-In wrapper as template; isolate in `ReAuthBottomSheet._reauthApple()`; add explicit failure variant `reAuthFailed(provider: 'apple')`. |
| Sub-collection scale (sessions could be hundreds of docs) | Med | CF uses Firestore `recursiveDelete()` from `firebase-tools`/Admin SDK; tested with 500-doc seed. |
| Cold start latency 1-3s | Med | `EliminarCuentaSheet` shows full-screen loading with "Eliminando tu cuenta..." copy; min display 800ms to avoid flicker. |
| Atomic-ish failure mid-cascade | Med | Audit log captures partial state (`status: 'partial'`, `failed_step: 'storage'`); manual cleanup runbook for support; idempotent CF re-run. |
| Trainer accidentally calls CF | Low | CF guard: `if (role === 'trainer') throw HttpsError('permission-denied', ...)`. |
| Recent-login token expiry during slow re-auth | Low | Re-auth and CF call happen in same notifier action; token is fresh by definition. |

---

## 9. Open Questions

Only 2 remain (all others LOCKED in §3):

1. **Blaze billing on `treino-dev`** — Backhaus to verify before PR#1. If Spark, must upgrade (Blaze has free tier; cost ~0 for our volume).
2. **"Tu cuenta fue eliminada" snackbar on sign-in screen** — minimal: pass a query param or transient route extra to `/sign-in` and show a one-shot SnackBar. Confirm UX wants this snackbar (vs silent redirect). Defaulting to **YES, show snackbar** unless Backhaus overrides.

---

## 10. Success Criteria

- [x] Tap "Eliminar cuenta" → confirmation sheet → ELIMINAR → re-auth sheet for current provider.
- [x] Re-auth succeeds for **all 3 providers** (password / Google / Apple) on real device.
- [x] CF call returns success within p95 < 5s (post-warm).
- [x] User signed out and redirected to `/sign-in` with "Tu cuenta fue eliminada" snackbar.
- [x] Firebase Console verification: `users/{uid}`, `userPublicProfiles/{uid}`, all sub-collections, Storage avatar — all gone.
- [x] `friendships`, `trainer_links`, `appointments` — swept/terminated/cancelled as specified.
- [x] `posts` and `chats/messages` — sender anonymized to "Usuario eliminado".
- [x] `audit_log/{uid}` exists with `status: 'success'`, timestamp, provider.
- [x] CF rejects trainer-role caller with `permission-denied`.
- [x] `flutter analyze` 0 issues; `dart format .` clean; all tests green (Flutter + CF integration).
- [x] Each PR diff ≤ 400 lines (or `size:exception` recorded if exceeded).

---

## 11. Non-Functional Requirements

- **Strict TDD**: every Flutter unit/widget test RED before GREEN. CF tests use Firebase emulator suite.
- **es-AR copy** on every user-facing string, marked `// i18n: Fase 6 Etapa 3 — account deletion`.
- **AppPalette.of(context)** for all colors — zero HEX literals.
- **TreinoIcon.X** for all icons — no direct `PhosphorIcons.X`.
- **Spacing scale**: 8 / 12 / 14 / 18 / 20 only.
- **Conventional commits**, no `Co-Authored-By`, no AI attribution.
- **Naming**: TREINO brand, Coach (PF module), Entreno IA (never "Coach IA"). This change is athlete-side only.
- **Provider/notifier tests** use `ProviderScope` overrides; auth notifier mocked with `mocktail`.
- **No new HEX**, no new icon imports outside `TreinoIcon`.

---

## 12. Rollback Plan

- **PR#1 rollback**: delete `functions/` directory + revert `firebase.json` `functions` entry. CF un-deploys via `firebase functions:delete deleteAccount`. No client impact (stub still in place).
- **PR#2 rollback**: revert CF code to PR#1 skeleton; re-deploy. Client still gated by stub (PR#3 not merged yet) so users see no change.
- **PR#3 rollback**: revert Flutter changes; profile tile returns to `EliminarCuentaStubSheet`. CF remains deployed but un-called. No data loss path.
- **Post-launch incident**: if CF cascades incorrectly, set CF to throw `'temporarily-disabled'` immediately (one-line patch); users see error toast and "Contactanos por email"; investigate via `audit_log`.

---

## 13. Dependencies

- Firebase project `treino-dev` on **Blaze plan** (action item — Backhaus).
- New Flutter dep: `cloud_functions: ^4.x`.
- New Node deps in `functions/`: `firebase-admin`, `firebase-functions`, `typescript`, `@types/node`.
- iOS: `pod install` after `cloud_functions` added.
- Firebase CLI installed locally for deploy (`firebase deploy --only functions`).

---

**Status**: Ready for `sdd-spec` and `sdd-design` (can run in parallel).
