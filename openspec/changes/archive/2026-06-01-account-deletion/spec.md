# Spec: account-deletion

**Change**: account-deletion
**Owner**: Backhaus
**Date**: 2026-05-28
**Artifact store**: hybrid (file + Engram `sdd/account-deletion/spec`)
**Proposal ref**: `openspec/changes/account-deletion/proposal.md`
**Scenario range**: SCENARIO-533..569

---

## Overview

Three new capabilities delivered across 3 chained PRs:
1. `cloud-functions-infra` — Firebase Functions bootstrap (PR#1)
2. `account-deletion` — CF full cascade (PR#2) + Flutter UI/orchestration (PR#3)
3. `auth-reauthentication` — provider-aware re-auth helpers (PR#3)

All capabilities are NEW — no existing specs to delta.

---

## Requirements

### REQ-ACCDEL-CF-001 — Callable Function Exists

The Cloud Function MUST be a Firebase Callable Function named `deleteAccount`, deployed to the `treino-dev` project, running on Node 20 with TypeScript.

#### SCENARIO-533: CF is callable by authenticated client
- **Given** an authenticated athlete with a valid Firebase ID token
- **When** the client invokes the `deleteAccount` callable with `{ uid: <caller_uid> }`
- **Then** the CF executes without a `permission-denied` or `not-found` error
- **Test target**: CF integration test (emulator)
- **REQ**: REQ-ACCDEL-CF-001

---

### REQ-ACCDEL-CF-002 — Anti-Spoofing Guard

The CF MUST verify `context.auth.uid === data.uid`. If they differ, MUST throw `HttpsError('permission-denied', 'uid mismatch')`.

#### SCENARIO-534: Caller spoofs another user's uid
- **Given** an authenticated athlete with uid `A`
- **When** they call `deleteAccount({ uid: 'B' })`
- **Then** the CF throws `HttpsError` with code `permission-denied`
- **Test target**: CF integration test (emulator)
- **REQ**: REQ-ACCDEL-CF-002

---

### REQ-ACCDEL-CF-003 — Trainer Role Rejection

The CF MUST read the caller's `users/{uid}.role` field. If `role === 'trainer'`, MUST throw `HttpsError('permission-denied', 'trainers cannot self-delete')`.

#### SCENARIO-535: Trainer calls deleteAccount
- **Given** an authenticated user whose `users/{uid}.role` is `'trainer'`
- **When** they call `deleteAccount({ uid: <their_uid> })`
- **Then** the CF throws `HttpsError` with code `permission-denied`
- **And** no data is modified
- **Test target**: CF integration test (emulator)
- **REQ**: REQ-ACCDEL-CF-003

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
- **REQ**: REQ-ACCDEL-CF-004

#### SCENARIO-537: trainerPublicProfiles deletion is no-op when absent
- **Given** an athlete who has no `trainerPublicProfiles/{uid}` document
- **When** the CF runs
- **Then** the CF does not throw an error for the missing document
- **And** all other deletions proceed
- **Test target**: CF integration test (emulator)
- **REQ**: REQ-ACCDEL-CF-004

---

### REQ-ACCDEL-CF-005 — Friendships Sweep

The CF MUST delete all documents in `friendships/*` where `members` array contains `uid`.

#### SCENARIO-538: Friendship documents are swept
- **Given** a seeded athlete with 3 friendship docs (as member on both sides)
- **When** the CF completes
- **Then** all 3 friendship docs are deleted from Firestore
- **Test target**: CF integration test (emulator)
- **REQ**: REQ-ACCDEL-CF-005

#### SCENARIO-539: No friendships is a no-op
- **Given** an athlete with zero friendship docs
- **When** the CF runs
- **Then** no error is thrown during the friendship sweep step
- **Test target**: CF integration test (emulator)
- **REQ**: REQ-ACCDEL-CF-005

---

### REQ-ACCDEL-CF-006 — Posts Anonymized

The CF MUST query `posts/*` where `authorUid == uid` and for each matching doc set `authorDisplayName = 'Usuario eliminado'` and `authorAvatarUrl = null`. The `authorUid` field MUST remain unchanged.

#### SCENARIO-540: Post author is anonymized
- **Given** an athlete who authored 2 posts
- **When** the CF completes
- **Then** both post docs have `authorDisplayName == 'Usuario eliminado'`
- **And** `authorAvatarUrl == null`
- **And** `authorUid` still equals the deleted uid
- **Test target**: CF integration test (emulator)
- **REQ**: REQ-ACCDEL-CF-006

#### SCENARIO-541: No posts authored is a no-op
- **Given** an athlete with zero posts
- **When** the CF runs
- **Then** no error is thrown during the posts anonymization step
- **Test target**: CF integration test (emulator)
- **REQ**: REQ-ACCDEL-CF-006

---

### REQ-ACCDEL-CF-007 — Chat Public Profile Deleted for Read-Time Anonymization

> **REVISED 2026-05-28** (ADR-ACCDEL-005): ~~The CF MUST query `chats/{chatId}/messages/*` where sender uid matches and update `senderDisplayName = 'Usuario eliminado'`. Chats themselves MUST NOT be deleted. Messages MUST NOT be deleted.~~
>
> CF MUST delete `userPublicProfiles/{uid}` so chat UI renders deleted users as "Usuario eliminado" via read-time fallback. Messages are immutable per `firestore.rules` — CF does NOT mutate them. The `Message` Freezed model has no `senderDisplayName` field; sender names are resolved at render time from `userPublicProfiles/{senderId}`.

#### SCENARIO-542: Chat UI renders "Usuario eliminado" when sender's public profile is missing
> **REVISED 2026-05-28** (ADR-ACCDEL-005): ~~CF integration test for message mutation~~ → chat UI integration test:
- **Given** a chat thread containing a message from a user whose `userPublicProfiles/{uid}` document has been deleted
- **When** the chat screen is mounted and the message row is rendered
- **Then** the displayed sender name is "Usuario eliminado"
- **And** the chat thread itself still exists and other messages are unaffected
- **Test target**: Widget test — mount chat row with missing `userPublicProfiles` entry and assert fallback display name (see SCENARIO-570 for the dedicated widget test)
- **REQ**: REQ-ACCDEL-CF-007

---

### REQ-ACCDEL-CF-008 — Trainer Links Terminated

The CF MUST query `trainer_links/*` where `athleteId == uid` and update each doc: `status = 'terminated'`, `reason = 'account-deleted'`, `terminatedAt = <server timestamp>`.

#### SCENARIO-543: Active trainer link is terminated
- **Given** an athlete with an active `trainer_links` doc
- **When** the CF completes
- **Then** the doc has `status == 'terminated'`
- **And** `reason == 'account-deleted'`
- **And** `terminatedAt` is set to a server timestamp
- **Test target**: CF integration test (emulator)
- **REQ**: REQ-ACCDEL-CF-008

---

### REQ-ACCDEL-CF-009 — Future Appointments Cancelled

The CF MUST query `appointments/*` where `athleteId == uid AND scheduledAt > now()` and update each: `status = 'cancelled'`, `reason = 'athlete-account-deleted'`. Past appointments MUST remain untouched.

#### SCENARIO-544: Future appointment is cancelled
- **Given** an athlete with 1 past appointment and 1 future appointment
- **When** the CF completes
- **Then** the future appointment has `status == 'cancelled'` and `reason == 'athlete-account-deleted'`
- **And** the past appointment is unchanged
- **Test target**: CF integration test (emulator)
- **REQ**: REQ-ACCDEL-CF-009

---

### REQ-ACCDEL-CF-010 — Storage Avatar Deleted

The CF MUST attempt to delete `avatars/{uid}.jpg` from Firebase Storage. If the file does not exist, the CF MUST treat this as a no-op (no error thrown).

#### SCENARIO-545: Avatar file deleted when it exists
- **Given** an athlete whose avatar file exists at `avatars/{uid}.jpg`
- **When** the CF completes
- **Then** the file no longer exists in Storage
- **Test target**: CF integration test (emulator)
- **REQ**: REQ-ACCDEL-CF-010

#### SCENARIO-546: Missing avatar file is a no-op
- **Given** an athlete with no avatar file in Storage
- **When** the CF runs
- **Then** no error is thrown for the missing file
- **Test target**: CF integration test (emulator)
- **REQ**: REQ-ACCDEL-CF-010

---

### REQ-ACCDEL-CF-011 — Audit Log Written

The CF MUST write `audit_log/{uid}` with at minimum: `deletedAt` (server timestamp), `provider` (sign-in provider string), `status` (`'success'` | `'partial'` | `'failed'`). The CF MUST write `status: 'started'` at CF entry and update to final status at end.

#### SCENARIO-547: Audit log records successful deletion
- **Given** a successful CF run for an athlete
- **When** the CF completes
- **Then** `audit_log/{uid}` exists with `status == 'success'` and `deletedAt` set
- **Test target**: CF integration test (emulator)
- **REQ**: REQ-ACCDEL-CF-011

#### SCENARIO-548: Audit log records partial failure
- **Given** the CF succeeds on Firestore steps but fails on Storage deletion
- **When** the CF completes with partial success
- **Then** `audit_log/{uid}` has `status == 'partial'` and `failedStep` indicating the step
- **Test target**: CF integration test (emulator)
- **REQ**: REQ-ACCDEL-CF-011

---

### REQ-ACCDEL-CF-012 — Auth User Deleted Last

The CF MUST call `admin.auth().deleteUser(uid)` as the final step, after all Firestore and Storage cleanup has completed.

#### SCENARIO-549: Auth user record is absent after CF success
- **Given** a successful CF run
- **When** the CF completes
- **Then** `admin.auth().getUser(uid)` throws a `user-not-found` error
- **Test target**: CF integration test (emulator)
- **REQ**: REQ-ACCDEL-CF-012

---

### REQ-ACCDEL-CF-013 — Idempotency on Partial Failure

If the CF is re-called after a partial failure (e.g., Storage deletion failed), it MUST resume from the failed step without duplicating completed steps or throwing on already-deleted documents.

#### SCENARIO-550: Re-call after partial failure completes cleanly
- **Given** the CF previously ran and deleted Firestore docs but failed on Storage
- **When** the CF is called again for the same uid
- **Then** it completes without error on already-deleted Firestore docs (no-op)
- **And** retries the Storage deletion successfully
- **Test target**: CF integration test (emulator)
- **REQ**: REQ-ACCDEL-CF-013

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
- **REQ**: REQ-ACCDEL-CF-014

---

### REQ-ACCDEL-REAUTH-001 — AuthService reauthenticate Method

`AuthService` MUST expose a `reauthenticate(AuthCredential credential)` method that calls `FirebaseAuth.instance.currentUser!.reauthenticateWithCredential(credential)`.

#### SCENARIO-552: reauthenticate succeeds with valid credential
- **Given** an authenticated user with a valid password credential
- **When** `AuthService.reauthenticate(credential)` is called
- **Then** it returns without throwing and the user's token is refreshed
- **Test target**: `test/features/auth/data/auth_service_test.dart`
- **REQ**: REQ-ACCDEL-REAUTH-001

#### SCENARIO-553: reauthenticate fails with wrong password
- **Given** an authenticated user with a wrong-password credential
- **When** `AuthService.reauthenticate(credential)` is called
- **Then** it throws or returns a failure carrying the `reAuthFailed` variant
- **Test target**: `test/features/auth/data/auth_service_test.dart`
- **REQ**: REQ-ACCDEL-REAUTH-001

---

### REQ-ACCDEL-REAUTH-002 — AuthService deleteAccount Orchestration

`AuthService` MUST expose a `deleteAccount()` method that orchestrates: detect provider → obtain re-auth credential → call `reauthenticate` → call CF `deleteAccount` → handle CF response.

#### SCENARIO-554: deleteAccount orchestrates all steps in order
- **Given** a mocked auth service and a mocked CF callable
- **When** `deleteAccount()` is called
- **Then** `reauthenticate` is called before the CF callable
- **And** `signOut` is called after CF success
- **Test target**: `test/features/auth/application/account_deletion_notifier_test.dart`
- **REQ**: REQ-ACCDEL-REAUTH-002

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
- **And** no Google or Apple button is shown
- **Test target**: `test/features/profile/presentation/re_auth_bottom_sheet_test.dart`
- **REQ**: REQ-ACCDEL-REAUTH-003

#### SCENARIO-556: Google provider triggers Google re-auth
- **Given** a user whose provider is `'google.com'`
- **When** `ReAuthBottomSheet` is opened and the user confirms
- **Then** the Google Sign-In flow is triggered
- **Test target**: `test/features/profile/presentation/re_auth_bottom_sheet_test.dart`
- **REQ**: REQ-ACCDEL-REAUTH-003

#### SCENARIO-557: Apple provider triggers Apple re-auth
- **Given** a user whose provider is `'apple.com'`
- **When** `ReAuthBottomSheet` is opened and the user confirms
- **Then** the Apple Sign-In flow is triggered
- **Test target**: `test/features/profile/presentation/re_auth_bottom_sheet_test.dart`
- **REQ**: REQ-ACCDEL-REAUTH-003

---

### REQ-ACCDEL-REAUTH-004 — AuthFailure Variants

`AuthFailure` MUST include three new variants: `requiresRecentLogin`, `reAuthFailed`, and `deletionFailed`. Each variant MUST be surfaced through the notifier as an `AsyncError` state.

#### SCENARIO-558: requiresRecentLogin variant surfaced
- **Given** the CF returns a `requires-recent-login` error
- **When** `AccountDeletionNotifier` processes the error
- **Then** the notifier state is `AsyncError` carrying `AuthFailure.requiresRecentLogin`
- **Test target**: `test/features/auth/application/account_deletion_notifier_test.dart`
- **REQ**: REQ-ACCDEL-REAUTH-004

---

### REQ-ACCDEL-REAUTH-005 — Cancelled Re-auth Does Not Invoke CF

If the user dismisses the `ReAuthBottomSheet` without completing re-auth, the CF MUST NOT be called.

#### SCENARIO-559: Dismissing re-auth sheet aborts the flow
- **Given** the user opened `ReAuthBottomSheet` and then dismissed it
- **When** the sheet is closed
- **Then** `AccountDeletionService.call()` is never invoked
- **And** the profile screen remains visible
- **Test target**: `test/features/profile/presentation/re_auth_bottom_sheet_test.dart`
- **REQ**: REQ-ACCDEL-REAUTH-005

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
- **And** both "CANCELAR" and "ELIMINAR" buttons are present
- **Test target**: `test/features/profile/presentation/eliminar_cuenta_sheet_test.dart`
- **REQ**: REQ-ACCDEL-UI-001

---

### REQ-ACCDEL-UI-002 — ELIMINAR Opens ReAuthBottomSheet

Tapping "ELIMINAR" in `EliminarCuentaSheet` MUST close the confirmation sheet and open `ReAuthBottomSheet`.

#### SCENARIO-561: ELIMINAR button transitions to re-auth sheet
- **Given** `EliminarCuentaSheet` is open
- **When** the user taps "ELIMINAR"
- **Then** `EliminarCuentaSheet` is dismissed
- **And** `ReAuthBottomSheet` is shown
- **Test target**: `test/features/profile/presentation/eliminar_cuenta_sheet_test.dart`
- **REQ**: REQ-ACCDEL-UI-002

---

### REQ-ACCDEL-UI-003 — Loading State During CF Call

While the CF call is in-flight, the UI MUST show a loading state (full-screen overlay or in-sheet spinner). The "ELIMINAR" button MUST be disabled during this period.

#### SCENARIO-562: Loading indicator visible during CF call
- **Given** re-auth completed and the CF call is in-flight
- **When** `AccountDeletionNotifier` state is `AsyncLoading`
- **Then** a loading indicator is visible and the "ELIMINAR" button is disabled
- **Test target**: `test/features/profile/presentation/eliminar_cuenta_sheet_test.dart`
- **REQ**: REQ-ACCDEL-UI-003

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
- **REQ**: REQ-ACCDEL-UI-004

---

### REQ-ACCDEL-UI-005 — Failure: Error Snackbar with Retry

On CF failure the app MUST show an error SnackBar with a "Reintentar" action button. The user MUST be able to retry without reopening the confirmation sheet.

#### SCENARIO-564: CF failure shows error snackbar with retry
- **Given** the CF call throws an error
- **When** `AccountDeletionNotifier` processes the error
- **Then** a SnackBar is shown with an error message and a "Reintentar" button
- **And** tapping "Reintentar" retries the CF call
- **Test target**: `test/features/profile/presentation/eliminar_cuenta_sheet_test.dart`
- **REQ**: REQ-ACCDEL-UI-005

---

### REQ-ACCDEL-UI-006 — Profile Tile Rewired

The "Eliminar cuenta" profile tile in `ProfileScreen` MUST open the real `EliminarCuentaSheet` (replacing `EliminarCuentaStubSheet`). The tile label and placement MUST remain unchanged.

#### SCENARIO-565: Tile tap opens real sheet
- **Given** the profile screen is displayed
- **When** the user taps the "Eliminar cuenta" tile
- **Then** `EliminarCuentaSheet` (not `EliminarCuentaStubSheet`) is shown
- **Test target**: `test/features/profile/presentation/profile_screen_test.dart`
- **REQ**: REQ-ACCDEL-UI-006

---

### REQ-ACCDEL-UI-007 — Chat UI Fallback for Deleted Users

> **ADDED 2026-05-28** (ADR-ACCDEL-005 resolution)

Chat UI MUST render sender name as "Usuario eliminado" (es-AR; marked `// i18n: Fase 6 Etapa 3`) when the corresponding `userPublicProfiles/{uid}` document is missing or has been deleted.

#### SCENARIO-570: Chat row shows "Usuario eliminado" when public profile is absent
- **Given** a chat message row where the sender's `userPublicProfiles/{senderId}` does not exist
- **When** the chat row widget is rendered
- **Then** the sender name displayed is "Usuario eliminado"
- **And** no error or exception is thrown
- **Test target**: `test/features/chat/presentation/widgets/chat_message_row_test.dart` — widget test pumping a `ChatMessageRow` (or equivalent) with a mocked empty `userPublicProfiles` stream, asserting text "Usuario eliminado" is found.
- **REQ**: REQ-ACCDEL-UI-007

---

### REQ-ACCDEL-CX-001 — Strict TDD

Every implementation commit for this change MUST be preceded by a RED test commit demonstrating the failing test. Tests MUST turn GREEN in the subsequent implementation commit.

#### SCENARIO-566: RED commit precedes GREEN commit in git log
- **Given** a task pair from the tasks list
- **When** reviewing the git log
- **Then** the test file commit appears before the implementation commit
- **Test target**: git log (manual review at PR time)
- **REQ**: REQ-ACCDEL-CX-001

---

### REQ-ACCDEL-CX-002 — CF Integration Tests via Emulator

All CF integration tests MUST run against the Firebase Local Emulator Suite (Firestore + Auth + Storage emulators) or a dedicated test project. Tests MUST NOT run against the production Firestore or live Storage.

#### SCENARIO-567: CF tests pass against emulator
- **Given** the emulator suite is running locally
- **When** `npm test` is executed inside `functions/`
- **Then** all CF integration tests pass without connecting to production Firebase
- **Test target**: `functions/src/__tests__/deleteAccount.test.ts`
- **REQ**: REQ-ACCDEL-CX-002

---

### REQ-ACCDEL-CX-003 — Client-Side Test Coverage

All new Flutter code (providers, notifiers, widgets) MUST be covered by Riverpod provider tests and widget tests using `ProviderScope` overrides and `mocktail` mocks.

#### SCENARIO-568: Provider tests cover AccountDeletionNotifier
- **Given** a mocked `AccountDeletionService` and mocked `AuthService`
- **When** `AccountDeletionNotifier` actions are exercised in tests
- **Then** all state transitions (loading, success, error variants) are covered
- **Test target**: `test/features/auth/application/account_deletion_notifier_test.dart`
- **REQ**: REQ-ACCDEL-CX-003

---

### REQ-ACCDEL-CX-004 — Commit and Attribution Conventions

All commits MUST follow conventional commits format. MUST NOT include `Co-Authored-By` or any AI attribution. Each PR diff MUST remain within the 400-line budget (no `size:exception` anticipated).

#### SCENARIO-569: PR diff stays within 400-line budget
- **Given** any one of the 3 PRs in this change
- **When** the PR diff is computed on GitHub
- **Then** additions + deletions total ≤ 400 lines
- **Test target**: GitHub PR diff (manual check at PR time)
- **REQ**: REQ-ACCDEL-CX-004

---

## REQ Coverage Matrix

| REQ ID | Description | SCENARIOs | PR |
|---|---|---|---|
| REQ-ACCDEL-CF-001 | Callable function exists | SCENARIO-533 | PR#1 |
| REQ-ACCDEL-CF-002 | Anti-spoofing guard | SCENARIO-534 | PR#1 |
| REQ-ACCDEL-CF-003 | Trainer role rejection | SCENARIO-535 | PR#2 |
| REQ-ACCDEL-CF-004 | Main user docs deleted | SCENARIO-536, 537 | PR#2 |
| REQ-ACCDEL-CF-005 | Friendships sweep | SCENARIO-538, 539 | PR#2 |
| REQ-ACCDEL-CF-006 | Posts anonymized | SCENARIO-540, 541 | PR#2 |
| REQ-ACCDEL-CF-007 | ~~Chat messages anonymized~~ → Public profile deleted for read-time chat anonymization | SCENARIO-542 | PR#2 |
| REQ-ACCDEL-CF-008 | Trainer links terminated | SCENARIO-543 | PR#2 |
| REQ-ACCDEL-CF-009 | Future appointments cancelled | SCENARIO-544 | PR#2 |
| REQ-ACCDEL-CF-010 | Storage avatar deleted | SCENARIO-545, 546 | PR#2 |
| REQ-ACCDEL-CF-011 | Audit log written | SCENARIO-547, 548 | PR#1+PR#2 |
| REQ-ACCDEL-CF-012 | Auth user deleted last | SCENARIO-549 | PR#1 |
| REQ-ACCDEL-CF-013 | Idempotency on partial failure | SCENARIO-550 | PR#2 |
| REQ-ACCDEL-CF-014 | Structured response | SCENARIO-551 | PR#1+PR#2 |
| REQ-ACCDEL-REAUTH-001 | AuthService reauthenticate method | SCENARIO-552, 553 | PR#3 |
| REQ-ACCDEL-REAUTH-002 | AuthService deleteAccount orchestration | SCENARIO-554 | PR#3 |
| REQ-ACCDEL-REAUTH-003 | Provider-branched re-auth UI | SCENARIO-555, 556, 557 | PR#3 |
| REQ-ACCDEL-REAUTH-004 | AuthFailure variants | SCENARIO-558 | PR#3 |
| REQ-ACCDEL-REAUTH-005 | Cancelled re-auth does not invoke CF | SCENARIO-559 | PR#3 |
| REQ-ACCDEL-UI-001 | EliminarCuentaSheet content | SCENARIO-560 | PR#3 |
| REQ-ACCDEL-UI-002 | ELIMINAR opens ReAuthBottomSheet | SCENARIO-561 | PR#3 |
| REQ-ACCDEL-UI-003 | Loading state during CF call | SCENARIO-562 | PR#3 |
| REQ-ACCDEL-UI-004 | Success: sign out and redirect | SCENARIO-563 | PR#3 |
| REQ-ACCDEL-UI-005 | Failure: error snackbar with retry | SCENARIO-564 | PR#3 |
| REQ-ACCDEL-UI-006 | Profile tile rewired | SCENARIO-565 | PR#3 |
| REQ-ACCDEL-UI-007 | Chat UI fallback for deleted users | SCENARIO-570 | PR#3 |
| REQ-ACCDEL-CX-001 | Strict TDD | SCENARIO-566 | all PRs |
| REQ-ACCDEL-CX-002 | CF integration tests via emulator | SCENARIO-567 | PR#2 |
| REQ-ACCDEL-CX-003 | Client-side test coverage | SCENARIO-568 | PR#3 |
| REQ-ACCDEL-CX-004 | Commit and attribution conventions | SCENARIO-569 | all PRs |

---

## PR Distribution Summary

| PR | REQs in scope |
|---|---|
| PR#1 — CF bootstrap | REQ-ACCDEL-CF-001, CF-002, CF-011 (started entry), CF-012, CF-014 (minimal) |
| PR#2 — Full cascade | REQ-ACCDEL-CF-003, CF-004, CF-005, CF-006, CF-007, CF-008, CF-009, CF-010, CF-011 (final update), CF-013, CF-014 (full), CX-002 |
| PR#3 — Flutter UI | REQ-ACCDEL-REAUTH-001, REAUTH-002, REAUTH-003, REAUTH-004, REAUTH-005, UI-001, UI-002, UI-003, UI-004, UI-005, UI-006, UI-007, CX-003 |
| All PRs | REQ-ACCDEL-CX-001, CX-004 |

---

## Out of Scope (Explicit)

- Pre-delete data export
- Trainer self-deletion (CF REJECTS trainers — REQ-ACCDEL-CF-003)
- Soft delete / grace period
- Email notification post-deletion
- Account restoration
- Storage rules audit
- Routines owned by deleted athlete (out of scope — no rules change)
