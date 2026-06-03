# Proposal: push-notifications-fcm

**Change**: push-notifications-fcm
**Owner**: Backhaus (Dev A)
**Date**: 2026-06-03
**Phase**: Fase 6 Etapa 2
**Artifact store**: hybrid (file + Engram `sdd/push-notifications-fcm/proposal`)
**Exploration**: `openspec/changes/push-notifications-fcm/explore.md` (Engram #137)

---

## 1. TL;DR

Ship Firebase Cloud Messaging (FCM) push notifications for the 4 user-facing surfaces that drive Fase 6 re-engagement: chat, agenda (appointments), trainer_links and reviews. Backend is 4 thin `onDocumentCreated`/`onDocumentWritten` Cloud Functions in `southamerica-east1` that share a single `send-fcm` helper (Admin SDK multicast + stale-token cleanup). Flutter client adds `firebase_messaging`, a small `FcmService` + `fcm_token_repository`, foreground SnackBar UX, and GoRouter deep-link on tap. Token storage is an array field `fcm_tokens` on `users/{uid}` — no new collections, no rules changes, no `flutter_local_notifications` dep. Delivered in 2 chained-to-main PRs (CF first, Flutter second). Blast radius: additive only — no behaviour change for users who deny the permission prompt.

---

## 2. Motivation

Fase 6 turned TREINO into a multi-party product (athletes ↔ trainers), but the new surfaces are silent:

- **Chat** is dead between sessions — a trainer sends a message and the athlete has no idea until they re-open the app.
- **Agenda confirmations** are invisible — an athlete requests a slot, the trainer confirms it, and the athlete has no signal until they manually re-open agenda.
- **`trainer_links` requests** get missed — a PF receives a link request and has no path back to it unless they happen to land on the Coach Hub.
- **Reviews** ship with no feedback loop — a trainer never finds out an athlete left a 5⭐ review unless they re-visit their public profile.

This is the canonical "feature shipped but no one knows it happened" problem. Etapa 2 fixes the re-engagement floor before recurring appointments (Etapa 4) and the rest of the trainer features make the gap worse. The roadmap (`docs/roadmap.md` line 415) explicitly gates Etapa 4 and Etapa 7 behind Etapa 2 for this reason.

CF infrastructure is bootstrapped (`deleteAccount`, `reviewAggregate` live in prod). Eventarc IAM is resolved. `admin.messaging()` ships with `firebase-admin ^12` — zero new server deps. The only real cost is a small Flutter feature directory and a manual APNs auth-key step.

---

## 3. Scope

### In Scope (v1)

- **4 CF notification triggers** in `southamerica-east1`:
  - `notifyOnChatMessage` (`onDocumentCreated` on `chats/{chatId}/messages/{messageId}`)
  - `notifyOnAppointment` (`onDocumentWritten` on `appointments/{apptId}`, guarded against account-deletion cascade)
  - `notifyOnLinkChange` (`onDocumentWritten` on `trainer_links/{linkId}`)
  - `notifyOnReview` (`onDocumentCreated` on `reviews/{reviewId}`)
- **Shared `send-fcm` helper** with multicast dispatch + stale-token cleanup (`arrayRemove` on `registration-token-not-registered` / `invalid-registration-token`).
- **FCM token lifecycle (Flutter)**: `firebase_messaging` dep, `FcmService` (init + permission + `getToken` + `onTokenRefresh`), `fcm_token_repository` (`arrayUnion` / `arrayRemove` on `users/{uid}.fcm_tokens`).
- **Foreground UX**: in-app `ScaffoldMessenger` SnackBar/banner — no `flutter_local_notifications` dep.
- **Background + cold-start tap → deep-link** via GoRouter (`onMessageOpenedApp` + `getInitialMessage`).
- **Permission prompt**: post-onboarding, on the first home shell render after `profile_setup_completed == true`, with brief es-AR copy.
- **Deep-link payload**: raw GoRouter path string under `notification.data.deepLink` (e.g. `"/coach/chat/abc123?other=xyz"`), consumed by `context.go(deepLink)`.
- **iOS plumbing**: `Info.plist` `UIBackgroundModes: [fetch, remote-notification]`. APNs key step documented as manual prerequisite.
- **Tests**: CF jest emulator tests per trigger + `send-fcm` helper; Flutter unit/widget tests for repo, service, handler.

### Out of Scope (deferred, v1 does NOT ship)

- Quiet hours / Do-Not-Disturb.
- Per-channel mute (mute chat but keep agenda, etc.).
- Notification preferences UI (settings screen).
- In-app notification center / history feed.
- Rich notifications (images, action buttons, inline reply).
- Notification grouping/collapsing beyond FCM/iOS defaults.
- Web push (mobile-only product).
- Email / SMS fallback.
- Group-chat notifications (data model is 1:1 today).
- Mute-on-active-device (cross-device race).
- Recurring-appointment notifications (Etapa 4, doesn't exist yet).
- Review-edited notifications (only `onDocumentCreated`).

---

## 4. Locked Decisions

The exploration phase surfaced 10 open questions. All are LOCKED below with rationale.

| # | Decision | Locked Choice | Rationale |
|---|----------|---------------|-----------|
| 1 | Token storage shape | **Array field** `fcm_tokens: string[]` on `users/{uid}` | Realistic count is 1–3 tokens per user. Fits well inside Firestore's 1 MiB doc cap. One-read lookup vs subcollection query. No new rules surface. |
| 2 | `trainer_links` terminated → who gets notified | **BOTH** parties (athlete + trainer), regardless of who terminated | Symmetric with how `terminationReason` is already written for both sides; relationship closure is bilateral, so the signal should be too. |
| 3 | Review notification in v1 | **YES** — included | Marginal effort is one extra trigger + jest test. Trainers need a feedback signal to engage with the review pattern shipped in Etapa 7. |
| 4 | Foreground UX | **In-app SnackBar/banner** via existing `ScaffoldMessenger` pattern. No `flutter_local_notifications` | Avoids extra iOS entitlement plumbing and a second notification pipeline. Matches how the rest of the app surfaces transient feedback. |
| 5 | Permission prompt timing | **Post-onboarding**, on first home shell render after `profile_setup_completed == true`, with brief copy: "Para avisarte cuando recibís un mensaje, sesión o solicitud" | Contextual moment — the user has just committed to the product. Avoids burning the iOS one-shot prompt on a cold launch where the request makes no sense yet. |
| 6 | Deep-link payload format | **Raw GoRouter path** string under `notification.data.deepLink` (e.g. `"/coach/chat/abc123?other=xyz"`). CF composes; client calls `context.go(deepLink)` | Simpler than a structured `{screen, id}` object. GoRouter is already declarative — the path IS the contract. Lower coupling than a parallel screen-key vocabulary. |
| 7 | PR delivery strategy | **2 chained PRs to main**: PR#1 CF layer; PR#2 Flutter layer. PR#3 (preferences UI) deferred — out of v1 scope | CF can be smoke-tested in isolation against the emulator and dev. PR#2 lands against a verified backend. Each PR fits under the 400-line budget. |
| 8 | Cancellation guard during account-deletion cascade (`appointments` + `trainer_links`) | **YES** — CFs read `after.reason`. Coupling values (verified 2026-06-03 against existing code): `notify-appointment` skips when `after.reason == 'athlete-account-deleted'` (set by [`functions/src/cascade/appointments.ts:61`](functions/src/cascade/appointments.ts#L61)); `notify-link-change` skips when `after.reason == 'account-deleted'` (set by [`functions/src/cascade/trainer-links.ts:48`](functions/src/cascade/trainer-links.ts#L48)). The pre-existing value asymmetry between the two collections is accepted as-is (rewriting cascade values would be churn to tested CF code with no functional benefit). | Avoids spamming the surviving party when a peer deletes their account. Field name is `reason` (NOT `cancellationReason` as the explore draft speculated). Additional finding from this verification: the existing cascade only fires on `athleteId == uid` paths — when a TRAINER deletes their account, neither `appointments` nor `trainer_links` are mutated by cascade, so notify CFs do NOT fire (incidentally safe — no spam). The orphan-trainer state is a pre-existing gap in `account-deletion`, logged as a separate follow-up. NOT in scope for this SDD. |
| 9 | Chat message body privacy | **FULL preview** (WhatsApp-style): `"${senderDisplayName}: ${truncate(text, 100)}"` | Precedent: chat is 1:1 only. Users expect message previews. iOS users can hide lock-screen previews via iOS Settings if they want. Body truncated at 100 chars to stay safely under APNs ~256-char body cap. |
| 10 | Review notification body | **Include rating**: `"${athleteDisplayName} dejó una reseña de ${rating}⭐"` | Trainer gets at-a-glance signal that drives them to open the public profile. Rating is not PII; review collection is public. |

---

## 5. Approach Summary

**Approach A — per-trigger CFs + shared `send-fcm` helper** (confirmed from explore.md §Approaches).

Architecture sketch:

- `functions/src/notifications/send-fcm.ts` is the single dispatch surface. It takes `{uids, notification, data}`, fans out by reading `fcm_tokens` per uid, calls `admin.messaging().sendEachForMulticast(...)`, and cleans up stale tokens by inspecting per-token `BatchResponse.responses[i].error.code` and calling `arrayRemove` for `messaging/registration-token-not-registered` and `messaging/invalid-registration-token`. Empty-token users are skipped silently with a log line.
- Four thin trigger files (`functions/src/notify-chat-message.ts`, `notify-appointment.ts`, `notify-link-change.ts`, `notify-review.ts`) each: (a) guard against no-op writes (`status` unchanged, missing fields, cancellation cascade), (b) resolve recipient uid(s), (c) compose `{title, body, data: {deepLink}}`, (d) delegate to the shared helper.
- Flutter side stays minimal: a `FcmService` wraps `firebase_messaging` (permission + token + refresh + foreground/background/initial streams), a `fcm_token_repository` persists tokens to `users/{uid}.fcm_tokens` via `arrayUnion`/`arrayRemove`, a `notification_handler` dispatches each stream — foreground → SnackBar, background/cold-start → `deepLinkRouter.go(context, deepLink)`. Riverpod ties the service to auth state (start on sign-in, remove-on-signout).

Rejected alternatives stay rejected: a single dispatcher CF doesn't reduce trigger count and worsens blast radius (B); an external Cloud Run poller introduces 30–60s latency unacceptable for chat (C).

---

## 6. Deliverable Surface

### Cloud Functions (PR#1)

- `functions/src/notifications/send-fcm.ts` — shared helper (multicast + stale-token cleanup).
- `functions/src/notify-chat-message.ts` — chat trigger.
- `functions/src/notify-appointment.ts` — appointment trigger (with account-deletion-cascade guard).
- `functions/src/notify-link-change.ts` — trainer_links trigger (both parties on terminated).
- `functions/src/notify-review.ts` — review trigger (rating in body).
- `functions/src/index.ts` — add 4 new exports.
- `functions/src/__tests__/send-fcm.test.ts` — multicast + stale-token cleanup.
- `functions/src/__tests__/notify-chat-message.test.ts` — full preview, sender ≠ recipient guard, empty-token skip.
- `functions/src/__tests__/notify-appointment.test.ts` — create + status transitions + account-deletion-cascade guard.
- `functions/src/__tests__/notify-link-change.test.ts` — pending/active/terminated, both-parties-on-terminated.
- `functions/src/__tests__/notify-review.test.ts` — rating included in body.

### Flutter (PR#2)

- `pubspec.yaml` — add `firebase_messaging: ^15.x`.
- `lib/features/notifications/data/fcm_token_repository.dart` — `saveToken` / `removeToken` via `arrayUnion` / `arrayRemove`.
- `lib/features/notifications/application/fcm_service.dart` — wraps `firebase_messaging`: `init`, `requestPermission`, `getToken`, `onTokenRefresh`, `dispose`.
- `lib/features/notifications/application/fcm_providers.dart` — Riverpod wiring against `authStateProvider`.
- `lib/features/notifications/application/notification_handler.dart` — foreground SnackBar + tap deep-link.
- `lib/features/notifications/application/deep_link_router.dart` — `notification.data.deepLink` → `context.go(deepLink)`.
- `lib/features/notifications/presentation/permission_prompt.dart` — first-home-render prompt gated on `profile_setup_completed`.
- `lib/app/app.dart` — attach foreground listener + cold-start handler on `initState`.
- `lib/main.dart` — eager-load provider after `Firebase.initializeApp()`.
- `ios/Runner/Info.plist` — `UIBackgroundModes: [fetch, remote-notification]`.
- `test/features/notifications/data/fcm_token_repository_test.dart` — `fake_cloud_firestore`.
- `test/features/notifications/application/fcm_service_test.dart` — mocked `firebase_messaging`.
- `test/features/notifications/application/notification_handler_test.dart` — foreground SnackBar + tap → router navigation.

### Manual (out-of-band, NOT in code)

- APNs auth key created in Apple Developer Console.
- APNs auth key uploaded in Firebase Console → Project Settings → Cloud Messaging → Apple app configuration.
- Real iOS device + real Android device for smoke validation.

---

## 7. Risks & Mitigations

Carried forward from exploration (8 risks). Mitigations resolve in the design phase.

| # | Risk | Severity | Mitigation (to be designed) |
|---|------|----------|-----------------------------|
| 1 | APNs auth key blocks iOS smoke | HIGH | Surface as manual prerequisite in §8. No code workaround. Document the Apple Developer Console → Firebase Console steps in the spec. |
| 2 | FCM delivery is not emulatable | MEDIUM | Jest tests validate CF logic and payload construction via a mocked/injected `messaging()`; real delivery validated via manual smoke on real devices. Document the limitation up-front. |
| 3 | iOS foreground system banners suppressed by default | MEDIUM | Resolved by Decision #4 — we always show in-app SnackBar via `ScaffoldMessenger` regardless of iOS foreground suppression. |
| 4 | `onDocumentWritten` on `appointments` + `trainer_links` fires on account-deletion cascade | MEDIUM | Resolved by Decision #8 — `notify-appointment` skips when `after.reason == 'athlete-account-deleted'`; `notify-link-change` skips when `after.reason == 'account-deleted'`. Field is `reason`, NOT `cancellationReason`. Values verified against `functions/src/cascade/appointments.ts:61` and `functions/src/cascade/trainer-links.ts:48`. Spec will document these contracts inline so future cascade edits don't silently break the guards. |
| 5 | Permission denied on iOS is sticky | MEDIUM | Resolved by Decision #5 — contextual post-onboarding prompt with explanatory copy. App degrades gracefully if denied (no crash, no notifications). |
| 6 | Token cleanup race (token invalid between read and dispatch) | LOW | Per-token `BatchResponse.responses[i].error.code` inspection in `send-fcm` helper → `arrayRemove` for `messaging/registration-token-not-registered` and `messaging/invalid-registration-token`. Covered by `send-fcm.test.ts`. |
| 7 | Chat fan-out for group chats | LOW | Out of scope v1 — data model is strictly 1:1. Future-proofing not done. |
| 8 | Cross-device notification race (reply on tablet, phone still rings) | LOW | Accepted for v1 — matches WhatsApp/Messenger UX. Mute-on-active is out of scope. |

Additional v1 guards (cross-cutting, surfaced during proposal):

- Empty-token user (`fcm_tokens` absent or `[]`): CF logs `info` and returns — does NOT throw. Covered by tests.
- Body length: chat preview truncated at 100 chars (safe under APNs ~256-char body cap and the 4 KiB total FCM payload).
- All bodies in es-AR with `// i18n: Fase 6 Etapa 2` markers.

---

## 8. Out-of-band Prerequisites (NON-CODE blockers)

These are NOT in PR scope. They block end-to-end validation, not code merge:

1. **APNs auth key generated** in Apple Developer Console (`Certificates, Identifiers & Profiles → Keys → +`).
2. **APNs auth key uploaded** to Firebase Console under `Project Settings → Cloud Messaging → Apple app configuration` for `treino-dev`.
3. **Real iOS device** (TestFlight build is acceptable; simulator cannot receive push) for smoke.
4. **Real Android device** (emulator with Play services CAN receive push but real device is the canonical signal) for smoke.

These are flagged for Backhaus before PR#2 sign-off.

---

## 9. Success Criteria

- [ ] 1530+ existing Dart tests still passing (no regressions). +~15 new tests covering `fcm_token_repository`, `FcmService`, `notification_handler`, `deep_link_router`.
- [ ] All existing CF jest tests passing (current 49). +~25 new tests across `send-fcm`, `notify-chat-message`, `notify-appointment`, `notify-link-change`, `notify-review`.
- [ ] `flutter analyze` → 0 issues.
- [ ] `dart format .` clean.
- [ ] Conventional commits only, no `Co-Authored-By`, no AI attribution.
- [ ] Smoke validation on real iOS device for each of the 4 surfaces (chat, appointment, link, review): receive in background, tap → land on correct screen via deep-link.
- [ ] Smoke validation on real Android device for the same 4 surfaces.
- [ ] Permission-denied path verified: app does NOT crash, no notifications received, no error toasts.
- [ ] Account-deletion cascade verified: deleting an athlete with a future appointment does NOT fire a "cancelled" notification to the surviving trainer.
- [ ] All bodies in es-AR with `// i18n: Fase 6 Etapa 2` markers.
- [ ] Strict TDD trail: every task pair has a RED commit before the GREEN commit.
- [ ] PR diffs ≤ 400 LOC each (or maintainer-approved `size:exception`).

---

## 10. Open Questions Carrying to Spec

All 10 exploration questions are LOCKED in §4. Residual items for spec:

1. **Exact es-AR copy** for the 4 notification surfaces (title + body templates). Proposal locks the SHAPE (e.g. `"${sender}: ${truncate(body,100)}"`); spec must lock the literal strings, including the empty-name fallback ("Usuario eliminado" precedent from account-deletion).
2. **Permission-prompt copy** — proposal locks the timing (post-onboarding, on first home shell render) and the gist ("Para avisarte cuando recibís un mensaje, sesión o solicitud"). Spec must lock the final string + the "no thanks" affordance (system prompt only, no app-side double prompt).
3. **Cold-start deep-link timing** — `getInitialMessage()` returns before GoRouter is ready. Design must specify the gate (delay until `routerProvider` reports ready, or `addPostFrameCallback`). This is a design-phase concern, not a proposal-phase decision.

---

## 11. PR Plan

**2 chained-to-main PRs.** Each independently mergeable; PR#2 depends on PR#1 being merged (or at minimum deployed to `treino-dev`) so the Flutter handler has a backend that actually dispatches.

| PR | Scope | LOC est. | Verification |
|----|-------|----------|--------------|
| **PR#1 — CF layer** | `functions/src/notifications/send-fcm.ts` + 4 `notify-*.ts` triggers + jest tests + `index.ts` exports. Includes iOS `Info.plist` `UIBackgroundModes` patch (it does not break anything without the Flutter side). APNs setup documented in PR description, NOT in code. | ~350 | `npm test` in `functions/` (emulator-backed) — all 49 existing + ~25 new tests green. Deploy to `treino-dev`. Manual: write a doc to `chats/{chatId}/messages/`, observe `messaging().sendEachForMulticast` invocation in CF logs. |
| **PR#2 — Flutter layer** | `firebase_messaging` dep, `FcmService`, `fcm_token_repository`, `notification_handler`, `deep_link_router`, permission prompt, app.dart + main.dart wiring, Flutter tests. | ~400 | `flutter analyze` 0 issues. `dart format .` clean. All Dart tests green (1530 existing + ~15 new). Manual smoke: real iOS + real Android, all 4 surfaces, foreground + background + cold-start. |
| **PR#3 — DEFERRED (out of v1 scope)** | Notification preferences UI (per-channel mute, quiet hours). | — | Not in this change. |

Risk mitigation rationale: PR#1 isolates CF risk (Eventarc, Admin SDK, stale-token cleanup) for focused review. PR#2 ships against a verified backend — if a notification doesn't show, the bug is unambiguously client-side.

Dependencies:

- PR#1 deploy to `treino-dev` is the gate for PR#2 smoke (Flutter side needs a real `sendEachForMulticast` to validate against).
- APNs auth key (out-of-band) gates PR#2 iOS smoke only; PR#1 and PR#2 code merges are NOT blocked.

---

## 12. Artifact References

- File: `openspec/changes/push-notifications-fcm/proposal.md`
- Engram: `sdd/push-notifications-fcm/proposal`
- Predecessor (exploration): `openspec/changes/push-notifications-fcm/explore.md` + Engram `sdd/push-notifications-fcm/explore` (#137)

**Status**: Ready for `sdd-spec` and `sdd-design` (can run in parallel).
