# Design: account-deletion

**Change**: account-deletion
**Owner**: Backhaus
**Date**: 2026-05-28
**Artifact store**: hybrid (file + Engram `sdd/account-deletion/design`)
**Proposal ref**: `openspec/changes/account-deletion/proposal.md`
**Spec ref**: `openspec/changes/account-deletion/spec.md`

---

## 1. TL;DR

We implement athlete account deletion as a **Cloud Function Cascade** with **provider-aware re-auth**, delivered in **3 chained PRs**. Stack: Firebase Functions on Node 20 (TypeScript) using the Admin SDK; the Flutter client uses the `cloud_functions` package to invoke a callable named `deleteAccount`. UI orchestration lives in a Riverpod `AsyncNotifier`; the existing `AuthService` only gains thin wrappers (`reauthenticate`, per-provider credential helpers) and remains free of UI state. The CF is **idempotent**, anti-spoofing guarded, role-guarded, and writes an `audit_log/{uid}` for support and post-incident recovery. PR sizes target ≤ 400 LOC each (no `size:exception` planned).

---

## 2. Architecture Overview

### High-level flow

```
ProfileScreen
   │ tap "Eliminar cuenta"
   ▼
EliminarCuentaSheet (confirmation, destructive copy)
   │ tap ELIMINAR
   ▼
ReAuthBottomSheet (branches on user.providerData[0].providerId)
   │     │     │
   │ password   google.com   apple.com
   │     │     │
   ▼     ▼     ▼
AuthService.reauthenticate(credential)        ← thin wrapper around Firebase
   │ success
   ▼
AccountDeletionNotifier (AsyncNotifier<void>)
   │ state transitions: idle → awaitingReAuth → deleting → success | error
   ▼
AccountDeletionService.deleteAccount()
   │ wraps cloud_functions callable
   ▼
   ┌───────────────────────────────────────────────────────────┐
   │  Firebase Cloud Function deleteAccount (callable, TS)     │
   │                                                           │
   │  1. Verify context.auth.uid === data.uid    (anti-spoof)  │
   │  2. Read users/{uid}.role; reject if 'trainer'            │
   │  3. audit_log/{uid} ← { status: 'started', ... }          │
   │  4. recursiveDelete(users/{uid})  ← sub-collections too   │
   │  5. delete userPublicProfiles/{uid}  (ignoreNotFound)     │
   │  6. delete trainerPublicProfiles/{uid} (ignoreNotFound)   │
   │  7. sweep friendships where members array-contains uid    │
   │  8. anonymize posts where authorUid == uid                │
   │  9. anonymize chat messages where senderId == uid         │
   │ 10. terminate trainer_links where athleteId == uid        │
   │ 11. cancel future appointments where athleteId == uid     │
   │ 12. delete Storage avatars/{uid}.jpg  (ignore 404)        │
   │ 13. audit_log/{uid} ← { status: 'success'|'partial', ... }│
   │ 14. admin.auth().deleteUser(uid)                          │
   │ 15. return { status, deletedCollections, errors }         │
   └───────────────────────────────────────────────────────────┘
   │ success
   ▼
AuthService.signOut()
   │ authStateChanges emits null
   ▼
GoRouter redirect → /sign-in
   │
   ▼
SnackBar "Tu cuenta fue eliminada"
```

### Component / module table

| Layer | Component | Responsibility |
|---|---|---|
| Presentation | `ProfileScreen` (modified) | Wires the tile to open `EliminarCuentaSheet` |
| Presentation | `EliminarCuentaSheet` (new) | Destructive confirmation UX; CANCELAR / ELIMINAR |
| Presentation | `ReAuthBottomSheet` (new) | Provider-branched re-auth UI; returns `AuthCredential?` |
| Application | `AccountDeletionNotifier` (new) | Orchestrates UI state: re-auth → CF call → sign-out |
| Data (client) | `AccountDeletionService` (new) | Wraps `cloud_functions.httpsCallable('deleteAccount')` |
| Data (client) | `AuthService` (modified) | Adds `reauthenticate(credential)` + per-provider credential builders |
| Domain | `AuthFailure` (modified) | Adds 3 variants: `requiresRecentLogin`, `reAuthFailed`, `deletionFailed` |
| Functions | `deleteAccount` callable (new) | Cascade across 8 collections + Storage + Auth + audit |
| Functions | `cascade/*.ts` (new) | One module per cascade step; idempotent; structured errors |

### Firestore + Storage paths touched

| Path | Operation | Source of authority |
|---|---|---|
| `users/{uid}` + sub-collections | `recursiveDelete` | CF (Admin) — client `delete: if false` |
| `userPublicProfiles/{uid}` | `delete` | CF (Admin) — client `delete: if false` |
| `trainerPublicProfiles/{uid}` | `delete if exists` | CF (Admin) — client `delete: if false` |
| `friendships/*` where `members ∋ uid` | `delete` | CF (Admin) — could be client but CF for atomicity |
| `posts/*` where `authorUid == uid` | `update` (anonymize) | CF (Admin) |
| `chats/{chatId}/messages/*` where `senderId == uid` | **NO MUTATION** — see ADR-ACCDEL-005 | CF (Admin) — see resolution |
| `trainer_links/*` where `athleteId == uid` | `update` (terminate) | CF (Admin) — client `delete: if false` |
| `appointments/*` where `athleteId == uid AND scheduledAt > now` | `update` (cancel) | CF (Admin) — client `delete: if false` |
| `audit_log/{uid}` | `set` | CF (Admin only) |
| Storage `avatars/{uid}.jpg` | `delete` (ignore 404) | CF (Admin) |
| Firebase Auth | `admin.auth().deleteUser(uid)` | CF (Admin) |

---

## 3. Architecture Decision Records (ADRs)

### ADR-ACCDEL-001 — Cloud Function over client-only deletion

**Decision**: Implement the cascade in a Firebase Callable Function with Admin SDK privileges.

**Rationale**: 6 of the 12 athlete-touched Firestore paths have `delete: if false` (`users/{uid}`, `userPublicProfiles/{uid}`, `trainerPublicProfiles/{uid}`, `trainer_links/*`, `chats/*/messages/*`, `appointments/*`). A client-only delete would orphan the canonical profile docs. The team already encoded this decision in `UserRepository.delete()` which throws `UnsupportedError`.

**Alternatives Considered**:
- **Client-only delete + tolerated orphans** — rejected; main profile doc orphans contradict GDPR semantics and produce dangling public profile records that other users still see.
- **Hybrid: client pre-clears what it can + CF for privileged** — rejected; two-phase failure window (client succeeds, CF fails) leaves an inconsistent state that is harder to debug than a single server-side run.

**Trade-offs**: Cold start (~1-3s on first invocation), Blaze billing requirement, new TypeScript codebase. Mitigated by loading state copy and the fact that Blaze has a generous free tier.

**Implications**: New `functions/` directory, new deploy step (`firebase deploy --only functions`), new dev dependency on `cloud_functions: ^4.x` in Flutter.

---

### ADR-ACCDEL-002 — TypeScript over JavaScript for the function

**Decision**: Write CF in TypeScript (Node 20 runtime).

**Rationale**: Type safety for the cascade — `WriteBatch`, `QuerySnapshot`, `HttpsError` types catch wrong-field-name bugs at compile time. Aligns with the rest of the Firebase ecosystem (modern Functions SDK is TS-first). Maintenance cost is lower because schema changes will surface as compile errors against `User`, `Post`, `Message` mirror types.

**Alternatives Considered**:
- **Plain JavaScript** — rejected; loses type safety on Admin SDK calls, no IDE assist on Firestore document shapes.

**Trade-offs**: Build step (`tsc`) required before deploy. Mitigated by `firebase-tools` standard pipeline (already handled by `predeploy` hooks).

**Implications**: `tsconfig.json`, `lib/` output directory, `npm run build` script. CI/CD must run `npm install && npm run build` before deploy.

---

### ADR-ACCDEL-003 — Callable function over HTTP trigger

**Decision**: Use `functions.https.onCall` (callable) instead of `functions.https.onRequest` (HTTP).

**Rationale**: Callable functions automatically validate the Firebase Auth ID token and inject `context.auth`. No CSRF mitigation required. The client uses `FirebaseFunctions.instance.httpsCallable('deleteAccount').call({uid})` and gets a typed response with built-in error mapping (`FirebaseFunctionsException`).

**Alternatives Considered**:
- **HTTP onRequest with manual token verification** — rejected; reinvents wheel, adds CORS + CSRF surface.
- **Firestore-triggered function on a `deletion_requests/{uid}` doc** — rejected; harder to make synchronous and to return structured responses to UI.

**Trade-offs**: Callable only — no public webhook surface. Acceptable since this is an in-app flow only.

**Implications**: Client uses `cloud_functions` package (not raw HTTP). Region defaults to `us-central1`; if latency from AR becomes an issue we can re-region later (out of scope here).

---

### ADR-ACCDEL-004 — Posts anonymize over hard delete

**Decision**: Update each `posts/{postId}` doc authored by the deleted user with `authorDisplayName = 'Usuario eliminado'` and `authorAvatarUrl = null`. `authorUid` remains unchanged for referential integrity.

**Rationale**: Posts have engagement (likes, comments) attached. Hard-deleting them would leave orphan comment threads and confuse other users. Anonymization preserves community context while removing PII linkage on screen.

**Alternatives Considered**:
- **Hard delete posts + cascade comments** — rejected; loss of conversation continuity for other users.
- **Soft delete via `deletedAt` flag** — rejected; no tombstone pattern elsewhere in the codebase.

**Trade-offs**: Author UID stays in Firestore; this is acceptable because feeds and queries never expose raw `authorUid` to other users — they render the (now-generic) `authorDisplayName`.

**Implications**: Feed widgets already render `authorDisplayName` from the post doc; no UI change needed. The CF runs a single `where('authorUid', '==', uid)` query and batches updates.

---

### ADR-ACCDEL-005 — Chat messages: KEEP intact, anonymize at READ time via deleted public profile

**Decision**: **DO NOT mutate `chats/{chatId}/messages/*` documents.** Instead, rely on the chat UI's existing read-time join: messages display the sender's name by looking up `userPublicProfiles/{senderId}`. Since the CF deletes that doc, the chat UI MUST fall back to "Usuario eliminado" when the public profile is missing.

**Rationale**: The `Message` Freezed model has fields `id`, `senderId`, `text`, `createdAt` — **no `senderDisplayName` field** (verified by reading `lib/features/chat/domain/message.dart`). Display names are looked up at render time from `userPublicProfiles`. Firestore rules also confirm: `messages` are immutable (`allow update, delete: if false` at line 279 of `firestore.rules`). Even Admin SDK respects schema invariants by convention — adding a new write-time field to thousands of historical messages is far more disruptive than adjusting the chat UI to handle missing public profiles.

This **supersedes** the spec's SCENARIO-542 wording. The new behavior is:
- CF does NOT touch messages.
- CF DOES delete `userPublicProfiles/{uid}`.
- Chat UI MUST handle missing public profile gracefully with "Usuario eliminado" fallback.

**This resolves spec risk R1** with a stronger answer than the spec anticipated.

**Alternatives Considered**:
- **Add `senderDisplayName` to messages on every send going forward** — rejected; requires schema migration + client write change + retro-fill for historical messages. Out of scope.
- **CF iterates and adds `senderDisplayName: 'Usuario eliminado'` to historical messages** — rejected; touches potentially thousands of docs per deletion; violates message immutability convention; messages still don't have `senderDisplayName` for non-deleted users so the field would only exist on anonymized messages, which is asymmetric.
- **Hard delete messages from deleted user** — rejected; WhatsApp/iMessage UX expectation is that the other party keeps history.

**Trade-offs**: Requires a small chat UI tweak (verify the existing fallback behavior). If the chat UI currently crashes on missing `userPublicProfiles/{senderId}`, that bug becomes a release-blocking discovery during PR#3 manual smoke test.

**Implications**:
- **Spec update**: REQ-ACCDEL-CF-007 / SCENARIO-542 should be re-worded by `sdd-tasks` (or by a spec patch in PR#3) to assert: "deletion of `userPublicProfiles/{uid}` causes chat UI to render sender as 'Usuario eliminado'". This is recorded here as design supersedence; tasks will carry a verification step.
- **PR#3 must include** a chat widget test or smoke check that confirms "missing public profile → 'Usuario eliminado'" fallback.

---

### ADR-ACCDEL-006 — Trainer links terminate (not delete) for audit trail

**Decision**: Update each matching `trainer_links/*` doc with `status = 'terminated'`, `reason = 'account-deleted'`, `terminatedAt = FieldValue.serverTimestamp()`. Do not delete.

**Rationale**: Firestore rules deny `delete` on `trainer_links` (line 115). Trainers need a history of their athletes (for billing reconciliation, churn analysis, support tickets). A terminated link preserves that record while semantically marking the relationship as over.

**Alternatives Considered**:
- **Delete via Admin SDK (bypassing rules)** — rejected; loses audit history.
- **Move to `trainer_links_archive/`** — rejected; no archive pattern exists in the codebase.

**Trade-offs**: Trainer's dashboards keep showing "terminated" entries. Acceptable — those screens already filter by `status == 'active'` in queries.

**Implications**: PF UI must handle `status: 'terminated'` rows gracefully (already does — same as user-initiated termination).

---

### ADR-ACCDEL-007 — Appointments: cancel future, keep past

**Decision**: For `appointments/*` where `athleteId == uid AND scheduledAt > now()`, update `status = 'cancelled'`, `reason = 'athlete-account-deleted'`. Past appointments untouched.

**Rationale**: Future appointments must be freed so the trainer's calendar reopens those slots. Past appointments are audit/reporting records — modifying them would corrupt PF earnings reports.

**Alternatives Considered**:
- **Cancel all appointments regardless of date** — rejected; rewrites historical financial records.
- **Delete future appointments** — rejected; rules deny delete (line 348); also loses cancellation audit trail.

**Trade-offs**: Trainer sees cancelled future slots in their agenda; clear `reason` field disambiguates from athlete-initiated cancellations.

**Implications**: PF agenda widget already handles `status: 'cancelled'` (existing pattern from athlete-initiated cancellations).

---

### ADR-ACCDEL-008 — Provider-aware re-auth: ONE sheet that branches at runtime

**Decision**: A single `ReAuthBottomSheet` widget detects `user.providerData[0].providerId` at `initState` and renders the correct UI variant (password field / "Re-confirmar con Google" button / "Re-confirmar con Apple" button). One widget, three rendering branches.

**Rationale**: A user only ever has one primary provider at a time (in practice). A single widget keeps the call site (`AccountDeletionNotifier`) clean: `await showModalBottomSheet<AuthCredential?>(...)` returns either a credential or `null` (cancel). Three separate widgets would force the notifier to dispatch on provider, duplicating the branching logic.

**Alternatives Considered**:
- **Three separate sheets (`ReAuthPasswordSheet`, `ReAuthGoogleSheet`, `ReAuthAppleSheet`) + a factory** — rejected; more files, more wiring, more import lines, identical UX surface.
- **Provider-specific routes (e.g. `/re-auth/password`)** — rejected; modal is the established pattern for this kind of confirmation in the codebase.

**Trade-offs**: One widget contains three branches; complexity localized in one file. Mitigated by extracting each branch into a private `_PasswordReAuthBody`, `_GoogleReAuthBody`, `_AppleReAuthBody` widget.

**Implications**: Widget tests can use a `pumpFakeUser(provider: 'google.com')` helper to render the right branch.

---

### ADR-ACCDEL-009 — `AuthService` vs `AccountDeletionNotifier` boundary (resolves spec R2)

**Decision**: Strict separation:
- **`AuthService`** stays a thin Firebase wrapper. New surface:
  - `Future<void> reauthenticate(AuthCredential credential)` — wraps `currentUser.reauthenticateWithCredential`.
  - `Future<AuthCredential> getPasswordCredential({required String password})` — builds `EmailAuthProvider.credential` from the current user's email.
  - `Future<AuthCredential> getGoogleCredential()` — triggers `_googleSignIn.authenticate()` + `authorizeScopes(['email'])` and assembles a `GoogleAuthProvider.credential`.
  - `Future<AuthCredential> getAppleCredential()` — triggers Apple Sign-In sheet and assembles an `OAuthProvider('apple.com').credential`.
  - **NO** `deleteAccount()` on `AuthService`. The spec mentioned this method name (REQ-ACCDEL-REAUTH-002 wording) but for clean separation we put orchestration in the notifier.
- **`AccountDeletionNotifier`** owns the orchestration: opens the sheet, calls AuthService helpers, calls AccountDeletionService, calls signOut, emits UI states.

This **supersedes** REQ-ACCDEL-REAUTH-002's literal wording. The notifier owns orchestration. AuthService stays single-purpose. **The same test (SCENARIO-554) still passes** because it asserts the *order* of mocked calls, not which class owns the method.

**Rationale**: Mixing UI orchestration (sheet open, state transitions, retry loops) into `AuthService` would make `AuthService` a god-object with dependencies on `BuildContext`, `ProviderContainer`, etc. The current `AuthService` has zero UI dependencies — keeping that invariant matters for testability.

**Alternatives Considered**:
- **Put `deleteAccount()` orchestration on `AuthService`** — rejected; pulls `BuildContext` and `Ref` into a service class.
- **Add a separate `AccountDeletionOrchestrator` class invoked by the notifier** — rejected; one extra layer for no testability gain; notifier IS the orchestrator.

**Trade-offs**: Three small helper methods on `AuthService` rather than one combined `deleteAccount()`. Mitigated by clear naming and a single call site.

**Implications**: `sdd-tasks` should record a spec note (REQ-ACCDEL-REAUTH-002 satisfied by notifier-level orchestration, not by an `AuthService.deleteAccount` method). Tests target the notifier.

---

### ADR-ACCDEL-010 — CF idempotency via tolerant deletes

**Decision**: Every cascade step tolerates "already gone" without throwing:
- Firestore deletes use `WriteBatch.delete` (which is idempotent — deleting a non-existent doc is a no-op).
- `recursiveDelete` from Admin SDK handles sub-collection batching internally.
- Storage delete catches the 404 error code (`object-not-found` / HTTP 404) and treats it as success.
- Anonymize/update steps use queries that simply return zero docs when nothing matches → no-op.

**Rationale**: If the CF fails mid-way (network blip, function timeout, transient Firestore error), the client retry button calls it again. The second run should not throw on already-deleted docs; it should resume from wherever the first run left off.

**Alternatives Considered**:
- **Track step-level progress in `audit_log/{uid}.completedSteps[]`** — rejected; over-engineered. Tolerant deletes give us the same effective resumption without state tracking.
- **Lock-and-resume via distributed mutex** — rejected; the CF is short-running (≤30s expected). Concurrent calls from the same uid are vanishingly rare; if two calls collide, both succeed (idempotently).

**Trade-offs**: If a step legitimately fails (e.g., Storage outage), the error is recorded in `audit_log/{uid}.errors[]` but the CF returns `status: 'partial'` and continues. Mitigation: client surfaces the partial status with a "Reintentar" button.

**Implications**: Each cascade module returns a structured `{ step: string, ok: boolean, error?: string }` that the orchestrator aggregates.

---

### ADR-ACCDEL-011 — Retry policy on CF failure (resolves spec R3)

**Decision**: Two-tier retry behavior triggered from `AccountDeletionNotifier`:

1. **If CF throws `FirebaseFunctionsException` with code `unauthenticated` OR `permission-denied` AND message contains `requires-recent-login`**:
   - Notifier emits `AsyncError(AuthFailure.requiresRecentLogin)`.
   - The "Reintentar" button **re-opens `ReAuthBottomSheet`** (full re-auth required).
2. **For any other CF error** (network, internal, partial):
   - Notifier emits `AsyncError(AuthFailure.deletionFailed)`.
   - The "Reintentar" button **calls the CF directly without re-opening re-auth**, as long as the re-auth was successful within the last 5 minutes. Firebase tokens are fresh for ~1 hour after re-auth; a retry within minutes does not require a fresh credential.

The 5-minute window is tracked in the notifier state (`_lastReauthAt: DateTime`). If retry happens after 5 minutes, the notifier auto-opens the re-auth sheet again as a safety measure.

**Rationale**: Re-auth UX cost is real (especially Apple). We should not force a user to re-do Apple Sign-In just because Firestore had a transient error. But we MUST force re-auth if Firebase itself says the token is stale.

**Alternatives Considered**:
- **Always re-open re-auth on any retry** — rejected; punishes users for transient errors.
- **Never re-open re-auth on retry; let the CF fail loudly** — rejected; the user gets stuck if their token expired during a slow CF.
- **Backoff-based auto-retry without user interaction** — rejected; deletion is destructive; user-initiated retry is safer.

**Trade-offs**: Small bit of state in the notifier (`_lastReauthAt`). Trivial.

**Implications**: `AccountDeletionNotifier` has a `retry()` method distinct from `deleteAccount()` — `retry()` skips the re-auth sheet when the recent-auth window is still open.

---

### ADR-ACCDEL-012 — Audit log document shape

**Decision**: `audit_log/{uid}` document with the following shape (TypeScript type mirrored to a Dart class only if the client ever needs to read it — which it doesn't, today):

```typescript
interface AuditLogEntry {
  uid: string;                  // doc id mirror
  provider: string;             // 'password' | 'google.com' | 'apple.com'
  startedAt: Timestamp;         // CF entry time
  deletedAt?: Timestamp;        // CF exit time (success or partial)
  status: 'started' | 'success' | 'partial' | 'failed';
  deletedCollections: string[]; // e.g. ['users','userPublicProfiles','friendships',...]
  errors: Array<{               // empty on full success
    step: string;               // e.g. 'storage', 'posts-anonymize'
    code: string;               // e.g. 'permission-denied', 'not-found', 'internal'
    message: string;
  }>;
  cfVersion: string;            // e.g. '1.0.0' — bumped on cascade logic changes
}
```

**Rationale**:
- `audit_log` exists only for **support and post-incident recovery**, not for user-facing surfaces.
- Admin SDK only — no client read or write rule needed; we explicitly leave `audit_log/{uid}` with no Firestore rule, meaning client access is denied by default.
- `provider` lets support answer "did the user authenticate before deletion?".
- `cfVersion` lets us correlate audit entries with deploy versions when post-incident debugging.

**Alternatives Considered**:
- **Per-step sub-documents** — rejected; over-structured for the support use case.
- **Logging to GCP Cloud Logging instead of Firestore** — partial yes; we DO emit structured logs (`functions.logger.info({...})`) as well, but Firestore is the canonical audit because it's easier for non-engineers to inspect.

**Trade-offs**: Tiny storage cost per deletion. Negligible.

**Implications**: `firestore.rules` should be reviewed in PR#2 — no `audit_log` rule means it defaults to denied for client. If a future feature needs client read (e.g., "show me my deletion confirmation"), a rule is added then.

---

### ADR-ACCDEL-013 — Storage rules verification: trust boundary documented

**Decision**: The CF uses Admin SDK to delete `avatars/{uid}.jpg`, which **bypasses Storage security rules entirely**. We document this trust boundary explicitly and proceed.

**Rationale**: Admin SDK has god-mode on Storage. There is no way to "verify" that Storage rules would have allowed this — the SDK doesn't consult rules. Acceptance: this is the standard Firebase pattern.

**Alternatives Considered**:
- **Have the client delete its own avatar before calling CF** — rejected; Storage rules are not in the repo (managed via Console) and may already deny client delete; would also create a two-phase failure window.
- **Use a signed URL workflow with rules enforcement** — rejected; massive over-engineering.

**Trade-offs**: A compromised CF service account could delete any avatar. Mitigated by IAM permissions on `treino-dev` (only deployer + Firebase service account can invoke).

**Implications**: PR#2 includes a code comment in `cascade/storage.ts` documenting this is intentional and that rules verification is not feasible.

---

### ADR-ACCDEL-014 — Anti-spoofing: verify caller uid matches target

**Decision**: First line in the CF body:

```typescript
if (context.auth?.uid !== data.uid) {
  throw new HttpsError('permission-denied', 'uid mismatch');
}
```

**Rationale**: Without this check, any authenticated user could pass another user's uid in `data.uid` and trigger their deletion. The callable's `context.auth.uid` is server-trusted (set by Firebase from the validated ID token).

**Alternatives Considered**:
- **Remove `data.uid` entirely and derive from `context.auth.uid`** — accepted as a possible refinement; the spec-required signature is `deleteAccount({uid})` (REQ-ACCDEL-CF-001, REQ-ACCDEL-CF-002 explicitly tests `data.uid`). We keep `data.uid` in the payload to match the spec and guard against mismatch. This also makes the test SCENARIO-534 implementable.

**Trade-offs**: Three lines of guard code. Worth every byte.

**Implications**: Test (SCENARIO-534) asserts the throw.

---

## 4. File-by-file structure

### NEW files

| Path | Purpose | Public surface / shape | PR | LOC est. |
|---|---|---|---|---|
| `functions/package.json` | Node project manifest; deps: `firebase-admin`, `firebase-functions`, `typescript`, `@types/node`. | npm scripts: `build`, `serve`, `deploy`, `test`. | 1 | ~30 |
| `functions/tsconfig.json` | TS compiler config (strict, target ES2022, outDir `lib`). | — | 1 | ~20 |
| `functions/.eslintrc.js` | Lint rules matching Firebase recommended TS config. | — | 1 | ~25 |
| `functions/.gitignore` | Ignore `lib/`, `node_modules/`, `.runtimeconfig.json`. | — | 1 | ~5 |
| `functions/src/index.ts` | Function exports entry point. | `export const deleteAccount = functions.https.onCall(handler)` | 1 | ~15 |
| `functions/src/delete-account.ts` | Main handler: auth + role guards, orchestrates cascade. | `export async function handler(data, context): Promise<DeleteAccountResponse>` | 1 (skeleton) / 2 (full) | ~120 |
| `functions/src/types.ts` | Shared TS types: `DeleteAccountResponse`, `AuditLogEntry`, `CascadeResult`. | — | 1 | ~30 |
| `functions/src/cascade/audit-log.ts` | Write/update `audit_log/{uid}`. | `writeStarted(uid, provider)`, `writeFinal(uid, status, deletedCollections, errors)` | 1 | ~40 |
| `functions/src/cascade/users.ts` | `recursiveDelete(users/{uid})` + public profile docs. | `deleteUserDocs(uid): Promise<CascadeResult>` | 2 | ~50 |
| `functions/src/cascade/friendships.ts` | Sweep `friendships` where members ∋ uid. | `sweepFriendships(uid): Promise<CascadeResult>` | 2 | ~40 |
| `functions/src/cascade/posts.ts` | Anonymize `posts` where authorUid == uid. | `anonymizePosts(uid): Promise<CascadeResult>` | 2 | ~40 |
| `functions/src/cascade/trainer-links.ts` | Terminate `trainer_links` where athleteId == uid. | `terminateTrainerLinks(uid): Promise<CascadeResult>` | 2 | ~40 |
| `functions/src/cascade/appointments.ts` | Cancel future appointments. | `cancelFutureAppointments(uid): Promise<CascadeResult>` | 2 | ~40 |
| `functions/src/cascade/storage.ts` | Delete `avatars/{uid}.jpg` (ignore 404). | `deleteAvatar(uid): Promise<CascadeResult>` | 2 | ~30 |
| `functions/src/__tests__/delete-account.test.ts` | Integration tests against Firebase emulator. | Test suite with seeded fixtures. | 1 (smoke) / 2 (full) | ~250 (total across both PRs) |
| `lib/features/profile/data/account_deletion_service.dart` | Thin wrapper around `cloud_functions` callable. | `class AccountDeletionService { Future<DeletionResult> call({required String uid}); }` | 3 | ~50 |
| `lib/features/profile/application/account_deletion_notifier.dart` | Riverpod AsyncNotifier orchestrating the flow. | `class AccountDeletionNotifier extends AsyncNotifier<void>` with `deleteAccount(BuildContext)`, `retry(BuildContext)` | 3 | ~120 |
| `lib/features/profile/presentation/widgets/eliminar_cuenta_sheet.dart` | Destructive confirmation modal. | `class EliminarCuentaSheet extends ConsumerWidget` | 3 | ~90 |
| `lib/features/profile/presentation/widgets/re_auth_bottom_sheet.dart` | Provider-branched re-auth modal. | `class ReAuthBottomSheet extends ConsumerStatefulWidget` + 3 private body widgets | 3 | ~150 |
| `test/features/profile/data/account_deletion_service_test.dart` | Mocks `cloud_functions` callable. | — | 3 | ~50 |
| `test/features/profile/application/account_deletion_notifier_test.dart` | Mocks AuthService + AccountDeletionService; asserts state transitions, retry policy, error variants. | — | 3 | ~120 |
| `test/features/profile/presentation/eliminar_cuenta_sheet_test.dart` | Widget test: renders content, buttons, transitions to re-auth sheet, loading state, error snackbar. | — | 3 | ~80 |
| `test/features/profile/presentation/re_auth_bottom_sheet_test.dart` | Widget test: branches per provider, dismiss returns null. | — | 3 | ~80 |

### MODIFIED files

| Path | Change | PR | LOC est. (delta) |
|---|---|---|---|
| `firebase.json` | Add `"functions": { "source": "functions", "predeploy": ["npm --prefix functions run build"], "runtime": "nodejs20" }` block. | 1 | +10 |
| `pubspec.yaml` | Add `cloud_functions: ^4.x` under `dependencies`. | 3 | +1 |
| `ios/Podfile.lock` | Auto-updated by `pod install` after `cloud_functions` added. | 3 | +20 (auto) |
| `lib/features/auth/data/auth_service.dart` | Add `reauthenticate(AuthCredential)`, `getPasswordCredential({required String password})`, `getGoogleCredential()`, `getAppleCredential()`. Reuse existing `_googleSignIn` and `_appleGateway` plumbing. | 3 | +80 |
| `lib/features/auth/domain/auth_failure.dart` | Add 3 variants: `requiresRecentLogin`, `reAuthFailed({String? provider})`, `deletionFailed({Object? cause})`. Update `userMessage` switch. Update `fromFirebase` switch to map `requires-recent-login` code. | 3 | +25 |
| `lib/features/profile/profile_screen.dart` | Change tile handler from `showModalBottomSheet(builder: ...EliminarCuentaStubSheet())` to `EliminarCuentaSheet()`. | 3 | +1 / -1 |
| `test/features/auth/data/auth_service_test.dart` | Add tests for `reauthenticate`, credential builders (where mockable). | 3 | +60 |

### DELETED files

| Path | Reason | PR |
|---|---|---|
| `lib/features/profile/presentation/widgets/eliminar_cuenta_stub_sheet.dart` | Replaced by real sheet. | 3 |
| `test/features/profile/presentation/eliminar_cuenta_stub_sheet_test.dart` (if exists) | Replaced. | 3 |

### PR LOC summary

| PR | Estimated lines | Notes |
|---|---|---|
| PR#1 (CF bootstrap) | ~150 (code) + ~80 (smoke test) ≈ **230** | Under budget. |
| PR#2 (full cascade) | ~280 (cascade modules + integration tests) ≈ **280** | Under budget. |
| PR#3 (Flutter UI) | ~390 (client + tests) ≈ **390** | At edge of budget; trim if needed by extracting reusable widget tests into a helper. |

---

## 5. Cloud Function design details

### Handler signature (TypeScript)

```typescript
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
admin.initializeApp();

interface DeleteAccountRequest {
  uid: string;
}

interface DeleteAccountResponse {
  status: 'success' | 'partial';
  deletedCollections: string[];
  errors: Array<{ step: string; code: string; message: string }>;
}

export const deleteAccount = functions
  .runWith({ timeoutSeconds: 60, memory: '512MB' })
  .https.onCall(async (data: DeleteAccountRequest, context): Promise<DeleteAccountResponse> => {
    // 1. Anti-spoofing
    if (!context.auth) {
      throw new functions.https.HttpsError('unauthenticated', 'no auth context');
    }
    if (context.auth.uid !== data.uid) {
      throw new functions.https.HttpsError('permission-denied', 'uid mismatch');
    }

    const uid = data.uid;
    const provider = context.auth.token.firebase?.sign_in_provider ?? 'unknown';

    // 2. Role guard
    const userSnap = await admin.firestore().doc(`users/${uid}`).get();
    if (userSnap.exists && userSnap.data()?.role === 'trainer') {
      throw new functions.https.HttpsError(
        'permission-denied',
        'trainers cannot self-delete',
      );
    }

    // 3. Start audit log
    await writeStartedAuditLog(uid, provider);

    // 4-12. Cascade
    const results: CascadeResult[] = [];
    results.push(await deleteUserDocs(uid));            // users + sub-collections + public profiles
    results.push(await sweepFriendships(uid));
    results.push(await anonymizePosts(uid));
    results.push(await terminateTrainerLinks(uid));
    results.push(await cancelFutureAppointments(uid));
    results.push(await deleteAvatar(uid));

    const errors = results.flatMap((r) => r.errors);
    const deletedCollections = results.filter((r) => r.ok).map((r) => r.step);
    const status: 'success' | 'partial' = errors.length === 0 ? 'success' : 'partial';

    // 13. Final audit log
    await writeFinalAuditLog(uid, status, deletedCollections, errors);

    // 14. Auth user delete LAST (so re-runs can still read users/{uid}.role during step 2)
    try {
      await admin.auth().deleteUser(uid);
    } catch (e: any) {
      if (e.code !== 'auth/user-not-found') {
        errors.push({ step: 'auth-delete', code: e.code ?? 'unknown', message: e.message });
        return { status: 'partial', deletedCollections, errors };
      }
      // Already deleted (idempotent re-run): treat as success for this step.
    }

    return { status, deletedCollections, errors };
  });
```

### Cascade module shape (example: `cascade/posts.ts`)

```typescript
import * as admin from 'firebase-admin';
import { CascadeResult } from '../types';

export async function anonymizePosts(uid: string): Promise<CascadeResult> {
  const db = admin.firestore();
  try {
    const snap = await db.collection('posts').where('authorUid', '==', uid).get();
    if (snap.empty) return { step: 'posts', ok: true, errors: [] };

    // Batched in chunks of 400 (under 500-write batch limit).
    const chunks = chunkArray(snap.docs, 400);
    for (const chunk of chunks) {
      const batch = db.batch();
      for (const doc of chunk) {
        batch.update(doc.ref, {
          authorDisplayName: 'Usuario eliminado',
          authorAvatarUrl: null,
          // authorUid intentionally unchanged (referential integrity)
        });
      }
      await batch.commit();
    }
    return { step: 'posts', ok: true, errors: [] };
  } catch (e: any) {
    return {
      step: 'posts',
      ok: false,
      errors: [{ step: 'posts', code: e.code ?? 'unknown', message: e.message }],
    };
  }
}
```

### Order of operations (final)

1. Validate `context.auth` and `data.uid` (anti-spoof).
2. Read `users/{uid}.role`; reject if `trainer`.
3. `audit_log/{uid}` ← `{ status: 'started', startedAt, provider }`.
4. `recursiveDelete(users/{uid})` — Admin SDK handles sub-collections (`sessions`, `setLogs`, `checkIns`).
5. Delete `userPublicProfiles/{uid}` (ignore not-found).
6. Delete `trainerPublicProfiles/{uid}` (ignore not-found).
7. Sweep `friendships` where `members array-contains uid`.
8. Anonymize `posts` where `authorUid == uid`.
9. Terminate `trainer_links` where `athleteId == uid`.
10. Cancel `appointments` where `athleteId == uid AND scheduledAt > now`.
11. Delete Storage `avatars/{uid}.jpg` (ignore 404).
12. Update `audit_log/{uid}` with final `status`, `deletedCollections`, `errors`.
13. `admin.auth().deleteUser(uid)` — LAST so we can still read `users/{uid}.role` on a retry.
14. Return response.

**Note**: Chat messages NOT mutated (per ADR-ACCDEL-005). Public profile delete in step 5 triggers the read-time anonymization in the chat UI.

### Failure handling

- Each cascade module catches its own errors and returns `{ ok: false, errors: [...] }`.
- The handler aggregates; if any step failed, `status: 'partial'`.
- The handler proceeds with subsequent steps even after a failure (a Storage outage shouldn't block Firestore cleanup).
- Step 13 (Auth delete) is special: if it fails, the user is still signed in, but Firestore is clean. The retry from the client will re-call the CF, which is idempotent.

### Idempotency

- `recursiveDelete` on non-existent docs is a no-op.
- `where(...).get()` on no-match queries returns empty snapshot → no-op.
- Storage delete catches `'storage/object-not-found'` (Admin SDK) or HTTP 404 → no-op.
- `admin.auth().deleteUser(uid)` throws `'auth/user-not-found'` if already deleted → caught and treated as success.

---

## 6. Re-auth design details

### Provider detection

```dart
final user = FirebaseAuth.instance.currentUser!;
final providerId = user.providerData.isNotEmpty
    ? user.providerData[0].providerId
    : 'password'; // fallback; should not happen in practice
```

### Password branch

```dart
Future<AuthCredential> getPasswordCredential({required String password}) async {
  final user = _auth.currentUser;
  if (user == null || user.email == null) {
    throw const AuthFailure.reAuthFailed(provider: 'password');
  }
  return EmailAuthProvider.credential(email: user.email!, password: password);
}
```

### Google branch

```dart
Future<AuthCredential> getGoogleCredential() async {
  try {
    final account = await _googleSignIn.authenticate();
    final auth = await account.authorizationClient.authorizeScopes(const ['email']);
    return GoogleAuthProvider.credential(
      idToken: account.authentication.idToken,
      accessToken: auth.accessToken,
    );
  } on GoogleSignInException catch (e) {
    if (e.code == GoogleSignInExceptionCode.canceled) {
      throw const AuthFailure.signInCancelled();
    }
    throw const AuthFailure.reAuthFailed(provider: 'google.com');
  }
}
```

### Apple branch

```dart
Future<AuthCredential> getAppleCredential() async {
  final rawNonce = generateNonce();
  final hashedNonce = sha256OfString(rawNonce);
  try {
    final appleCred = await _appleGateway.getAppleIDCredential(
      scopes: const [AppleIDAuthorizationScopes.email],
      nonce: hashedNonce,
    );
    return OAuthProvider('apple.com').credential(
      idToken: appleCred.identityToken,
      rawNonce: rawNonce,
      accessToken: appleCred.authorizationCode,
    );
  } on SignInWithAppleAuthorizationException catch (e) {
    if (e.code == AuthorizationErrorCode.canceled) {
      throw const AuthFailure.signInCancelled();
    }
    throw const AuthFailure.reAuthFailed(provider: 'apple.com');
  }
}
```

### `reauthenticate` wrapper

```dart
Future<void> reauthenticate(AuthCredential credential) async {
  final user = _auth.currentUser;
  if (user == null) throw const AuthFailure.userNotFound();
  try {
    await user.reauthenticateWithCredential(credential);
  } on FirebaseAuthException catch (e) {
    if (e.code == 'wrong-password' || e.code == 'invalid-credential') {
      throw const AuthFailure.reAuthFailed();
    }
    throw AuthFailure.fromFirebase(e);
  }
}
```

### `ReAuthBottomSheet` widget

```dart
class ReAuthBottomSheet extends ConsumerStatefulWidget {
  const ReAuthBottomSheet({super.key});
  @override
  ConsumerState<ReAuthBottomSheet> createState() => _ReAuthBottomSheetState();
}

class _ReAuthBottomSheetState extends ConsumerState<ReAuthBottomSheet> {
  late final String _providerId;

  @override
  void initState() {
    super.initState();
    _providerId = FirebaseAuth.instance.currentUser?.providerData.isNotEmpty == true
        ? FirebaseAuth.instance.currentUser!.providerData[0].providerId
        : 'password';
  }

  @override
  Widget build(BuildContext context) {
    return switch (_providerId) {
      'password' => _PasswordReAuthBody(),
      'google.com' => _GoogleReAuthBody(),
      'apple.com' => _AppleReAuthBody(),
      _ => _PasswordReAuthBody(),  // safe fallback
    };
  }
}
```

Each `_XReAuthBody` invokes the matching `AuthService.getXCredential()`, calls `AuthService.reauthenticate(credential)`, and on success `Navigator.pop(context, credential)`. On failure: shows in-sheet error; user can retry or cancel.

---

## 7. Notifier orchestration (resolves spec R2)

### State model

```dart
sealed class AccountDeletionState {
  const AccountDeletionState();
}
class _Idle extends AccountDeletionState { const _Idle(); }
class _AwaitingReAuth extends AccountDeletionState { const _AwaitingReAuth(); }
class _Deleting extends AccountDeletionState { const _Deleting(); }
class _Success extends AccountDeletionState { const _Success(); }
class _Error extends AccountDeletionState {
  const _Error(this.failure);
  final AuthFailure failure;
}
```

(Or: `AsyncNotifier<void>` exposes the same via `AsyncValue` + a separate `awaitingReAuthProvider` boolean if simpler.)

### Notifier shape

```dart
class AccountDeletionNotifier extends AsyncNotifier<void> {
  DateTime? _lastReauthAt;

  @override
  Future<void> build() async {}

  Future<void> deleteAccount(BuildContext context) async {
    final credential = await _openReAuthSheet(context);
    if (credential == null) return; // user cancelled
    state = const AsyncLoading();
    try {
      final authService = ref.read(authServiceProvider);
      await authService.reauthenticate(credential);
      _lastReauthAt = DateTime.now();
      await _callCfAndFinish();
    } on AuthFailure catch (e) {
      state = AsyncError(e, StackTrace.current);
    } catch (e, st) {
      state = AsyncError(AuthFailure.deletionFailed(cause: e), st);
    }
  }

  Future<void> retry(BuildContext context) async {
    final reauthFresh = _lastReauthAt != null &&
        DateTime.now().difference(_lastReauthAt!) < const Duration(minutes: 5);
    if (!reauthFresh) {
      await deleteAccount(context); // full re-auth path
      return;
    }
    state = const AsyncLoading();
    try {
      await _callCfAndFinish();
    } catch (e, st) {
      state = AsyncError(_mapError(e), st);
    }
  }

  Future<void> _callCfAndFinish() async {
    final service = ref.read(accountDeletionServiceProvider);
    final user = ref.read(firebaseAuthProvider).currentUser!;
    final result = await service.call(uid: user.uid);
    if (result.status == 'partial') {
      state = AsyncError(
        const AuthFailure.deletionFailed(),
        StackTrace.current,
      );
      return;
    }
    await ref.read(authServiceProvider).signOut();
    state = const AsyncData(null);
  }

  Future<AuthCredential?> _openReAuthSheet(BuildContext context) =>
      showModalBottomSheet<AuthCredential?>(
        context: context,
        isScrollControlled: true,
        builder: (_) => const ReAuthBottomSheet(),
      );

  AuthFailure _mapError(Object e) {
    if (e is FirebaseFunctionsException) {
      if (e.code == 'unauthenticated' ||
          (e.code == 'permission-denied' && e.message?.contains('recent-login') == true)) {
        return const AuthFailure.requiresRecentLogin();
      }
    }
    return AuthFailure.deletionFailed(cause: e);
  }
}
```

### Test surface

The notifier tests use `mocktail` to stub `AuthService` and `AccountDeletionService` and assert:
- `deleteAccount()` opens the sheet exactly once.
- On `null` from the sheet, neither `reauthenticate` nor the CF is called.
- On valid credential, `reauthenticate` is called BEFORE the CF.
- On CF success, `signOut` is called and state becomes `AsyncData(null)`.
- On CF `partial`, state becomes `AsyncError(deletionFailed)`.
- On CF `unauthenticated`, state becomes `AsyncError(requiresRecentLogin)`.
- `retry()` within 5 minutes skips the sheet.
- `retry()` after 5 minutes re-opens the sheet.

---

## 8. Test strategy

### Cloud Function tests (PR#1 smoke + PR#2 full)

- **Runner**: `jest` with `firebase-functions-test` (online mode against the emulator suite).
- **Emulators**: Firestore + Auth + Storage, started by `firebase emulators:exec --only firestore,auth,storage "npm test"`.
- **Fixtures**: Seed script in `functions/src/__tests__/fixtures.ts` creates a test athlete with: 1 user doc, 1 public profile, 5 sessions, 3 friendships, 2 posts, 4 chat messages across 2 threads, 1 active trainer_link, 1 past + 1 future appointment, 1 avatar file.
- **Cases** (one per scenario in spec): SCENARIO-533..551.
- **Cleanup**: Each test runs in a fresh emulator state via `emulator clear` between tests.

### Flutter unit tests (PR#3)

- `AccountDeletionService`: mock `FirebaseFunctions` + `HttpsCallable`; assert payload shape and response parsing.
- `AuthService` new methods: mock `FirebaseAuth.currentUser` and the gateways; assert credential builder shapes.
- `AccountDeletionNotifier`: mock `AuthService` + `AccountDeletionService`; cover all state transitions and retry policy branches.

### Flutter widget tests (PR#3)

- `EliminarCuentaSheet`: renders title, body, both buttons; tap ELIMINAR dismisses self and opens `ReAuthBottomSheet`.
- `ReAuthBottomSheet`: renders password branch / google branch / apple branch based on mocked `providerData`; dismiss returns `null`; submit returns credential.

### E2E smoke (manual, PR#3 close-out)

- Create three test accounts (one per provider) on `treino-dev`.
- For each: tap "Eliminar cuenta" → confirm → re-auth → verify Firestore Console + Storage + Auth all cleaned.
- Verify chat partner now sees "Usuario eliminado" in their chat history (validates ADR-ACCDEL-005).

---

## 9. Copy table (es-AR)

All strings tagged `// i18n: Fase 6 Etapa 3 — account deletion` in source.

| Key | Spanish text | Used in |
|---|---|---|
| `confirm_sheet_title` | `Eliminar cuenta` | `EliminarCuentaSheet` |
| `confirm_sheet_body` | `Esta acción es irreversible.\n\nSe eliminan: tu perfil, tus entrenamientos, tus check-ins, tus amigos, tu vínculo con tu PF, tus turnos futuros y tu foto.\n\nSe anonimizan: tus posts (quedan como "Usuario eliminado") y tus chats (el otro lado los conserva pero te ve como "Usuario eliminado").\n\nNo hay vuelta atrás.` | `EliminarCuentaSheet` body |
| `confirm_eliminar_button` | `ELIMINAR` | `EliminarCuentaSheet` (danger primary) |
| `confirm_cancelar_button` | `CANCELAR` | `EliminarCuentaSheet` (secondary) |
| `reauth_sheet_title` | `Confirmá tu identidad` | `ReAuthBottomSheet` (all branches) |
| `reauth_sheet_subtitle` | `Por seguridad, necesitamos confirmar que sos vos antes de eliminar tu cuenta.` | `ReAuthBottomSheet` (all branches) |
| `reauth_password_label` | `Contraseña` | `_PasswordReAuthBody` field label |
| `reauth_password_button` | `CONTINUAR` | `_PasswordReAuthBody` primary |
| `reauth_google_button` | `Continuar con Google` | `_GoogleReAuthBody` primary |
| `reauth_apple_button` | `Continuar con Apple` | `_AppleReAuthBody` primary |
| `reauth_cancel_button` | `CANCELAR` | `ReAuthBottomSheet` secondary (all branches) |
| `deletion_loading_title` | `Eliminando tu cuenta...` | Loading overlay in `EliminarCuentaSheet` |
| `deletion_loading_subtitle` | `Esto puede tardar unos segundos.` | Loading overlay |
| `deletion_success_snackbar` | `Tu cuenta fue eliminada` | Shown on `/sign-in` after redirect |
| `deletion_error_snackbar` | `No pudimos eliminar tu cuenta. Probá de nuevo.` | Error state in `EliminarCuentaSheet` |
| `deletion_error_retry_button` | `Reintentar` | SnackBar action |
| `reauth_failed_snackbar` | `No pudimos verificar tu identidad. Probá de nuevo.` | Re-auth failure |
| `reauth_requires_recent_login_snackbar` | `Tu sesión venció. Tenés que volver a confirmar tu identidad.` | `requiresRecentLogin` case |

All copy goes through `AppPalette.of(context)` for any color reference (danger color for title, primary for ELIMINAR, etc.). No `PhosphorIcons.X` direct imports — use `TreinoIcon.X` (no specific icon required for this flow, but if one is added — e.g. a warning icon — it goes through `TreinoIcon`).

---

## 10. Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| Cold start ~1-3s on first CF call | Med | Loading state with explicit copy ("Esto puede tardar unos segundos") + min display 800ms to avoid flicker. |
| Blaze billing not active on `treino-dev` | High (blocks PR#1) | Action item on Backhaus before PR#1 merge; CF deploy fails loudly if Spark. |
| Apple re-auth UX quirks (sheet behavior on re-trigger) | High | Manual smoke test mandatory on real iOS device; isolated `_AppleReAuthBody` for focused debugging. |
| Sub-collection scale (sessions could be 500+) | Med | `recursiveDelete` from Admin SDK handles batching internally (500-doc batch limit respected). |
| Atomic-ish failures mid-cascade | Med | Audit log captures partial state; idempotent re-run via "Reintentar"; runbook for support to inspect `audit_log/{uid}`. |
| Chat UI crashes on missing `userPublicProfiles` | Med | Verify fallback at PR#3 manual smoke; add widget test if missing. |
| `cloud_functions` package iOS pod issues | Med | `cd ios && pod install` immediately after `pubspec.yaml` change; commit updated `Podfile.lock`. |
| `requires-recent-login` during slow re-auth → CF window | Low | Retry policy (ADR-ACCDEL-011) re-opens re-auth sheet on `requiresRecentLogin` error. |
| CF version drift between deploys | Low | `cfVersion` in audit log lets support correlate. |

---

## 11. Out of scope (explicit)

- Trainer self-deletion (CF guards via role check — REQ-ACCDEL-CF-003).
- Data export pre-delete (deferred GDPR work).
- Soft delete / grace period.
- Email notifications post-deletion.
- Account recovery / undo.
- Storage rules audit.
- Routines owned by deleted athlete (no rules change in this SDD).
- Chat schema change to add `senderDisplayName` (ADR-ACCDEL-005).
- Multi-region CF deployment (us-central1 only).

---

## 12. Spec risks resolution summary

| Risk | Resolution |
|---|---|
| **R1** — chat messages `sender` field name unspecified | Verified by reading `lib/features/chat/domain/message.dart` + `firestore.rules` (line 272). Field is `senderId`. Messages also have NO `senderDisplayName` field. **ADR-ACCDEL-005** changes the approach: CF does NOT mutate messages; chat UI handles missing public profile via "Usuario eliminado" fallback. This is a stronger answer than the spec wording and requires a spec note update by `sdd-tasks`. |
| **R2** — `AuthService.deleteAccount()` vs `AccountDeletionNotifier` boundary | **ADR-ACCDEL-009**: AuthService stays thin (only `reauthenticate` + per-provider credential builders). The notifier owns orchestration. No `AuthService.deleteAccount()` method is added. SCENARIO-554's call-order assertion is satisfied by mocking at the notifier level. |
| **R3** — retry behavior on CF failure when re-auth expired | **ADR-ACCDEL-011**: Two-tier retry. On `requiresRecentLogin` → re-open re-auth sheet. On any other error → retry CF directly if within 5-min recent-auth window; otherwise re-open sheet. Window tracked in notifier state (`_lastReauthAt`). |

---

## 13. Open questions (remaining)

1. **Blaze billing on `treino-dev`** — Backhaus to verify before PR#1 merge.
2. **Chat UI fallback** — needs verification during PR#3 that the chat widget already handles missing `userPublicProfiles` gracefully; if not, a tiny patch is added to PR#3 scope.

All other open questions were closed in the proposal (§3 locked decisions) or in the ADRs above.

---

**Status**: Ready for `sdd-tasks`. Spec note suggested: REQ-ACCDEL-CF-007 / SCENARIO-542 wording should be updated to reflect ADR-ACCDEL-005 (read-time anonymization via public profile deletion, not message mutation).
