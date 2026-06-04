# Canonical Spec: push-notifications-fcm

**Feature**: Firebase Cloud Messaging (FCM) push notifications
**Version**: 1.0 (shipped Fase 6 Etapa 2)
**Date**: 2026-06-04
**Owner**: Backhaus (Dev C)
**Status**: ARCHIVED (PASS-WITH-DEVIATIONS)

---

## Overview

FCM push notifications across 4 user-facing surfaces: chat, agenda (appointments), trainer_links, and reviews. The system is entirely new — no existing specs to delta against. All requirements are NEW. The system remains additive-only: users who deny the permission prompt experience no behaviour change.

Architecture: 4 Cloud Functions in `southamerica-east1` (CF) + Flutter client with `firebase_messaging`, token repository, service, handlers, and permission gate. Token storage is an array field `fcmTokens` on `users/{uid}`. Zero new collections, zero rules changes, zero new indexes.

---

## Requirements

---

### REQ-PN-DATA-001 — fcmTokens Array Field on users/{uid}

The system MUST store FCM tokens as an array field `fcmTokens: string[]` on the existing `users/{uid}` Firestore document. No new collections or sub-collections MUST be created for token storage.

#### SCENARIO-619: Token field absent on new user document
- **Given** a freshly created `users/{uid}` document with no `fcmTokens` field
- **When** `FcmTokenRepository.saveToken(uid, 'tok-1')` is called
- **Then** `users/{uid}.fcmTokens` equals `['tok-1']`
- **Test target**: `test/features/notifications/data/fcm_token_repository_test.dart`
- **REQ**: REQ-PN-DATA-001
- **Status**: PASS ✅

#### SCENARIO-620: Token field is idempotent on duplicate save
- **Given** `users/{uid}.fcmTokens == ['tok-1']`
- **When** `FcmTokenRepository.saveToken(uid, 'tok-1')` is called again
- **Then** `users/{uid}.fcmTokens` still equals `['tok-1']` (no duplicate)
- **Test target**: `test/features/notifications/data/fcm_token_repository_test.dart`
- **REQ**: REQ-PN-DATA-001
- **Status**: PASS ✅

---

### REQ-PN-DATA-002 — FcmTokenRepository.saveToken Uses arrayUnion

`FcmTokenRepository.saveToken(uid, token)` MUST write to `users/{uid}` using Firestore `arrayUnion` semantics, ensuring the operation is idempotent and multi-device safe.

#### SCENARIO-621: Second device token added without overwriting first
- **Given** `users/{uid}.fcmTokens == ['tok-phone']`
- **When** `FcmTokenRepository.saveToken(uid, 'tok-tablet')` is called
- **Then** `users/{uid}.fcmTokens` equals `['tok-phone', 'tok-tablet']`
- **Test target**: `test/features/notifications/data/fcm_token_repository_test.dart`
- **REQ**: REQ-PN-DATA-002
- **Status**: PASS ✅

---

### REQ-PN-DATA-003 — FcmTokenRepository.removeToken Uses arrayRemove

`FcmTokenRepository.removeToken(uid, token)` MUST write to `users/{uid}` using Firestore `arrayRemove` semantics. Removing a token that is not in the array MUST be a no-op (no error thrown).

#### SCENARIO-622: Token removed from array
- **Given** `users/{uid}.fcmTokens == ['tok-1', 'tok-2']`
- **When** `FcmTokenRepository.removeToken(uid, 'tok-1')` is called
- **Then** `users/{uid}.fcmTokens` equals `['tok-2']`
- **Test target**: `test/features/notifications/data/fcm_token_repository_test.dart`
- **REQ**: REQ-PN-DATA-003
- **Status**: PASS ✅

#### SCENARIO-623: Removing absent token is a no-op
- **Given** `users/{uid}.fcmTokens == ['tok-2']`
- **When** `FcmTokenRepository.removeToken(uid, 'tok-999')` is called
- **Then** no error is thrown and `users/{uid}.fcmTokens` still equals `['tok-2']`
- **Test target**: `test/features/notifications/data/fcm_token_repository_test.dart`
- **REQ**: REQ-PN-DATA-003
- **Status**: PASS ✅

---

### REQ-PN-DATA-004 — No Firestore Rules Change Required

The `firestore.rules` file MUST NOT be modified by this change. The existing owner-write rule on `users/{uid}` already permits writing `fcmTokens` as a new array field. This MUST be verified and treated as a binding constraint.

#### SCENARIO-624: Authenticated user can write fcmTokens under existing rules
- **Given** the current `firestore.rules` unchanged and an authenticated user writing to their own `users/{uid}` document
- **When** a write updating `fcmTokens` via `arrayUnion` is attempted
- **Then** the write is allowed without a `permission-denied` error
- **Test target**: Firestore rules emulator test (manual check — no rules change needed)
- **REQ**: REQ-PN-DATA-004
- **Status**: PASS ✅

---

### REQ-PN-CF-001 — send-fcm Shared Helper

The project MUST include a shared helper `functions/src/notifications/send-fcm.ts` that accepts `{ uids: string[], notification: { title: string, body: string }, data: Record<string, string> }`. It MUST read `fcmTokens` per uid via `Promise.all`, call `admin.messaging().sendEachForMulticast({ tokens, notification, data })`, inspect per-token `BatchResponse` errors, and call `arrayRemove` on `users/{uid}.fcmTokens` for any token returning `messaging/registration-token-not-registered` or `messaging/invalid-registration-token`. Recipients with an empty or absent `fcmTokens` array MUST be skipped silently with a log line.

#### SCENARIO-625: sendFcm dispatches to all valid tokens across multiple uids
- **Given** two uids each with one valid token
- **When** `sendFcm({ uids: [uid1, uid2], notification: {...}, data: {...} })` is called
- **Then** `sendEachForMulticast` is invoked with both tokens in the tokens array
- **Test target**: `functions/src/__tests__/send-fcm.test.ts`
- **REQ**: REQ-PN-CF-001
- **Status**: PASS ✅

#### SCENARIO-626: sendFcm removes stale token on registration-token-not-registered error
- **Given** a uid with tokens `['tok-valid', 'tok-stale']` and FCM returns `messaging/registration-token-not-registered` for `tok-stale`
- **When** `sendFcm` inspects the `BatchResponse`
- **Then** `arrayRemove('tok-stale')` is called on `users/{uid}.fcmTokens`
- **And** `tok-valid` remains in the array
- **Test target**: `functions/src/__tests__/send-fcm.test.ts`
- **REQ**: REQ-PN-CF-001
- **Status**: PASS ✅

#### SCENARIO-627: sendFcm removes stale token on invalid-registration-token error
- **Given** a uid with token `['tok-invalid']` and FCM returns `messaging/invalid-registration-token`
- **When** `sendFcm` inspects the `BatchResponse`
- **Then** `arrayRemove('tok-invalid')` is called on `users/{uid}.fcmTokens`
- **Test target**: `functions/src/__tests__/send-fcm.test.ts`
- **REQ**: REQ-PN-CF-001
- **Status**: PASS ✅

#### SCENARIO-628: sendFcm skips uid with empty fcmTokens array
- **Given** a uid whose `users/{uid}.fcmTokens` is `[]` or absent
- **When** `sendFcm` reads the tokens for that uid
- **Then** no `sendEachForMulticast` call is made for that uid
- **And** a log line is emitted indicating the skip
- **And** no error is thrown
- **Test target**: `functions/src/__tests__/send-fcm.test.ts`
- **REQ**: REQ-PN-CF-001
- **Status**: PASS ✅

#### SCENARIO-677: sendFcm called with zero uids is a no-op
- **Given** `sendFcm({ uids: [], notification: {...}, data: {...} })` is called
- **When** the helper runs
- **Then** no Firestore reads and no `sendEachForMulticast` call occur
- **And** no error is thrown
- **Test target**: `functions/src/__tests__/send-fcm.test.ts`
- **REQ**: REQ-PN-CF-001
- **Status**: PASS ✅

---

### REQ-PN-CF-002 — notifyOnChatMessage Trigger

The project MUST include a CF `notifyOnChatMessage` triggered by `onDocumentCreated('chats/{chatId}/messages/{messageId}')` deployed in `southamerica-east1`. It MUST read `chats/{chatId}.members`, compute `recipients = members.filter(m => m !== senderId)`, compose title `"Nuevo mensaje"` and body `"${senderDisplayName}: ${truncate(text, 100)}"`, set `data.deepLink = "/coach/chat/${chatId}?other=${senderUid}"`, and call `sendFcm`. All string literals MUST carry `// i18n: Fase 6 Etapa 2`. Body MUST NOT exceed 256 characters.

#### SCENARIO-629: Chat notification sent to the other member
- **Given** a chat with `members: ['athlete-uid', 'trainer-uid']` and `senderId: 'athlete-uid'`
- **When** a new message document is created
- **Then** `sendFcm` is called with `uids: ['trainer-uid']` and body containing the sender name and truncated text
- **Test target**: `functions/src/__tests__/notify-chat-message.test.ts`
- **REQ**: REQ-PN-CF-002
- **Status**: PASS ✅

#### SCENARIO-630: Chat notification body is truncated at 100 chars
- **Given** a message with `text` of 150 characters
- **When** `notifyOnChatMessage` composes the body
- **Then** the text portion of the body is at most 100 characters long
- **And** the total body length is ≤ 256 characters
- **Test target**: `functions/src/__tests__/notify-chat-message.test.ts`
- **REQ**: REQ-PN-CF-002
- **Status**: PASS ✅

#### SCENARIO-631: Chat notification deep link targets the correct chat
- **Given** `chatId = 'chat-abc'` and `senderUid = 'uid-xyz'`
- **When** `notifyOnChatMessage` composes the payload
- **Then** `data.deepLink == "/coach/chat/chat-abc?other=uid-xyz"`
- **Test target**: `functions/src/__tests__/notify-chat-message.test.ts`
- **REQ**: REQ-PN-CF-002
- **Status**: PASS ✅

#### SCENARIO-680: notifyOnChatMessage does not notify the sender
- **Given** a chat message created by `senderId = 'athlete-uid'` in a chat with `members: ['athlete-uid', 'trainer-uid']`
- **When** `notifyOnChatMessage` fires
- **Then** `sendFcm` is NOT called with `'athlete-uid'` in the uids array
- **Test target**: `functions/src/__tests__/notify-chat-message.test.ts`
- **REQ**: REQ-PN-CF-002
- **Status**: PASS ✅

---

### REQ-PN-CF-003 — notifyOnAppointment Trigger

The project MUST include a CF `notifyOnAppointment` triggered by `onDocumentWritten('appointments/{apptId}')` deployed in `southamerica-east1`. It MUST fire on document create OR on `before.status !== after.status`. It MUST skip (return silently) when `after.reason === 'athlete-account-deleted'`. It MUST branch notification copy and recipient by status transition: `requested` (trainer notified), `confirmed` (athlete notified), `cancelled` (the other party notified). All bodies MUST be es-AR, tagged `// i18n: Fase 6 Etapa 2`, and ≤ 256 chars.

| Status | Title | Body | Recipient | deepLink |
|---|---|---|---|---|
| `requested` (create) | `"Nueva solicitud"` | `"${athleteName} solicitó una sesión para ${date}"` | trainer | `"/coach/agenda"` |
| `confirmed` | `"Sesión confirmada"` | `"${trainerName} confirmó tu sesión para ${date}"` | athlete | `"/coach?tab=agenda"` |
| `cancelled` | `"Sesión cancelada"` | `"La sesión del ${date} fue cancelada"` | other party | role-dependent (see below) |

Cancelled deep links: trainer receives `"/coach/agenda"`, athlete receives `"/coach?tab=agenda"`.

#### SCENARIO-632: appointment create fires trainer notification
- **Given** a new `appointments/{apptId}` document with `status: 'requested'` and no `before` data
- **When** `notifyOnAppointment` fires
- **Then** `sendFcm` is called with `uids: [trainerId]` and `data.deepLink == "/coach/agenda"`
- **Test target**: `functions/src/__tests__/notify-appointment.test.ts`
- **REQ**: REQ-PN-CF-003
- **Status**: PASS ✅

#### SCENARIO-633: appointment confirmed fires athlete notification
- **Given** `before.status == 'requested'` and `after.status == 'confirmed'`
- **When** `notifyOnAppointment` fires
- **Then** `sendFcm` is called with `uids: [athleteId]` and `data.deepLink == "/coach?tab=agenda"`
- **Test target**: `functions/src/__tests__/notify-appointment.test.ts`
- **REQ**: REQ-PN-CF-003
- **Status**: PASS ✅

#### SCENARIO-634: appointment cancelled fires other-party notification
- **Given** `before.status == 'confirmed'`, `after.status == 'cancelled'`, `after.reason` is absent or not `'athlete-account-deleted'`
- **When** `notifyOnAppointment` fires
- **Then** `sendFcm` is called with the uid of the party who did NOT cancel
- **Test target**: `functions/src/__tests__/notify-appointment.test.ts`
- **REQ**: REQ-PN-CF-003
- **Status**: PASS ✅

#### SCENARIO-635: account-deletion cascade guard skips notification
- **Given** `after.status == 'cancelled'` and `after.reason == 'athlete-account-deleted'`
- **When** `notifyOnAppointment` fires
- **Then** `sendFcm` is NOT called
- **And** no error is thrown
- **Test target**: `functions/src/__tests__/notify-appointment.test.ts`
- **REQ**: REQ-PN-CF-003
- **Status**: PASS ✅

#### SCENARIO-636: no-op when status unchanged
- **Given** `before.status == 'confirmed'` and `after.status == 'confirmed'` (non-status field updated)
- **When** `notifyOnAppointment` fires
- **Then** `sendFcm` is NOT called
- **Test target**: `functions/src/__tests__/notify-appointment.test.ts`
- **REQ**: REQ-PN-CF-003
- **Status**: PASS ✅

#### SCENARIO-684: account-deletion cascade on appointments (trainer deletes — no cascade, no notification)
- **Given** a trainer deletes their account (note: current cascade only handles athlete deletions per existing CF)
- **When** `notifyOnAppointment` fires for any appointment
- **Then** no appointment documents are mutated by cascade (trainer-deletion cascade is a pre-existing gap, out of scope)
- **And** the notification trigger behaves as a normal status change (if it fires at all)
- **Test target**: Code review / architecture note at PR time (out of scope, not a test target for this change)
- **REQ**: REQ-PN-CF-003
- **Status**: DESIGN ACKNOWLEDGED — out-of-scope; addressed in ADR-PN-015

---

### REQ-PN-CF-004 — notifyOnLinkChange Trigger

The project MUST include a CF `notifyOnLinkChange` triggered by `onDocumentWritten('trainer_links/{linkId}')` deployed in `southamerica-east1`. It MUST fire on document create OR on `before.status !== after.status`. It MUST skip when `after.reason === 'account-deleted'`. It MUST branch by status transition: `pending` (trainer notified), `active` (athlete notified), `terminated` (BOTH athlete AND trainer notified). All bodies MUST be es-AR, tagged `// i18n: Fase 6 Etapa 2`, and ≤ 256 chars. `data.deepLink` MUST be `"/coach"` for all branches.

| Status | Title | Body | Recipients |
|---|---|---|---|
| `pending` (create) | `"Nueva solicitud de vínculo"` | `"${athleteName} quiere vincularse con vos"` | trainer |
| `active` | `"Vínculo aceptado"` | `"${trainerName} aceptó tu solicitud"` | athlete |
| `terminated` | `"Vínculo finalizado"` | `"El vínculo con ${otherPartyName} fue finalizado"` | both |

#### SCENARIO-637: pending link fires trainer notification
- **Given** a new `trainer_links/{linkId}` document with `status: 'pending'`
- **When** `notifyOnLinkChange` fires
- **Then** `sendFcm` is called with `uids: [trainerId]` and `data.deepLink == "/coach"`
- **Test target**: `functions/src/__tests__/notify-link-change.test.ts`
- **REQ**: REQ-PN-CF-004
- **Status**: PASS ✅

#### SCENARIO-638: active link fires athlete notification
- **Given** `before.status == 'pending'` and `after.status == 'active'`
- **When** `notifyOnLinkChange` fires
- **Then** `sendFcm` is called with `uids: [athleteId]` and `data.deepLink == "/coach"`
- **Test target**: `functions/src/__tests__/notify-link-change.test.ts`
- **REQ**: REQ-PN-CF-004
- **Status**: PASS ✅

#### SCENARIO-639: terminated link fires both parties
- **Given** `before.status == 'active'` and `after.status == 'terminated'` with `after.reason` absent or not `'account-deleted'`
- **When** `notifyOnLinkChange` fires
- **Then** `sendFcm` is called once with `uids: [athleteId, trainerId]`
- **Test target**: `functions/src/__tests__/notify-link-change.test.ts`
- **REQ**: REQ-PN-CF-004
- **Status**: PASS ✅

#### SCENARIO-640: account-deleted guard skips notification
- **Given** `after.status == 'terminated'` and `after.reason == 'account-deleted'`
- **When** `notifyOnLinkChange` fires
- **Then** `sendFcm` is NOT called and no error is thrown
- **Test target**: `functions/src/__tests__/notify-link-change.test.ts`
- **REQ**: REQ-PN-CF-004
- **Status**: PASS ✅

#### SCENARIO-641: no-op when status unchanged
- **Given** `before.status == 'active'` and `after.status == 'active'`
- **When** `notifyOnLinkChange` fires
- **Then** `sendFcm` is NOT called
- **Test target**: `functions/src/__tests__/notify-link-change.test.ts`
- **REQ**: REQ-PN-CF-004
- **Status**: PASS ✅

---

### REQ-PN-CF-005 — notifyOnReview Trigger

The project MUST include a CF `notifyOnReview` triggered by `onDocumentCreated('reviews/{reviewId}')` deployed in `southamerica-east1`. It MUST notify the trainer with title `"Nueva reseña"` and body `"${athleteDisplayName} dejó una reseña de ${rating}⭐"`. `data.deepLink` MUST be `"/coach/trainer/${trainerId}"`. Body MUST be es-AR, tagged `// i18n: Fase 6 Etapa 2`, and ≤ 256 chars.

#### SCENARIO-642: review creates trainer notification with rating
- **Given** a new review document with `trainerId: 'trainer-1'`, `athleteDisplayName: 'Juan'`, `rating: 5`
- **When** `notifyOnReview` fires
- **Then** `sendFcm` is called with `uids: ['trainer-1']` and body `"Juan dejó una reseña de 5⭐"`
- **And** `data.deepLink == "/coach/trainer/trainer-1"`
- **Test target**: `functions/src/__tests__/notify-review.test.ts`
- **REQ**: REQ-PN-CF-005
- **Status**: PASS ✅

#### SCENARIO-681: notifyOnReview trainer with empty fcmTokens — skip silently
- **Given** a review is created for a trainer whose `users/{trainerId}.fcmTokens` is `[]`
- **When** `notifyOnReview` → `sendFcm` runs
- **Then** no dispatch occurs and no error is thrown
- **Test target**: `functions/src/__tests__/notify-review.test.ts` + `functions/src/__tests__/send-fcm.test.ts`
- **REQ**: REQ-PN-CF-005, REQ-PN-CF-001
- **Status**: PASS ✅

---

### REQ-PN-CF-006 — All CFs Exported from index.ts

All four notification CFs (`notifyOnChatMessage`, `notifyOnAppointment`, `notifyOnLinkChange`, `notifyOnReview`) MUST be exported from `functions/src/index.ts` alongside the existing exports (`deleteAccount`, `reviewAggregate`).

#### SCENARIO-643: index.ts exports all four notification CFs
- **Given** `functions/src/index.ts` is imported
- **When** its named exports are inspected
- **Then** `notifyOnChatMessage`, `notifyOnAppointment`, `notifyOnLinkChange`, and `notifyOnReview` are all present
- **Test target**: `functions/src/__tests__/` — covered implicitly by CF trigger tests registering the handler
- **REQ**: REQ-PN-CF-006
- **Status**: PASS ✅

---

### REQ-PN-CLIENT-001 — firebase_messaging Dependency

`pubspec.yaml` MUST add `firebase_messaging: ^15.x` as a dependency. No `flutter_local_notifications` dependency MUST be added.

#### SCENARIO-644: pubspec.yaml lists firebase_messaging and not flutter_local_notifications
- **Given** `pubspec.yaml` after PR#2 is merged
- **When** the file is read
- **Then** `firebase_messaging` is present under `dependencies`
- **And** `flutter_local_notifications` is absent
- **Test target**: Manual inspection at PR review time
- **REQ**: REQ-PN-CLIENT-001
- **Status**: PASS ✅

---

### REQ-PN-CLIENT-002 — FcmService.init Saves Token and Watches Refresh

`FcmService.init()` MUST: call `FirebaseMessaging.instance.getToken()` once and persist the result via `FcmTokenRepository.saveToken(uid, token)`; subscribe to `FirebaseMessaging.instance.onTokenRefresh` and persist each new token via `FcmTokenRepository.saveToken(uid, newToken)`. `init()` MUST NOT request user permission (permission is handled separately per REQ-PN-PERM-001).

#### SCENARIO-645: init saves initial token
- **Given** `FirebaseMessaging.instance.getToken()` returns `'tok-init'`
- **When** `FcmService.init(uid)` is called
- **Then** `FcmTokenRepository.saveToken(uid, 'tok-init')` is called exactly once
- **Test target**: `test/features/notifications/data/fcm_service_test.dart`
- **REQ**: REQ-PN-CLIENT-002
- **Status**: PASS ✅

#### SCENARIO-646: init persists refreshed token
- **Given** `FcmService.init(uid)` has been called and `onTokenRefresh` subsequently emits `'tok-refreshed'`
- **When** the refresh event fires
- **Then** `FcmTokenRepository.saveToken(uid, 'tok-refreshed')` is called
- **Test target**: `test/features/notifications/data/fcm_service_test.dart`
- **REQ**: REQ-PN-CLIENT-002
- **Status**: PASS ✅

#### SCENARIO-647: init does NOT call requestPermission
- **Given** `FcmService.init(uid)` is called
- **When** the method runs to completion
- **Then** `FirebaseMessaging.instance.requestPermission()` is NOT invoked
- **Test target**: `test/features/notifications/data/fcm_service_test.dart`
- **REQ**: REQ-PN-CLIENT-002
- **Status**: PASS ✅

#### SCENARIO-678: FcmService does not init if getToken returns null
- **Given** `FirebaseMessaging.instance.getToken()` returns `null` (no permission or FCM unavailable)
- **When** `FcmService.init(uid)` runs
- **Then** `FcmTokenRepository.saveToken` is NOT called
- **And** no error is thrown
- **Test target**: `test/features/notifications/data/fcm_service_test.dart`
- **REQ**: REQ-PN-CLIENT-002
- **Status**: PASS ✅

---

### REQ-PN-CLIENT-003 — FcmService.dispose Removes Token on Logout

`FcmService.dispose(uid)` MUST call `FirebaseMessaging.instance.getToken()` to obtain the current token and then call `FcmTokenRepository.removeToken(uid, token)`. This call is best-effort: if it fails (e.g. the user was already signed out from Firestore), the error MUST be caught and logged without crashing the app.

#### SCENARIO-648: dispose removes current token
- **Given** `FcmService` was initialized for `uid` with token `'tok-current'`
- **When** `FcmService.dispose(uid)` is called
- **Then** `FcmTokenRepository.removeToken(uid, 'tok-current')` is called
- **Test target**: `test/features/notifications/data/fcm_service_test.dart`
- **REQ**: REQ-PN-CLIENT-003
- **Status**: PASS ✅

#### SCENARIO-649: dispose failure is swallowed
- **Given** `FcmTokenRepository.removeToken` throws a Firestore exception
- **When** `FcmService.dispose(uid)` is called
- **Then** no exception propagates to the caller
- **Test target**: `test/features/notifications/data/fcm_service_test.dart`
- **REQ**: REQ-PN-CLIENT-003
- **Status**: PASS ✅

#### SCENARIO-679: onTokenRefresh subscription is cancelled on dispose
- **Given** `FcmService.init(uid)` subscribed to `onTokenRefresh`
- **When** `FcmService.dispose(uid)` is called
- **Then** the `onTokenRefresh` subscription is cancelled
- **And** subsequent token refresh events do NOT trigger further saveToken calls
- **Test target**: `test/features/notifications/data/fcm_service_test.dart`
- **REQ**: REQ-PN-CLIENT-003
- **Status**: PASS ✅

---

### REQ-PN-CLIENT-004 — Riverpod Provider Wires FcmService to Auth State

A Riverpod provider MUST watch `authStateProvider`. When a user signs in (auth state changes to non-null uid), it MUST call `FcmService.init(uid)`. When the user signs out (auth state changes to null), it MUST call `FcmService.dispose(previousUid)`.

#### SCENARIO-650: provider calls init on sign-in
- **Given** the `fcmServiceProvider` is live and `authStateProvider` emits a non-null uid
- **When** the auth state change propagates
- **Then** `FcmService.init(uid)` is called
- **Test target**: `test/features/notifications/application/fcm_providers_test.dart`
- **REQ**: REQ-PN-CLIENT-004
- **Status**: PASS ✅

#### SCENARIO-651: provider calls dispose on sign-out
- **Given** the `fcmServiceProvider` is live and a user was signed in
- **When** `authStateProvider` emits null
- **Then** `FcmService.dispose(previousUid)` is called
- **Test target**: `test/features/notifications/application/fcm_providers_test.dart`
- **REQ**: REQ-PN-CLIENT-004
- **Status**: PASS ✅

#### SCENARIO-683: foreground handler not attached before user is authenticated
- **Given** the app is on the sign-in screen (no authenticated user)
- **When** a FCM message arrives (edge case — e.g. token not yet cleared after logout)
- **Then** no navigation or SnackBar call occurs that would crash due to missing context
- **Test target**: `test/features/notifications/application/fcm_providers_test.dart`
- **REQ**: REQ-PN-CLIENT-004
- **Status**: PASS ✅

---

### REQ-PN-HANDLER-001 — Foreground Message Shows SnackBar

When a FCM notification arrives in the foreground (app in focus, `FirebaseMessaging.onMessage`), the app MUST show a SnackBar via `ScaffoldMessenger.of(context)` displaying `notification.title` and `notification.body`. Tapping the SnackBar action (or the bar itself) MUST navigate via `context.go(notification.data['deepLink'])`. Invalid or missing deep link MUST log an error and fall back to `"/coach"` without crashing.

#### SCENARIO-652: foreground message shows SnackBar with title and body
- **Given** the app is foregrounded and a FCM message arrives with `title: 'Hola'` and `body: 'Mensaje'`
- **When** `FirebaseMessaging.onMessage` emits the message
- **Then** a SnackBar is visible containing 'Hola' and 'Mensaje'
- **Test target**: `test/features/notifications/presentation/foreground_snackbar_test.dart`
- **REQ**: REQ-PN-HANDLER-001
- **Status**: PASS ✅

#### SCENARIO-653: tapping SnackBar navigates via deep link
- **Given** a foreground SnackBar is shown with `data.deepLink = "/coach/chat/abc?other=xyz"`
- **When** the user taps the SnackBar
- **Then** `context.go("/coach/chat/abc?other=xyz")` is called
- **Test target**: `test/features/notifications/presentation/foreground_snackbar_test.dart`
- **REQ**: REQ-PN-HANDLER-001
- **Status**: PASS ✅

#### SCENARIO-654: invalid deep link falls back to /coach without crash
- **Given** a foreground message with `data.deepLink` absent or empty
- **When** the SnackBar tap handler executes
- **Then** `context.go("/coach")` is called instead
- **And** no exception is thrown
- **Test target**: `test/features/notifications/application/notification_router_test.dart`
- **REQ**: REQ-PN-HANDLER-001
- **Status**: PASS ✅

#### SCENARIO-682: deep link router handles unknown path with /coach fallback
- **Given** `notification.data['deepLink'] = "/unknown/route/that/doesnt/exist"`
- **When** the deep link router processes the value
- **Then** `context.go("/coach")` is called instead
- **And** no exception is thrown
- **Test target**: `test/features/notifications/application/notification_handler_test.dart`
- **REQ**: REQ-PN-HANDLER-001
- **Status**: PASS ✅

---

### REQ-PN-HANDLER-002 — Background Tap Navigates via Deep Link

When the user taps a FCM notification while the app is backgrounded (`FirebaseMessaging.onMessageOpenedApp`), the app MUST navigate via `context.go(notification.data['deepLink'])`. Invalid or missing deep link MUST log and fall back to `"/coach"` without crashing.

#### SCENARIO-655: background tap navigates to correct screen
- **Given** a FCM notification with `data.deepLink = "/coach?tab=agenda"` is tapped from the background
- **When** `onMessageOpenedApp` fires
- **Then** `context.go("/coach?tab=agenda")` is called
- **Test target**: `test/features/notifications/application/notification_handler_test.dart`
- **REQ**: REQ-PN-HANDLER-002
- **Status**: PASS ✅

#### SCENARIO-656: background tap with missing deep link falls back to /coach
- **Given** a FCM notification tapped from the background with no `deepLink` in data
- **When** `onMessageOpenedApp` fires
- **Then** `context.go("/coach")` is called
- **And** no exception is thrown
- **Test target**: `test/features/notifications/application/notification_handler_test.dart`
- **REQ**: REQ-PN-HANDLER-002
- **Status**: PASS ✅

---

### REQ-PN-HANDLER-003 — Cold-Start Tap Navigates After Router Ready

When the app is launched from a terminated state by tapping a FCM notification (`FirebaseMessaging.instance.getInitialMessage()`), the app MUST wait until GoRouter is ready before calling `context.go(notification.data['deepLink'])`. The gate MUST be a post-first-frame callback (e.g. `WidgetsBinding.instance.addPostFrameCallback`) on the root navigator so no navigation occurs before the router has initialized. Invalid or missing deep link MUST fall back to `"/coach"`.

#### SCENARIO-657: cold-start tap defers navigation until post-frame
- **Given** the app is launched from a terminated state by tapping a notification with `deepLink = "/coach/trainer/uid-1"`
- **When** `getInitialMessage()` returns the pending message
- **Then** navigation to `"/coach/trainer/uid-1"` is triggered after the first frame, not during widget build
- **Test target**: `test/features/notifications/application/notification_handler_test.dart`
- **REQ**: REQ-PN-HANDLER-003
- **Status**: PASS ✅

#### SCENARIO-658: cold-start with no initial message is a no-op
- **Given** the app launches normally (not from a notification tap)
- **When** `getInitialMessage()` returns `null`
- **Then** no navigation is triggered and no error occurs
- **Test target**: `test/features/notifications/application/notification_handler_test.dart`
- **REQ**: REQ-PN-HANDLER-003
- **Status**: PASS ✅

---

### REQ-PN-PERM-001 — Permission Requested Post-Onboarding

`FirebaseMessaging.instance.requestPermission()` MUST be called exactly once per app session, ONLY after `profile_setup_completed == true`, on the first home shell render that satisfies this condition. The prompt MUST NOT fire during onboarding, during sign-in flows, or if `profile_setup_completed` is false or not yet loaded.

#### SCENARIO-659: permission requested on first home shell render post-setup
- **Given** `profile_setup_completed == true` and no prior permission prompt in this session
- **When** the home shell renders for the first time
- **Then** `requestPermission()` is called
- **Test target**: `test/features/notifications/presentation/permission_gate_test.dart`
- **REQ**: REQ-PN-PERM-001
- **Status**: PASS ✅

#### SCENARIO-660: permission NOT requested when profile_setup_completed is false
- **Given** `profile_setup_completed == false`
- **When** the home shell renders
- **Then** `requestPermission()` is NOT called
- **Test target**: `test/features/notifications/presentation/permission_gate_test.dart`
- **REQ**: REQ-PN-PERM-001
- **Status**: PASS ✅

#### SCENARIO-661: permission NOT requested a second time in the same session
- **Given** `requestPermission()` was already called once in this session
- **When** the home shell re-renders (e.g. tab switch or rebuild)
- **Then** `requestPermission()` is NOT called again
- **Test target**: `test/features/notifications/presentation/permission_gate_test.dart`
- **REQ**: REQ-PN-PERM-001
- **Status**: PASS ✅

---

### REQ-PN-PERM-002 — Permission Copy and Graceful Denial

The permission prompt MUST use iOS/Android system dialogs only — no custom double-prompt UI. The app MUST NOT show any in-app pre-prompt dialog in v1. When the system prompt is displayed, the explanation text (where supported by the OS) MUST be: `"Para avisarte cuando recibís un mensaje, sesión o solicitud"` (es-AR, tagged `// i18n: Fase 6 Etapa 2`). If the user denies, the app MUST continue to function normally with no crash, no notifications, and no retry prompt within the same session.

#### SCENARIO-662: denied permission does not crash the app
- **Given** `requestPermission()` is called and the user denies
- **When** the denial response is processed
- **Then** the app remains on the home shell without error
- **And** no SnackBar or retry prompt is shown
- **Test target**: `test/features/notifications/presentation/permission_gate_test.dart`
- **REQ**: REQ-PN-PERM-002
- **Status**: PASS ✅

#### SCENARIO-663: foreground messages are not shown when permission was denied
- **Given** the user denied permission
- **When** a FCM message arrives
- **Then** no SnackBar is shown and no navigation occurs
- **Test target**: `test/features/notifications/application/notification_handler_test.dart` (permission-denied path)
- **REQ**: REQ-PN-PERM-002
- **Status**: WARNING — OS-enforced behaviour; no unit test possible

---

### REQ-PN-CX-001 — iOS UIBackgroundModes

`ios/Runner/Info.plist` MUST include `UIBackgroundModes` with at minimum `fetch` and `remote-notification`. This is required for FCM background delivery on iOS.

#### SCENARIO-664: Info.plist contains required background modes
- **Given** `ios/Runner/Info.plist` after PR#2 is merged
- **When** the file is read
- **Then** `UIBackgroundModes` array contains both `fetch` and `remote-notification`
- **Test target**: Manual inspection at PR review time
- **REQ**: REQ-PN-CX-001
- **Status**: PASS ✅

---

### REQ-PN-CX-002 — No flutter_local_notifications Dependency

The project MUST NOT add `flutter_local_notifications` as a dependency. All foreground notification UX MUST use `ScaffoldMessenger` SnackBars. This avoids additional iOS entitlement plumbing and a parallel notification pipeline.

#### SCENARIO-665: pubspec.yaml does not list flutter_local_notifications
- **Given** `pubspec.yaml` after all PRs are merged
- **When** the file is read
- **Then** `flutter_local_notifications` is absent from `dependencies` and `dev_dependencies`
- **Test target**: Manual inspection at PR review time
- **REQ**: REQ-PN-CX-002
- **Status**: PASS ✅

---

### REQ-PN-CX-003 — Notification Body Length Constraint

All FCM notification bodies composed by CFs MUST NOT exceed 256 characters. Chat message previews MUST be truncated at 100 characters before inclusion in the body string.

#### SCENARIO-666: chat body with max-length preview stays under 256 chars
- **Given** a sender display name of 50 chars and a message truncated to 100 chars
- **When** the body string is assembled as `"${name}: ${preview}"`
- **Then** the resulting string is ≤ 256 characters
- **Test target**: `functions/src/__tests__/notify-chat-message.test.ts`
- **REQ**: REQ-PN-CX-003
- **Status**: PASS ✅

---

### REQ-PN-CX-004 — Existing Collections Only — No New Collections

This change MUST NOT create any new Firestore collections or sub-collections. FCM tokens MUST be stored as a field on the existing `users/{uid}` document. `firestore.indexes.json` MUST NOT receive new indexes for this change.

#### SCENARIO-667: no new collection paths appear in CF or Flutter code
- **Given** all new files introduced by this change
- **When** Firestore write paths are enumerated
- **Then** all writes target `users/{uid}` only (no new collections)
- **Test target**: Code review at PR time
- **REQ**: REQ-PN-CX-004
- **Status**: PASS ✅

---

### REQ-PN-CX-005 — storage.rules Unchanged

`storage.rules` MUST NOT be modified by this change.

#### SCENARIO-668: storage.rules git diff is empty for this change
- **Given** PR#1 and PR#2 diffs
- **When** changes to `storage.rules` are inspected
- **Then** the file is not present in the diff
- **Test target**: Code review at PR time
- **REQ**: REQ-PN-CX-005
- **Status**: PASS ✅

---

### REQ-PN-CX-006 — es-AR Copy with i18n Markers

All user-facing string literals in new `.dart` files and all CF body/title strings MUST be written in es-AR. Each file containing a user-facing string MUST include at least one `// i18n: Fase 6 Etapa 2` marker comment adjacent to the string literal.

#### SCENARIO-669: i18n markers present in all files with copy
- **Given** any `.dart` or `.ts` file added or modified by this change that contains a user-facing string
- **When** the file is inspected
- **Then** at least one `// i18n: Fase 6 Etapa 2` comment is present
- **Test target**: Manual review at PR time
- **REQ**: REQ-PN-CX-006
- **Status**: PASS ✅

---

### REQ-PN-CX-007 — Zero HEX Literals and Zero PhosphorIcons Direct

All new and modified `.dart` files MUST contain zero HEX color literals and zero direct `PhosphorIcons.X` references. Colors MUST use `AppPalette.of(context)`. Icons (if any notification UI requires them) MUST use `TreinoIcon.X`.

#### SCENARIO-670: rg finds no HEX literals in new dart files
- **Given** the diff of PR#2 in this change
- **When** `rg '#[0-9a-fA-F]{3,8}' <new-dart-files>` is run
- **Then** no matches are found
- **Test target**: CI lint or manual rg check at PR time
- **REQ**: REQ-PN-CX-007
- **Status**: PASS ✅

---

### REQ-PN-CX-008 — Strict TDD

Every implementation commit for this change MUST be preceded by a RED test commit demonstrating the failing test. Tests MUST turn GREEN in the subsequent implementation commit.

#### SCENARIO-671: RED commit precedes GREEN commit in git log
- **Given** any task pair from the tasks list
- **When** the git log for this change is reviewed
- **Then** the test file commit appears before the implementation commit
- **Test target**: git log (manual review at PR time)
- **REQ**: REQ-PN-CX-008
- **Status**: PASS ✅

---

### REQ-PN-CX-009 — Conventional Commits, No AI Attribution

All commits MUST follow conventional commits format. Commits MUST NOT include `Co-Authored-By` or any AI attribution.

#### SCENARIO-672: PR commit messages are conventional and attribution-free
- **Given** any commit in this change's PRs
- **When** the commit message is read
- **Then** it follows `type(scope): description` format
- **And** contains no `Co-Authored-By` lines
- **Test target**: git log (manual review at PR time)
- **REQ**: REQ-PN-CX-009
- **Status**: PASS ✅

---

### REQ-PN-CX-010 — LOC Budget per PR

Each PR diff MUST remain within ≤ 400 changed lines (additions + deletions) or carry an explicit maintainer-approved `size:exception` label.

#### SCENARIO-673: PR#1 CF layer is within 400-line budget
- **Given** PR#1 diff on GitHub
- **When** additions + deletions are totaled
- **Then** the total is ≤ 400 lines (estimated ~350)
- **Test target**: GitHub PR diff (manual check at PR time)
- **REQ**: REQ-PN-CX-010
- **Status**: PASS ✅

#### SCENARIO-674: PR#2 Flutter layer is within 400-line budget
- **Given** PR#2 diff on GitHub
- **When** additions + deletions are totaled
- **Then** the total is ≤ 400 lines (estimated ~400)
- **Test target**: GitHub PR diff (manual check at PR time)
- **REQ**: REQ-PN-CX-010
- **Status**: PASS ✅

---

### REQ-PN-CX-011 — APNs Auth Key as Manual Prerequisite

The APNs authentication key MUST be generated in Apple Developer Console and uploaded to Firebase Console before PR#2 iOS smoke validation. This is a non-code, out-of-band prerequisite. The spec documents this as a hard dependency for iOS end-to-end validation, not for PR code merge.

#### SCENARIO-675: iOS smoke requires APNs key configured in Firebase Console
- **Given** PR#2 is merged and a TestFlight or direct-install build is available on a real iOS device
- **When** a notification is triggered from the CF layer
- **Then** the iOS device receives the notification (requires APNs key in Firebase Console)
- **Test target**: Manual smoke on real iOS device
- **REQ**: REQ-PN-CX-011
- **Status**: PASS ✅

---

### REQ-PN-CX-012 — CF Emulator Tests (Not FCM Delivery)

All CF jest tests MUST run against the Firebase Local Emulator Suite (Firestore emulator). FCM delivery (`sendEachForMulticast`) MUST be mocked/injected in tests — the FCM service itself is not emulatable. This limitation MUST be documented and real delivery validated via manual smoke on real devices.

#### SCENARIO-676: CF tests pass against emulator without real FCM dispatch
- **Given** the Firebase Local Emulator Suite is running
- **When** `npm test` is executed inside `functions/`
- **Then** all notification CF tests pass with mocked FCM dispatch
- **And** no call is made to a real FCM endpoint
- **Test target**: `functions/src/__tests__/` (all notify-*.test.ts + send-fcm.test.ts)
- **REQ**: REQ-PN-CX-012
- **Status**: PASS ✅

---

## Hard Constraints (15)

1. NO `flutter_local_notifications` dependency
2. NO new Firestore collections or sub-collections
3. NO `firestore.rules` changes
4. NO `storage.rules` changes
5. NO new Firestore indexes
6. All CF notification triggers deployed in `southamerica-east1`
7. All FCM body strings ≤ 256 characters
8. Chat preview truncated at ≤ 100 characters
9. `notify-appointment` MUST skip when `after.reason === 'athlete-account-deleted'`
10. `notify-link-change` MUST skip when `after.reason === 'account-deleted'`
11. Permission prompt fires at most once per session, only post-onboarding
12. All es-AR strings tagged `// i18n: Fase 6 Etapa 2`
13. Zero HEX literals; zero `PhosphorIcons.X` direct references
14. Strict TDD — RED before GREEN on every task pair
15. Conventional commits — no `Co-Authored-By`, no AI attribution
16. APNs auth key is a manual, out-of-band prerequisite for iOS smoke only (not a code-merge blocker)

---

## Artifact References

- Proposal: `openspec/changes/push-notifications-fcm/proposal.md`
- Exploration: `openspec/changes/push-notifications-fcm/explore.md`
- Design: `openspec/changes/push-notifications-fcm/design.md`
- Tasks: `openspec/changes/push-notifications-fcm/tasks.md`
- Verification Report: `openspec/changes/push-notifications-fcm/verify-report.md`

---

**Status**: ARCHIVED — change complete, all PRs merged, smoke validated.
