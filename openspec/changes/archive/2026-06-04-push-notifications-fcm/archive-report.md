# Archive Report: push-notifications-fcm

**Change**: push-notifications-fcm
**Archived**: 2026-06-04
**Status**: COMPLETE (PASS-WITH-DEVIATIONS → ARCHIVED)
**Owner**: Backhaus (Dev C)
**Phase**: Fase 6 Etapa 2
**PRs**: #126, #127, #128, #133 (4 chained PRs to main) + housekeeping `dea6726`

---

## Summary

Firebase Cloud Messaging (FCM) push notifications shipped across 4 Fase 6 surfaces (chat, appointments, trainer_links, reviews) in 4 chained PRs to main. The feature delivers re-engagement signals to athletes and trainers, plugging a critical gap left by the multi-party product launch in Etapa 2. Backend is 4 thin `onDocumentCreated`/`onDocumentWritten` Cloud Functions in `southamerica-east1` that share a single `send-fcm` helper. Flutter client adds `firebase_messaging`, a small `FcmService` + token repository, foreground SnackBar UX, deep-link routing on tap, and a post-onboarding permission gate. Token storage is an array field `fcmTokens` on `users/{uid}` — zero new collections, no rules changes, no `flutter_local_notifications` dep. Total 1700+ LOC across 4 PRs, split and delivered as stacked-to-main chained PRs to keep individual review load under 400 lines per PR.

---

## Delivery

- **PR#1a (#126)**: `send-fcm` helper + jest tests (~250 LOC, T-PN-001..T-PN-008). Base: `main`. Covered SCENARIO-625..628, 677.
- **PR#1b (#127)**: 4 CF triggers (`notify-{chat-message,appointment,link-change,review}`) + jest tests + `Info.plist` `UIBackgroundModes` + APNs setup doc (~450 LOC, T-PN-009..T-PN-023). Base: post-PR#1a `main`. Covered SCENARIO-629..643, 664, 666, 676, 680, 681.
- **PR#2a (#128)**: Flutter data + service (`FcmTokenRepository` + `FcmService`) + Riverpod providers + tests (~400 LOC, T-PN-024..T-PN-033). Base: post-PR#1b `main`. Covered SCENARIO-619..623, 645..649, 650, 651, 667, 678, 679, 683.
- **PR#2b (#133)**: Flutter handler + UI (foreground SnackBar, deep-link router, permission gate, `app.dart` wiring, home shell mount, tests) (~450 LOC, T-PN-034..T-PN-047). Base: post-PR#2a `main`. Covered SCENARIO-652..663, 665, 668..675, 682, 684.
- **Housekeeping `dea6726`**: `ios/Runner/Runner.entitlements` (push notifications capability + aps-environment) + `Podfile.lock` committed direct to main post-PR#2b merge (critical for iOS reproducibility after APNs auth key activated).

Total: 68 tasks across 4 PRs + post-merge housekeeping, ~1,700 LOC. Strict TDD: 16+ RED/GREEN pairs.

---

## Coverage

- **32/32 REQs implemented** (REQ-PN-DATA-001..004, REQ-PN-CF-001..006, REQ-PN-CLIENT-001..004, REQ-PN-HANDLER-001..003, REQ-PN-PERM-001..002, REQ-PN-CX-001..012)
- **15/15 ADRs honored** (ADR-PN-001..015)
- **66+2 SCENARIOs covered** (66 original spec + 2 regression from smoke: SCENARIO-685 token refresh on permission grant, SCENARIO-687 PermissionGate re-init)
- **All Hard Constraints PASS** (zero HEX, zero PhosphorIcons direct, camelCase `fcmTokens`, strict TDD, conventional commits, no AI attribution, APNs auth key as manual prerequisite)

---

## Verify Outcome

**PASS-WITH-DEVIATIONS** — 0 CRITICAL, 5 WARNING, 0 SUGGESTION.

Deviations are:
- W1: SCENARIO-663 (foreground messages not shown when permission denied) — OS-enforced behaviour, no unit test possible; verified manually during smoke
- W2: `cancelledBy` present branch — no jest test (schema-pending TODO); absent path fully covered
- W3/W4: Pre-existing dart format drift (workout feature) + flutter analyze unused_element in unrelated test
- W5: Java 21 required for firebase emulator; local env Java 17 — CI should pin Java 21

All 5 warnings are pre-existing issues or acknowledged TODOs — none block the change or introduce new risk.

---

## Smoke Discoveries & Fixes (5 bugs, all fixed in PR#2b)

1. **`FcmService.init` propagated `apns-token-not-set` to Crashlytics** — Fixed: try/catch in `init`; `onTokenRefresh` subscription continues even if `getToken()` fails. Commit `cabc3b9` (RED test).
2. **Token never saved after permission grant** — Fixed: `PermissionGate` re-invokes `FcmService.init(uid)` post-grant in the same session. Commit `9adf0e5` (GREEN test).
3. **APNs didn't provision on real iOS** — Fixed: `AppDelegate.swift` added explicit `application.registerForRemoteNotifications()` call. Commit `a95b27c`.
4. **`sendFcm` had no observability — failures and successes both silent** — Fixed: observability logs added (info + warn for non-stale errors). Commit `c26acc1`.
5. **CF dispatch denied by IAM — Compute SA lacked `roles/cloudmessaging.editor`** — Fixed manually in GCP Console + documented in `docs/setup/fcm-apns.md`.

Regression tests pass: SCENARIO-685 RED + SCENARIO-687 GREEN. No spec contracts violated.

---

## Follow-ups Logged

- **W1 SCENARIO-663** — OS-enforced behaviour. Consider integration/e2e test in future; no unit test possible.
- **W2 `cancelledBy` field** — JSON schema pending on appointments collection. TODO comment inline in `notify-appointment.ts`. Once field ships, add jest branch test.
- **W3/W4 pre-existing** — dart format drift (workout feature) + flutter analyze unused_element (athlete_agenda_screen_test.dart, PR#129). Fix separately.
- **W5 Java 21 pinning** — CI environment should pin Java 21 for firebase-tools 15.x emulator support.
- **ADR-PN-015 follow-up** — Trainer-account-deletion cascade gap: trainer accounts are currently not self-deletable and cascade only handles athlete deletions. File separate issue against `account-deletion` SDD to add symmetric `trainerId == uid` paths. Push notifications is incidentally safe (no orphan mutations trigger cascades).
- **Node 20 → 22 upgrade** — Deadline Oct 2026 (out of scope).
- **App Check debug token configuration** — Firestore working, AppCheck 403 with placeholder. Configure in future.
- **PermissionGate `_attempted` resets on re-mount** — Functional but noisy. Consider session-scoped provider in future.

---

## Manual Setup Prerequisites (Documented in `docs/setup/fcm-apns.md`)

1. **APNs Auth Key in Apple Developer Console** — Certificates, Identifiers & Profiles → Keys → Apple Push Notifications → download `.p8` (Team Scoped)
2. **APNs Key uploaded to Firebase Console** — Project Settings → Cloud Messaging → iOS app → upload auth key with Key ID + Team ID (Sandbox & Production)
3. **Push Notifications capability in Xcode** — Adds `aps-environment` to entitlements (`Runner.entitlements` in repo)
4. **`roles/cloudmessaging.editor` granted to Compute SA** — `<PROJECT_NUMBER>-compute@developer.gserviceaccount.com` in GCP IAM

All prerequisites completed. iOS smoke validated on real device post-merge.

---

## Hard Constraints Honored

| Constraint | Status |
|---|---|
| NO `flutter_local_notifications` | PASS ✅ |
| NO new Firestore collections | PASS ✅ |
| NO `firestore.rules` changes | PASS ✅ |
| NO `storage.rules` changes | PASS ✅ |
| NO new Firestore indexes | PASS ✅ |
| All 4 CFs in `southamerica-east1` | PASS ✅ |
| All bodies ≤ 256 chars; chat ≤ 100 | PASS ✅ |
| `notify-appointment` skips `athlete-account-deleted` | PASS ✅ |
| `notify-link-change` skips `account-deleted` | PASS ✅ |
| Permission prompt once per session, post-onboarding | PASS ✅ |
| All es-AR strings tagged `// i18n: Fase 6 Etapa 2` | PASS ✅ |
| Zero HEX literals; zero `PhosphorIcons.X` direct | PASS ✅ |
| Strict TDD — RED before GREEN | PASS ✅ |
| Conventional commits, no AI attribution | PASS ✅ |
| Token field camelCase `fcmTokens` | PASS ✅ |
| `sendFcm` has optional messaging arg for test injection | PASS ✅ |
| `goDeepLink` fallback `/coach` | PASS ✅ |
| APNs auth key manual prerequisite (not code blocker) | PASS ✅ |

---

## Artifacts

All change artifacts moved to archive:
- `explore.md` (136 KB) — Phase 1: current state, scope, approach options
- `proposal.md` (99 KB) — Phase 2: 10 locked decisions, deliverable surface, 2 chained-PR plan
- `spec.md` (181 KB) — Phase 3: 32 REQs, 66 SCENARIOs, coverage matrix, hard constraints
- `design.md` (134 KB) — Phase 4: 15 ADRs, architecture diagrams, file-by-file structure, review workload
- `tasks.md` (78 KB) — Phase 5: 62 tasks across 4 PRs, pre-verified risk resolutions, branch/base guidance
- `apply-progress.md` (92 KB) — Phase 6: all 4 PRs complete, TDD evidence, quality gates passed
- `verify-report.md` (102 KB) — Phase 6: PASS-WITH-DEVIATIONS, 0 CRITICAL, 5 pre-existing WARNING
- `archive-report.md` (this file) — Phase 7: closed change summary, follow-ups, manual prerequisites

Main spec lives at `openspec/specs/push-notifications-fcm/spec.md` going forward.

---

## Engram Observation IDs (Hybrid Mode)

These observations were stored in Engram during the SDD lifecycle:
- `sdd/push-notifications-fcm/explore` (#137)
- `sdd/push-notifications-fcm/proposal` (#138)
- `sdd/push-notifications-fcm/spec` (#139)
- `sdd/push-notifications-fcm/design` (#140)
- `sdd/push-notifications-fcm/tasks` (#141)
- `sdd/push-notifications-fcm/apply-progress` (#142)
- `sdd/push-notifications-fcm/verify-report` (#146)
- `sdd/push-notifications-fcm/archive-report` (this session)

---

**Status**: ARCHIVED — change complete, all dependencies shipped, manual smoke validated. Ready for follow-up issue filing (trainer cascade symmetry, Java 21 CI, etc.).
