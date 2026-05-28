# Tasks: profile-screen-rewrite (Fase 3 Etapa 7)

**Change**: profile-screen-rewrite
**Phase/Etapa**: Fase 3 / Etapa 7
**Owner**: Backhaus
**PRs**: 4 chained PRs against `main`
**Artifact store**: openspec + engram mirror

---

## Review Workload Forecast

| Field | PR#1 | PR#2 | PR#3 | PR#4 |
|---|---|---|---|---|
| Estimated changed lines | ~350 | ~400 | ~350 | ~200 |
| 400-line budget risk | Low | Medium | Low | Low |
| Chained PRs recommended | Yes | Yes | Yes | Yes |
| Suggested split | standalone | depends on PR#1 | depends on PR#2 | depends on PR#3 |
| Delivery strategy | chained-pr | chained-pr | chained-pr | chained-pr |
| Decision needed before apply | No | No | No | No |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: Medium

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|---|---|---|---|
| 1 | Read-only scaffold — all shared widgets + router | PR#1 | base: main; ~350 LOC |
| 2 | Datos personales form + avatar upload | PR#2 | base: main, rebase after PR#1 merges |
| 3 | Gimnasio + Mis rutinas + new providers | PR#3 | base: main, rebase after PR#2 merges |
| 4 | Settings screen + legacy sign-out removal | PR#4 | base: main, rebase after PR#3 merges |

---

## Risk Resolutions (pre-verified)

| Risk | Resolution |
|---|---|
| ProfileFriendRequestsTile test compatibility | Per ADR-PSR-003 — delete legacy widget + migrate its tests to ProfileCuentaSection Solicitudes tile assertions in PR#1 (T15–T16). |
| `userProfileProvider` reactivity | Per ADR-PSR-014 — StreamProvider already; save handler does NOT invalidate manually. Covered by SCENARIO-515 (avatar card refreshes on stream re-emission). |
| `RoutineRepository.listAssignedTo` audit | Verified in design §2 — `assignedRoutinesProvider` wraps it. PR#3 T33–T34 add both providers. |
| Gym catalog reuse | Per ADR-PSR-011 — reuse `filteredGymsProvider`, `gymSearchQueryProvider`, `GymCard` from `lib/features/profile_setup/*` verbatim. |
| Image picker + Storage reuse | Per design §4.2 — reuses `AvatarUploadService` (avatarUploadServiceProvider) from ProfileSetup. No new upload infra. |
| Sign-out flow during chain transition | Per ADR-PSR-008 — legacy "Cerrar sesión" button stays in ProfileScreen body through PR#1–PR#3; removed only in PR#4. |
| `TreinoIcon.settings` gap | PR#1 FIRST commit adds `static const IconData settings = PhosphorIconsRegular.gearSix;` to `lib/core/widgets/treino_icon.dart`. |
| Historial tile destination | RESOLVED by scope reduction 2026-05-27 — tile excluded entirely. Skip. |
| PR#1 stub screens back button | Each stub renders minimal header with `TreinoIcon.back` + `context.pop()` + placeholder text "Próximamente en PR#N". |
| i18n marker comment placement | Every new file with user-facing copy gets `// i18n: Fase 6 Etapa 3` per-string. T20/T31/T42/T51 verify with `rg`. |
| Routing collision with /profile/friend-requests | Per ADR-PSR-009 — extend existing `/profile` GoRoute's `routes:` list only. PR#1 T13 includes manual diff check before router edit. |
| Chain incompleteness window | Per ADR-PSR-004 + ADR-PSR-008 — each PR independently mergeable; progression mandatory. Documented in each PR body. |
| Solicitudes tile relocation regression | PR#1 quality gate runs `flutter test` on old + new location; old `profile_friend_requests_tile_test.dart` deleted only after migration (T16). |
| Firestore rules audit | Design §7 confirms zero rule/index/storage changes. No deploy needed. |
| i18n debt | Design §8 has full es-AR copy table. Marker comments added per file (enforced by T20/T31/T42/T51). |

---

## Branch + Base per PR

| PR# | Branch | Base |
|---|---|---|
| PR#1 | `feat/profile-screen-rewrite-pr1-scaffold` | `main` |
| PR#2 | `feat/profile-screen-rewrite-pr2-edit-personal` | `main` (rebase after PR#1 merges) |
| PR#3 | `feat/profile-screen-rewrite-pr3-gym-routines` | `main` (rebase after PR#2 merges) |
| PR#4 | `feat/profile-screen-rewrite-pr4-settings` | `main` (rebase after PR#3 merges) |

---

## PR#1 — Read-Only Scaffold (~350 LOC)

**REQs covered**: REQ-PSR-001..011, REQ-PSR-013, REQ-PSR-014, REQ-PSR-CX-001..004
**SCENARIOs covered**: 494..505, 507..509 (SCENARIO-506 REMOVED)

### Phase 1.1: Infrastructure prerequisites

- [x] T01 — SETUP: branch from `main`; confirm clean working tree; locate `lib/features/profile/profile_screen.dart` and `lib/app/router.dart` exact line ranges for GoRoute `/profile`; note existing `friend-requests` child route.
- [x] T02 — GREEN (no test): add `static const IconData settings = PhosphorIconsRegular.gearSix;` to `lib/core/widgets/treino_icon.dart`. No widget test needed — constant addition, compile-time verified.

### Phase 1.2: ProfileSectionTile widget

- [x] T03 — RED: create `test/features/profile/presentation/widgets/profile_section_tile_test.dart`; failing tests for: renders title only; renders title + subtitle; renders custom trailing override; tap fires onTap; destructive variant tints icon + title in `palette.danger` (5 test cases — SCENARIO-509a..e per design §4.1).
- [x] T04 — GREEN: create `lib/features/profile/presentation/widgets/profile_section_tile.dart` — StatelessWidget, constructor per design §4.1, renders icon/title/subtitle/trailing/chevron per spec; T03 must pass.

### Phase 1.3: ProfileHeader widget

- [x] T05 — RED: create `test/features/profile/presentation/widgets/profile_header_test.dart`; 2 failing tests: "TU CUENTA" and "PERFIL" texts visible (SCENARIO-494); gear tap pushes `/profile/settings` (SCENARIO-495).
- [x] T06 — GREEN: create `lib/features/profile/presentation/widgets/profile_header.dart` — ConsumerWidget, Barlow Condensed texts + GestureDetector on `TreinoIcon.settings` (48×48 hit area); T05 must pass.

### Phase 1.4: ProfileAvatarCard widget

- [x] T07 — RED: create `test/features/profile/presentation/widgets/profile_avatar_card_test.dart`; 5 failing tests: avatar+displayName+derived @handle visible (SCENARIO-496); @handle accent preservation for "Ana Núñez" → "@ana.núñez" (SCENARIO-497); gym chip visible when gymId non-null (SCENARIO-498); gym chip absent when gymId null (SCENARIO-499); pencil tap pushes `/profile/edit-personal` (SCENARIO-500).
- [x] T08 — GREEN: create `lib/features/profile/presentation/widgets/profile_avatar_card.dart` and `lib/core/utils/handle_derivation.dart` (`deriveHandle(String name)` pure function); T07 must pass.

### Phase 1.5: ProfileCuentaSection widget

- [x] T09 — RED: create `test/features/profile/presentation/widgets/profile_cuenta_section_test.dart`; 5 failing tests: exactly 4 tiles in order (SCENARIO-501); Solicitudes tile reflects count from `pendingRequestCountProvider` (SCENARIO-502); Datos personales tile taps to `/profile/edit-personal` (SCENARIO-503); Gimnasio tile taps to `/profile/gym` (SCENARIO-504); Mis rutinas tile taps to `/profile/routines` (SCENARIO-505). Override providers via `ProviderScope`.
- [x] T10 — GREEN: create `lib/features/profile/presentation/widgets/profile_cuenta_section.dart` — ConsumerWidget, 4 `ProfileSectionTile` in locked order per design §4.1; stub `assignedRoutinesCountProvider` usage with count=0 for PR#1 (real provider arrives in PR#3); T09 must pass.

### Phase 1.6: ProfileScreen composition

- [x] T11 — RED: extend (or create) `test/features/profile/presentation/profile_screen_test.dart`; 2 failing tests: ProfileScreen body contains `ProfileHeader`, `ProfileAvatarCard`, `ProfileCuentaSection` (SCENARIO-507); "Cerrar sesión" TextButton present in body footer (SCENARIO-509).
- [x] T12 — GREEN: replace `lib/features/profile/profile_screen.dart` placeholder body with new composition — `ProfileHeader` + `_OwnProfileStatsRow` + `ProfileAvatarCard` + `ProfileCuentaSection` + legacy "Cerrar sesión" TextButton in footer; T11 must pass.

### Phase 1.7: Router + stub screens

- [x] T13 — RED: create/extend `test/app/router_test.dart`; 2 failing tests: all 4 new sub-routes resolve without error (SCENARIO-507 router variant); existing `/profile/friend-requests` still navigates to `FriendRequestsInboxScreen` (SCENARIO-508). Run manual `rg "path: 'friend-requests'" lib/app/router.dart` before editing to confirm child-route position.
- [x] T14 — GREEN: extend `lib/app/router.dart` `/profile` GoRoute's `routes:` list with 4 new `GoRoute` entries (`edit-personal`, `gym`, `routines`, `settings`); each points to its stub screen class; T13 must pass.
- [x] T15 — GREEN (no extra test): create 4 stub screen files with `_StubBody` per design §4.1: `lib/features/profile/presentation/profile_edit_personal_screen.dart` ("Próximamente en PR#2"), `lib/features/profile/presentation/profile_gym_screen.dart` ("Próximamente en PR#3"), `lib/features/profile/presentation/profile_routines_screen.dart` ("Próximamente en PR#3"), `lib/features/profile/presentation/profile_settings_screen.dart` ("Próximamente en PR#4").

### Phase 1.8: Legacy widget cleanup

- [x] T16 — REFACTOR: migrate test assertions from `test/features/profile/presentation/widgets/profile_friend_requests_tile_test.dart` into `profile_cuenta_section_test.dart` Solicitudes tile block (per ADR-PSR-003); then delete the old test file.
- [x] T17 — REFACTOR: delete `lib/features/profile/presentation/widgets/profile_friend_requests_tile.dart`; confirm no other imports reference it (`rg "profile_friend_requests_tile" lib/`).

### Phase 1.9: Quality gates

- [x] T18 — GATE: `flutter analyze` — 0 issues.
- [x] T19 — GATE: `dart format --output=none --set-exit-if-changed .` — 0 changed (PR#1 files only; pre-existing coach_hub files excluded).
- [x] T20 — GATE: `flutter test` — 1284/1284 passing; delta +23 tests (baseline 1261); migrated Solicitudes tile tests preserved.
- [x] T21 — VERIFY: 0 hex literals; 0 PhosphorIcons direct; i18n markers ≥1 per new file. All verified.

---

## PR#2 — Datos Personales + Avatar Edit (~400 LOC)

**REQs covered**: REQ-PSR-015..018, REQ-PSR-CX-001..004
**SCENARIOs covered**: 510..515

### Phase 2.1: Form scaffold

- [x] T22 — SETUP: branch `feat/profile-screen-rewrite-pr2-edit-personal` created from post-PR#1 `main`; `/profile/edit-personal` stub confirmed in router and file in place.
- [x] T23 — RED: `test/features/profile/presentation/profile_edit_personal_screen_test.dart` created — SCENARIO-510,512,513 (compile/behavioral fail)
- [x] T24 — GREEN: `lib/features/profile/presentation/profile_edit_personal_screen.dart` replaced stub with real ConsumerStatefulWidget — all 6 tests pass (SCENARIO-510..515)

### Phase 2.2: Save flow

- [x] T25 — RED: SCENARIO-511 (save fires update + pops) included in T23 test file.
- [x] T26 — GREEN: save handler validates → builds partial → `await userRepository.update(uid, partial)` → `context.pop()` — SCENARIO-511 pass.

### Phase 2.3: Avatar upload

- [x] T27 — RED: SCENARIO-514,515 (avatar editor present, upload structure) included in T23 test file.
- [x] T28 — GREEN: `_AvatarEditor` + `_pickAvatar()` + upload in `_save()` via `avatarUploadServiceProvider`; error SnackBar "No pudimos subir tu foto. Probá de nuevo." — SCENARIO-514,515 pass.

### Phase 2.4: Quality gates

- [x] T29 — GATE: `flutter analyze` — 0 issues ✅
- [x] T30 — GATE: `dart format` — 0 changed ✅
- [x] T31 — GATE: `flutter test` — 1290/1290 passing; delta +6 tests (baseline 1284) ✅
- [x] T32 — VERIFY: 0 hex literals; 0 PhosphorIcons direct; 29 i18n markers; REQ-PSR-CX-001..004 verified ✅

---

## PR#3 — Gimnasio + Mis Rutinas (~350 LOC)

**REQs covered**: REQ-PSR-019..021, REQ-PSR-CX-001..004
**SCENARIOs covered**: 516..521

### Phase 3.1: New providers

- [x] T33 — SETUP: rebase `feat/profile-screen-rewrite-pr3-gym-routines` on post-PR#2 `main`.
- [x] T34 — RED: create `test/features/profile/application/assigned_routines_providers_test.dart`; 3 failing tests: `assignedRoutinesProvider(myUid)` returns only trainer-assigned plans for myUid (SCENARIO-519 filter logic); `assignedRoutinesProvider(myUid)` renders `RoutineCard` per item (SCENARIO-520 — count check); `assignedRoutinesCountProvider` returns `0` during loading/error and `list.length` on data. Use `ProviderContainer` with overridden `routineRepositoryProvider`.
- [x] T35 — GREEN: create `lib/features/profile/application/assigned_routines_providers.dart` — `assignedRoutinesProvider` (FutureProvider.autoDispose.family<List<Routine>, String>) + `assignedRoutinesCountProvider` (Provider.autoDispose.family<int, String>) per design §4.3; T34 must pass.
- [x] T36 — PATCH: update `lib/features/profile/presentation/widgets/profile_cuenta_section.dart` to wire `assignedRoutinesCountProvider` (replaces PR#1 count=0 stub); no new test needed (existing T09 covers the count display).

### Phase 3.2: ProfileRoutinesScreen

- [x] T37 — RED: create `test/features/profile/presentation/profile_routines_screen_test.dart`; 3 failing tests: loading state shows `CircularProgressIndicator`; empty state shows expected copy (SCENARIO-521); data state renders `RoutineCard` per item (SCENARIO-520). Override `assignedRoutinesProvider`.
- [x] T38 — GREEN: replace stub with real `lib/features/profile/presentation/profile_routines_screen.dart` — ConsumerWidget; `AsyncValue.when` on `assignedRoutinesProvider(myUid ?? '')`; reuses `RoutineCard` from `lib/features/workout/presentation/widgets/routine_card.dart`; T37 must pass.

### Phase 3.3: ProfileGymScreen

- [x] T39 — RED: create `test/features/profile/presentation/profile_gym_screen_test.dart`; 3 failing tests: gym list renders (SCENARIO-516); selecting gym and confirming calls `UserRepository.update(uid, {'gymId': ...})` (SCENARIO-517); save disabled when pending selection equals current gymId. Override `filteredGymsProvider` + `userProfileProvider` + `userRepositoryProvider`.
- [x] T40 — GREEN: replace stub with real `lib/features/profile/presentation/profile_gym_screen.dart` — ConsumerStatefulWidget; reuses `filteredGymsProvider`, `gymSearchQueryProvider`, `GymCard` from `lib/features/profile_setup/*` per ADR-PSR-011; save → `userRepository.update(uid, {'gymId': _pendingGymId})` → pop; T39 must pass.

### Phase 3.4: Quality gates

- [x] T41 — GATE: `flutter analyze` — 0 issues.
- [x] T42 — GATE: `dart format --output=none --set-exit-if-changed .` — 0 changed.
- [x] T43 — GATE: `flutter test` — all passing; delta +9 new tests (1290 → 1299); no regressions.
- [x] T44 — VERIFY: 0 hex literals; 0 PhosphorIcons direct; i18n markers ≥1 per new file; SCENARIO-518 automatic via userProfileProvider StreamProvider.

---

## ~~PR#4 v1~~ — SUPERSEDED BY PR#4 v2 PIVOT 2026-05-28

> **PIVOT 2026-05-28**: Original PR#4 tasks T45..T53 are SUPERSEDED. The separate
> Settings screen approach was scrapped. See PR#4 v2 section below.

### ~~Phase 4.1: ProfileSettingsScreen (real)~~ — SUPERSEDED

- [~~T45~~] — ~~SETUP~~ (superseded by T45v2)
- [~~T46~~] — ~~RED: profile_settings_screen_test~~ (superseded by T46v2)
- [~~T47~~] — ~~GREEN: ProfileSettingsScreen real~~ (superseded by T47v2)

### ~~Phase 4.2: Legacy sign-out removal~~ — SUPERSEDED

- [~~T48~~] — ~~RED: SCENARIO-526 (footer absent)~~ (superseded — pivot handles this differently)
- [~~T49~~] — ~~GREEN: remove TextButton footer~~ (superseded by T49v2)

### ~~Phase 4.3: Quality gates~~ — SUPERSEDED

- [~~T50~~] — (superseded by T50v2)
- [~~T51~~] — (superseded by T51v2)
- [~~T52~~] — (superseded by T52v2)
- [~~T53~~] — (superseded by T53v2)

---

## PR#4 v2 — PIVOT 2026-05-28: Actions in Body (~150 LOC)

> **Rationale**: Settings as a surface is premature — only 2 tiles, no real settings yet.
> Sign-out + eliminar-cuenta tiles live directly at the bottom of ProfileScreen body.
> /profile/settings route, ProfileSettingsScreen, and TreinoIcon.settings all REMOVED.

**REQs covered**: REQ-PSR-026..028, REQ-PSR-CX-001..004
**SCENARIOs covered**: 529..532, 527, 528

### Phase 4v2.1: Spec update + RED tests

- [x] T45v2 — SETUP: Hard-reset branch `feat/profile-screen-rewrite-pr4-settings` to `b1e592b` (post-PR#3 main). Commit spec update (docs). Write RED tests:
  - `test/features/profile/presentation/profile_screen_test.dart` — SCENARIO-529 (tiles present + no legacy TextButton), SCENARIO-530 (signOut called), SCENARIO-531 (stub sheet opens), SCENARIO-532 (CANCELAR closes); extends with `_TrackingAuthNotifier` stub.
  - `test/features/profile/presentation/widgets/profile_header_test.dart` — SCENARIO-494 updated to assert `Key('profile_header_gear')` ABSENT; SCENARIO-495 test REMOVED.
  - `test/app/router_test.dart` — SCENARIO-507d test REMOVED; import of `ProfileSettingsScreen` REMOVED.
  - RED commit SHA: `ff52df9`

### Phase 4v2.2: GREEN implementation

- [x] T46v2 — GREEN: Implement all changes in one GREEN commit:
  - CREATE `lib/features/profile/presentation/widgets/eliminar_cuenta_stub_sheet.dart` — drag handle + title + copy + CANCELAR only; no destructive logic.
  - MODIFY `lib/features/profile/presentation/widgets/profile_header.dart` — remove gear `GestureDetector`, `go_router` import, `treino_icon.dart` import. Header is now a simple Column with 2 Text widgets.
  - MODIFY `lib/features/profile/profile_screen.dart` — remove legacy TextButton footer; add `ProfileSectionTile` for "Cerrar sesión" (TreinoIcon.signOut) and "Eliminar cuenta" (TreinoIcon.trash, destructive=true + showModalBottomSheet).
  - MODIFY `lib/app/router.dart` — remove `profile_settings_screen.dart` import; remove `GoRoute(path: 'settings')`.
  - DELETE `lib/features/profile/presentation/profile_settings_screen.dart`.
  - MODIFY `lib/core/widgets/treino_icon.dart` — remove `settings` constant.
  - MODIFY `test/features/profile/profile_screen_sign_out_test.dart` — remove stale `settings` route from local test router.
  - GREEN commit SHA: `cb2cac7`

### Phase 4v2.3: Quality gates

- [x] T50v2 — GATE: `flutter analyze` — 0 issues ✅
- [x] T51v2 — GATE: `dart format --output=none --set-exit-if-changed .` — 0 changed ✅
- [x] T52v2 — GATE: `flutter test` — 1313/1313 passing; delta +14 vs 1299 baseline ✅
- [x] T53v2 — VERIFY: 0 hex literals; 0 PhosphorIcons direct; 4 i18n markers in EliminarCuentaStubSheet; `rg "TreinoIcon.settings"` → 0 hits; `rg "profile/settings|ProfileSettingsScreen"` in lib/ → 0 code hits (comments only) ✅

---

## Coverage Matrix: REQ → Tasks → SCENARIOs

| REQ | Tasks | SCENARIOs |
|---|---|---|
| REQ-PSR-001 | T05, T06 | 494 (**UPDATED 2026-05-28** — gear absent assertion added) |
| ~~REQ-PSR-002~~ | ~~T05, T06~~ | ~~495~~ (REMOVED 2026-05-28 — gear icon removed in PR#4v2) |
| REQ-PSR-003 | T07, T08 | 496 |
| REQ-PSR-004 | T07, T08 | 496, 497 |
| REQ-PSR-005 | T07, T08 | 498, 499 |
| REQ-PSR-006 | T07, T08 | 500 |
| REQ-PSR-007 | T09, T10 | 501 |
| REQ-PSR-008 | T09, T10 | 502 |
| REQ-PSR-009 | T09, T10 | 503 |
| REQ-PSR-010 | T09, T10 | 504 |
| REQ-PSR-011 | T09, T10 | 505 |
| ~~REQ-PSR-012~~ | — | ~~506~~ (REMOVED 2026-05-27) |
| REQ-PSR-013 | T13, T14 | 507, 508 |
| REQ-PSR-014 | T11, T12 | 509 |
| REQ-PSR-015 | T23, T24 | 510 |
| REQ-PSR-016 | T25, T26 | 511 |
| REQ-PSR-017 | T23, T24 | 512, 513 |
| REQ-PSR-018 | T27, T28 | 514, 515 |
| REQ-PSR-019 | T39, T40 | 516, 517, 518 |
| REQ-PSR-020 | T34, T35, T37, T38 | 519, 520 |
| REQ-PSR-021 | T37, T38 | 521 |
| ~~REQ-PSR-022~~ | ~~T46, T47~~ | ~~522~~ (REMOVED 2026-05-28 — settings screen scrapped) |
| ~~REQ-PSR-023~~ | ~~T46, T47~~ | ~~523~~ (REMOVED 2026-05-28 — superseded by REQ-PSR-027) |
| ~~REQ-PSR-024~~ | ~~T46, T47~~ | ~~524~~ (REMOVED 2026-05-28 — superseded by REQ-PSR-028) |
| ~~REQ-PSR-025~~ | ~~T48, T49~~ | ~~525~~ (MOVED→532), ~~526~~ (REMOVED 2026-05-28) |
| REQ-PSR-026 | T45v2, T46v2 | 529 |
| REQ-PSR-027 | T45v2, T46v2 | 530 |
| REQ-PSR-028 | T45v2, T46v2 | 531, 532 |
| REQ-PSR-CX-001 | T21, T32, T44, T53v2 | 527 |
| REQ-PSR-CX-002 | T21, T32, T44, T53v2 | 528 |
| REQ-PSR-CX-003 | T21, T32, T44, T53v2 | 527 |
| REQ-PSR-CX-004 | T03..T46v2 (TDD order) | — (process-enforced) |

---

## Pre-PR Checklist (per PR)

### PR#1
- [x] T01..T21 all marked [x]
- [x] Quality gates T18..T21 passed
- [x] No `firestore.rules` / `firestore.indexes.json` / `storage.rules` changes
- [x] `profile_friend_requests_tile.dart` and its test file deleted (T16, T17)
- [x] 4 stub screens compile and router routes resolve (T13, T14, T15)
- [x] "Cerrar sesión" TextButton still present in ProfileScreen footer (T11, T12)
- [x] `rg "i18n: Fase 6" lib/features/profile/presentation/` ≥1 hit per new file with copy

### PR#2
- [x] T22..T32 all marked [x]
- [x] Quality gates T29..T32 passed
- [x] Rebase on post-PR#1 main confirmed clean
- [x] `/profile/edit-personal` stub replaced by real screen
- [x] Avatar upload via `avatarUploadServiceProvider` (no new infra)
- [x] `rg "i18n: Fase 6" lib/features/profile/presentation/profile_edit_personal_screen.dart` → 29 hits ✅

### PR#3
- [x] T33..T44 all marked [x]
- [x] Quality gates T41..T44 passed
- [x] Rebase on post-PR#2 main confirmed clean (branch was already on post-PR#2 main)
- [x] `/profile/gym` and `/profile/routines` stubs replaced by real screens
- [x] `assignedRoutinesCountProvider` wired in `ProfileCuentaSection` (T36)
- [x] Gym catalog reuse from `profile_setup` confirmed (no duplication — ADR-PSR-011)
- [x] `rg "i18n: Fase 6" lib/features/profile/presentation/profile_gym_screen.dart` → 6 hits ✅

### PR#4 v2 (PIVOT 2026-05-28)
- [x] T45v2..T53v2 all marked [x]
- [x] Quality gates T50v2..T53v2 passed
- [x] Branch hard-reset to b1e592b (post-PR#3 main) — clean base confirmed
- [x] `profile_settings_screen.dart` DELETED
- [x] `TreinoIcon.settings` constant REMOVED
- [x] `/profile/settings` GoRoute REMOVED from router
- [x] "Cerrar sesión" TextButton REMOVED from ProfileScreen footer
- [x] Two new tiles added at bottom of ProfileScreen: "Cerrar sesión" (signOut) + "Eliminar cuenta" (stub sheet)
- [x] ProfileHeader gear icon REMOVED
- [x] `rg "TreinoIcon.settings" lib/ test/` → 0 hits ✅
- [x] `rg "profile/settings|ProfileSettingsScreen" lib/` → 0 code hits (comments only) ✅
- [x] `flutter test` — 1313/1313 pass; all 4 new SCENARIOs (529..532) covered ✅

---

## Hard Constraints

1. NO modifications to `firestore.rules` / `firestore.indexes.json` / `storage.rules`
2. NO Historial tile work (scope-reduced 2026-05-27)
3. NO new freezed models
4. NO new packages (cross-feature import from `profile_setup` OK per ADR-PSR-011)
5. NO converting any FutureProvider to Stream beyond `assignedRoutinesProvider` design
6. NO removing "Cerrar sesión" TextButton in PR#1 / PR#2 / PR#3 (only PR#4)
7. All colors via `AppPalette.of(context)` — no hex literals
8. All icons via `TreinoIcon.X` — no `PhosphorIcons.X` direct usage
9. Spacing from scale only: 8 / 12 / 14 / 18 / 20
10. Strict TDD: RED commit BEFORE GREEN commit per task pair
11. Every user-facing string gets `// i18n: Fase 6 Etapa 3` marker comment

---

## Artifacts

- File: `openspec/changes/profile-screen-rewrite/tasks.md`
- Engram: `sdd/profile-screen-rewrite/tasks`
