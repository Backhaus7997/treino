# Exploration: push-notifications-fcm

**Change**: push-notifications-fcm
**Owner**: Backhaus (Dev C)
**Date**: 2026-06-03
**Phase**: Fase 6 Etapa 2
**Artifact store**: hybrid (openspec + engram `sdd/push-notifications-fcm/explore` #137)

---

## Scope Summary

Ship Firebase Cloud Messaging (FCM) push notifications for the 4 user-facing surfaces that drive re-engagement:

1. **Chat** — new message in `chats/{chatId}/messages/{messageId}` → notify the other member
2. **Agenda** — appointment created OR status change → notify the other party
3. **Vínculos** — `trainer_links` create or status change to `active`/`terminated` → notify the other party
4. **Reviews** (v1, optional) — new review in `reviews/{reviewId}` → notify the trainer

Cloud Function event triggers (`onDocumentWritten`/`onDocumentCreated`) compose the payload and send via Admin SDK `admin.messaging()`. Flutter client manages FCM tokens (refresh + multi-device), handles foreground/background/tap, and deep-links to the relevant screen via GoRouter.

**Explicit out of scope for v1**:
- Quiet hours / per-channel mute / Do-Not-Disturb (defer to follow-up)
- Notification grouping/collapsing (rely on FCM/iOS defaults)
- Rich notifications (images, action buttons)
- In-app notification center / history feed
- Web push (only mobile clients)
- Email/SMS fallback

---

## Current State

### Flutter (no `firebase_messaging`)

- `pubspec.yaml` — `firebase_messaging` is **absent**. `firebase_core ^3.6.0`, `cloud_firestore ^5.4.0`, `cloud_functions ^5.2.0` already present and compatible with `firebase_messaging` ^15.x.
- `lib/main.dart` — Firebase initialized cleanly. NO FCM init, NO permission request, NO token handler.
- `lib/app/app.dart` — `TreinoApp` is a `ConsumerStatefulWidget` — good attachment point for foreground message stream listener in `initState`.
- `lib/app/router.dart` — declarative GoRouter. Deep-link target inventory:
  - `/coach/chat/:chatId?other=:otherUid` — ChatScreen
  - `/coach/trainer/:uid` — TrainerPublicProfileScreen
  - `/coach?tab=agenda` — CoachScreen agenda tab
  - `/coach/agenda` — AthleteAgendaScreen
  - All destinations already exist — no new routes needed for v1.

### Cloud Functions (no FCM handlers)

- `functions/src/index.ts` — exports only `deleteAccount` (callable v2) and `reviewAggregate` (onDocumentWritten on `reviews/{reviewId}`).
- `functions/package.json` — `firebase-admin ^12` present. Admin SDK already includes `admin.messaging()` — **no additional npm dep needed** for FCM sending.
- `functions/src/__tests__/review-aggregate.test.ts` — clear template to model after (emulator-backed, named apps, handler extracted for testability).
- Region: `southamerica-east1` (all existing CFs).

### Firestore

- `users/{uid}` — no `fcm_tokens` field exists. `firestore.rules` immutability guard only covers `uid`, `role`, `email`, `createdAt`. Adding `fcm_tokens` as an array field is rules-safe without any rule change.
- `chats/{chatId}/messages/{messageId}` — live, has `senderId, text, createdAt`. Chat members in parent `chats/{chatId}.members[]`.
- `appointments` — live, has `athleteId, trainerId, status, startsAt`, plus more.
- `trainer_links` — live, has `athleteId, trainerId, status, requestedAt, acceptedAt, terminatedAt`.
- `reviews` — live (shipped 2026-06-02), has `linkId, athleteId, trainerId, rating, comment, createdAt, updatedAt`.

### Account-deletion + trainer-reviews playbook (re-usable)

Patterns already established in the codebase that v1 should mirror:

- CF testability: extract pure handler from trigger, test via emulator with named apps (see `review-aggregate.test.ts`).
- Region pinning at trigger registration time.
- Eventarc IAM bootstrap is DONE (first time was during trainer-reviews; not a blocker anymore).
- Cloud Run public access already configured for the project.

### iOS setup status

- `ios/Runner/GoogleService-Info.plist` — present (FCM uses it for sender ID + project number).
- `ios/Runner/Info.plist` — needs `UIBackgroundModes: [fetch, remote-notification]` for background notifications (standard `firebase_messaging` setup).
- **APNs auth key** — **NOT YET CONFIGURED** in Apple Developer Console + Firebase Console. This is a manual step that blocks iOS smoke. Must be flagged as a pre-delivery prerequisite.

### Android setup status

- `google-services.json` already configured (FCM is part of Firebase by default).
- No additional Android Manifest changes needed beyond what `firebase_messaging` package documents.

---

## What Needs to Be Built

### Data layer (Flutter)

- `lib/features/notifications/data/fcm_token_repository.dart` — `saveToken(uid, token)`, `removeToken(uid, token)` using Firestore `arrayUnion` / `arrayRemove` on `users/{uid}.fcm_tokens`.
- `lib/features/profile/data/user_repository.dart` — add helpers for fcm_tokens field if not done via the repo above.
- `firestore.rules` — verify additive-only: `fcm_tokens` field on `users/{uid}` does NOT need a rules change (owner-write already allows it).

### Notification service layer (Flutter)

- `lib/features/notifications/application/fcm_service.dart` — wraps `firebase_messaging` with:
  - `init()` — request permission, get initial token, subscribe to `onTokenRefresh`
  - `dispose()` — unsubscribe on logout
- `lib/features/notifications/application/fcm_providers.dart` — Riverpod providers wiring the service to current auth state (initializes when user signs in, cleans up token on signout).
- `lib/features/notifications/application/notification_handler.dart` — handles:
  - Foreground messages → in-app SnackBar/banner
  - Background tap (`onMessageOpenedApp`) → deep-link via GoRouter
  - Cold start tap (`getInitialMessage`) → deep-link with delay until router ready

### Deep-link router helper

- `lib/features/notifications/application/deep_link_router.dart` — maps `notification.data.deepLink` payload to GoRouter `context.go(path)`.
- Payload shape: `{ "deepLink": "/coach/chat/abc123?other=xyz" }` (literal router path).

### CF layer

- `functions/src/notifications/send-fcm.ts` — shared helper:
  - `sendFcm({uids: string[], notification: {title, body}, data: Record<string,string>})`
  - Reads tokens from `users/{uid}.fcm_tokens` for each uid
  - Calls `admin.messaging().sendEachForMulticast({tokens, notification, data})`
  - Cleans up stale tokens (NotRegistered / InvalidRegistration errors) via `arrayRemove`
- `functions/src/notify-chat-message.ts` — `onDocumentCreated('chats/{chatId}/messages/{messageId}')`:
  - Read parent `chats/{chatId}.members` → notify members ≠ sender
  - Body: `${senderName}: ${truncate(text, 100)}`
  - Data: `{ deepLink: "/coach/chat/{chatId}" }`
- `functions/src/notify-appointment.ts` — `onDocumentWritten('appointments/{apptId}')`:
  - Guard: only fire on create OR `after.status != before.status`
  - Branch by status: requested / confirmed / cancelled
  - Notify the OTHER party (athlete if status changed by trainer, vice versa)
  - Data: `{ deepLink: "/coach?tab=agenda" }` (athlete) or `{ deepLink: "/coach/agenda" }` (trainer)
- `functions/src/notify-link-change.ts` — `onDocumentWritten('trainer_links/{linkId}')`:
  - Guard: fire on create OR `after.status != before.status`
  - Branch by status: pending (new request → notify trainer), active (accepted → notify athlete), terminated (notify other party)
  - Data: `{ deepLink: "/coach" }`
- `functions/src/notify-review.ts` (optional v1) — `onDocumentCreated('reviews/{reviewId}')`:
  - Notify the trainer of the new review
  - Body: `${athleteName} dejó una reseña de ${rating}⭐`
  - Data: `{ deepLink: "/coach/trainer/{trainerId}" }` — opens public profile to see review
- `functions/src/index.ts` — add 3–4 new exports.

### Tests

- `test/features/notifications/data/fcm_token_repository_test.dart` — token save/remove with `fake_cloud_firestore`.
- `test/features/notifications/application/fcm_service_test.dart` — mocked `firebase_messaging`.
- `test/features/notifications/application/notification_handler_test.dart` — foreground SnackBar + tap → router navigation.
- `functions/src/__tests__/notify-chat-message.test.ts` — emulator-backed, all branches.
- `functions/src/__tests__/notify-appointment.test.ts` — emulator-backed, all status transitions + cascade-deletion guard.
- `functions/src/__tests__/notify-link-change.test.ts` — emulator-backed.
- `functions/src/__tests__/notify-review.test.ts` — emulator-backed (if in v1).
- `functions/src/__tests__/send-fcm.test.ts` — multi-token dispatch + stale token cleanup.

### iOS setup (manual, not code)

- Apple Developer Console: create APNs auth key (or upload existing one to Firebase Console under `Project Settings → Cloud Messaging → Apple app configuration`).
- `ios/Runner/Info.plist` — add `UIBackgroundModes: [fetch, remote-notification]`.

---

## Approach Options

| Approach | Pros | Cons | Effort |
|---|---|---|---|
| **A — Per-trigger CFs (RECOMMENDED)** | Mirrors `reviewAggregate` pattern. Each trigger independently deployable, testable, disableable. Shared send helper avoids duplication. Small blast radius if one trigger has a bug. | Slightly more files (4 CF exports). | Medium |
| **B — Single dispatcher CF** | Centralized notification logic superficially | Does NOT reduce CF count — still needs 3–4 trigger registrations per collection path. Harder to disable one type independently. Test surface larger. Cold-start per trigger is independent anyway. | Medium (same work, worse maintainability) |
| **C — External worker / Cloud Run poller** | Viable fallback if CF triggers had IAM issues (already resolved). | 30–60s latency unacceptable for chat. Expensive polling. Over-engineered given triggers work. | High |

**Recommendation: Approach A.**

- Each trigger in `functions/src/notify-{surface}.ts`
- Shared `functions/src/notifications/send-fcm.ts` helper for multi-token dispatch + stale token cleanup via `admin.messaging().sendEachForMulticast()`
- Token storage as array field `fcm_tokens: string[]` on `users/{uid}` (simpler than subcollection, realistic count is 1–3 per user)
- Foreground UX: in-app SnackBar/banner (no extra package, avoids `flutter_local_notifications` iOS complexity)
- Review notification IN v1 (low marginal cost, CF infra ready)

---

## Open Questions for Proposal

1. **Token storage** — array field on `users/{uid}.fcm_tokens` (recommended) vs subcollection `users/{uid}/fcm_tokens/{token}`?
2. **`trainer_links` terminated** — notify initiator only, other party only, or both?
3. **Review notification in v1** — yes (recommended) or defer?
4. **Foreground UX** — in-app SnackBar/banner (recommended) vs `flutter_local_notifications` package?
5. **Permission prompt timing** — post-profile-setup (recommended) vs contextual (on first chat message sent, etc.)?
6. **Deep-link payload key format** — raw GoRouter path string `"/coach/chat/abc?other=xyz"` (recommended) vs structured `{ screen: "chat", id: "abc", extras: {...} }`?
7. **PR delivery strategy** — single PR or chained (CF layer first, then Flutter layer)?
8. **Cancellation guard for `appointments`** — should the trigger skip notifications during account-deletion cascade? (Yes, otherwise athletes/trainers get spammed when a peer deletes their account.) How to detect: `before.status` was active and `after.status` is `cancelled` with `cancellationReason == 'account-deleted'`?
9. **Chat message body privacy** — preview full message (precedent: WhatsApp) or just `Nuevo mensaje de ${senderName}`?
10. **Review notification body** — expose rating in body or just `${athleteName} dejó una reseña`?

---

## Risks

1. **APNs auth key blocks iOS smoke**. Mitigation: surface this as a manual prerequisite in the proposal. No code workaround.
2. **FCM delivery is not emulatable**. Jest tests validate CF logic + token lookup; real delivery requires a physical device. Document this explicitly.
3. **iOS foreground system banners suppressed by default**. Mitigation: in-app SnackBar/banner (chosen UX) OR set `setForegroundNotificationPresentationOptions(alert: true, badge: true, sound: true)`.
4. **`onDocumentWritten` on `appointments` fires on account-deletion cascade**. Mitigation: detect cancellation reason and skip notification.
5. **Permission denied on iOS is sticky** — once user says No, only Settings re-enables. Mitigation: ask in a contextual moment (after profile-setup completes) with a brief copy explaining why.
6. **Token cleanup race**: token can become invalid between read from Firestore and `sendEachForMulticast`. Mitigation: handle `messaging/registration-token-not-registered` and `messaging/invalid-registration-token` per-token responses → `arrayRemove`.
7. **Chat notification fan-out** for group chats (future): current data model is 1:1 only — array of 2 members. Not a v1 issue.
8. **Cross-device notification race**: user has phone + tablet, replies on tablet → phone still gets notification. Acceptable for v1 (matches WhatsApp/Messenger). Mute-on-active is out of scope.

---

## Ready for Proposal

**YES.** All trigger collections are live in production. CF infrastructure is bootstrapped. Eventarc IAM is resolved. The architecture path is clear: Approach A with shared helper. Proposal phase must lock the 10 open decisions above before spec can be written.

---

## Artifacts

- File: `openspec/changes/push-notifications-fcm/explore.md`
- Engram: `sdd/push-notifications-fcm/explore` (id #137)
