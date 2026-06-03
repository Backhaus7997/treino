# Tasks: push-notifications-fcm

**Change**: push-notifications-fcm
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-03
**PRs**: 4 chained PRs against `main` (stacked-to-main)
**Artifact store**: hybrid (file `openspec/changes/push-notifications-fcm/tasks.md` + Engram `sdd/push-notifications-fcm/tasks`)
**Phase**: Fase 6 Etapa 2

---

## Summary

62 tasks across 4 chained PRs. Total estimated ~1,550 LOC (test-heavy). Chain strategy: stacked-to-main — each PR merges to main in order, the next rebases before implementation begins. Strict TDD throughout: every implementation task is preceded by a RED task (failing test commit) then a GREEN task (passing implementation commit).

---

## Review Workload Forecast

| Field | PR#1a | PR#1b | PR#2a | PR#2b |
|---|---|---|---|---|
| Estimated changed lines | ~250 | ~450 | ~400 | ~450 |
| 400-line budget risk | Low | Medium | Medium | Medium |
| Chained PRs recommended | Yes | Yes | Yes | Yes |
| Decision needed before apply | No (already decided) | No | No | No |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: Medium (PR#1b, PR#2a, PR#2b highest)

Chained PRs recommended: Yes. Chain strategy: stacked-to-main. Delivery strategy: chained-pr (user signed off 4 sub-PRs on 2026-06-03). Original design estimated ~950 LOC per original 2-PR plan; the 4-slice split keeps each PR within a reviewable range.

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|---|---|---|---|
| PR#1a | `send-fcm` shared helper + jest tests | PR#1a | Base: `main`; CF layer only; standalone deploy |
| PR#1b | 4 CF triggers + jest tests + `Info.plist` + APNs doc | PR#1b | Base: `main`, rebase after PR#1a merges; depends on PR#1a |
| PR#2a | Flutter `FcmTokenRepository` + `FcmService` + Riverpod providers + tests | PR#2a | Base: `main`, rebase after PR#1b merges; adds `firebase_messaging` dep |
| PR#2b | Foreground SnackBar + cold-start handler + permission gate + deep-link router + `app.dart` wiring + tests | PR#2b | Base: `main`, rebase after PR#2a merges |

---

## Risk Resolutions (pre-verified)

| Risk | Resolution |
|---|---|
| APNs auth key manual prerequisite | ADR-PN-013: `docs/setup/fcm-apns.md` created in PR#1b; iOS smoke blocked until key configured; NOT a code-merge blocker |
| FCM not emulatable | ADR-PN-014: jest+emulator covers logic; `messaging()` injected via optional 3rd arg in `sendFcm`; real delivery validated manually |
| iOS foreground suppression | ADR-PN-010: in-app SnackBar via root `_scaffoldMessengerKey` — no native foreground suppression needed |
| Account-deletion cascade guards | ADR-PN-006: `notifyOnAppointment` skips on `after.reason === 'athlete-account-deleted'`; ADR-PN-007: `notifyOnLinkChange` skips on `after.reason === 'account-deleted'` |
| Trainer-side cascade gap | ADR-PN-015: incidentally safe (trainer accounts not self-deletable); follow-up issue MUST be filed against `account-deletion` SDD |
| `cancelledBy` field absent | ADR-PN-006: `notifyOnAppointment` defaults to "notify both" when `after.cancelledBy` is absent; TODO comment in source |
| `Info.plist` UIBackgroundModes merge | Pre-verified: current `Info.plist` has NO `UIBackgroundModes` key → PR#1b adds it fresh (no merge conflict) |
| iOS sticky permission denial | ADR-PN-012: `_attempted` flag blocks second call within session; denial is log-only, no retry |
| Token cleanup race | ADR-PN-004: per-token `BatchResponse` error inspection; `arrayRemove` is idempotent |
| Token field naming | ADR-PN-001: field is `fcmTokens` (camelCase) everywhere — supersedes any snake_case in proposal/spec |

---

## Branch + Base per PR

| PR | Branch | Base |
|---|---|---|
| PR#1a | `feat/push-notifications-pr1a-send-fcm-helper` | `main` |
| PR#1b | `feat/push-notifications-pr1b-cf-triggers` | `main` (rebase after PR#1a merges) |
| PR#2a | `feat/push-notifications-pr2a-flutter-service` | `main` (rebase after PR#1b merges) |
| PR#2b | `feat/push-notifications-pr2b-flutter-handler` | `main` (rebase after PR#2a merges) |

---

## PR#1a — Send-FCM Helper (~250 LOC)

**REQs covered**: REQ-PN-CF-001, REQ-PN-CX-009, REQ-PN-CX-012
**SCENARIOs covered**: 625–628, 677

### Phase 1a.1: Branch setup

- [ ] T-PN-001 — SETUP: create branch `feat/push-notifications-pr1a-send-fcm-helper` from `main`; confirm clean working tree; verify `functions/src/index.ts` exports only `deleteAccount` and `reviewAggregate`.

### Phase 1a.2: `sendFcm` helper — signature + token fan-out

- [ ] T-PN-002 — RED: create `functions/src/__tests__/send-fcm.test.ts`; failing tests: empty `uids[]` → no Firestore reads, no `sendEachForMulticast`, no error (SCENARIO-677); single uid with single token → `sendEachForMulticast` called with `[token]` (SCENARIO-625); two uids each with one token → `sendEachForMulticast` called with both tokens flattened (SCENARIO-625); uid with empty/absent `fcmTokens` → skipped silently with a log line (SCENARIO-628).
- [ ] T-PN-003 — GREEN: create `functions/src/notifications/send-fcm.ts`; export `SendFcmInput` interface `{ uids: string[], notification: { title: string, body: string }, data: Record<string, string> }`; export `SendFcmResult` interface `{ successCount: number, failureCount: number }`; export `async function sendFcm(app, input, messaging?)` — reads `users/{uid}.fcmTokens` per uid via `Promise.all`; logs and skips empty/absent arrays; calls `messaging.sendEachForMulticast({ tokens, notification, data })`; returns aggregated result; T-PN-002 must pass. (SCENARIO-625, 628, 677)

### Phase 1a.3: `sendFcm` helper — stale token cleanup

- [ ] T-PN-004 — RED: extend `functions/src/__tests__/send-fcm.test.ts`; failing tests: uid with `['tok-valid', 'tok-stale']` where FCM returns `messaging/registration-token-not-registered` for `tok-stale` → `arrayRemove('tok-stale')` called on `users/{uid}.fcmTokens`, `tok-valid` remains (SCENARIO-626); uid with `['tok-invalid']` where FCM returns `messaging/invalid-registration-token` → `arrayRemove('tok-invalid')` called (SCENARIO-627).
- [ ] T-PN-005 — GREEN: extend `sendFcm` — iterate `BatchResponse.responses[i]`; when `error?.code` is `messaging/registration-token-not-registered` or `messaging/invalid-registration-token`, call `arrayRemove(token)` on that token's owner uid document; healthy tokens not affected; T-PN-004 must pass. (SCENARIO-626, 627)

### Phase 1a.4: PR#1a quality gates

- [ ] T-PN-006 — GATE: `npm --prefix functions run build` 0 errors; `npm --prefix functions run lint` 0 warnings/errors.
- [ ] T-PN-007 — GATE: `firebase emulators:exec --only firestore,auth "npm --prefix functions test"` — all tests pass; delta ≥ +6 tests vs baseline (covering SCENARIO-625..628, 677).
- [ ] T-PN-008 — VERIFY: no Flutter files changed; no `pubspec.yaml` changes; no `ios/` changes; no `firestore.rules` changes; no `storage.rules` changes; no `firestore.indexes.json` changes; `functions/src/index.ts` NOT yet modified (exports added in PR#1b); conventional commits only; no Co-Authored-By.

---

## PR#1b — CF Triggers + Info.plist (~450 LOC)

**REQs covered**: REQ-PN-CF-002, REQ-PN-CF-003, REQ-PN-CF-004, REQ-PN-CF-005, REQ-PN-CF-006, REQ-PN-CX-001, REQ-PN-CX-003, REQ-PN-CX-006, REQ-PN-CX-009, REQ-PN-CX-010, REQ-PN-CX-012
**SCENARIOs covered**: 629–643, 664, 666, 676, 680–681

### Phase 1b.1: Branch setup

- [ ] T-PN-009 — SETUP: create branch `feat/push-notifications-pr1b-cf-triggers` from post-PR#1a `main`; confirm clean rebase; verify `functions/src/notifications/send-fcm.ts` exists from PR#1a.

### Phase 1b.2: `notifyOnChatMessage` trigger

- [ ] T-PN-010 — RED: create `functions/src/__tests__/notify-chat-message.test.ts`; failing tests: new message in chat with `members: ['athlete-uid', 'trainer-uid']` and `senderId: 'athlete-uid'` → `sendFcm` called with `uids: ['trainer-uid']` (SCENARIO-629); sender NOT in uids (SCENARIO-680); body contains sender name + truncated text; text of 150 chars → body text portion ≤ 100 chars (SCENARIO-630); total body ≤ 256 chars (SCENARIO-666); `data.deepLink == "/coach/chat/chat-abc?other=uid-xyz"` (SCENARIO-631).
- [ ] T-PN-011 — GREEN: create `functions/src/notifications/notify-chat-message.ts`; export `notifyOnChatMessage` via `onDocumentCreated('chats/{chatId}/messages/{messageId}', { region: 'southamerica-east1' })`; reads `chats/{chatId}.members`; `recipients = members.filter(m => m !== msg.senderId)`; reads `userPublicProfiles/{senderId}.displayName ?? 'Alguien'`; body = `"${senderName}: ${truncate(text, 100)}"` with `…` if cut; `deepLink = "/coach/chat/${chatId}?other=${senderId}"`; all string literals tagged `// i18n: Fase 6 Etapa 2`; calls `sendFcm`; T-PN-010 must pass. (SCENARIO-629, 630, 631, 666, 680)

### Phase 1b.3: `notifyOnAppointment` trigger

- [ ] T-PN-012 — RED: create `functions/src/__tests__/notify-appointment.test.ts`; failing tests: new doc with `status: 'requested'` → `sendFcm` called with `uids: [trainerId]`, `data.deepLink == "/coach/agenda"` (SCENARIO-632); `before.status == 'requested'` → `after.status == 'confirmed'` → `sendFcm` called with `uids: [athleteId]`, `data.deepLink == "/coach?tab=agenda"` (SCENARIO-633); `before.status == 'confirmed'` → `after.status == 'cancelled'`, reason absent → `sendFcm` called with other-party uid (SCENARIO-634); `after.reason == 'athlete-account-deleted'` → `sendFcm` NOT called, no error (SCENARIO-635); `before.status == after.status` → `sendFcm` NOT called (SCENARIO-636).
- [ ] T-PN-013 — GREEN: create `functions/src/notifications/notify-appointment.ts`; export `notifyOnAppointment` via `onDocumentWritten('appointments/{apptId}', { region: 'southamerica-east1' })`; guards: missing `after` → skip; `after.reason === 'athlete-account-deleted'` → skip; `before?.status === after.status` → skip; branch `requested` → notify trainer `"/coach/agenda"`; branch `confirmed` → notify athlete `"/coach?tab=agenda"`; branch `cancelled` → use `after.cancelledBy` if present else notify both (`// TODO: cancelledBy not yet in appointments schema — defaults to both; update when field added`); all strings es-AR tagged `// i18n: Fase 6 Etapa 2`; T-PN-012 must pass. (SCENARIO-632..636)

### Phase 1b.4: `notifyOnLinkChange` trigger

- [ ] T-PN-014 — RED: create `functions/src/__tests__/notify-link-change.test.ts`; failing tests: new doc `status: 'pending'` → `sendFcm` called with `uids: [trainerId]`, `data.deepLink == "/coach"` (SCENARIO-637); `pending → active` → `sendFcm` called with `uids: [athleteId]` (SCENARIO-638); `active → terminated`, reason absent → `sendFcm` called with `uids: [athleteId, trainerId]` (SCENARIO-639); `after.reason == 'account-deleted'` → `sendFcm` NOT called (SCENARIO-640); `before.status == after.status` → `sendFcm` NOT called (SCENARIO-641).
- [ ] T-PN-015 — GREEN: create `functions/src/notifications/notify-link-change.ts`; export `notifyOnLinkChange` via `onDocumentWritten('trainer_links/{linkId}', { region: 'southamerica-east1' })`; guards: missing `after` → skip; `after.reason === 'account-deleted'` → skip; `before?.status === after.status` → skip; branch `pending` → notify trainer; branch `active` → notify athlete; branch `terminated` → notify BOTH; deepLink `"/coach"` for all; all strings es-AR tagged `// i18n: Fase 6 Etapa 2`; T-PN-014 must pass. (SCENARIO-637..641)

### Phase 1b.5: `notifyOnReview` trigger

- [ ] T-PN-016 — RED: create `functions/src/__tests__/notify-review.test.ts`; failing tests: new review with `trainerId: 'trainer-1'`, `athleteDisplayName: 'Juan'`, `rating: 5` → `sendFcm` called with `uids: ['trainer-1']`, body `"Juan dejó una reseña de 5⭐"`, `data.deepLink == "/coach/trainer/trainer-1"` (SCENARIO-642); trainer with empty `fcmTokens` → `sendFcm` silently skips (SCENARIO-681).
- [ ] T-PN-017 — GREEN: create `functions/src/notifications/notify-review.ts`; export `notifyOnReview` via `onDocumentCreated('reviews/{reviewId}', { region: 'southamerica-east1' })`; reads `review.trainerId`, `review.athleteId`, `review.rating`; looks up `userPublicProfiles/{athleteId}.displayName ?? 'Un atleta'`; body = `"${athleteName} dejó una reseña de ${rating}⭐"` tagged `// i18n: Fase 6 Etapa 2`; deepLink = `"/coach/trainer/${review.trainerId}"`; calls `sendFcm`; T-PN-016 must pass. (SCENARIO-642, 681)

### Phase 1b.6: Export all 4 CFs from `index.ts`

- [ ] T-PN-018 — GREEN: edit `functions/src/index.ts` — append exports for `notifyOnChatMessage`, `notifyOnAppointment`, `notifyOnLinkChange`, `notifyOnReview` alongside existing `deleteAccount` and `reviewAggregate` exports. (SCENARIO-643)

### Phase 1b.7: iOS `Info.plist` + APNs setup doc

- [ ] T-PN-019 — GREEN: edit `ios/Runner/Info.plist` — add `UIBackgroundModes` array with `fetch` and `remote-notification` entries (pre-verified: key does not currently exist, no merge needed); entry goes adjacent to `UIApplicationSceneManifest`. (SCENARIO-664, REQ-PN-CX-001, ADR-PN-013)
- [ ] T-PN-020 — GREEN: create `docs/setup/fcm-apns.md` documenting the APNs auth key steps: Apple Developer Console → Certificates, Identifiers & Profiles → Keys → create key with Apple Push Notifications capability → download `.p8`; Firebase Console → Project Settings → Cloud Messaging → iOS app → upload auth key with Key ID and Team ID; note: this is a prerequisite for iOS smoke only, not for code merge. (REQ-PN-CX-011, ADR-PN-013)

### Phase 1b.8: PR#1b quality gates

- [ ] T-PN-021 — GATE: `npm --prefix functions run build` 0 errors; `npm --prefix functions run lint` 0 warnings/errors.
- [ ] T-PN-022 — GATE: `firebase emulators:exec --only firestore,auth "npm --prefix functions test"` — all tests pass; delta ≥ +18 tests vs PR#1a baseline (covering SCENARIO-629..643, 676, 680, 681).
- [ ] T-PN-023 — VERIFY: no Flutter lib files changed; no `pubspec.yaml` changes; `firestore.rules` unchanged; `storage.rules` unchanged; `firestore.indexes.json` unchanged; `Info.plist` only adds `UIBackgroundModes` block; all CF bodies ≤ 256 chars; all es-AR strings tagged `// i18n: Fase 6 Etapa 2`; `cancelledBy` TODO comment present in `notify-appointment.ts`; conventional commits only; no Co-Authored-By.

---

## PR#2a — Flutter Data + Service (~400 LOC)

**REQs covered**: REQ-PN-DATA-001, REQ-PN-DATA-002, REQ-PN-DATA-003, REQ-PN-DATA-004, REQ-PN-CLIENT-001, REQ-PN-CLIENT-002, REQ-PN-CLIENT-003, REQ-PN-CLIENT-004, REQ-PN-CX-004, REQ-PN-CX-008, REQ-PN-CX-009
**SCENARIOs covered**: 619–624, 644–651, 667, 678, 679, 683

### Phase 2a.1: Branch setup + dependency

- [ ] T-PN-024 — SETUP: create branch `feat/push-notifications-pr2a-flutter-service` from post-PR#1b `main`; confirm clean rebase; add `firebase_messaging: ^15.x` to `pubspec.yaml` under `dependencies`; run `flutter pub get`; confirm `flutter_local_notifications` is NOT present. (SCENARIO-644, REQ-PN-CLIENT-001, REQ-PN-CX-002)

### Phase 2a.2: `FcmTokenRepository`

- [ ] T-PN-025 — RED: create `test/features/notifications/data/fcm_token_repository_test.dart` using `fake_cloud_firestore`; failing tests: `saveToken` on new doc with no `fcmTokens` field → `users/{uid}.fcmTokens == ['tok-1']` (SCENARIO-619); `saveToken` with duplicate token → `fcmTokens` still `['tok-1']` (SCENARIO-620); `saveToken` with second device → `fcmTokens == ['tok-phone', 'tok-tablet']` (SCENARIO-621); `removeToken` → `['tok-2']` (SCENARIO-622); removing absent token → no error, array unchanged (SCENARIO-623); `saveToken` uses `arrayUnion` semantics (SCENARIO-621); `removeToken` uses `arrayRemove` semantics (SCENARIO-622, 623).
- [ ] T-PN-026 — GREEN: create `lib/features/notifications/data/fcm_token_repository.dart`; class `FcmTokenRepository` with `final FirebaseFirestore _firestore`; `Future<void> saveToken(String uid, String token)` → `_firestore.collection('users').doc(uid).update({'fcmTokens': FieldValue.arrayUnion([token])})` with `SetOptions(merge: true)` fallback for missing doc; `Future<void> removeToken(String uid, String token)` → `_firestore.collection('users').doc(uid).update({'fcmTokens': FieldValue.arrayRemove([token])})` swallowing `not-found`; field name is `fcmTokens` (camelCase, ADR-PN-001); T-PN-025 must pass. (SCENARIO-619..623, REQ-PN-DATA-001..003)

### Phase 2a.3: `FcmService`

- [ ] T-PN-027 — RED: create `test/features/notifications/data/fcm_service_test.dart` using `mocktail`; failing tests: `init(uid)` calls `getToken()` once and `saveToken(uid, 'tok-init')` (SCENARIO-645); `init(uid)` does NOT call `requestPermission()` (SCENARIO-647); `onTokenRefresh` emits `'tok-refreshed'` → `saveToken(uid, 'tok-refreshed')` called (SCENARIO-646); `getToken()` returns null → `saveToken` NOT called, no error (SCENARIO-678); `dispose(uid)` → `removeToken(uid, currentToken)` called (SCENARIO-648); `FcmTokenRepository.removeToken` throws → error swallowed, no propagation (SCENARIO-649); `dispose(uid)` cancels `onTokenRefresh` subscription → subsequent refresh events do not trigger `saveToken` (SCENARIO-679).
- [ ] T-PN-028 — GREEN: create `lib/features/notifications/data/fcm_service.dart`; class `FcmService` with `final FirebaseMessaging _messaging` and `final FcmTokenRepository _repo`; `Future<void> init(String uid)` — calls `getToken()`, calls `saveToken` if non-null, subscribes to `onTokenRefresh` storing the subscription; `Future<void> dispose(String uid)` — calls `getToken()` + `removeToken` in try/catch, cancels refresh subscription; does NOT call `requestPermission()` in `init`; `Stream<RemoteMessage> get onForegroundMessage => _messaging.onMessage`; `Stream<RemoteMessage> get onMessageOpenedApp => FirebaseMessaging.onMessageOpenedApp`; `Future<RemoteMessage?> getInitialMessage() => _messaging.getInitialMessage()`; `Future<void> requestPermission() => _messaging.requestPermission()`; T-PN-027 must pass. (SCENARIO-645..649, 678, 679)

### Phase 2a.4: Riverpod providers + lifecycle

- [ ] T-PN-029 — RED: create `test/features/notifications/application/fcm_providers_test.dart` using `mocktail`; failing tests: `fcmLifecycleProvider` live + `authStateProvider` emits non-null uid → `FcmService.init(uid)` called (SCENARIO-650); `authStateProvider` emits null after sign-in → `FcmService.dispose(previousUid)` called (SCENARIO-651); foreground handler not attached before user is authenticated → no navigation or SnackBar crash (SCENARIO-683).
- [ ] T-PN-030 — GREEN: create `lib/features/notifications/application/notification_providers.dart`; `firebaseMessagingProvider` (Provider<FirebaseMessaging> → `FirebaseMessaging.instance`); `fcmTokenRepositoryProvider` (Provider<FcmTokenRepository>); `fcmServiceProvider` (Provider<FcmService>); `fcmLifecycleProvider` (Provider<void>) — uses `ref.listen(authStateProvider, (prev, next) { if next.uid != null → init; else if prev.uid != null → dispose(prev.uid) })`; T-PN-029 must pass. (SCENARIO-650, 651, 683, ADR-PN-003)

### Phase 2a.5: PR#2a quality gates

- [ ] T-PN-031 — GATE: `flutter analyze` 0 issues; `dart format --output=none --set-exit-if-changed .` 0 changed.
- [ ] T-PN-032 — GATE: `flutter test` — all passing; delta ≥ +20 tests vs PR#1b baseline (covering SCENARIO-619..624, 645..651, 678, 679, 683).
- [ ] T-PN-033 — VERIFY: `firebase_messaging: ^15.x` present in `pubspec.yaml`; `flutter_local_notifications` absent; `firestore.rules` unchanged; `storage.rules` unchanged; `firestore.indexes.json` unchanged; field name `fcmTokens` (camelCase) used consistently; no HEX literals; no `PhosphorIcons.X` direct; conventional commits only; no Co-Authored-By.

---

## PR#2b — Flutter Handler + UI (~450 LOC)

**REQs covered**: REQ-PN-HANDLER-001, REQ-PN-HANDLER-002, REQ-PN-HANDLER-003, REQ-PN-PERM-001, REQ-PN-PERM-002, REQ-PN-CX-002, REQ-PN-CX-005, REQ-PN-CX-006, REQ-PN-CX-007, REQ-PN-CX-008, REQ-PN-CX-009, REQ-PN-CX-010
**SCENARIOs covered**: 652–663, 665, 668–675, 682, 684

### Phase 2b.1: Branch setup

- [ ] T-PN-034 — SETUP: create branch `feat/push-notifications-pr2b-flutter-handler` from post-PR#2a `main`; confirm clean rebase; verify `FcmService` and `notification_providers.dart` exist from PR#2a.

### Phase 2b.2: `goDeepLink` router helper

- [ ] T-PN-035 — RED: create `test/features/notifications/application/notification_router_test.dart`; failing widget tests: `goDeepLink(context, null)` → `context.go('/coach')` (SCENARIO-654); `goDeepLink(context, '')` → `context.go('/coach')` (SCENARIO-654); `goDeepLink(context, 'no-leading-slash')` → logs error + `context.go('/coach')` (SCENARIO-682); `goDeepLink(context, '/coach/chat/abc?other=xyz')` → `context.go('/coach/chat/abc?other=xyz')` (SCENARIO-653); `goDeepLink(context, '/coach?tab=agenda')` → `context.go('/coach?tab=agenda')` (SCENARIO-655).
- [ ] T-PN-036 — GREEN: create `lib/features/notifications/application/notification_router.dart`; export `void goDeepLink(BuildContext context, String? deepLink)` per ADR-PN-009: const `fallback = '/coach'`; null/empty → `context.go(fallback)`; no leading `/` → `debugPrint('[fcm] invalid deepLink: ...')` + `context.go(fallback)`; valid → `context.go(deepLink)`; callers check `context.mounted` before calling; T-PN-035 must pass. (SCENARIO-653, 654, 655, 682)

### Phase 2b.3: Foreground SnackBar handler tests

- [ ] T-PN-037 — RED: create `test/features/notifications/presentation/foreground_snackbar_test.dart`; failing widget tests: `FirebaseMessaging.onMessage` emits message with `title: 'Hola'`, `body: 'Mensaje'` → SnackBar visible containing 'Hola' and 'Mensaje' (SCENARIO-652); tapping SnackBar action → `goDeepLink` called with `data['deepLink']` (SCENARIO-653); `data['deepLink']` absent → `goDeepLink` receives null (SCENARIO-654); permission denied → no SnackBar shown (SCENARIO-663).
- [ ] T-PN-038 — RED: create `test/features/notifications/application/notification_handler_test.dart`; failing tests: `onMessageOpenedApp` fires with `deepLink: '/coach?tab=agenda'` → `goDeepLink('/coach?tab=agenda')` called (SCENARIO-655); `onMessageOpenedApp` fires with no deepLink → `goDeepLink(null)` called (SCENARIO-656); `getInitialMessage()` returns message with `deepLink: '/coach/trainer/uid-1'` → navigation deferred to post-frame, `goDeepLink('/coach/trainer/uid-1')` called after first frame (SCENARIO-657); `getInitialMessage()` returns null → no navigation, no error (SCENARIO-658).

### Phase 2b.4: Permission gate

- [ ] T-PN-039 — RED: create `test/features/notifications/presentation/permission_gate_test.dart`; failing widget tests: `userProfile.displayName != null` and `_attempted == false` on first build → `requestPermission()` called once (SCENARIO-659); `displayName == null` → `requestPermission()` NOT called (SCENARIO-660); re-render after first permission call → `requestPermission()` NOT called again (SCENARIO-661); `requestPermission()` returns denied → app continues normally, no SnackBar, no retry (SCENARIO-662).

### Phase 2b.5: `PermissionGate` widget + foreground handler GREEN

- [ ] T-PN-040 — GREEN: create `lib/features/notifications/presentation/permission_gate.dart`; `ConsumerStatefulWidget` per ADR-PN-012; holds `bool _attempted = false`; on build where `authStateProvider.valueOrNull != null && userProfileProvider.valueOrNull?.displayName != null && !_attempted` → sets `_attempted = true`, calls `await ref.read(fcmServiceProvider).requestPermission()` in fire-and-forget; renders `SizedBox.shrink()`; denial swallowed (log only); T-PN-039 must pass. (SCENARIO-659..662, ADR-PN-012)
- [ ] T-PN-041 — GREEN: implement foreground SnackBar stream attachment — T-PN-037 and T-PN-038 must pass (covered in next task as part of `app.dart` wiring).

### Phase 2b.6: `app.dart` wiring — foreground + cold-start + lifecycle

- [ ] T-PN-042 — GREEN: edit `lib/app/app.dart`; convert `TreinoApp` to `ConsumerStatefulWidget` if not already; add `GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey` and pass to `MaterialApp.router(scaffoldMessengerKey: ...)`; in `initState` after router build: (a) attach `ref.read(fcmServiceProvider).onForegroundMessage.listen(_onForeground)` storing subscription in `_fgSub`; (b) add `WidgetsBinding.instance.addPostFrameCallback((_) async { ... })` for `getInitialMessage()` cold-start per ADR-PN-011; (c) call `ref.read(fcmLifecycleProvider)` to wire auth lifecycle; cancel `_fgSub` in `dispose()`; `_onForeground` handler resolves context from `_router.routerDelegate.navigatorKey.currentContext` — if null, swallow; calls `ScaffoldMessenger.maybeOf(context)?.showSnackBar(...)` with 4s duration and action calling `goDeepLink`; T-PN-037 and T-PN-038 must pass. (SCENARIO-652, 653, 654, 655, 656, 657, 658, ADR-PN-010, ADR-PN-011)

### Phase 2b.7: Mount `PermissionGate` in home shell

- [ ] T-PN-043 — GREEN: edit `lib/features/home/home_screen.dart`; mount `PermissionGate()` once in the build tree as a sibling widget; renders `SizedBox.shrink()` so no layout impact. (REQ-PN-PERM-001, ADR-PN-012)

### Phase 2b.8: Follow-up issue deliverable

- [ ] T-PN-044 — DELIVERABLE: file a GitHub issue titled "Trainer-account-deletion cascade symmetry — add trainerId paths to appointments + trainer_links cascade" against the `account-deletion` SDD; reference ADR-PN-015 and SCENARIO-684; note: `delete-account.ts:75-79` currently rejects `role === 'trainer'` so gap is theoretical; issue ensures it is not forgotten when trainer self-delete is added. (ADR-PN-015)

### Phase 2b.9: PR#2b quality gates

- [ ] T-PN-045 — GATE: `flutter analyze` 0 issues; `dart format --output=none --set-exit-if-changed .` 0 changed.
- [ ] T-PN-046 — GATE: `flutter test` — all passing; delta ≥ +25 tests vs PR#2a baseline (covering SCENARIO-652..663, 682).
- [ ] T-PN-047 — VERIFY: `flutter_local_notifications` absent from `pubspec.yaml`; `storage.rules` unchanged; `firestore.rules` unchanged; `firestore.indexes.json` unchanged; 0 HEX literals in new Dart files (`rg '#[0-9a-fA-F]{3,8}' lib/features/notifications/`); 0 direct `PhosphorIcons.X` references; all user-facing strings tagged `// i18n: Fase 6 Etapa 2`; `_scaffoldMessengerKey` passed to `MaterialApp.router`; `_fgSub` cancelled in `dispose()`; `context.mounted` checked before `goDeepLink` calls; `_attempted` flag blocks second permission call; GitHub follow-up issue filed (T-PN-044); conventional commits only; no Co-Authored-By.

---

## Coverage Matrix: REQ → Tasks → SCENARIOs

| REQ | Tasks | SCENARIOs |
|---|---|---|
| REQ-PN-DATA-001 | T-PN-025, T-PN-026 | 619, 620 |
| REQ-PN-DATA-002 | T-PN-025, T-PN-026 | 621 |
| REQ-PN-DATA-003 | T-PN-025, T-PN-026 | 622, 623 |
| REQ-PN-DATA-004 | T-PN-033 (VERIFY) | 624 |
| REQ-PN-CF-001 | T-PN-002, T-PN-003, T-PN-004, T-PN-005 | 625, 626, 627, 628, 677 |
| REQ-PN-CF-002 | T-PN-010, T-PN-011 | 629, 630, 631, 680 |
| REQ-PN-CF-003 | T-PN-012, T-PN-013 | 632, 633, 634, 635, 636, 684 |
| REQ-PN-CF-004 | T-PN-014, T-PN-015 | 637, 638, 639, 640, 641 |
| REQ-PN-CF-005 | T-PN-016, T-PN-017 | 642, 681 |
| REQ-PN-CF-006 | T-PN-018 | 643 |
| REQ-PN-CLIENT-001 | T-PN-024, T-PN-033 | 644 |
| REQ-PN-CLIENT-002 | T-PN-027, T-PN-028 | 645, 646, 647, 678 |
| REQ-PN-CLIENT-003 | T-PN-027, T-PN-028 | 648, 649, 679 |
| REQ-PN-CLIENT-004 | T-PN-029, T-PN-030 | 650, 651, 683 |
| REQ-PN-HANDLER-001 | T-PN-035, T-PN-036, T-PN-037, T-PN-041, T-PN-042 | 652, 653, 654, 682 |
| REQ-PN-HANDLER-002 | T-PN-038, T-PN-042 | 655, 656 |
| REQ-PN-HANDLER-003 | T-PN-038, T-PN-042 | 657, 658 |
| REQ-PN-PERM-001 | T-PN-039, T-PN-040, T-PN-043 | 659, 660, 661 |
| REQ-PN-PERM-002 | T-PN-039, T-PN-040 | 662, 663 |
| REQ-PN-CX-001 | T-PN-019 | 664 |
| REQ-PN-CX-002 | T-PN-024, T-PN-047 | 665 |
| REQ-PN-CX-003 | T-PN-010, T-PN-011 | 666 |
| REQ-PN-CX-004 | T-PN-008, T-PN-023, T-PN-033, T-PN-047 (VERIFY steps) | 667 |
| REQ-PN-CX-005 | T-PN-008, T-PN-023, T-PN-033, T-PN-047 (VERIFY steps) | 668 |
| REQ-PN-CX-006 | T-PN-011, T-PN-013, T-PN-015, T-PN-017, T-PN-047 | 669 |
| REQ-PN-CX-007 | T-PN-033, T-PN-047 | 670 |
| REQ-PN-CX-008 | All RED/GREEN task pairs | 671 |
| REQ-PN-CX-009 | T-PN-008, T-PN-023, T-PN-033, T-PN-047 (VERIFY steps) | 672 |
| REQ-PN-CX-010 | T-PN-008, T-PN-023, T-PN-033, T-PN-047 (VERIFY steps) | 673, 674 |
| REQ-PN-CX-011 | T-PN-020 | 675 |
| REQ-PN-CX-012 | T-PN-007, T-PN-022 (emulator gates) | 676 |

---

## Pre-PR Checklist per PR

### PR#1a — Send-FCM Helper
- [ ] T-PN-001 (SETUP) complete
- [ ] T-PN-002..T-PN-005 RED/GREEN pairs complete
- [ ] T-PN-006: `npm --prefix functions run build` 0 errors; lint 0 warnings
- [ ] T-PN-007: all jest emulator tests pass; delta ≥ +6 tests
- [ ] T-PN-008: no Flutter files, no `pubspec.yaml`, no `ios/`, no rules files, no indexes changed
- [ ] `functions/src/index.ts` NOT modified (exports come in PR#1b)
- [ ] All `sendFcm` tests mock `messaging()` injection — no real FCM calls
- [ ] `fcmTokens` (camelCase) used in all TS code, not `fcm_tokens`
- [ ] Conventional commits only; no Co-Authored-By

### PR#1b — CF Triggers + Info.plist
- [ ] Rebased cleanly on post-PR#1a `main` (T-PN-009)
- [ ] T-PN-010..T-PN-017 RED/GREEN pairs complete
- [ ] T-PN-018: `index.ts` exports all 4 CFs alongside existing exports
- [ ] T-PN-019: `UIBackgroundModes` added to `Info.plist` (not overwriting existing)
- [ ] T-PN-020: `docs/setup/fcm-apns.md` created
- [ ] T-PN-021: build 0 errors, lint 0 warnings
- [ ] T-PN-022: all jest emulator tests pass; delta ≥ +18 tests
- [ ] T-PN-023: `firestore.rules`, `storage.rules`, `firestore.indexes.json` all unchanged
- [ ] All CF bodies ≤ 256 chars verified
- [ ] Chat preview truncation at 100 chars verified
- [ ] `cancelledBy` TODO comment present in `notify-appointment.ts`
- [ ] All es-AR strings tagged `// i18n: Fase 6 Etapa 2`
- [ ] No Flutter lib files changed; no `pubspec.yaml` changes
- [ ] Conventional commits only; no Co-Authored-By

### PR#2a — Flutter Data + Service
- [ ] Rebased cleanly on post-PR#1b `main` (T-PN-024)
- [ ] `firebase_messaging: ^15.x` added to `pubspec.yaml`; `flutter_local_notifications` absent
- [ ] T-PN-025..T-PN-030 RED/GREEN pairs complete
- [ ] T-PN-031: `flutter analyze` 0 issues; `dart format` 0 changed
- [ ] T-PN-032: `flutter test` all passing; delta ≥ +20 tests
- [ ] T-PN-033: `fcmTokens` camelCase everywhere; `firestore.rules` unchanged; `storage.rules` unchanged; `firestore.indexes.json` unchanged
- [ ] No HEX literals; no `PhosphorIcons.X` direct references
- [ ] Conventional commits only; no Co-Authored-By

### PR#2b — Flutter Handler + UI
- [ ] Rebased cleanly on post-PR#2a `main` (T-PN-034)
- [ ] T-PN-035..T-PN-043 tasks complete
- [ ] T-PN-044: GitHub follow-up issue filed (ADR-PN-015 trainer cascade gap)
- [ ] T-PN-045: `flutter analyze` 0 issues; `dart format` 0 changed
- [ ] T-PN-046: `flutter test` all passing; delta ≥ +25 tests
- [ ] T-PN-047: `flutter_local_notifications` absent; `storage.rules` unchanged; 0 HEX literals; 0 direct `PhosphorIcons.X`; all strings tagged `// i18n: Fase 6 Etapa 2`; `_scaffoldMessengerKey` passed to `MaterialApp.router`; `_fgSub` cancelled in `dispose()`; `context.mounted` checked before `goDeepLink`; `_attempted` blocks second permission call
- [ ] Manual smoke test scheduled on real iOS + Android after PR#2b merges (requires APNs key configured)
- [ ] Conventional commits only; no Co-Authored-By

---

## Hard Constraints

1. 4 PRs chained-to-main, stacked sequentially: PR#1a → PR#1b → PR#2a → PR#2b. Each rebased on top of the previous merged PR.
2. Strict TDD: RED commit (failing test) BEFORE GREEN commit (implementation) on every task pair. Both commits are conventional, no Co-Authored-By.
3. Token field is `fcmTokens` (camelCase) on `users/{uid}` — NOT `fcm_tokens`. ADR-PN-001 supersedes spec/proposal informal naming.
4. `notify-appointment` MUST skip when `after.reason === 'athlete-account-deleted'`.
5. `notify-link-change` MUST skip when `after.reason === 'account-deleted'`.
6. Both triggers MUST also skip when `before?.status === after.status` (no-op writes).
7. NO `flutter_local_notifications` package added — ever.
8. NO `pubspec.yaml` changes in PR#1a or PR#1b.
9. `pubspec.yaml` changes only in PR#2a (add `firebase_messaging: ^15.x`).
10. `ios/Runner/Info.plist` only changes in PR#1b — add `UIBackgroundModes` with `fetch` and `remote-notification` (pre-verified: no existing key, simple add).
11. `storage.rules` unchanged across all 4 PRs.
12. `firestore.rules` unchanged across all 4 PRs (additive `fcmTokens` field on `users/{uid}` does not require a rule change — existing owner-write rule covers it).
13. `firestore.indexes.json` unchanged across all 4 PRs.
14. All CF notification triggers declared with `{ region: 'southamerica-east1' }`.
15. All FCM dispatch via Admin SDK only — no direct client-to-FCM writes.
16. Every notification body ≤ 256 characters; chat preview truncated at ≤ 100 characters.
17. `sendFcm` accepts an optional `messaging` arg for test injection (ADR-PN-004).
18. `goDeepLink` fallback is `/coach`; invalid paths log + fall back, never throw.
19. All es-AR user-facing string literals tagged `// i18n: Fase 6 Etapa 2`.
20. Spacing scale 8/12/14/18/20 in all new Flutter UI.
21. Colors via `AppPalette.of(context)` — zero HEX literals.
22. Icons via `TreinoIcon.X` — zero direct `PhosphorIcons.X` references.
23. APNs auth key is a manual, out-of-band prerequisite for iOS smoke only — not a code-merge blocker.
24. Cold-start gate is `addPostFrameCallback` in `TreinoApp.initState` + `getInitialMessage()` (ADR-PN-011).
25. Permission gate flag derives from `userProfileProvider.valueOrNull?.displayName != null` — no new boolean field added (ADR-PN-012).
26. `_scaffoldMessengerKey` passed to `MaterialApp.router` to enable SnackBar from `_onForeground` handler outside widget tree.
27. `_fgSub` (foreground subscription) cancelled in `TreinoApp.dispose()`.
28. `context.mounted` checked before every `goDeepLink` call.
29. Follow-up GitHub issue for trainer cascade symmetry MUST be filed before PR#2b merges (T-PN-044, ADR-PN-015).

---

## Final Deliverables Beyond Code

1. **Follow-up issue filed** (T-PN-044): GitHub issue against `account-deletion` SDD for trainer-side cascade symmetry (add `trainerId == uid` paths to `cascade/appointments.ts` and `cascade/trainer-links.ts`). Reference ADR-PN-015 and SCENARIO-684.
2. **APNs auth key manual prerequisite**: Apple Developer Console → Certificates, Identifiers & Profiles → Keys → Apple Push Notifications key → download `.p8`; upload to Firebase Console → Project Settings → Cloud Messaging → iOS app → Auth Key. Documented in `docs/setup/fcm-apns.md` (T-PN-020). Out-of-band, not a code-merge blocker.
3. **Smoke validation on real devices**: after PR#2b merges and APNs key is configured, test each notification type on real iOS + Android devices. Chat, appointment, link, and review triggers should each deliver a push. Foreground (SnackBar), background tap, and cold-start flows verified manually.

---

## Artifacts

- File: `openspec/changes/push-notifications-fcm/tasks.md`
- Engram: `sdd/push-notifications-fcm/tasks`
