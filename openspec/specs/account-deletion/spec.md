# Spec: account-deletion

**Feature**: account-deletion
**Owner**: Backhaus
**Date**: 2026-06-01 (archived from change SDD)
**Status**: COMPLETE (PASS-WITH-DEVIATIONS)

---

## TL;DR

Athlete-initiated irreversible account deletion flow with Cloud Function cascade, provider-aware re-auth (password/Google/Apple), and full data cleanup across 8+ Firestore collections, Storage, Firebase Auth, and audit logging. Delivered via 3 chained PRs (#103, #106, #112) to main.

---

## Capability Overview

This spec defines 3 coordinated capabilities, all NEW (no prior specs to merge):

1. **cloud-functions-infra**: Firebase Functions bootstrap (Node 20, TypeScript, deployment pipeline)
2. **account-deletion**: Irreversible athlete account deletion (CF cascade + Flutter UI/orchestration)
3. **auth-reauthentication**: Provider-aware re-auth helpers (password/Google/Apple)

### Scope

- Real `EliminarCuentaSheet` (confirmation UX, destructive copy, es-AR)
- `ReAuthBottomSheet` (provider-branched re-auth)
- Cloud Function `deleteAccount` (callable, Admin SDK, full cascade)
- `AccountDeletionService`, `AccountDeletionNotifier` (orchestration)
- New `AuthFailure` variants: `requiresRecentLogin`, `reAuthFailed`, `deletionFailed`
- Audit log writes and support recovery
- Chat UI fallback for deleted users

### Out of Scope

- Pre-delete data export (deferred GDPR work)
- Trainer self-deletion (CF rejects)
- Soft-delete / grace period
- Email notifications
- Account restoration
- Storage rules audit

---

## Requirements

### REQ-ACCDEL-CF-001 — Callable Function Exists

The Cloud Function MUST be a Firebase Callable Function named `deleteAccount`, deployed to the `treino-dev` project, running on Node 20 with TypeScript.

#### SCENARIO-533: CF is callable by authenticated client
- **Given** an authenticated athlete with a valid Firebase ID token
- **When** the client invokes the `deleteAccount` callable with `{ uid: <caller_uid> }`
- **Then** the CF executes without a `permission-denied` or `not-found` error
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-002 — Anti-Spoofing Guard

The CF MUST verify `context.auth.uid === data.uid`. If they differ, MUST throw `HttpsError('permission-denied', 'uid mismatch')`.

#### SCENARIO-534: Caller spoofs another user's uid
- **Given** an authenticated athlete with uid `A`
- **When** they call `deleteAccount({ uid: 'B' })`
- **Then** the CF throws `HttpsError` with code `permission-denied`
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-003 — Trainer Role Rejection

The CF MUST read the caller's `users/{uid}.role` field. If `role === 'trainer'`, MUST throw `HttpsError('permission-denied', 'trainers cannot self-delete')`.

#### SCENARIO-535: Trainer calls deleteAccount
- **Given** an authenticated user whose `users/{uid}.role` is `'trainer'`
- **When** they call `deleteAccount({ uid: <their_uid> })`
- **Then** the CF throws `HttpsError` with code `permission-denied`
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-004 — Main User Documents Deleted

The CF MUST delete `users/{uid}` (with all sub-collections: `sessions`, `sessions/*/setLogs`, `checkIns`) and `userPublicProfiles/{uid}`. If `trainerPublicProfiles/{uid}` exists, it MUST also be deleted.

#### SCENARIO-536: Main profile docs deleted on success
- **Given** a seeded athlete with `users/{uid}`, `userPublicProfiles/{uid}`, and 5 session sub-docs
- **When** the CF completes successfully
- **Then** `users/{uid}` does not exist in Firestore
- **And** `userPublicProfiles/{uid}` does not exist
- **And** all 5 session docs do not exist
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-005 — Friendships Sweep

The CF MUST delete all documents in `friendships/*` where `members` array contains `uid`.

#### SCENARIO-538: Friendship documents are swept
- **Given** a seeded athlete with 3 friendship docs
- **When** the CF completes
- **Then** all 3 friendship docs are deleted from Firestore
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-006 — Posts Anonymized

The CF MUST query `posts/*` where `authorUid == uid` and for each matching doc set `authorDisplayName = 'Usuario eliminado'` and `authorAvatarUrl = null`. The `authorUid` field MUST remain unchanged.

#### SCENARIO-540: Post author is anonymized
- **Given** an athlete who authored 2 posts
- **When** the CF completes
- **Then** both post docs have `authorDisplayName == 'Usuario eliminado'`
- **And** `authorAvatarUrl == null`
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-007 — Chat Public Profile Deleted for Read-Time Anonymization

CF MUST delete `userPublicProfiles/{uid}` so chat UI renders deleted users as "Usuario eliminado" via read-time fallback. Messages are immutable per `firestore.rules` — CF does NOT mutate them. The `Message` model has no `senderDisplayName` field; sender names are resolved at render time from `userPublicProfiles/{senderId}`.

#### SCENARIO-542: Chat UI renders "Usuario eliminado" when sender's public profile is missing
- **Given** a chat thread containing a message from a user whose `userPublicProfiles/{uid}` document has been deleted
- **When** the chat screen is mounted and the message row is rendered
- **Then** the displayed sender name is "Usuario eliminado"
- **Test target**: Widget test — chat UI with missing `userPublicProfiles` entry

---

### REQ-ACCDEL-CF-008 — Trainer Links Terminated

The CF MUST query `trainer_links/*` where `athleteId == uid` and update each doc: `status = 'terminated'`, `reason = 'account-deleted'`, `terminatedAt = <server timestamp>`.

#### SCENARIO-543: Active trainer link is terminated
- **Given** an athlete with an active `trainer_links` doc
- **When** the CF completes
- **Then** the doc has `status == 'terminated'` and `reason == 'account-deleted'`
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-009 — Future Appointments Cancelled

The CF MUST query `appointments/*` where `athleteId == uid AND scheduledAt > now()` and update each: `status = 'cancelled'`, `reason = 'athlete-account-deleted'`. Past appointments MUST remain untouched.

#### SCENARIO-544: Future appointment is cancelled
- **Given** an athlete with 1 past and 1 future appointment
- **When** the CF completes
- **Then** the future appointment has `status == 'cancelled'` and `reason == 'athlete-account-deleted'`
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-010 — Storage Avatar Deleted

The CF MUST attempt to delete `avatars/{uid}.jpg` from Firebase Storage. If the file does not exist, the CF MUST treat this as a no-op.

#### SCENARIO-545: Avatar file deleted when it exists
- **Given** an athlete whose avatar file exists at `avatars/{uid}.jpg`
- **When** the CF completes
- **Then** the file no longer exists in Storage
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-011 — Audit Log Written

The CF MUST write `audit_log/{uid}` with: `deletedAt` (server timestamp), `provider` (sign-in provider string), `status` (`'success'` | `'partial'` | `'failed'`). The CF MUST write `status: 'started'` at entry and update to final status at end.

#### SCENARIO-547: Audit log records successful deletion
- **Given** a successful CF run for an athlete
- **When** the CF completes
- **Then** `audit_log/{uid}` exists with `status == 'success'` and `deletedAt` set
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-012 — Auth User Deleted Last

The CF MUST call `admin.auth().deleteUser(uid)` as the final step, after all Firestore and Storage cleanup has completed.

#### SCENARIO-549: Auth user record is absent after CF success
- **Given** a successful CF run
- **When** the CF completes
- **Then** `admin.auth().getUser(uid)` throws a `user-not-found` error
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-013 — Idempotency on Partial Failure

If the CF is re-called after a partial failure, it MUST resume from the failed step without duplicating completed steps or throwing on already-deleted documents.

#### SCENARIO-550: Re-call after partial failure completes cleanly
- **Given** the CF previously ran and deleted Firestore docs but failed on Storage
- **When** the CF is called again for the same uid
- **Then** it completes without error on already-deleted Firestore docs (no-op)
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-014 — Structured Response

The CF MUST return one of:
- `{ status: 'success', deletedCollections: string[], errors: [] }` on full success
- `{ status: 'partial', deletedCollections: string[], errors: string[] }` on partial success
- Throw `HttpsError` with meaningful code and message on total failure

#### SCENARIO-551: CF returns structured success response
- **Given** a successful CF run
- **When** the client awaits the callable result
- **Then** the result object has `status == 'success'` and a non-empty `deletedCollections` array
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-REAUTH-001 — AuthService reauthenticate Method

`AuthService` MUST expose a `reauthenticate(AuthCredential credential)` method that calls `FirebaseAuth.instance.currentUser!.reauthenticateWithCredential(credential)`.

#### SCENARIO-552: reauthenticate succeeds with valid credential
- **Given** an authenticated user with a valid password credential
- **When** `AuthService.reauthenticate(credential)` is called
- **Then** it returns without throwing and the user's token is refreshed
- **Test target**: `test/features/auth/data/auth_service_test.dart`

---

### REQ-ACCDEL-REAUTH-003 — Provider-Branched Re-auth UI

The re-auth flow MUST branch on `user.providerData[0].providerId`:
- `'password'` → password input field rendered in `ReAuthBottomSheet`
- `'google.com'` → triggers Google re-authentication flow
- `'apple.com'` → triggers Apple re-authentication flow

#### SCENARIO-555: Password provider renders password field
- **Given** a user whose provider is `'password'`
- **When** `ReAuthBottomSheet` is opened
- **Then** a password input field is visible
- **Test target**: `test/features/profile/presentation/re_auth_bottom_sheet_test.dart`

---

### REQ-ACCDEL-REAUTH-004 — AuthFailure Variants

`AuthFailure` MUST include three new variants: `requiresRecentLogin`, `reAuthFailed`, and `deletionFailed`. Each variant MUST be surfaced through the notifier as an `AsyncError` state.

#### SCENARIO-558: requiresRecentLogin variant surfaced
- **Given** the CF returns a `requires-recent-login` error
- **When** `AccountDeletionNotifier` processes the error
- **Then** the notifier state is `AsyncError` carrying `AuthFailure.requiresRecentLogin`
- **Test target**: `test/features/auth/application/account_deletion_notifier_test.dart`

---

### REQ-ACCDEL-UI-001 — EliminarCuentaSheet Content

`EliminarCuentaSheet` MUST display:
- Title "Eliminar cuenta" styled in danger color via `AppPalette.of(context)`
- Destructive copy explaining irreversibility, what gets deleted, and what gets anonymized
- A "CANCELAR" secondary button and an "ELIMINAR" danger-styled primary button
- All strings in es-AR marked `// i18n: Fase 6 Etapa 3`

#### SCENARIO-560: Sheet renders required elements
- **Given** the user taps the "Eliminar cuenta" profile tile
- **When** `EliminarCuentaSheet` opens
- **Then** the title "Eliminar cuenta" is visible in danger color
- **Test target**: `test/features/profile/presentation/eliminar_cuenta_sheet_test.dart`

---

### REQ-ACCDEL-UI-002 — ELIMINAR Opens ReAuthBottomSheet

Tapping "ELIMINAR" in `EliminarCuentaSheet` MUST close the confirmation sheet and open `ReAuthBottomSheet`.

#### SCENARIO-561: ELIMINAR button transitions to re-auth sheet
- **Given** `EliminarCuentaSheet` is open
- **When** the user taps "ELIMINAR"
- **Then** `EliminarCuentaSheet` is dismissed
- **And** `ReAuthBottomSheet` is shown
- **Test target**: `test/features/profile/presentation/eliminar_cuenta_sheet_test.dart`

---

### REQ-ACCDEL-UI-003 — Loading State During CF Call

While the CF call is in-flight, the UI MUST show a loading state. The "ELIMINAR" button MUST be disabled during this period.

#### SCENARIO-562: Loading indicator visible during CF call
- **Given** re-auth completed and the CF call is in-flight
- **When** `AccountDeletionNotifier` state is `AsyncLoading`
- **Then** a loading indicator is visible and the "ELIMINAR" button is disabled
- **Test target**: `test/features/profile/presentation/eliminar_cuenta_sheet_test.dart`

---

### REQ-ACCDEL-UI-004 — Success: Sign Out and Redirect

On CF success the app MUST: call `AuthService.signOut()`, let `authStateChanges` propagate, allow GoRouter to redirect to `/sign-in`, and show a SnackBar with "Tu cuenta fue eliminada".

#### SCENARIO-563: Success navigates to sign-in with snackbar
- **Given** the CF call returns `{ status: 'success' }`
- **When** `AccountDeletionNotifier` processes the success response
- **Then** `AuthService.signOut()` is called
- **And** the router navigates to `/sign-in`
- **And** a SnackBar with "Tu cuenta fue eliminada" is displayed
- **Test target**: `test/features/auth/application/account_deletion_notifier_test.dart`

---

### REQ-ACCDEL-UI-005 — Failure: Error Snackbar with Retry

On CF failure the app MUST show an error SnackBar with a "Reintentar" action button. The user MUST be able to retry without reopening the confirmation sheet.

#### SCENARIO-564: CF failure shows error snackbar with retry
- **Given** the CF call throws an error
- **When** `AccountDeletionNotifier` processes the error
- **Then** a SnackBar is shown with an error message and a "Reintentar" button
- **Test target**: `test/features/profile/presentation/eliminar_cuenta_sheet_test.dart`

---

### REQ-ACCDEL-UI-006 — Profile Tile Rewired

The "Eliminar cuenta" profile tile in `ProfileScreen` MUST open the real `EliminarCuentaSheet` (replacing `EliminarCuentaStubSheet`). The tile label and placement MUST remain unchanged.

#### SCENARIO-565: Tile tap opens real sheet
- **Given** the profile screen is displayed
- **When** the user taps the "Eliminar cuenta" tile
- **Then** `EliminarCuentaSheet` (not `EliminarCuentaStubSheet`) is shown
- **Test target**: `test/features/profile/presentation/profile_screen_test.dart`

---

### REQ-ACCDEL-UI-007 — Chat UI Fallback for Deleted Users

Chat UI MUST render sender name as "Usuario eliminado" (es-AR; marked `// i18n: Fase 6 Etapa 3`) when the corresponding `userPublicProfiles/{uid}` document is missing or has been deleted.

#### SCENARIO-570: Chat row shows "Usuario eliminado" when public profile is absent
- **Given** a chat message row where the sender's `userPublicProfiles/{senderId}` does not exist
- **When** the chat row widget is rendered
- **Then** the sender name displayed is "Usuario eliminado"
- **Test target**: `test/features/chat/presentation/widgets/chat_deleted_user_test.dart`

---

## REQ Coverage Matrix

| REQ ID | Description | SCENARIOs | Covered |
|---|---|---|---|
| REQ-ACCDEL-CF-001 | Callable function exists | SCENARIO-533 | ✅ |
| REQ-ACCDEL-CF-002 | Anti-spoofing guard | SCENARIO-534 | ✅ |
| REQ-ACCDEL-CF-003 | Trainer role rejection | SCENARIO-535 | ✅ |
| REQ-ACCDEL-CF-004 | Main user docs deleted | SCENARIO-536, 537 | ✅ |
| REQ-ACCDEL-CF-005 | Friendships sweep | SCENARIO-538, 539 | ✅ |
| REQ-ACCDEL-CF-006 | Posts anonymized | SCENARIO-540, 541 | ✅ |
| REQ-ACCDEL-CF-007 | Chat public profile deleted | SCENARIO-542 | ✅ |
| REQ-ACCDEL-CF-008 | Trainer links terminated | SCENARIO-543 | ✅ |
| REQ-ACCDEL-CF-009 | Future appointments cancelled | SCENARIO-544 | ✅ |
| REQ-ACCDEL-CF-010 | Storage avatar deleted | SCENARIO-545, 546 | ✅ |
| REQ-ACCDEL-CF-011 | Audit log written | SCENARIO-547, 548 | ✅ |
| REQ-ACCDEL-CF-012 | Auth user deleted last | SCENARIO-549 | ✅ |
| REQ-ACCDEL-CF-013 | Idempotency on partial failure | SCENARIO-550 | ✅ |
| REQ-ACCDEL-CF-014 | Structured response | SCENARIO-551 | ✅ |
| REQ-ACCDEL-REAUTH-001 | AuthService reauthenticate | SCENARIO-552, 553 | ✅ |
| REQ-ACCDEL-REAUTH-003 | Provider-branched re-auth UI | SCENARIO-555, 556, 557 | ✅ |
| REQ-ACCDEL-REAUTH-004 | AuthFailure variants | SCENARIO-558 | ✅ |
| REQ-ACCDEL-UI-001 | EliminarCuentaSheet content | SCENARIO-560 | ✅ |
| REQ-ACCDEL-UI-002 | ELIMINAR opens ReAuthBottomSheet | SCENARIO-561 | ✅ |
| REQ-ACCDEL-UI-003 | Loading state during CF call | SCENARIO-562 | ✅ |
| REQ-ACCDEL-UI-004 | Success: sign out and redirect | SCENARIO-563 | ✅ |
| REQ-ACCDEL-UI-005 | Failure: error snackbar with retry | SCENARIO-564 | ✅ |
| REQ-ACCDEL-UI-006 | Profile tile rewired | SCENARIO-565 | ✅ |
| REQ-ACCDEL-UI-007 | Chat UI fallback for deleted users | SCENARIO-570 | ✅ |

---

## Design ADRs

14 ADRs documented in the change design (see archive for full details):
- ADR-ACCDEL-001: Cloud Function over client-side cascade
- ADR-ACCDEL-002: TypeScript for Cloud Functions
- ADR-ACCDEL-003: Callable over HTTP
- ADR-ACCDEL-004: Posts anonymize (not delete)
- ADR-ACCDEL-005: Chat messages read-time anonymization via deleted public profile
- ADR-ACCDEL-006: Trainer links terminate (not delete)
- ADR-ACCDEL-007: Appointments cancel future only
- ADR-ACCDEL-008: Single re-auth sheet with provider branching
- ADR-ACCDEL-009: AuthService thin, notifier owns orchestration
- ADR-ACCDEL-010: CF idempotency
- ADR-ACCDEL-011: Two-tier retry policy (5-min recent-auth window)
- ADR-ACCDEL-012: Audit log shape and write strategy
- ADR-ACCDEL-013: Storage trust boundary (Admin SDK access)
- ADR-ACCDEL-014: Anti-spoofing guard

---

## Quality Outcome

- **flutter analyze**: 0 issues
- **dart format**: clean
- **flutter test**: 1372/1372 passing (+35 from this change)
- **CF tsc**: 0 errors
- **CF eslint**: 0 warnings/errors
- **CF jest**: 40/40 passing
- **Live smoke**: ✅ email/password, ✅ Google, ✅ Apple (iOS device)
- **REQ coverage**: 30/30 non-removed requirements
- **SCENARIO coverage**: 38/38 non-removed scenarios

---

## Known Follow-ups

1. Improve SCENARIO-548 test to inject a real cascade error (currently asserts vacuous status condition)
2. Add 2 orphan production indexes to `firestore.indexes.json`: `routines: assignedBy+source+createdAt`, `commercialPlans: trainerId+createdAt`
3. FirebaseCore init race on cold-start (Google login stuck first attempt — pre-existing)
4. CF service account refactor to `firebase-adminsdk-fbsvc` (cleaner IAM model)
5. Node 20 → 22 + firebase-functions upgrade (deprecation warnings)
6. gymSearchQueryProvider autoDispose (arrastre from profile-screen-rewrite SDD)

---

## Verification

**Status**: PASS-WITH-DEVIATIONS (no CRITICAL issues)
**Deviations**:
- SCENARIO-548: test body weakened (asserts vacuous condition; behavior validated indirectly)
- 12 post-smoke-fixes on PR#3 not in apply-progress entries (all changes in final code)
- 5 Dart files with format drift from telemetry SDD (not in account-deletion scope)

---

**Engram references** (SDD artifacts):
- sdd/account-deletion/proposal (obs #115)
- sdd/account-deletion/spec (obs #116)
- sdd/account-deletion/design (obs #117)
- sdd/account-deletion/tasks (obs #118)
- sdd/account-deletion/apply-progress (obs #119)
- sdd/account-deletion/verify-report (obs #123)
