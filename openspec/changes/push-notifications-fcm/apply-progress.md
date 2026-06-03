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
