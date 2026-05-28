# Tasks: account-deletion

**Change**: account-deletion
**Owner**: Backhaus
**Date**: 2026-05-28
**PRs**: 3 chained PRs against `main`
**Artifact store**: hybrid (file + Engram `sdd/account-deletion/tasks`)
**Spec patch applied**: 2026-05-28 — REQ-ACCDEL-CF-007 revised, SCENARIO-542 revised, REQ-ACCDEL-UI-007 added, SCENARIO-570 added

---

## Review Workload Forecast

| Field | PR#1 | PR#2 | PR#3 |
|---|---|---|---|
| Estimated changed lines | ~230 | ~280 | ~390 |
| 400-line budget risk | Low | Low | Medium (close to ceiling) |
| Chained PRs recommended | Yes | Yes | Yes |
| Suggested split | standalone CF bootstrap | depends on PR#1 | depends on PR#2 |
| Delivery strategy | chained-pr | chained-pr | chained-pr |
| Decision needed before apply | No | No | No |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: Medium

Total: ~900 LOC across 3 PRs.

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|---|---|---|---|
| 1 | CF infra bootstrap — callable skeleton, guards, audit-log, smoke test | PR#1 | base: main; ~230 LOC; standalone deploy |
| 2 | CF full cascade — 8 cascade modules + full integration test suite | PR#2 | base: main, rebase after PR#1 merges; depends on PR#1 |
| 3 | Flutter UI — re-auth, deletion notifier, sheets, chat fallback | PR#3 | base: main, rebase after PR#2 merges; depends on PR#2 |

---

## Risk Resolutions (pre-verified)

| Risk | Resolution |
|---|---|
| Blaze billing on treino-dev | **ACTION ITEM for Backhaus before PR#1 apply phase.** CF deploy fails loudly on Spark plan. |
| Apple re-auth UX quirks | Manual smoke test mandatory at PR#3 close-out on real iOS device; `_AppleReAuthBody` isolated for focused debugging. |
| Sub-collection scale (sessions 500+) | Admin SDK `recursiveDelete` handles batching internally. |
| Cold start ~1-3s | Loading overlay with "Eliminando tu cuenta..." + min-display 800ms to avoid flicker. |
| Trainer self-deletion | CF role guard (REQ-ACCDEL-CF-003) throws `permission-denied` before any cascade. |
| Chat message immutability | **Resolved by spec patch 2026-05-28** (ADR-ACCDEL-005): CF deletes `userPublicProfiles/{uid}`; chat UI renders "Usuario eliminado" at read time via existing sender-name join. Messages untouched. |
| Chat UI crashes on missing profile | PR#3 T41/T42 add widget test + fallback implementation to confirm safe render. |
| cloud_functions iOS pod issues | `cd ios && pod install` immediately after pubspec change; commit updated `Podfile.lock`. |
| Atomic-ish failures mid-cascade | Each cascade module catches its own errors; CF returns `partial`; client surfaces "Reintentar". |

---

## Branch + Base per PR

| PR# | Branch | Base |
|---|---|---|
| PR#1 | `feat/account-deletion-pr1-cf-bootstrap` | `main` |
| PR#2 | `feat/account-deletion-pr2-cf-cascade` | `main` (rebase after PR#1 merges) |
| PR#3 | `feat/account-deletion-pr3-flutter-ui` | `main` (rebase after PR#2 merges) |

---

## PR#1 — CF Bootstrap (~230 LOC)

**REQs covered**: REQ-ACCDEL-CF-001, CF-002, CF-011 (started entry), CF-012, CF-014 (minimal shape), CX-001, CX-004
**SCENARIOs covered**: 533, 534, 547 (started), 549, 551, 566, 569

### Phase 1.1: CF infrastructure bootstrap

- [ ] T01 — SETUP: create branch `feat/account-deletion-pr1-cf-bootstrap` from `main`; confirm clean working tree.
- [ ] T02 — SETUP: create `functions/` directory; create `functions/package.json` with deps `firebase-admin`, `firebase-functions@^4`, `typescript`, `@types/node`, `jest`, `ts-jest`, `firebase-functions-test`; npm scripts: `build`, `serve`, `test`.
- [ ] T03 — SETUP: create `functions/tsconfig.json` (strict, target ES2022, outDir `lib`, module commonjs).
- [ ] T04 — SETUP: create `functions/.eslintrc.js` (Firebase recommended TS rules) and `functions/.gitignore` (ignore `lib/`, `node_modules/`, `.runtimeconfig.json`).
- [ ] T05 — SETUP: edit `firebase.json` — add `"functions": { "source": "functions", "predeploy": ["npm --prefix functions run build"], "runtime": "nodejs20" }` block (+10 LOC).

### Phase 1.2: Shared types + audit-log module

- [ ] T06 — RED: create `functions/src/__tests__/audit-log.test.ts`; failing unit tests: `writeStarted` writes `status: 'started'` and `startedAt` to `audit_log/{uid}`; `writeFinal` updates `status`, `deletedAt`, `deletedCollections`, `errors`.
- [ ] T07 — GREEN: create `functions/src/types.ts` (`DeleteAccountRequest`, `DeleteAccountResponse`, `AuditLogEntry`, `CascadeResult` interfaces). Create `functions/src/cascade/audit-log.ts` — `writeStarted(uid, provider)` and `writeFinal(uid, status, deletedCollections, errors)`; T06 must pass.

### Phase 1.3: Main handler skeleton

- [ ] T08 — RED: create `functions/src/__tests__/delete-account.smoke.test.ts`; emulator-backed tests using `firebase-functions-test` in online mode:
  - SCENARIO-533: authenticated athlete can call `deleteAccount({uid: callerUid})` without `permission-denied`.
  - SCENARIO-534: calling `deleteAccount({uid: 'other-uid'})` throws `HttpsError` code `permission-denied`.
  - SCENARIO-549: after successful call, `admin.auth().getUser(uid)` throws `user-not-found`.
  - SCENARIO-551: successful response has `status == 'success'` and non-empty `deletedCollections`.
  - SCENARIO-547 (partial): `audit_log/{uid}` exists with `status == 'started'` written at entry.
- [ ] T09 — GREEN: create `functions/src/index.ts` (exports `deleteAccount`). Create `functions/src/delete-account.ts` — skeleton handler with: auth context check, anti-spoofing guard (ADR-ACCDEL-014), role read (`users/{uid}.role`; returns `permission-denied` if trainer), `writeStarted` audit call, deletes Auth user via `admin.auth().deleteUser(uid)`, `writeFinal` with `status: 'success'`, returns response shape (no cascade modules yet). Wired to emulator for T08; all T08 tests must pass.

### Phase 1.4: PR#1 quality gates

- [ ] T10 — GATE: `npm --prefix functions run build` — TypeScript compilation 0 errors.
- [ ] T11 — GATE: ESLint — 0 warnings/errors.
- [ ] T12 — GATE: `firebase emulators:exec --only firestore,auth,storage "npm --prefix functions test"` — all PR#1 smoke tests pass.
- [ ] T13 — VERIFY: deployment dry-run (`firebase deploy --only functions --dry-run`) succeeds; document Blaze billing action item.

---

## PR#2 — CF Full Cascade (~280 LOC)

**REQs covered**: REQ-ACCDEL-CF-003, CF-004, CF-005, CF-006, CF-007, CF-008, CF-009, CF-010, CF-011 (final), CF-013, CF-014 (full), CX-001, CX-002, CX-004
**SCENARIOs covered**: 535, 536, 537, 538, 539, 540, 541, 542, 543, 544, 545, 546, 547 (final), 548, 550, 551 (full), 566, 567, 569

### Phase 2.1: Rebase + cascade module RED tests

- [ ] T14 — SETUP: create branch `feat/account-deletion-pr2-cf-cascade` from post-PR#1 `main`; confirm clean rebase.
- [ ] T15 — RED: create `functions/src/__tests__/cascade/users.test.ts`; emulator tests: SCENARIO-536 (user doc + sub-collections deleted), SCENARIO-537 (missing `trainerPublicProfiles` is no-op).
- [ ] T16 — RED: create `functions/src/__tests__/cascade/friendships.test.ts`; emulator tests: SCENARIO-538 (3 friendship docs deleted), SCENARIO-539 (zero friendships is no-op).
- [ ] T17 — RED: create `functions/src/__tests__/cascade/posts.test.ts`; emulator tests: SCENARIO-540 (2 posts anonymized — `authorDisplayName`, `authorAvatarUrl`; `authorUid` unchanged), SCENARIO-541 (zero posts is no-op).
- [ ] T18 — RED: create `functions/src/__tests__/cascade/trainer-links.test.ts`; emulator test: SCENARIO-543 (active link gets `status: 'terminated'`, `reason: 'account-deleted'`, `terminatedAt` set).
- [ ] T19 — RED: create `functions/src/__tests__/cascade/appointments.test.ts`; emulator test: SCENARIO-544 (future appointment cancelled, past appointment unchanged).
- [ ] T20 — RED: create `functions/src/__tests__/cascade/storage.test.ts`; emulator tests: SCENARIO-545 (avatar deleted when present), SCENARIO-546 (missing avatar is no-op).
- [ ] T21 — RED: extend `functions/src/__tests__/delete-account.smoke.test.ts` with full integration tests: SCENARIO-535 (trainer role rejection), SCENARIO-547 (audit log success), SCENARIO-548 (audit log partial), SCENARIO-550 (idempotent re-run), SCENARIO-551 (full `deletedCollections` array).

### Phase 2.2: Cascade module GREEN implementations

- [ ] T22 — GREEN: create `functions/src/cascade/users.ts` — `deleteUserDocs(uid)`: `recursiveDelete(users/{uid})`, `userPublicProfiles/{uid}` delete (ignoreNotFound), `trainerPublicProfiles/{uid}` delete (ignoreNotFound); returns `CascadeResult`; T15 must pass.
- [ ] T23 — GREEN: create `functions/src/cascade/friendships.ts` — `sweepFriendships(uid)`: query `friendships` where `members array-contains uid`, batch delete; T16 must pass.
- [ ] T24 — GREEN: create `functions/src/cascade/posts.ts` — `anonymizePosts(uid)`: query `posts` where `authorUid == uid`, batch update `authorDisplayName: 'Usuario eliminado'` + `authorAvatarUrl: null`; chunks of 400; T17 must pass.
- [ ] T25 — GREEN: create `functions/src/cascade/trainer-links.ts` — `terminateTrainerLinks(uid)`: query `trainer_links` where `athleteId == uid`, update `status: 'terminated'`, `reason: 'account-deleted'`, `terminatedAt: FieldValue.serverTimestamp()`; T18 must pass.
- [ ] T26 — GREEN: create `functions/src/cascade/appointments.ts` — `cancelFutureAppointments(uid)`: query `appointments` where `athleteId == uid AND scheduledAt > now()`, update `status: 'cancelled'`, `reason: 'athlete-account-deleted'`; T19 must pass.
- [ ] T27 — GREEN: create `functions/src/cascade/storage.ts` — `deleteAvatar(uid)`: delete `avatars/{uid}.jpg` from Admin Storage; catch `storage/object-not-found` and HTTP 404 as no-op; add code comment documenting Admin SDK trust boundary (ADR-ACCDEL-013); T20 must pass.
- [ ] T28 — GREEN: update `functions/src/delete-account.ts` — replace skeleton with full cascade handler: add trainer role guard (SCENARIO-535), call all 6 cascade modules in order (steps 4–11 per design §5), aggregate errors, write final audit log (`writeFinal`), then `admin.auth().deleteUser(uid)` last; T21 must pass.

### Phase 2.3: PR#2 quality gates

- [ ] T29 — GATE: `npm --prefix functions run build` — 0 TypeScript errors.
- [ ] T30 — GATE: ESLint — 0 warnings/errors.
- [ ] T31 — GATE: `firebase emulators:exec --only firestore,auth,storage "npm --prefix functions test"` — all 19 emulator tests (SCENARIO-533..551) pass.
- [ ] T32 — VERIFY: each cascade module file has the Admin SDK trust-boundary comment; `audit_log/{uid}` shape matches ADR-ACCDEL-012 interface; no `firestore.rules` / `storage.rules` modifications.

---

## PR#3 — Flutter UI (~390 LOC)

**REQs covered**: REQ-ACCDEL-REAUTH-001, REAUTH-002, REAUTH-003, REAUTH-004, REAUTH-005, UI-001, UI-002, UI-003, UI-004, UI-005, UI-006, UI-007, CX-001, CX-003, CX-004
**SCENARIOs covered**: 552, 553, 554, 555, 556, 557, 558, 559, 560, 561, 562, 563, 564, 565, 566, 568, 569, 570

### Phase 3.1: Dependencies + domain setup

- [ ] T33 — SETUP: create branch `feat/account-deletion-pr3-flutter-ui` from post-PR#2 `main`; add `cloud_functions: ^4.x` to `pubspec.yaml`; run `flutter pub get`; run `cd ios && pod install`; commit updated `Podfile.lock`.
- [ ] T34 — RED: create `test/features/auth/domain/auth_failure_test.dart` (extend existing if present); failing tests for 3 new variants: `AuthFailure.requiresRecentLogin` exists and has a non-empty `userMessage`; `AuthFailure.reAuthFailed(provider: 'google.com')` exists; `AuthFailure.deletionFailed(cause: Exception())` exists.
- [ ] T35 — GREEN: edit `lib/features/auth/domain/auth_failure.dart` — add 3 variants: `requiresRecentLogin`, `reAuthFailed({String? provider})`, `deletionFailed({Object? cause})`; update `userMessage` switch; update `fromFirebase` to map `requires-recent-login` code to `requiresRecentLogin`; T34 must pass.

### Phase 3.2: AccountDeletionService

- [ ] T36 — RED: create `test/features/profile/data/account_deletion_service_test.dart`; failing tests: `AccountDeletionService.call({uid})` invokes `FirebaseFunctions.httpsCallable('deleteAccount').call({'uid': uid})`; response with `status: 'success'` is parsed to `DeletionResult.success`; response with `status: 'partial'` is parsed to `DeletionResult.partial` (SCENARIO-551 client side).
- [ ] T37 — GREEN: create `lib/features/profile/data/account_deletion_service.dart` — `AccountDeletionService` with `Future<DeletionResult> call({required String uid})`; wraps `FirebaseFunctions.instance.httpsCallable('deleteAccount').call({'uid': uid})`; simple `DeletionResult` data class (NOT freezed — per Hard Constraint #3); T36 must pass.

### Phase 3.3: AuthService re-auth helpers

- [ ] T38 — RED: extend `test/features/auth/data/auth_service_test.dart`; failing tests: `reauthenticate(credential)` calls `currentUser.reauthenticateWithCredential(credential)` (SCENARIO-552); `reauthenticate(wrongCredential)` throws `AuthFailure.reAuthFailed` on `wrong-password` code (SCENARIO-553); `getPasswordCredential({password})` returns `EmailAuthProvider.credential` built from current user email.
- [ ] T39 — GREEN: edit `lib/features/auth/data/auth_service.dart` — add `reauthenticate(AuthCredential credential)`, `getPasswordCredential({required String password})`, `getGoogleCredential()`, `getAppleCredential()` per design §6; reuses existing `_googleSignIn` and `_appleGateway` plumbing; T38 must pass.

### Phase 3.4: AccountDeletionNotifier

- [ ] T40 — RED: create `test/features/profile/application/account_deletion_notifier_test.dart`; failing tests: on `null` from re-auth sheet, neither `reauthenticate` nor CF is called (SCENARIO-559); on valid credential, `reauthenticate` called BEFORE CF callable (SCENARIO-554); on CF success, `signOut` called and state becomes `AsyncData(null)` (SCENARIO-563); on CF `partial`, state becomes `AsyncError(deletionFailed)` (SCENARIO-558 / SCENARIO-564 combined); on CF `unauthenticated`, state becomes `AsyncError(requiresRecentLogin)` (SCENARIO-558); `retry()` within 5 min skips re-auth sheet; `retry()` after 5 min re-opens sheet.
- [ ] T41 — GREEN: create `lib/features/profile/application/account_deletion_notifier.dart` — `AccountDeletionNotifier extends AsyncNotifier<void>` with `deleteAccount(BuildContext)`, `retry(BuildContext)`, `_lastReauthAt`, two-tier retry policy (ADR-ACCDEL-011), `_callCfAndFinish()`, `_openReAuthSheet()`, `_mapError()` per design §7; T40 must pass.

### Phase 3.5: ReAuthBottomSheet widget

- [ ] T42 — RED: create `test/features/profile/presentation/re_auth_bottom_sheet_test.dart`; failing widget tests: password provider renders password input field + no Google/Apple button (SCENARIO-555); google.com provider renders Google re-auth button + no password field (SCENARIO-556); apple.com provider renders Apple re-auth button (SCENARIO-557); dismissing sheet without completing returns null (SCENARIO-559 UI check); cancel button present in all 3 variants.
- [ ] T43 — GREEN: create `lib/features/profile/presentation/widgets/re_auth_bottom_sheet.dart` — `ReAuthBottomSheet` with `_PasswordReAuthBody`, `_GoogleReAuthBody`, `_AppleReAuthBody` private widgets; detects `user.providerData[0].providerId` at `initState`; each body calls matching `AuthService.getXCredential()`, then `reauthenticate(credential)`, then `Navigator.pop(context, credential)`; cancel → `Navigator.pop(context, null)`; all strings tagged `// i18n: Fase 6 Etapa 3`; colors via `AppPalette.of(context)`; T42 must pass.

### Phase 3.6: EliminarCuentaSheet widget

- [ ] T44 — RED: create `test/features/profile/presentation/eliminar_cuenta_sheet_test.dart`; failing widget tests: sheet renders title "Eliminar cuenta" in danger color (SCENARIO-560); "CANCELAR" and "ELIMINAR" buttons present (SCENARIO-560); tapping "ELIMINAR" dismisses self and opens `ReAuthBottomSheet` (SCENARIO-561); loading state shows spinner and disables ELIMINAR button when notifier is `AsyncLoading` (SCENARIO-562); error state shows SnackBar with "Reintentar" button (SCENARIO-564).
- [ ] T45 — GREEN: create `lib/features/profile/presentation/widgets/eliminar_cuenta_sheet.dart` — `EliminarCuentaSheet extends ConsumerWidget`; renders destructive copy from design §9 copy table; CANCELAR → `Navigator.pop`; ELIMINAR → calls `accountDeletionNotifierProvider.notifier.deleteAccount(context)`; `ref.listen` for `AsyncError` → show error SnackBar with "Reintentar" action; `AsyncLoading` → show overlay with "Eliminando tu cuenta..." copy; success → show SnackBar "Tu cuenta fue eliminada" after GoRouter redirect; all strings tagged `// i18n: Fase 6 Etapa 3`; T44 must pass.

### Phase 3.7: Profile screen rewiring + stub deletion

- [ ] T46 — RED: extend `test/features/profile/presentation/profile_screen_test.dart`; failing test: tapping "Eliminar cuenta" tile opens `EliminarCuentaSheet` (not `EliminarCuentaStubSheet`) (SCENARIO-565).
- [ ] T47 — GREEN: edit `lib/features/profile/profile_screen.dart` — change `showModalBottomSheet` builder from `EliminarCuentaStubSheet` to `EliminarCuentaSheet`; update import; T46 must pass.
- [ ] T48 — REFACTOR: delete `lib/features/profile/presentation/widgets/eliminar_cuenta_stub_sheet.dart`; delete `test/features/profile/presentation/eliminar_cuenta_stub_sheet_test.dart` if present; confirm no remaining imports with `rg "eliminar_cuenta_stub_sheet" lib/ test/`.

### Phase 3.8: Chat UI fallback (REQ-ACCDEL-UI-007)

- [ ] T49 — RED: create `test/features/chat/presentation/widgets/chat_message_row_test.dart` (or extend if exists); failing widget test: mount chat message row widget with mocked empty/null `userPublicProfiles` for `senderId`; assert text "Usuario eliminado" is visible (SCENARIO-570).
- [ ] T50 — GREEN: locate the chat sender-name lookup in `lib/features/chat/` (search for `senderId` / `senderName` / `userPublicProfiles` usage); implement or confirm the "Usuario eliminado" fallback when `userPublicProfiles/{senderId}` is absent; add `// i18n: Fase 6 Etapa 3` comment on the fallback string; T49 must pass.

### Phase 3.9: PR#3 quality gates

- [ ] T51 — GATE: `flutter analyze` — 0 issues.
- [ ] T52 — GATE: `dart format --output=none --set-exit-if-changed .` — 0 changed.
- [ ] T53 — GATE: `flutter test` — all passing; delta ≥ +15 tests vs PR#2 baseline (covering SCENARIOs 552..570).
- [ ] T54 — VERIFY: `rg "0x[0-9a-fA-F]{6}|Color(0xFF" lib/features/profile/ lib/features/chat/` → 0 hits; `rg "PhosphorIcons\." lib/features/profile/ lib/features/chat/` → 0 hits; `rg "i18n: Fase 6" lib/features/profile/presentation/widgets/eliminar_cuenta_sheet.dart lib/features/profile/presentation/widgets/re_auth_bottom_sheet.dart` → ≥1 hit per file; manual smoke test on all 3 providers (email/password, Google, Apple) on treino-dev.

---

## Coverage Matrix: REQ → Tasks → SCENARIOs

| REQ | Tasks | SCENARIOs |
|---|---|---|
| REQ-ACCDEL-CF-001 | T08, T09 | 533 |
| REQ-ACCDEL-CF-002 | T08, T09 | 534 |
| REQ-ACCDEL-CF-003 | T21, T28 | 535 |
| REQ-ACCDEL-CF-004 | T15, T22 | 536, 537 |
| REQ-ACCDEL-CF-005 | T16, T23 | 538, 539 |
| REQ-ACCDEL-CF-006 | T17, T24 | 540, 541 |
| REQ-ACCDEL-CF-007 (REVISED) | T22 (public profile deleted), T49, T50 | 542 (chat UI), 570 |
| REQ-ACCDEL-CF-008 | T18, T25 | 543 |
| REQ-ACCDEL-CF-009 | T19, T26 | 544 |
| REQ-ACCDEL-CF-010 | T20, T27 | 545, 546 |
| REQ-ACCDEL-CF-011 | T06, T07 (started), T21, T28 (final) | 547, 548 |
| REQ-ACCDEL-CF-012 | T08, T09 | 549 |
| REQ-ACCDEL-CF-013 | T21, T28 | 550 |
| REQ-ACCDEL-CF-014 | T08, T09 (minimal), T21, T28 (full) | 551 |
| REQ-ACCDEL-REAUTH-001 | T38, T39 | 552, 553 |
| REQ-ACCDEL-REAUTH-002 | T40, T41 | 554 |
| REQ-ACCDEL-REAUTH-003 | T42, T43 | 555, 556, 557 |
| REQ-ACCDEL-REAUTH-004 | T40, T41 | 558 |
| REQ-ACCDEL-REAUTH-005 | T40, T41, T42, T43 | 559 |
| REQ-ACCDEL-UI-001 | T44, T45 | 560 |
| REQ-ACCDEL-UI-002 | T44, T45 | 561 |
| REQ-ACCDEL-UI-003 | T44, T45 | 562 |
| REQ-ACCDEL-UI-004 | T40, T41, T44, T45 | 563 |
| REQ-ACCDEL-UI-005 | T44, T45 | 564 |
| REQ-ACCDEL-UI-006 | T46, T47, T48 | 565 |
| REQ-ACCDEL-UI-007 (NEW) | T49, T50 | 570 |
| REQ-ACCDEL-CX-001 | T08/T09 pairs, T15-T28 pairs, T34-T50 pairs | 566 |
| REQ-ACCDEL-CX-002 | T12, T31 | 567 |
| REQ-ACCDEL-CX-003 | T36, T37, T38, T39, T40, T41, T42, T43, T44, T45, T49, T50 | 568 |
| REQ-ACCDEL-CX-004 | All tasks (conventional commits, no AI attribution) | 569 |

---

## Pre-PR Checklist per PR

### PR#1 — CF Bootstrap
- [ ] T01..T13 all marked complete
- [ ] Quality gates T10..T13 passed
- [ ] `firebase.json` updated with functions block (T05)
- [ ] TypeScript compilation 0 errors (T10)
- [ ] Smoke tests SCENARIO-533, 534, 549, 551 all pass against emulator (T12)
- [ ] Blaze billing confirmed active on treino-dev before merge (T13)
- [ ] No `firestore.rules` / `firestore.indexes.json` / `storage.rules` changes
- [ ] Conventional commits only; no Co-Authored-By

### PR#2 — CF Full Cascade
- [ ] T14..T32 all marked complete
- [ ] Quality gates T29..T32 passed
- [ ] Rebase on post-PR#1 main confirmed clean (T14)
- [ ] All 19 emulator tests (SCENARIO-533..551) pass (T31)
- [ ] Each cascade module has Admin SDK trust-boundary comment where applicable
- [ ] No `firestore.rules` / `firestore.indexes.json` / `storage.rules` changes
- [ ] Conventional commits only; no Co-Authored-By

### PR#3 — Flutter UI
- [ ] T33..T54 all marked complete
- [ ] Quality gates T51..T54 passed
- [ ] Rebase on post-PR#2 main confirmed clean (T33)
- [ ] `cloud_functions` added to `pubspec.yaml`; `Podfile.lock` updated and committed (T33)
- [ ] `eliminar_cuenta_stub_sheet.dart` and its test deleted (T48)
- [ ] `rg "eliminar_cuenta_stub_sheet" lib/ test/` → 0 hits
- [ ] Chat UI "Usuario eliminado" fallback widget test passes (T49, T50)
- [ ] Manual smoke test completed on all 3 providers (email/password, Google, Apple) on treino-dev (T54)
- [ ] No `firestore.rules` / `firestore.indexes.json` / `storage.rules` changes
- [ ] Conventional commits only; no Co-Authored-By

---

## Hard Constraints

1. CF Blaze plan MUST be active on treino-dev before PR#1 merge.
2. NO modifications to `firestore.rules` / `firestore.indexes.json` / `storage.rules` — CF uses Admin SDK which bypasses rules.
3. NO new freezed models in Flutter — use simple Dart data classes for CF response (`DeletionResult`).
4. NO new Flutter packages beyond `cloud_functions` in pubspec.
5. All Flutter colors via `AppPalette.of(context)` — no hex literals.
6. All Flutter icons via `TreinoIcon.X` — no `PhosphorIcons.X` direct imports.
7. Spacing scale only: 8 / 12 / 14 / 18 / 20.
8. Strict TDD: RED commit BEFORE GREEN commit per task pair — enforced per REQ-ACCDEL-CX-001.
9. Every user-facing string in Flutter gets `// i18n: Fase 6 Etapa 3` marker comment.
10. Conventional commits only — NO Co-Authored-By, NO AI attribution.
11. CF integration tests run against Firebase Local Emulator Suite (Firestore + Auth + Storage) — NOT production.
12. `AccountDeletionNotifier` owns orchestration; `AuthService` stays thin (per ADR-ACCDEL-009).
13. Chat messages are NEVER mutated by the CF — read-time anonymization only via deleted `userPublicProfiles/{uid}` (per ADR-ACCDEL-005).

---

## Artifacts

- File: `openspec/changes/account-deletion/tasks.md`
- Engram: `sdd/account-deletion/tasks`
- Spec patched: `openspec/changes/account-deletion/spec.md` (REQ-ACCDEL-CF-007 revised, SCENARIO-542 revised, REQ-ACCDEL-UI-007 added, SCENARIO-570 added, Coverage Matrix updated)
