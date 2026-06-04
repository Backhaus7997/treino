# Design: push-notifications-fcm

**Change**: push-notifications-fcm
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-03
**Phase**: Fase 6 Etapa 2
**Artifact store**: hybrid (file `openspec/changes/push-notifications-fcm/design.md` + Engram `sdd/push-notifications-fcm/design`)
**Proposal ref**: `openspec/changes/push-notifications-fcm/proposal.md` (#138)
**Spec ref**: `openspec/changes/push-notifications-fcm/spec.md` (#139)
**ADR range**: ADR-PN-001 … ADR-PN-015

---

## 1. Scope Summary

Add FCM push notifications across chat, agenda, trainer_links, and reviews. PR#1 ships 4 `southamerica-east1` Cloud Functions plus a shared `send-fcm` helper. PR#2 ships the Flutter client: `firebase_messaging`, a thin `FcmService`, an `FcmTokenRepository`, foreground SnackBar handler, background + cold-start deep-link routing, and a post-onboarding system-permission prompt. Token storage is a new camelCase array field `fcmTokens: string[]` on existing `users/{uid}`. Zero new collections, zero rules changes, zero new indexes. Additive-only blast radius.

---

## 2. Architecture Overview

### Write path (token lifecycle)

```
Firebase Auth signIn  ─────────────────────────┐
                                               ▼
authStateProvider (Stream<User?>)         FcmService.init(uid)
        │                                  │
        ▼                                  ├── requestPermission (gated, post-onboarding)
fcmLifecycleProvider                       ├── getToken()            ──┐
        │ ref.listen(authStateProvider)    ├── onTokenRefresh stream ──┤
        │                                  ▼                           │
        │                            FcmTokenRepository.saveToken(uid) │
        │                                                              ▼
        │                                                users/{uid}.fcmTokens
        │                                                (arrayUnion — idempotent)
        ▼
on signOut → FcmService.dispose(previousUid)
              └── FcmTokenRepository.removeToken(uid, currentToken)
```

### Notify path (CF fan-out)

```
Firestore write
   │
   ├── chats/{chatId}/messages/{messageId}  → notifyOnChatMessage  ──┐
   ├── appointments/{apptId}                → notifyOnAppointment   ─┤
   ├── trainer_links/{linkId}               → notifyOnLinkChange    ─┤
   └── reviews/{reviewId}                   → notifyOnReview        ─┤
                                                                    ▼
                                              sendFcm({uids, notification, data})
                                                  │
                                                  ├── Promise.all read fcmTokens per uid
                                                  ├── admin.messaging().sendEachForMulticast(...)
                                                  └── stale-token arrayRemove on per-token errors
                                                                    │
                                                                    ▼
                                                       APNs / FCM   →   Device
```

### Receive path (Flutter handler)

```
                              ┌── onMessage           → in-app SnackBar (tap → goDeepLink)
FirebaseMessaging streams  ───┼── onMessageOpenedApp  → goDeepLink immediately
                              └── getInitialMessage() → post-first-frame gate → goDeepLink

goDeepLink(context, data['deepLink'])
   │ null/empty → context.go('/coach')
   │ invalid    → log + context.go('/coach')
   └ valid      → context.go(deepLink)
```

---

## 3. Architecture Decision Records (ADRs)

### ADR-PN-001 — Token storage as `fcmTokens` camelCase array on `users/{uid}`

**Context**: Spec REQ-PN-DATA-001 locks an array on `users/{uid}` with no new collection. Field naming must match existing project convention.

**Decision**: Add `fcmTokens: List<String>` (Dart) / `fcmTokens: string[]` (Firestore). camelCase, NOT snake_case.

**Consequences**:
- Matches every other field on `users/{uid}` (`displayName`, `avatarUrl`, `trainerMonthlyRate`, `trainerLocations`) and on `trainerPublicProfiles` (`averageRating`, `reviewCount`). Snake_case would be a one-off inconsistency.
- The proposal/spec used `fcm_tokens` informally; this ADR overrides that label — the underlying behavior is unchanged.
- The `_immutableFields` set in `UserRepository` (`{'uid','role','email','createdAt'}`) does NOT include `fcmTokens`, so client `arrayUnion`/`arrayRemove` operations are allowed by the existing owner-write rule.
- No backfill: a missing field reads as null/empty array; `arrayUnion` upserts the field on first write.

**Status**: ACCEPTED

---

### ADR-PN-002 — Token writes use `arrayUnion` / `arrayRemove` (no cap, no transaction)

**Context**: Tokens can rotate (`onTokenRefresh`) and a user can sign in on multiple devices. Realistic count is 1–3 per user.

**Decision**:
- `saveToken(uid, token)` → `update({'fcmTokens': FieldValue.arrayUnion([token])})`. Idempotent.
- `removeToken(uid, token)` → `update({'fcmTokens': FieldValue.arrayRemove([token])})`. No-op when absent.
- No client-side cap, no transaction. Firestore arrays in this doc stay well under the 1 MB doc limit.

**Consequences**:
- No race on concurrent multi-device sign-ins (server-side merge).
- Stale token accumulation bounded by the server-side cleanup in ADR-PN-004.
- Tests use `fake_cloud_firestore` — both helpers support `arrayUnion`/`arrayRemove` since 2.x.

**Status**: ACCEPTED

---

### ADR-PN-003 — `FcmService` is a thin class instantiated by a Riverpod provider; lifecycle wired via `ref.listen(authStateProvider)`

**Context**: Spec open question Q3 asks: class singleton vs pure-Riverpod streams vs hybrid. Existing precedents in the codebase: `AuthService`, `AccountDeletionService`, `UserRepository`, `TrainerLinkRepository` — all are plain classes constructed by a `Provider<T>` and exposing imperative methods. There are zero direct-stream-as-provider patterns in `lib/features/`.

**Decision**: Hybrid in the project's existing style.
- `FcmService` — plain Dart class with `init(uid)`, `dispose(uid)`, `requestPermission()`, `onForegroundMessage` (exposes `_messaging.onMessage`), `onMessageOpenedApp`, `getInitialMessage()`. Holds `FirebaseMessaging` and `FcmTokenRepository`.
- `fcmServiceProvider` — `Provider<FcmService>` constructs it once.
- `fcmLifecycleProvider` — `Provider<void>` that does `ref.listen(authStateProvider, (prev, next) { ... })` and dispatches `init`/`dispose`. Eagerly read from `TreinoApp.initState` so it's alive for the app lifetime.

**Alternatives rejected**:
- Pure Riverpod streams (`StreamProvider` wrapping `onTokenRefresh`/`onMessage`): no precedent in this codebase; spreads the side-effect logic across providers; harder to unit-test as a unit.
- Singleton static class: inconsistent with the IoC convention enforced by every other service in `lib/features/`.

**Status**: ACCEPTED

---

### ADR-PN-004 — `send-fcm` shared helper signature + stale token cleanup

**Context**: Spec REQ-PN-CF-001 mandates a single helper. CF tests must inject a mock `messaging()`.

**Decision**: `functions/src/notifications/send-fcm.ts` exports:
```typescript
export interface SendFcmInput {
  uids: string[];
  notification: { title: string; body: string };
  data: Record<string, string>;
}
export interface SendFcmResult { successCount: number; failureCount: number; }

export async function sendFcm(
  app: admin.app.App,
  input: SendFcmInput,
  messaging?: admin.messaging.Messaging,   // optional for tests
): Promise<SendFcmResult>;
```
Internals:
1. `Promise.all` read `users/{uid}.fcmTokens` for every uid.
2. Build a flat `{token, ownerUid}[]` list. Empty uids logged `"sendFcm: no tokens for uid=$uid, skipping"` and skipped.
3. Call `messaging.sendEachForMulticast({tokens, notification, data})`.
4. Iterate `BatchResponse.responses[i]`: when `error?.code` is `messaging/registration-token-not-registered` or `messaging/invalid-registration-token`, `arrayRemove(token)` from THAT token's owner uid.
5. Return aggregated `{successCount, failureCount}`.

Mirrors the `recomputeAggregate(app, trainerId)` testability shape from `review-aggregate.ts`.

**Consequences**:
- Stale tokens cleaned up on the same trigger that hit them. No background sweeper required.
- Body length enforcement (`≤ 256 chars`) lives in each per-trigger CF that builds the body, not in `sendFcm`.
- Per-token error inspection avoids removing healthy tokens.

**Status**: ACCEPTED

---

### ADR-PN-005 — `notifyOnChatMessage` trigger

**Context**: REQ-PN-CF-002. WhatsApp parity: full preview, sender name, 100-char cap.

**Decision**: `onDocumentCreated('chats/{chatId}/messages/{messageId}', { region: 'southamerica-east1' })`. Flow:
1. Read parent `chats/{chatId}` → `members: string[]`.
2. `recipients = members.filter(m => m !== msg.senderId)`. Empty → return.
3. Look up sender display name from `userPublicProfiles/{senderId}.displayName ?? 'Alguien'`.
4. Body = `"${senderName}: ${truncate(text, 100)}"`. Truncate appends `…` if cut.
5. `deepLink = "/coach/chat/${chatId}?other=${senderId}"`.
6. Call `sendFcm({uids: recipients, notification: {title: senderName, body}, data: {deepLink}})`.

Guard: none beyond "skip if message has no text" — message create cascades from account-deletion are zero (messages are immutable).

**Status**: ACCEPTED

---

### ADR-PN-006 — `notifyOnAppointment` trigger

**Context**: REQ-PN-CF-003. Branches on create vs status change, must skip account-deletion cascade writes.

**Decision**: `onDocumentWritten('appointments/{apptId}', { region: 'southamerica-east1' })`.

Guards (return early):
- `event.data?.after` missing → skip (deletion, not in scope).
- `after.reason === 'athlete-account-deleted'` → skip (cascade write, verified against `cascade/appointments.ts:60-62`).
- `before` exists AND `before.status === after.status` → skip (no-op write).

Branches:
- `before == null && after.status === 'requested'` → notify `trainerId`, deepLink `"/coach?tab=agenda"`, body `"Nuevo turno solicitado por ${athleteName}"`.
- transition `requested → confirmed` → notify `athleteId`, deepLink `"/coach/agenda"`, body `"Tu turno fue confirmado por ${trainerName}"`.
- transition `* → cancelled` → notify the OTHER party (cancelled by athlete → notify trainer; cancelled by trainer → notify athlete). Distinguish via `after.cancelledBy` field if present; fallback notify both.

**Consequences**:
- Identical guard pattern to the existing `notifyOnLinkChange` (ADR-PN-007). Both rely on `reason` rather than the proposal's earlier `cancellationReason` strawman.
- `cancelledBy` is not currently a field on appointments — the CF tolerates its absence by defaulting to "notify both", which is the safer side of the asymmetry.

**Status**: ACCEPTED

---

### ADR-PN-007 — `notifyOnLinkChange` trigger

**Context**: REQ-PN-CF-004. Locked proposal decision: terminated → notify BOTH.

**Decision**: `onDocumentWritten('trainer_links/{linkId}', { region: 'southamerica-east1' })`.

Guards:
- `event.data?.after` missing → skip.
- `after.reason === 'account-deleted'` → skip (verified against `cascade/trainer-links.ts:46-49`).
- `before?.status === after.status` → skip.

Branches:
- `before == null && status === 'pending'` → notify `trainerId`, body `"${athleteName} solicitó vincularse"`, deepLink `"/coach"`.
- `pending → active` → notify `athleteId`, body `"${trainerName} aceptó tu solicitud"`, deepLink `"/coach"`.
- `* → terminated` → notify BOTH `trainerId` and `athleteId`, body `"El vínculo con ${otherName} terminó"`, deepLink `"/coach"`.

**Status**: ACCEPTED

---

### ADR-PN-008 — `notifyOnReview` trigger

**Context**: REQ-PN-CF-005. Locked: include rating in body.

**Decision**: `onDocumentCreated('reviews/{reviewId}', { region: 'southamerica-east1' })`.
- Read `review.trainerId`, `review.athleteId`, `review.rating`.
- Look up `userPublicProfiles/{athleteId}.displayName ?? 'Un atleta'`.
- Body = `"${athleteName} dejó una reseña de ${rating}⭐"`.
- DeepLink = `"/coach/trainer/${review.trainerId}"` (trainer's own public profile — section already exists from trainer-reviews SDD).
- No `onDocumentWritten`: review edits in v1 do NOT re-notify (spec REQ-PN-CF-005 explicit, mirrors trainer-reviews UX).

**Status**: ACCEPTED

---

### ADR-PN-009 — Flutter deep-link router helper

**Context**: REQ-PN-HANDLER-001..003 share the same routing semantics.

**Decision**: `lib/features/notifications/application/notification_router.dart` exports a free function:
```dart
void goDeepLink(BuildContext context, String? deepLink) {
  const fallback = '/coach';
  if (deepLink == null || deepLink.trim().isEmpty) {
    context.go(fallback);
    return;
  }
  if (!deepLink.startsWith('/')) {
    debugPrint('[fcm] invalid deepLink: $deepLink → fallback');
    context.go(fallback);
    return;
  }
  context.go(deepLink);
}
```
Callers MUST check `context.mounted` first.

**Consequences**:
- No allowlist of valid paths — GoRouter's redirect handles auth (`authRedirect` in `lib/app/router.dart`). Unauthenticated users land on `/welcome` automatically.
- Easy to unit-test with a `MockGoRouter` extension or a widget pump.

**Status**: ACCEPTED

---

### ADR-PN-010 — Foreground SnackBar handler attached in `TreinoApp.initState`; uses root `ScaffoldMessenger`

**Context**: REQ-PN-HANDLER-001. Spec open question Q4 asks the attachment point.

**Decision**: In `TreinoApp.initState` (after `_router` is built), call `ref.read(fcmServiceProvider).onForegroundMessage.listen(_onForeground)`. The stream subscription is stored in `_TreinoAppState._fgSub` and cancelled in `dispose()`. The handler:
1. Resolves a `BuildContext` from `_router.routerDelegate.navigatorKey.currentContext`. If null, swallow.
2. `ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: ..., action: SnackBarAction(label: 'Ver', onPressed: () => goDeepLink(context, deepLink))))`. Duration 4s.

**Consequences**:
- The router's `navigatorKey` is the canonical place to find a live `BuildContext` outside the widget tree.
- `MaterialApp.router` does NOT automatically provide a `scaffoldMessengerKey`; we add one in PR#2 (`_scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>()`) and pass it to `MaterialApp.router(scaffoldMessengerKey: ...)`. This removes the `context`-lookup race.
- Subscription is bound to the widget that owns the router → no leak.

**Status**: ACCEPTED

---

### ADR-PN-011 — Cold-start tap handled in `TreinoApp.initState` via `addPostFrameCallback` + `getInitialMessage()`

**Context**: Spec open question Q1. `getInitialMessage()` resolves immediately, but `GoRouter` is not "ready" until after the first frame (the `redirect` runs against `/splash` first, then the auth-aware redirect lands the user somewhere real).

**Decision**: Approach (a) from Q1, with a guard:

```dart
@override
void initState() {
  super.initState();
  // ... existing _router build ...
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    final fcm = ref.read(fcmServiceProvider);
    final initial = await fcm.getInitialMessage();
    if (initial == null || !mounted) return;
    final ctx = _router.routerDelegate.navigatorKey.currentContext;
    if (ctx == null || !ctx.mounted) return;
    final deepLink = initial.data['deepLink'] as String?;
    goDeepLink(ctx, deepLink);
  });
}
```

Rejected alternatives:
- **(b) NavigatorObserver `didPush` trigger**: fires on every nav, requires deduplication; more state than the problem warrants.
- **(c) "router-ready" provider**: introduces a synthetic state-machine; `addPostFrameCallback` already encodes "first frame committed" deterministically.

**Consequences**:
- The auth `redirect` always lands the user before the post-frame callback fires; if the deep-link target requires auth, GoRouter's own redirect bumps them to `/welcome` after `context.go(deepLink)`.
- Tap on an unauthenticated install (cold launch from a notification while signed out) → `context.go('/coach/chat/X')` → router redirect → `/welcome`. Acceptable v1.

**Status**: ACCEPTED

---

### ADR-PN-012 — Permission prompt source flag: derive `profileSetupCompleted` from `userProfile.displayName != null`

**Context**: Spec open question Q2. REQ-PN-PERM-001 needs a "post-onboarding" flag.

**Decision**: Use the router's existing convention: profile setup is complete IFF `userProfileProvider.valueOrNull?.displayName != null`. This is verbatim what `authRedirect` in `lib/app/router.dart:124` checks. No new field on `UserProfile`, no migration, no dual-write.

Permission flow lives in a new `lib/features/notifications/presentation/permission_gate.dart` widget mounted as a sibling inside the `/home` route shell. It:
1. Watches `userProfileProvider` AND `authStateProvider`.
2. Holds a session-scoped `bool _attempted = false`.
3. On first build where `auth.valueOrNull != null && profile.displayName != null && !_attempted`, sets `_attempted = true` and calls `await ref.read(fcmServiceProvider).requestPermission()`.
4. Result is fire-and-forget. Denial path: log only, no UI, no retry within the session.

**Consequences**:
- Reuses the source of truth the router already trusts; if we ever add a real `profileSetupCompleted` field, only two call sites (`authRedirect` + `permission_gate`) change together.
- The gate widget renders a `SizedBox.shrink()` — it exists only for its side effect.
- The Home shell is the first authenticated screen after onboarding, matching the proposal Decision #5.

**Status**: ACCEPTED

---

### ADR-PN-013 — iOS native setup (Info.plist + APNs auth key out-of-band)

**Context**: REQ-PN-CX-001 + REQ-PN-CX-011.

**Decision**:
- `ios/Runner/Info.plist` MUST gain:
  ```xml
  <key>UIBackgroundModes</key>
  <array>
    <string>fetch</string>
    <string>remote-notification</string>
  </array>
  ```
- `AppDelegate.swift` is NOT modified. `firebase_messaging` 15.x handles swizzling automatically.
- APNs auth key (`.p8` from Apple Developer Console) is a manual prerequisite uploaded to the Firebase Console. Documented in `docs/setup/fcm-apns.md` (new doc in PR#1).
- `setForegroundNotificationPresentationOptions` is NOT called. Foreground UX is the in-app SnackBar per Decision #4.

**Consequences**:
- Code merges without the APNs key. iOS smoke test requires the key.
- Android needs zero native changes (Firebase Messaging already in `google-services.json` since auth setup).

**Status**: ACCEPTED

---

### ADR-PN-014 — Testing strategy

**Context**: REQ-PN-CX-012 + REQ-PN-CX-008 (strict TDD).

**Decision**:

| Layer | Tool | What it covers |
|---|---|---|
| CF logic (each trigger) | Jest + firebase-functions-test (online mode) + Firestore + Auth emulator | Guard branches, recipient resolution, body composition, deepLink shape. `messaging()` is INJECTED via the optional 3rd arg of `sendFcm` (ADR-PN-004). |
| `sendFcm` helper | Jest, mocked `messaging()` | Empty-token skip, stale-token arrayRemove on `registration-token-not-registered` and `invalid-registration-token`, success aggregation. |
| `FcmTokenRepository` | `fake_cloud_firestore` | `arrayUnion`/`arrayRemove` shape, missing-field tolerance, removeToken-of-absent is no-op. |
| `FcmService` | `mocktail` over `FirebaseMessaging` and `FcmTokenRepository` | init wires `getToken` + `onTokenRefresh`; dispose calls `removeToken(currentToken)`; permission denial doesn't crash. |
| Deep-link router helper | Widget pump with `MockGoRouter` | Empty/null/invalid → `/coach`; valid → unchanged. |
| Foreground SnackBar | `WidgetTester.pumpWidget` + emitting a fake `RemoteMessage` via a test stream | SnackBar renders, tap fires `goDeepLink`. |
| Permission gate | Widget pump with mocked providers | `_attempted` blocks second call within session; flag-not-set → no call. |
| Real FCM delivery | NOT AUTOMATABLE | Manual smoke on real iOS + real Android. Blocked until APNs key configured. |

**Status**: ACCEPTED

---

### ADR-PN-015 — Trainer-account-deletion cascade gap: acknowledged out-of-scope; PN is incidentally safe

**Context**: Spec SCENARIO-684. The current account-deletion CF has NO `trainerId == uid` cascade — `functions/src/cascade/appointments.ts:33` and `cascade/trainer-links.ts:30-32` query only `athleteId == uid`. If a trainer account were deletable today, the trainer's appointments/links would orphan rather than be cancelled/terminated.

**Decision**:
- Accept the gap for push-notifications-fcm. It is incidentally safe: orphan documents are never mutated by the cascade, so `notifyOnAppointment` and `notifyOnLinkChange` never fire on them. Zero notification spam from orphan data.
- A separate follow-up issue MUST be filed against the `account-deletion` SDD (or a future `trainer-account-deletion` SDD) to add the symmetric paths. Out of scope for THIS change.
- Trainers are seeded server-side and have no self-delete UI today (`delete-account.ts:75-79` rejects `role === 'trainer'`), so the gap is theoretical for now.

**Status**: ACCEPTED (gap documented; follow-up tracked outside this SDD)

---

## 4. File-by-file structure

### PR#1 — Cloud Functions (NEW)

| Path | Purpose | LOC est. |
|---|---|---|
| `functions/src/notifications/send-fcm.ts` | Shared helper (ADR-PN-004). Exports `sendFcm(app, input, messaging?)`. | ~110 |
| `functions/src/notifications/notify-chat-message.ts` | Trigger (ADR-PN-005). `onDocumentCreated('chats/{chatId}/messages/{messageId}')`. | ~80 |
| `functions/src/notifications/notify-appointment.ts` | Trigger (ADR-PN-006). `onDocumentWritten('appointments/{apptId}')`. | ~110 |
| `functions/src/notifications/notify-link-change.ts` | Trigger (ADR-PN-007). `onDocumentWritten('trainer_links/{linkId}')`. | ~90 |
| `functions/src/notifications/notify-review.ts` | Trigger (ADR-PN-008). `onDocumentCreated('reviews/{reviewId}')`. | ~60 |
| `functions/src/__tests__/send-fcm.test.ts` | Empty-token, success, stale-token cleanup. | ~120 |
| `functions/src/__tests__/notify-chat-message.test.ts` | Recipient resolution, truncation. | ~80 |
| `functions/src/__tests__/notify-appointment.test.ts` | Guards (`reason`, no-op), branches. | ~110 |
| `functions/src/__tests__/notify-link-change.test.ts` | Guards, terminated→BOTH. | ~90 |
| `functions/src/__tests__/notify-review.test.ts` | Body + deepLink shape. | ~50 |
| `docs/setup/fcm-apns.md` | APNs auth key + Firebase Console steps. | ~40 |

### PR#1 — Cloud Functions (MODIFIED)

| Path | Change | LOC est. (delta) |
|---|---|---|
| `functions/src/index.ts` | Append 4 exports: `notifyOnChatMessage`, `notifyOnAppointment`, `notifyOnLinkChange`, `notifyOnReview`. | +4 |
| `ios/Runner/Info.plist` | Add `UIBackgroundModes` array (ADR-PN-013). | +5 |

**PR#1 total**: ~950 LOC (test-heavy). Above the 400-line review budget — see §7.

### PR#2 — Flutter client (NEW)

| Path | Purpose | LOC est. |
|---|---|---|
| `lib/features/notifications/data/fcm_token_repository.dart` | `saveToken(uid, token)` / `removeToken(uid, token)` via Firestore `arrayUnion`/`arrayRemove`. | ~50 |
| `lib/features/notifications/data/fcm_service.dart` | Class (ADR-PN-003). Holds `FirebaseMessaging` + `FcmTokenRepository`. Exposes `init(uid)`, `dispose(uid)`, `requestPermission()`, `onForegroundMessage`, `onMessageOpenedApp`, `getInitialMessage()`. | ~140 |
| `lib/features/notifications/application/notification_providers.dart` | `firebaseMessagingProvider`, `fcmTokenRepositoryProvider`, `fcmServiceProvider`, `fcmLifecycleProvider`. | ~70 |
| `lib/features/notifications/application/notification_router.dart` | `goDeepLink(BuildContext, String?)` helper (ADR-PN-009). | ~40 |
| `lib/features/notifications/presentation/permission_gate.dart` | `ConsumerStatefulWidget` (ADR-PN-012). Renders `SizedBox.shrink`; triggers permission once. | ~80 |
| `test/features/notifications/data/fcm_token_repository_test.dart` | `fake_cloud_firestore` based. | ~110 |
| `test/features/notifications/data/fcm_service_test.dart` | `mocktail` based. | ~140 |
| `test/features/notifications/application/notification_router_test.dart` | Fallback + valid path branches. | ~70 |
| `test/features/notifications/presentation/permission_gate_test.dart` | Gate logic. | ~90 |
| `test/features/notifications/presentation/foreground_snackbar_test.dart` | Foreground UX. | ~110 |

### PR#2 — Flutter client (MODIFIED)

| Path | Change | LOC est. (delta) |
|---|---|---|
| `pubspec.yaml` | Add `firebase_messaging: ^15.x`. | +1 |
| `lib/app/app.dart` | Convert to attach foreground subscription (ADR-PN-010), add `addPostFrameCallback` for cold-start tap (ADR-PN-011), add `_scaffoldMessengerKey` to `MaterialApp.router`. Eagerly `ref.read(fcmLifecycleProvider)` to wire init/dispose. | +50 |
| `lib/features/home/home_screen.dart` | Mount `PermissionGate()` once in the build tree. | +2 |
| `ios/Podfile.lock` | Auto-updated by `pod install`. | +~20 (auto) |

**PR#2 total**: ~950 LOC. Above the 400-line review budget — see §7.

### DELETED

None.

---

## 5. PR boundary

| PR | Layer | Why this boundary |
|---|---|---|
| **PR#1** | Cloud Functions + iOS Info.plist + APNs setup doc | CF layer is self-contained: deploys to `southamerica-east1`, can be smoke-tested by writing fake Firestore docs and inspecting logs. Independently revertable (a no-op CF deployed twice is harmless). Info.plist + APNs doc ship with PR#1 because they unblock iOS smoke as soon as the Flutter side lands. |
| **PR#2** | `firebase_messaging` dep + service/repo/providers + handler + permission gate + deep-link router + tests | Has a hard dependency on PR#1 (recipients on the device need tokens that PR#1's CFs will read). Cannot smoke until PR#1 is deployed. |

Both PRs exceed the 400-line review budget. Tasks phase MUST decide chained-stacked PRs or maintainer-approved `size:exception`. See §6.

---

## 6. Review Workload Forecast (passed to tasks phase)

- Estimated changed lines (PR#1): ~950 (most is tests).
- Estimated changed lines (PR#2): ~950 (test-heavy).
- **400-line budget risk**: High (both PRs)
- **Chained PRs recommended**: Yes — split PR#1 into PR#1a `send-fcm` helper + tests, PR#1b 4 triggers + tests. Split PR#2 into PR#2a service+repo+providers+tests, PR#2b handler+permission gate+routing+tests+`app.dart` wiring.
- **Decision needed before apply**: Yes

---

## 7. Risks resolution table

| Proposal Risk | ADR / Mitigation |
|---|---|
| 1. APNs auth key manual prerequisite | ADR-PN-013 — docs/setup/fcm-apns.md; iOS smoke blocked until configured. |
| 2. FCM not emulatable | ADR-PN-014 — jest+emulator covers logic, mocked `messaging()` via injected param. Real delivery manual. |
| 3. iOS foreground suppression | Decision #4 unchanged → ADR-PN-010 in-app SnackBar via root `scaffoldMessengerKey`. |
| 4. Account-deletion cascade asymmetry | ADR-PN-006 + ADR-PN-007 guard on `reason` per collection. ADR-PN-015 documents trainer-side gap (incidentally safe). |
| 5. iOS sticky permission denial | ADR-PN-012 — gate fires once per session, denial path is log-only. |
| 6. Token cleanup race | ADR-PN-004 — per-token error inspection in helper; idempotent `arrayRemove`. |
| 7. Group chat fan-out | Out of scope v1 (data model is 1:1). ADR-PN-005 nonetheless supports N recipients via `members.filter`. |
| 8. Cross-device race | Accepted — `arrayUnion` is commutative, multiple devices converge. |

---

## 8. Open questions for tasks phase

1. **Chained PR split**: confirm the 4-slice split in §6 is acceptable, or fall back to `size:exception` on both PRs.
2. **`UIBackgroundModes` collision**: if `Info.plist` already contains `UIBackgroundModes`, merge the array; verify during PR#1 implementation. (Quick check: `bat ios/Runner/Info.plist | rg UIBackgroundModes`).

All other questions closed by ADRs above.

---

## 9. Hard constraints (enforceable)

1. NO `flutter_local_notifications` dependency.
2. NO new Firestore collections / sub-collections.
3. NO `firestore.rules` changes.
4. NO `storage.rules` changes.
5. NO new Firestore indexes.
6. All 4 CFs declared with `{ region: 'southamerica-east1' }`.
7. Every notification body ≤ 256 chars; chat preview ≤ 100 chars.
8. `notifyOnAppointment` skips when `after.reason === 'athlete-account-deleted'`.
9. `notifyOnLinkChange` skips when `after.reason === 'account-deleted'`.
10. `notifyOnAppointment` and `notifyOnLinkChange` skip when `before?.status === after.status`.
11. Permission prompt at most once per session, only when `userProfileProvider.valueOrNull?.displayName != null`.
12. Every es-AR string tagged `// i18n: Fase 6 Etapa 2`.
13. Zero HEX literals; zero `PhosphorIcons.X` direct references (use `AppPalette.of(context)` and `TreinoIcon.X`).
14. Strict TDD — RED before GREEN on every task pair.
15. Conventional commits — no `Co-Authored-By`, no AI attribution.
16. Token field is `fcmTokens` (camelCase), array of strings, on `users/{uid}`.
17. Token writes use `arrayUnion`; removes use `arrayRemove`. No transactions.
18. `sendFcm` accepts an optional `messaging` arg for test injection.
19. `goDeepLink` fallback is `/coach`; invalid paths log + fall back, never throw.
20. APNs auth key is a manual prerequisite — gates iOS smoke only, not code merge.

---

## 10. Artifact references

- Proposal: `openspec/changes/push-notifications-fcm/proposal.md` + Engram `sdd/push-notifications-fcm/proposal` (#138)
- Spec: `openspec/changes/push-notifications-fcm/spec.md` + Engram `sdd/push-notifications-fcm/spec` (#139)
- Explore: `openspec/changes/push-notifications-fcm/explore.md` + Engram `sdd/push-notifications-fcm/explore` (#137)
- Verified files (this session): `lib/app/app.dart`, `lib/app/router.dart`, `lib/features/profile/application/user_providers.dart`, `lib/features/profile/data/user_repository.dart`, `lib/features/profile/domain/user_profile.dart`, `lib/features/coach/domain/trainer_public_profile.dart`, `lib/features/profile/data/account_deletion_service.dart`, `lib/features/profile/application/account_deletion_notifier.dart`, `lib/features/coach/application/trainer_link_providers.dart`, `lib/features/chat/domain/message.dart`, `lib/features/profile_setup/application/profile_setup_providers.dart`, `lib/features/auth/data/auth_service.dart`, `functions/src/index.ts`, `functions/src/delete-account.ts`, `functions/src/review-aggregate.ts`, `functions/src/cascade/appointments.ts`, `functions/src/cascade/trainer-links.ts`.

---

**Status**: Ready for `sdd-tasks`. ADR-PN-001 supersedes the proposal/spec mention of snake_case `fcm_tokens` → use `fcmTokens` everywhere downstream.
