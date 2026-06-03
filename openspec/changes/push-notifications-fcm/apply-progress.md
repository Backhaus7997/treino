# Apply Progress: push-notifications-fcm

**Change**: push-notifications-fcm
**Mode**: Strict TDD
**PR scope**: PR#1a — Send-FCM Helper (~250 LOC)
**Apply batch**: 1 of 4 (first batch)
**Date**: 2026-06-03
**Branch**: `feat/push-notifications-pr1a-send-fcm-helper`

---

## Delivery Strategy

chained-pr (stacked-to-main, 4 sub-PRs, user signed off 2026-06-03). This batch implements PR#1a only. PR#1b, PR#2a, PR#2b are out of scope for this batch.

---

## Environment Notes

**Java 21 env constraint**: firebase-tools 15.x requires Java 21. The machine has Java 17 (Zulu JDK at `/Library/Java/JavaVirtualMachines/zulu-17.jdk`) and Java 21 via Homebrew (`/opt/homebrew/opt/openjdk@21`). The Firebase emulators were already running (started separately), so tests were run against the already-running emulators on ports 8080 (Firestore) and 9099 (Auth). The command `firebase emulators:exec --only firestore,auth "npm --prefix functions test"` cannot be used directly if no Java 21 is on PATH — use `JAVA_HOME=/opt/homebrew/opt/openjdk@21 PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH" firebase emulators:exec ...` or start emulators separately first.

---

## TDD Cycle Evidence

| Task | Test File | Layer | Safety Net | RED | GREEN | TRIANGULATE | REFACTOR |
|------|-----------|-------|------------|-----|-------|-------------|----------|
| T-PN-001 (SETUP) | N/A | N/A | ✅ 49/49 baseline | N/A | N/A | N/A | N/A |
| T-PN-002 (RED) | `functions/src/__tests__/send-fcm.test.ts` | Integration (emulator) | N/A (new file) | ✅ Written | N/A | N/A | N/A |
| T-PN-003 (GREEN) | `functions/src/__tests__/send-fcm.test.ts` | Integration (emulator) | N/A | ✅ Written | ✅ 7/7 passed | ✅ 5 cases (SCENARIO-625a, 625b, 628a, 628b, 677) | ✅ Clean |
| T-PN-004 (RED) | `functions/src/__tests__/send-fcm.test.ts` | Integration (emulator) | N/A (same file) | ✅ Written in T-PN-002 commit | N/A | N/A | N/A |
| T-PN-005 (GREEN) | `functions/src/__tests__/send-fcm.test.ts` | Integration (emulator) | N/A | ✅ Written | ✅ 7/7 passed | ✅ 2 cases (SCENARIO-626, 627) | ✅ Clean |
| T-PN-006 (GATE) | N/A | Build + lint | N/A | N/A | ✅ 0 errors, 0 warnings | N/A | N/A |
| T-PN-007 (GATE) | Full suite | Integration (emulator) | N/A | N/A | ✅ 56/56 passed, delta +7 | N/A | N/A |
| T-PN-008 (VERIFY) | N/A | Scope guard | N/A | N/A | ✅ All checks passed | N/A | N/A |

**Note on RED structure**: T-PN-002 and T-PN-004 share the same test file. The RED commit (T-PN-002) included all tests for both phases (1a.2 and 1a.3) because stale token tests and basic dispatch tests are in the same `send-fcm.test.ts`. The GREEN (T-PN-003 + T-PN-005) created the single `send-fcm.ts` file that satisfies all tests. This is a pragmatic deviation — noted here for verify phase.

---

## Test Summary

- **Total tests written**: 7 (in `send-fcm.test.ts`)
- **Total tests passing**: 7/7
- **Full suite**: 56/56 (delta +7 from baseline 49)
- **Layers used**: Integration/emulator (7)
- **Approval tests (refactoring)**: None — no refactoring tasks
- **Pure functions created**: 1 (`sendFcm`)

---

## Completed Tasks (PR#1a)

- [x] T-PN-001 — SETUP: branch confirmed `feat/push-notifications-pr1a-send-fcm-helper`, working tree clean, `functions/src/index.ts` exports only `deleteAccount` and `reviewAggregate`
- [x] T-PN-002 — RED: `functions/src/__tests__/send-fcm.test.ts` created with failing tests for SCENARIO-625, 628, 677 (basic dispatch) and SCENARIO-626, 627 (stale cleanup). Build failed as expected.
- [x] T-PN-003 — GREEN: `functions/src/notifications/send-fcm.ts` created. Exports `SendFcmInput`, `SendFcmResult`, and `sendFcm(app, input, messaging?)`. Reads `users/{uid}.fcmTokens` per uid (camelCase per ADR-PN-001), skips empty/absent arrays, calls `sendEachForMulticast`. T-PN-002 tests pass.
- [x] T-PN-004 — RED: stale token tests already written in T-PN-002 commit (same file). Structural RED maintained — implementation did not exist when tests were committed.
- [x] T-PN-005 — GREEN: `sendFcm` iterates `BatchResponse.responses[i]`; on `messaging/registration-token-not-registered` or `messaging/invalid-registration-token`, calls `FieldValue.arrayRemove(token)` on the token's owner uid. SCENARIO-626 and 627 pass.
- [x] T-PN-006 — GATE: `npm --prefix functions run build` 0 errors; `npm --prefix functions run lint` 0 warnings/errors.
- [x] T-PN-007 — GATE: 56/56 jest tests pass against running emulators (Firestore :8080, Auth :9099). Delta +7 tests (≥ +6 required). Covers SCENARIO-625, 626, 627, 628, 677.
- [x] T-PN-008 — VERIFY: no Flutter files changed; no `pubspec.yaml` changes; no `ios/` changes; no `firestore.rules`, `storage.rules`, `firestore.indexes.json` changes; `functions/src/index.ts` NOT modified; conventional commits only; no Co-Authored-By.

---

## Files Changed (PR#1a)

| File | Action | What |
|------|--------|------|
| `openspec/changes/push-notifications-fcm/design.md` | Created | SDD design artifact |
| `openspec/changes/push-notifications-fcm/explore.md` | Created | SDD explore artifact |
| `openspec/changes/push-notifications-fcm/proposal.md` | Created | SDD proposal artifact |
| `openspec/changes/push-notifications-fcm/spec.md` | Created | SDD spec artifact |
| `openspec/changes/push-notifications-fcm/tasks.md` | Created | SDD tasks artifact |
| `functions/src/__tests__/send-fcm.test.ts` | Created | 7 jest tests for sendFcm (RED commit) |
| `functions/src/notifications/send-fcm.ts` | Created | sendFcm helper implementation (GREEN commit) |
| `openspec/changes/push-notifications-fcm/apply-progress.md` | Created | This file |

---

## Commits in PR#1a

1. `docs(sdd): add push-notifications-fcm planning artifacts` — planning artifacts (explore, proposal, spec, design, tasks)
2. `test(notifications): RED — failing tests for sendFcm helper` — T-PN-002 RED
3. `feat(notifications): GREEN — sendFcm helper with stale token cleanup` — T-PN-003 + T-PN-005 GREEN

---

## Deviations from Design

None — implementation matches ADR-PN-004 exactly:
- `sendFcm(app, input, messaging?)` signature
- Reads `fcmTokens` (camelCase per ADR-PN-001)
- `Promise.all` per-uid reads
- Flat token list to single `sendEachForMulticast` call
- Per-token `BatchResponse.responses[i]` error inspection
- `arrayRemove` for both stale error codes

---

## Remaining Tasks (Out of Scope for PR#1a)

PR#1b tasks: T-PN-009 through T-PN-023 (CF triggers + Info.plist)
PR#2a tasks: T-PN-024 through T-PN-033 (Flutter FcmService + repository)
PR#2b tasks: T-PN-034 through T-PN-047 (Flutter handler + UI)

---

## PR#1a Boundary

- **Start**: `feat/push-notifications-pr1a-send-fcm-helper` from `main`
- **End**: `send-fcm.ts` helper + tests + SDD artifacts committed and pushed
- **Scope**: CF-only, no Flutter, no index.ts modification
- **Quality gates**: build 0 errors, lint 0 warnings, 56/56 tests passing, delta +7
- **Next**: `sdd-verify` for PR#1a, then PR#1b branch after PR#1a merges to main

---

## PR#1b — CF Triggers + Info.plist (~450 LOC)

**PR scope**: PR#1b — 4 CF Triggers + Info.plist + APNs doc
**Apply batch**: 2 of 4 (second batch)
**Date**: 2026-06-02
**Branch**: `feat/push-notifications-pr1b-cf-triggers`
**Base**: post-PR#1a `main` (commit `1390393`)
**Status**: COMPLETE — branch pushed, PR#1b quality gates passed

---

### TDD Cycle Evidence (PR#1b)

| Task | Test File | RED | GREEN |
|------|-----------|-----|-------|
| T-PN-009 | SETUP | N/A | ✅ Branch confirmed clean, send-fcm.ts present |
| T-PN-010 | `notify-chat-message.test.ts` | ✅ Single RED commit (all 4 test files bundled) | N/A |
| T-PN-011 | `notify-chat-message.ts` | N/A | ✅ Tests pass |
| T-PN-012 | `notify-appointment.test.ts` | ✅ Same RED commit | N/A |
| T-PN-013 | `notify-appointment.ts` | N/A | ✅ Tests pass |
| T-PN-014 | `notify-link-change.test.ts` | ✅ Same RED commit | N/A |
| T-PN-015 | `notify-link-change.ts` | N/A | ✅ Tests pass |
| T-PN-016 | `notify-review.test.ts` | ✅ Same RED commit | N/A |
| T-PN-017 | `notify-review.ts` | N/A | ✅ Tests pass |
| T-PN-018 | `index.ts` | N/A | ✅ 4 exports added |
| T-PN-019 | `Info.plist` | N/A | ✅ UIBackgroundModes added (fresh add, key was absent) |
| T-PN-020 | `docs/setup/fcm-apns.md` | N/A | ✅ Created |
| T-PN-021 | Build + lint | N/A | ✅ 0 errors, 0 warnings |
| T-PN-022 | Full suite | N/A | ✅ 81/81, delta +25 (≥ +18 required) |
| T-PN-023 | VERIFY | N/A | ✅ All checks passed |

**Note on RED structure**: All 4 test files were bundled into a single RED commit (parallel to PR#1a deviation). The tests imported non-existent handler modules, so build failed as expected at RED time. The GREEN commit created all 4 handler files + index.ts + Info.plist + APNs doc simultaneously.

---

### Test Summary (PR#1b)

- **Tests written**: 25 new tests (across 4 test files)
- **Full suite**: 81/81 passing (delta +25 from PR#1a baseline of 56)
- **Coverage**: SCENARIO-629..643, 664, 666, 680, 681

---

### Completed Tasks (PR#1b)

- [x] T-PN-009 — SETUP: branch `feat/push-notifications-pr1b-cf-triggers` confirmed on post-PR#1a main
- [x] T-PN-010 — RED: all 4 test files created with failing imports
- [x] T-PN-011 — GREEN: `notify-chat-message.ts` — senderId filter, 100-char truncate, deepLink
- [x] T-PN-012 — RED: `notify-appointment.test.ts` in same RED commit
- [x] T-PN-013 — GREEN: `notify-appointment.ts` — cascade guard, status guards, cancelledBy TODO
- [x] T-PN-014 — RED: `notify-link-change.test.ts` in same RED commit
- [x] T-PN-015 — GREEN: `notify-link-change.ts` — cascade guard, both-parties on terminated
- [x] T-PN-016 — RED: `notify-review.test.ts` in same RED commit
- [x] T-PN-017 — GREEN: `notify-review.ts` — athleteName lookup + fallback, rating⭐ body
- [x] T-PN-018 — GREEN: `index.ts` exports 4 new CFs
- [x] T-PN-019 — GREEN: `Info.plist` UIBackgroundModes added (fresh add, no merge needed)
- [x] T-PN-020 — GREEN: `docs/setup/fcm-apns.md` created
- [x] T-PN-021 — GATE: build 0 errors; lint 0 warnings
- [x] T-PN-022 — GATE: 81/81 tests passing, delta +25
- [x] T-PN-023 — VERIFY: all scope guards passed

---

### Files Changed (PR#1b)

| File | Action | What |
|------|--------|------|
| `functions/src/__tests__/notify-chat-message.test.ts` | Created | 8 tests (RED commit) |
| `functions/src/__tests__/notify-appointment.test.ts` | Created | 8 tests (RED commit) |
| `functions/src/__tests__/notify-link-change.test.ts` | Created | 8 tests (RED commit) |
| `functions/src/__tests__/notify-review.test.ts` | Created | 6 tests (RED commit) |
| `functions/src/notifications/notify-chat-message.ts` | Created | Chat trigger handler (GREEN commit) |
| `functions/src/notifications/notify-appointment.ts` | Created | Appointment trigger handler (GREEN commit) |
| `functions/src/notifications/notify-link-change.ts` | Created | Link change trigger handler (GREEN commit) |
| `functions/src/notifications/notify-review.ts` | Created | Review trigger handler (GREEN commit) |
| `functions/src/index.ts` | Modified | +4 CF exports (GREEN commit) |
| `ios/Runner/Info.plist` | Modified | UIBackgroundModes added (GREEN commit) |
| `docs/setup/fcm-apns.md` | Created | APNs auth key setup guide (GREEN commit) |
| `openspec/changes/push-notifications-fcm/tasks.md` | Modified | [x] marks for T-PN-009..T-PN-023 |
| `openspec/changes/push-notifications-fcm/apply-progress.md` | Modified | This file |

---

### Commits in PR#1b (2 commits)

1. `test(notifications): RED — failing tests for 4 CF triggers (chat, appointment, link, review)`
2. `feat(notifications): GREEN — 4 CF triggers, index.ts exports, Info.plist UIBackgroundModes, APNs setup doc`

---

### Deviations from Design

- **RED commit structure**: 4 test files bundled into 1 RED commit (same deviation as PR#1a). Design called for one RED per task pair. Pragmatic — all 4 imports fail identically; splitting into 4 separate RED commits would add noise without safety benefit. Noted for verify phase.
- **Info.plist placement**: UIBackgroundModes was placed adjacent to `UIApplicationSupportsIndirectInputEvents` rather than `UIApplicationSceneManifest` as noted in task text. This is equally valid — the plist is a dict and key order is not significant.

---

## PR#1b Boundary

- **Branch**: `feat/push-notifications-pr1b-cf-triggers` (pushed to remote)
- **Scope**: 4 CF triggers + index.ts exports + Info.plist + APNs doc. No Flutter, no rules, no indexes.
- **Quality gates**: build 0 errors, lint 0 warnings, 81/81 tests, delta +25
- **Next**: Backhaus opens PR manually → PR#1b merges → PR#2a branch created after merge

---

## PR#2a — Flutter Data + Service (~400 LOC) — COMPLETE

**Branch**: `feat/push-notifications-pr2a-flutter-service`
**Base**: post-PR#1b `main` (commit `4a156c5`)
**Status**: COMPLETE — branch pushed to remote
**Date**: 2026-06-02

### TDD Cycle Evidence (PR#2a)

| Task | Test File | RED | GREEN |
|------|-----------|-----|-------|
| T-PN-024 | SETUP | N/A | ✅ `firebase_messaging: ^15.0.0` added (resolved to 15.2.10) |
| T-PN-025 | `fcm_token_repository_test.dart` | ✅ Fails: FcmTokenRepository not found | N/A |
| T-PN-026 | `fcm_token_repository.dart` | N/A | ✅ 10/10 tests pass |
| T-PN-027 | `fcm_service_test.dart` | ✅ Fails: FcmService not found | N/A |
| T-PN-028 | `fcm_service.dart` | N/A | ✅ 7/7 tests pass |
| T-PN-029 | `fcm_providers_test.dart` | ✅ Fails: notification_providers not found | N/A |
| T-PN-030 | `notification_providers.dart` | N/A | ✅ 3/3 tests pass |
| T-PN-031 | Format + analyze | N/A | ✅ 0 issues, 0 changed |
| T-PN-032 | Full suite | N/A | ✅ 1556 passing, delta +20 (≥ +20 required) |
| T-PN-033 | VERIFY | N/A | ✅ All scope guards passed |

### Test Summary (PR#2a)

- Tests written: 20 new tests (10 repo + 7 service + 3 providers)
- Full suite: 1556 passing (baseline 1536, delta +20)
- Pre-existing failures: 2 (athlete_coach_view_test.dart, pre-existing, unrelated)
- Covers: SCENARIO-619..623, 645..649, 650, 651, 678, 679, 683

### Files Changed (PR#2a)

| File | Action | What |
|------|--------|------|
| `pubspec.yaml` | Modified | +firebase_messaging: ^15.0.0 (resolved to 15.2.10) |
| `pubspec.lock` | Modified | Auto-updated by flutter pub get |
| `lib/features/notifications/data/fcm_token_repository.dart` | Created | FcmTokenRepository with arrayUnion/arrayRemove (GREEN) |
| `lib/features/notifications/data/fcm_service.dart` | Created | FcmService with token lifecycle + refresh sub (GREEN) |
| `lib/features/notifications/application/notification_providers.dart` | Created | Riverpod providers + fcmLifecycleProvider (GREEN) |
| `test/features/notifications/data/fcm_token_repository_test.dart` | Created | 10 tests with fake_cloud_firestore (RED+edge cases) |
| `test/features/notifications/data/fcm_service_test.dart` | Created | 7 tests with mocktail (RED) |
| `test/features/notifications/application/fcm_providers_test.dart` | Created | 3 tests with mocktail (RED) |
| `openspec/changes/push-notifications-fcm/tasks.md` | Modified | [x] marks T-PN-024..T-PN-033 |
| `openspec/changes/push-notifications-fcm/apply-progress.md` | Modified | This file |

### Commits in PR#2a (10 commits)

1. `chore(notifications): add firebase_messaging ^15.x dependency (T-PN-024)`
2. `test(notifications): RED — failing tests for FcmTokenRepository (T-PN-025, SCENARIO-619..623)`
3. `feat(notifications): GREEN — FcmTokenRepository with arrayUnion/arrayRemove (T-PN-026, SCENARIO-619..623)`
4. `test(notifications): RED — failing tests for FcmService (T-PN-027, SCENARIO-645..649, 678, 679)`
5. `feat(notifications): GREEN — FcmService with token lifecycle, refresh sub, best-effort dispose (T-PN-028, SCENARIO-645..649, 678, 679)`
6. `test(notifications): RED — failing tests for fcmLifecycleProvider (T-PN-029, SCENARIO-650, 651, 683)`
7. `feat(notifications): GREEN — Riverpod providers + fcmLifecycleProvider with auth listener (T-PN-030, SCENARIO-650, 651, 683)`
8. `style(notifications): dart format fixes on notification test files (T-PN-031)`
9. `test(notifications): add edge case tests for FcmTokenRepository field naming and missing-doc guard (T-PN-032)`
10. `docs(sdd): mark PR#2a tasks complete (T-PN-024..T-PN-033)`

### Deviations from Design (PR#2a)

- **`onForegroundMessage` static getter**: `FirebaseMessaging.onMessage` is a static getter in firebase_messaging 15.x, not an instance method. `FcmService.onForegroundMessage` and `onMessageOpenedApp` delegate to the static getters. Consistent with the firebase_messaging API.
- **`fcmLifecycleProvider` wired to `authStateChangesProvider`**: The codebase uses `authStateChangesProvider` (not a generic `authStateProvider`). The lifecycle provider was correctly wired to this existing provider.
- **Eager-read in TreinoApp.initState**: Per ADR-PN-003, `ref.read(fcmLifecycleProvider)` must be eagerly called in `TreinoApp.initState`. This wiring is **PR#2b scope** — the provider exists and is tested, but connecting it to app.dart is in the next PR.

---

## Remaining Tasks

PR#2b: T-PN-034..T-PN-047 (Flutter handler + UI + app.dart wiring) — await PR#2a merge
