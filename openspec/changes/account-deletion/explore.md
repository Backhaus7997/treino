# Exploration: account-deletion

**Change**: account-deletion
**Owner**: Backhaus
**Date**: 2026-05-28
**Trigger**: PR#4 v2 of `profile-screen-rewrite` shipped Eliminar cuenta as a STUB (`EliminarCuentaStubSheet`). This SDD designs and implements the real flow.
**Engram mirror**: `sdd/account-deletion/explore` (observation #114)

---

## Scope Summary

Implement a real "Eliminar cuenta" flow replacing the current stub. The feature requires: re-auth before deletion (Firebase requirement), a Cloud Function for cascade deletion with Admin SDK privileges (already anticipated by `UserRepository.delete` throwing `UnsupportedError`), and careful handling of 8+ Firestore collections plus Firebase Auth + Storage assets.

---

## Current State

### Stub exists at
- `lib/features/profile/presentation/widgets/eliminar_cuenta_stub_sheet.dart` — StatelessWidget, shows support email copy, single CANCELAR button. No delete logic.
- `lib/features/profile/profile_screen.dart` — tile tap calls `showModalBottomSheet` with `EliminarCuentaStubSheet`.

### Auth feature
- Supports: email/password, Google Sign-In (`google_sign_in` 7.x), Apple Sign-In.
- `AuthService.cancelOnboarding()` calls `user.delete()` — precedent for client-side deletion, but only used within seconds of signup (token is recent).
- `AuthNotifier` exposes the notifier pattern; delete would follow the same `AsyncValue.guard` pattern.
- `AuthFailure` union is extensible via `const factory`.
- `AuthService.signOut()` disconnects Google session via `_googleSignIn.signOut()` — deletion must do the same.
- NO re-auth helpers exist yet. `reauthenticateWithCredential` is not wrapped.

### UserRepository
- `delete()` explicitly throws `UnsupportedError` pointing to a Cloud Function — clear team pre-decision.
- Writes to 3 collections: `users/{uid}`, `userPublicProfiles/{uid}`, `trainerPublicProfiles/{uid}`.
- All deletions from client-side denied by Firestore rules.

### Firestore rules — cascade scope
| Collection | Client delete? | Notes |
|---|---|---|
| `users/{uid}` | NO | owner-only read; `delete: if false` |
| `users/{uid}/sessions/*` | YES | owner-only R/W |
| `users/{uid}/sessions/*/setLogs/*` | YES | owner-only R/W |
| `users/{uid}/checkIns/*` | YES | owner-only R/W |
| `userPublicProfiles/{uid}` | NO | `delete: if false` |
| `trainerPublicProfiles/{uid}` | NO | `delete: if false` |
| `friendships/*` (members) | YES | members can delete |
| `posts/*` (author) | YES | author can delete |
| `trainer_links/*` | NO | terminate via update only |
| `chats/*` | NO | `delete: if false` |
| `chats/*/messages/*` | NO | update/delete: if false |
| `routines/*` | NO | `delete: if false` |
| `appointments/*` | NO | `delete: if false` |
| `coach_availability_rules/*` | trainer's own | not athlete-scope |
| `coach_availability_overrides/*` | trainer's own | not athlete-scope |

### Collections touched by typical athlete deletion
1. `users/{uid}` — main profile doc (PII) → **CF required**
2. `userPublicProfiles/{uid}` → **CF required**
3. `users/{uid}/sessions/*` — workout history → client CAN delete or CF
4. `users/{uid}/sessions/*/setLogs/*` — sub-sub collection → same
5. `users/{uid}/checkIns/*` → client CAN delete
6. `friendships/*` where uid in members → client CAN delete
7. `posts/*` where authorUid == uid → client CAN delete
8. `trainer_links/*` where athleteId == uid → cannot delete (rules deny); terminate via update or CF
9. Storage: `avatars/{uid}.jpg` → client has no delete rule (rules not committed to repo); CF via Admin SDK can delete

### Trainer deletion (future-proof note — not in scope today)
- `trainerPublicProfiles/{uid}` → CF required
- `coach_availability_rules` / `overrides` — trainer can delete own
- `routines` with `assignedBy == uid` → `delete: if false` → CF required

### No Cloud Functions infrastructure exists
- No `functions/` directory found
- `firebase.json` has no `functions` key — only `firestore`, `hosting`, `emulators`
- `pubspec.yaml` has NO `cloud_functions` Flutter package
- Scripts in `scripts/` are Node.js Admin SDK scripts run locally, not deployed functions
- **Cloud Functions must be bootstrapped from scratch** (Firebase project `treino-dev` exists)

### Firebase Storage
- `firebase_storage: ^12.3.0` in pubspec — package exists
- `AvatarUploadService` uploads to `avatars/{uid}.jpg`
- No Storage security rules file found in repo (likely managed via Console)

### Other gaps
- No comments collection exists
- No data export functionality
- No soft-delete/tombstone pattern anywhere

### Provider detection
- Firebase Auth `User.providerData` returns the list of sign-in providers. For re-auth, the app must branch on `password` / `google.com` / `apple.com`.

---

## Affected Areas

**Replace/modify:**
- `lib/features/profile/presentation/widgets/eliminar_cuenta_stub_sheet.dart`
- `lib/features/profile/profile_screen.dart` (minimal — hook up new sheet)
- `lib/features/auth/data/auth_service.dart` — add `reauthenticate()` + `deleteAccount()` methods
- `lib/features/auth/application/auth_notifier.dart` — add `deleteAccount()` action
- `lib/features/auth/domain/auth_failure.dart` — add `requiresRecentLogin`, `reAuthFailed`, `deletionFailed` variants
- `lib/features/profile/data/user_repository.dart` — `delete()` stays as UnsupportedError; optionally add `deleteOwnedData()` for client-permitted collections
- `pubspec.yaml` — add `cloud_functions: ^4.x`

**New files:**
- `functions/src/index.ts` (or `functions/index.js`) — Cloud Function `deleteAccount`
- `functions/package.json`
- `lib/features/profile/presentation/widgets/eliminar_cuenta_sheet.dart` — real confirmation sheet
- `lib/features/profile/presentation/re_auth_bottom_sheet.dart` (or in `auth/presentation/`)
- `lib/features/profile/application/account_deletion_notifier.dart` — orchestrates re-auth + CF call
- `lib/features/profile/data/account_deletion_service.dart` — wraps `cloud_functions` callable

**Existing supporting files:**
- `firestore.rules` — Admin SDK bypasses rules, so no change needed for CF deletes
- `firebase.json` — add `"functions"` key

---

## Approaches

### Option 1 — Cloud Function Cascade (RECOMMENDED)

Client triggers a callable Cloud Function `deleteAccount` after re-auth. Function runs with Admin privileges: deletes `users/{uid}`, `userPublicProfiles/{uid}`, `trainerPublicProfiles/{uid}`, all sub-collections (sessions, setLogs, checkIns), Storage file, and then calls `admin.auth().deleteUser(uid)`. Posts/friendships can be left to the CF too (Admin bypasses rules).

- **Pros**: atomic-ish (single server-side execution), no client-side permission battles, Admin SDK can delete all collections including those denied by rules, cleaner cascade, easier to audit, consistent with existing `UserRepository.delete()` comment.
- **Cons**: requires bootstrapping Cloud Functions from zero (new infra, new deployment step), cold start latency ~1-3s first call, Blaze plan required, new Node.js/TypeScript codebase to maintain.
- **Effort**: High (infra setup + function writing + Flutter callable integration).

### Option 2 — Hybrid: client pre-clears + CF for privileged

Client deletes what it can (sessions, setLogs, checkIns, friendships, posts), then calls minimal CF for privileged deletes (`users`, `userPublicProfiles`, `trainerPublicProfiles`, Storage, Auth user).

- **Pros**: simpler CF (fewer collection traversals), less Admin SDK surface, partially testable on client.
- **Cons**: two-phase failure risk (client partial + CF fail = inconsistent state); still requires CF infra; more code paths.
- **Effort**: High (same infra, more risk).

### Option 3 — Client-only (no CF)

Delete what client rules allow, then call `user.delete()`. Collections that can't be deleted from client are left as orphans.

- **Pros**: no new infrastructure.
- **Cons**: `users/{uid}` and `userPublicProfiles/{uid}` CANNOT be deleted from client (rules `delete: if false`). Main profile doc would remain orphaned. Contradicts team's pre-decision in `UserRepository.delete()`. **NOT viable.**
- **Effort**: N/A.

---

## Recommendation

**Option 1 (Cloud Function Cascade)**. The team already decided this — `UserRepository.delete()` throws `UnsupportedError` with the exact message "Account deletion goes through a privileged Cloud Function." The infra cost is unavoidable. The proposal phase should decide whether to scope the function narrowly (auth + privileged Firestore docs only) or broadly (full cascade).

**UX flow:**
1. User taps tile → confirmation bottom sheet with destructive copy
2. Confirmation → re-auth bottom sheet (password prompt OR Google/Apple re-trigger based on `user.providerData`)
3. Re-auth succeeds → call Cloud Function (loading state)
4. CF completes → `admin.auth().deleteUser()` invalidates client token → `authStateChanges` emits null → GoRouter redirects to sign-in with "Tu cuenta fue eliminada" message

---

## Open Questions for Proposal

1. **Hard delete vs soft delete with grace period** — current codebase has no tombstone pattern; hard delete is simpler and consistent.
2. **Posts authored by deleted user** — anonymize `authorDisplayName` to "Usuario eliminado" OR hard delete? Anonymization keeps community integrity; hard delete removes content ownership.
3. **Friendships** — client can delete; but should the CF sweep them to avoid orphan reads?
4. **Trainer links** — cannot be deleted from client; CF should sweep them (or terminate with reason 'account-deleted').
5. **Appointments** — `delete: if false`; CF must handle cancellation of future appointments (audit trail requirement).
6. **Chats/messages** — `delete: if false`; anonymize or leave? Messages can't be bulk-deleted even by CF without iterating.
7. **Data export** — out of scope for v1?
8. **Audit log** — log deletion event to `audit_log/{uid}` (Admin-only write) for support/compliance?
9. **Provider re-auth** — email/password straightforward; Google requires re-running `authenticate()` + `authorizeScopes()`; Apple requires a new Sign-In sheet.
10. **Cloud Function deployment** — `treino-dev` on Spark plan? Blaze required for callable functions. Needs verification.

---

## Risks

1. **CF infra bootstrapping from zero** — adds setup time + Firebase billing plan requirement (Blaze).
2. **`cloud_functions` package absent** — must be added; triggers `pod install` on iOS.
3. **Apple re-auth complexity** — Apple may not return email after first sign-in; native sheet behavior on re-auth differs.
4. **Sub-collection deletion at scale** — `users/{uid}/sessions` could have hundreds of docs; CF must paginate or use `recursiveDelete()`.
5. **Storage rules not in repo** — actual delete permission for `avatars/{uid}.jpg` unknown; Admin SDK bypasses rules, so this is OK for CF but should be confirmed.
6. **Trainer deletion** — out of scope (trainers created via Admin SDK, never self-delete) but CF should guard against it.
7. **Cold start latency** — ~1-3s on first CF call could make UX feel slow; need proper loading state.
8. **`requires-recent-login`** — Firebase Auth requires re-auth before `user.delete()`; the CF approach moves the deletion to Admin SDK (no recent-login requirement) but the client should still re-auth as a security measure before calling the CF.

---

## Ready for Proposal

Yes. Proposal phase should lock:
- Hard vs soft delete
- Posts: anonymize vs hard delete
- CF scope: narrow vs full cascade
- Delivery phasing: single PR or chained (re-auth + stub → real CF → full cascade)
- Audit log: yes/no
- Data export pre-delete: yes/no
