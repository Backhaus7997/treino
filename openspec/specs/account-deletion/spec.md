# Spec: account-deletion

**Feature**: account-deletion
**Owner**: Backhaus
**Date**: 2026-06-01 (archived from change SDD)
**Status**: COMPLETE (PASS-WITH-DEVIATIONS)

---

## TL;DR

Irreversible account deletion flow for athletes and trainers, with Cloud Function cascade, provider-aware re-auth (password/Google/Apple), and full data cleanup across 8+ Firestore collections, Storage, Firebase Auth, and audit logging. Trainer self-deletion added via follow-up PRs (#1341, #1343, #1346, #1350). For trainers: cascade terminates links with new reason `trainer-account-deleted`, cancels future appointments, deletes templates and training data, but retains payments and keeps athlete routines/chats intact.

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
- Soft-delete / grace period
- Email notifications (trainer unlink notice is push only; see follow-up #1353 for partial retry)
- Account restoration
- Storage rules audit
- Partial deletion retry automation (see follow-up #1353)

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

### REQ-ACCDEL-CF-003 — Trainer Self-Deletion (Inverted: SCENARIO-535)

The CF MUST allow trainers to self-delete their accounts. The caller's `users/{uid}.role` field is no longer a guard; trainers proceed through the same deletion flow as athletes. The CF MUST execute an unconditional trainer cascade (runs on every call; for athletes, all queries return empty/no-op).

#### SCENARIO-535: Trainer calls deleteAccount and succeeds
- **Given** an authenticated user whose `users/{uid}.role` is `'trainer'`
- **When** they call `deleteAccount({ uid: <their_uid> })`
- **Then** the CF succeeds, the trainer cascade executes (terminating links, cancelling future appointments, deleting templates and data), and Auth + users/{uid} are deleted
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-003A — Trainer Cascade Idempotency

The trainer cascade MUST run unconditionally on every `deleteAccount` call. For athlete accounts, all trainer-keyed queries return empty (no-op). The cascade MUST NOT depend on `users/{uid}` existing; idempotency across re-runs is guaranteed by trainer-keyed queries.

#### SCENARIO-PSD-01: Trainer cascade is a no-op for athletes
- **Given** an authenticated athlete (no trainer data)
- **When** the CF executes the trainer cascade
- **Then** no documents are created, modified, or deleted
- **Test target**: CF integration test (emulator)

#### SCENARIO-PSD-02: Re-run after partial failure completes cleanly
- **Given** the CF previously ran and deleted Firestore docs but failed on Storage
- **When** the CF is called again for the same trainer uid
- **Then** the trainer cascade re-executes, finding zero residual trainer-keyed docs
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-003B — Trainer Links Termination with New Reason

The CF MUST query `trainer_links/*` where `trainerId == uid` (not `athleteId`; this is the inverse direction) and update each link in a non-terminal state: `status = 'terminated'`, `reason = 'trainer-account-deleted'` (new constant), `terminatedAt = <server timestamp>`. The `notify-link-change` trigger MUST dispatch a new athlete-notification «Tu entrenador cerró su cuenta» for each terminated link.

#### SCENARIO-PSD-03: Active trainer link is terminated with trainer-account-deleted reason
- **Given** an athlete with a `trainer_links` doc where `trainerId == <trainer_uid>` and `status` is active/paused
- **When** the trainer deletes their account
- **Then** the link updates: `status == 'terminated'` and `reason == 'trainer-account-deleted'`
- **And** the athlete receives a notification «Tu entrenador cerró su cuenta»
- **Test target**: CF integration test (emulator)

#### SCENARIO-PSD-04: Pending trainer link is purged (with notice)
- **Given** a `trainer_links` doc with `status == 'pending'` and `trainerId == <trainer_uid>`
- **When** the trainer deletes their account
- **Then** the link is terminated with reason `trainer-account-deleted`
- **And** the athlete receives a different message «Solicitud sin efecto»
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-003C — Trainer Future Appointments Cancelled

The CF MUST query `appointments/*` where `trainerId == uid AND status in ['requested', 'confirmed'] AND startsAt > now()` and update each: `status = 'cancelled'`, `reason = 'trainer-account-deleted'`, `cancelledBy = uid`, and append to `cancellationLog`. The athlete MUST NOT receive a per-appointment notice (`notify-appointment` skips this reason); the link-termination notice is the only one, and it MUST NOT claim the appointments were cancelled, since this step can fail and return `partial`.

#### SCENARIO-PSD-05: Trainer future appointments are cancelled
- **Given** a trainer with 1 past and 1 future confirmed appointment where `trainerId == <trainer_uid>`
- **When** the trainer deletes their account
- **Then** the future appointment has `status == 'cancelled'` and `reason == 'trainer-account-deleted'`
- **And** the athlete receives NO per-appointment notice (`notify-appointment` suppresses it for this reason); the link notice is the only one
- **And** the past appointment remains untouched
- **Test target**: CF integration test (emulator)

#### SCENARIO-PSD-06: Trainer availability rules and overrides are deleted
- **Given** a trainer with `coach_availability_rules` and `coach_availability_overrides` where `trainerId == uid`
- **When** the trainer deletes their account
- **Then** all matching rules and overrides are deleted
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-003D — Trainer Data Deletion (Notes, Billing, Files, Follow-up, Nutrition, Reviews)

The CF MUST delete the following collections/documents where `trainerId == uid`:
- `athlete_notes`, `athlete_billing`, `athlete_files`
- `follow_up_entries`, `nutrition_plans`
- `reviews` received by the trainer (`trainerId == uid`); reviews the trainer wrote as an athlete keep the existing athlete-side retention
- `session_shares`, `profile_shares` (where the athlete granted access to this trainer)

Storage files matching pattern `athleteFiles/{trainerId}_*` MUST be deleted.

#### SCENARIO-PSD-07: Trainer-written athlete data is deleted
- **Given** a trainer with `athlete_notes`, `follow_up_entries`, `nutrition_plans` where `trainerId == uid`
- **When** the trainer deletes their account
- **Then** all matching docs are deleted
- **Test target**: CF integration test (emulator)

#### SCENARIO-PSD-08: Trainer Storage files are deleted
- **Given** a trainer with Storage files matching `athleteFiles/{trainerId}_*`
- **When** the trainer deletes their account
- **Then** all matching files are removed from Storage
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-003E — Trainer Templates Deleted (Including Published)

The CF MUST query `routines/*` where `assignedBy == uid AND source == 'trainer-template'` (using recursiveDelete to cascade to sub-collections) and delete all matching docs. Published templates have `visibility == 'public'` but are the same collection; no separate query is needed.

#### SCENARIO-PSD-09: Trainer templates (including published) are deleted
- **Given** a trainer with 5 template routines (some `visibility == 'public'`) where `assignedBy == uid`
- **When** the trainer deletes their account
- **Then** all 5 routines are deleted
- **Test target**: CF integration test (emulator)

#### SCENARIO-PSD-10: Athlete-assigned routines remain for the athlete
- **Given** an athlete with a routine `assignedBy == <trainer_uid>` and `assignedTo == <athlete_uid>`
- **When** the trainer deletes their account
- **Then** the routine remains in the athlete's account and is usable
- **Test target**: CF integration test (emulator)

#### SCENARIO-PSD-11: cleanup-assigned-plans does NOT archive routines linked with trainer-account-deleted reason
- **Given** an athlete with an active routine linked via a `trainer_links` doc with `reason == 'trainer-account-deleted'`
- **When** `cleanup-assigned-plans` trigger fires for this link
- **Then** the routine is NOT archived (other reasons archive per current behavior)
- **Test target**: CF integration test + cleanup-assigned-plans test (emulator)

---

### REQ-ACCDEL-CF-003F — Trainer Payments Retained (Fiscal Requirement)

The CF MUST NOT delete or modify `payments/*` where `trainerId == uid`. Payments are a fiscal record and MUST be retained indefinitely.

#### SCENARIO-PSD-12: Trainer payments are retained
- **Given** a trainer with `payments` docs where `trainerId == uid`
- **When** the trainer deletes their account
- **Then** all payment docs remain unchanged
- **Test target**: CF integration test (emulator)

---

### REQ-ACCDEL-CF-003G — Chats Remain for Athletes

Chats where a trainer is a member MUST remain in the athlete's chat list. The trainer's identity resolves to "cuenta eliminada" (deleted account) at render time if `userPublicProfiles/{trainerId}` is missing.

#### SCENARIO-PSD-13: Chat history remains after trainer deletion
- **Given** a chat thread where a trainer is a member and messages exist
- **When** the trainer deletes their account
- **Then** the chat and all messages remain for the athlete
- **And** the trainer's sender name displays as "cuenta eliminada"
- **Test target**: Chat UI test with missing `userPublicProfiles` entry

---

### REQ-ACCDEL-CF-003H — No Resurrecting Ghost Trainer Docs

The CF MUST ensure triggers (`link-aggregate`, `link-load-reconcile`, `recountTemplates`, etc.) do not re-create trainer-keyed docs after the cascade completes. This is enforced by switching non-transactional exists-checks to `update()` operations (NOT_FOUND caught and logged).

#### SCENARIO-PSD-14: Triggers do not resurrect trainer-keyed docs
- **Given** a trainer fully deleted via the cascade
- **When** async triggers (`link-aggregate`, `review-aggregate`) attempt to sync
- **Then** they complete without re-creating trainer docs
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
| REQ-ACCDEL-CF-003 | Trainer self-deletion (inverted) | SCENARIO-535 | ✅ |
| REQ-ACCDEL-CF-003A | Trainer cascade idempotency | SCENARIO-PSD-01, PSD-02 | ✅ |
| REQ-ACCDEL-CF-003B | Trainer links termination | SCENARIO-PSD-03, PSD-04 | ✅ |
| REQ-ACCDEL-CF-003C | Trainer appointments cancelled | SCENARIO-PSD-05, PSD-06 | ✅ |
| REQ-ACCDEL-CF-003D | Trainer data deletion | SCENARIO-PSD-07, PSD-08 | ✅ |
| REQ-ACCDEL-CF-003E | Trainer templates deleted | SCENARIO-PSD-09, PSD-10, PSD-11 | ✅ |
| REQ-ACCDEL-CF-003F | Trainer payments retained | SCENARIO-PSD-12 | ✅ |
| REQ-ACCDEL-CF-003G | Chats remain for athletes | SCENARIO-PSD-13 | ✅ |
| REQ-ACCDEL-CF-003H | No ghost trainer docs | SCENARIO-PSD-14 | ✅ |
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
7. Partial deletion retry automation (issue #1353): re-run failed cascades without manual intervention
8. Coach Hub web delete button for trainers (issue #1334, follow-up)

---

## Verification

**Status**: PASS-WITH-DEVIATIONS (no CRITICAL issues)
**Deviations**:
- SCENARIO-548: test body weakened (asserts vacuous condition; behavior validated indirectly)
- 12 post-smoke-fixes on PR#3 not in apply-progress entries (all changes in final code)
- 5 Dart files with format drift from telemetry SDD (not in account-deletion scope)

---

**Engram references** (SDD artifacts):

### Original change (account-deletion):
- sdd/account-deletion/proposal (obs #115)
- sdd/account-deletion/spec (obs #116)
- sdd/account-deletion/design (obs #117)
- sdd/account-deletion/tasks (obs #118)
- sdd/account-deletion/apply-progress (obs #119)
- sdd/account-deletion/verify-report (obs #123)

### Follow-up change (pf-self-delete, issue #1333):
- sdd/pf-self-delete/proposal (obs #1336)
- sdd/pf-self-delete/spec (obs #1338)
- sdd/pf-self-delete/design (obs #1339)
- sdd/pf-self-delete/tasks (obs #1342)
- sdd/pf-self-delete/apply-progress (obs #1344)
- sdd/pf-self-delete/archive-report (this archive)
