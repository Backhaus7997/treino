# Apply Progress: profile-screen-rewrite — PR#1

**Change**: profile-screen-rewrite
**Branch**: `feat/profile-screen-rewrite-pr1-scaffold`
**Mode**: Strict TDD
**Baseline test count**: 1261
**Final test count**: 1284
**Delta**: +23 tests (21 new SCENARIO tests + net of +3 from migration: 8 new CuentaSection tests including 3 migrated from deleted tile test, minus 3 deleted profile_friend_requests_tile tests = +23 net)

---

## PR#1 TDD Cycle Evidence

| Task | Test File | Layer | RED | GREEN | REFACTOR |
|------|-----------|-------|-----|-------|----------|
| T02 | N/A — constant addition | — | N/A (compile-time) | ✅ Constant added to `treino_icon.dart` | — |
| T03 | `test/features/profile/presentation/widgets/profile_section_tile_test.dart` | Widget | ✅ Written (compile fail — widget not found) | — | — |
| T04 | same | Widget | — | ✅ 5/5 SCENARIO-509a..e pass | ✅ Clean |
| T05 | `test/features/profile/presentation/widgets/profile_header_test.dart` | Widget | ✅ Written (compile fail — widget not found) | — | — |
| T06 | same | Widget | — | ✅ 2/2 SCENARIO-494,495 pass | ✅ Clean |
| T07 | `test/features/profile/presentation/widgets/profile_avatar_card_test.dart` | Widget | ✅ Written (compile fail — widget not found) | — | — |
| T08 | same | Widget | — | ✅ 5/5 SCENARIO-496..500 pass | ✅ Clean |
| T09 | `test/features/profile/presentation/widgets/profile_cuenta_section_test.dart` | Widget | ✅ Written (compile fail — widget not found) | — | — |
| T10 | same | Widget | — | ✅ 8/8 SCENARIO-501..505 + migrated 465a/466/467 pass | ✅ Clean |
| T11 | `test/features/profile/presentation/profile_screen_test.dart` | Widget | ✅ Written (behavioral fail — SCENARIO-507 ProfileHeader not in tree) | — | — |
| T12 | same | Widget | — | ✅ 2/2 SCENARIO-507,509 pass | ✅ Clean |
| T13 | `test/app/router_test.dart` (extended) | Widget | ✅ Written (compile fail — stub screens not found) | — | — |
| T14 | same | Widget | — | ✅ 6/6 SCENARIO-468b+507a..d+508 pass | ✅ Clean |
| T15 | N/A — stub screens, covered by T14 tests | — | — | ✅ 4 stub screens created | — |
| T16 | REFACTOR: migrated tests into T09/T10 file | Widget | — | — | ✅ Old test file deleted; 3 assertions migrated |
| T17 | REFACTOR: legacy widget deleted | — | — | — | ✅ `profile_friend_requests_tile.dart` deleted; 0 orphaned imports |
| T18 | GATE | — | — | ✅ `flutter analyze` — 0 issues | — |
| T19 | GATE | — | — | ✅ `dart format` — 0 changed (PR#1 files) | — |
| T20 | GATE | — | — | ✅ `flutter test` — 1284/1284 pass | — |
| T21 | VERIFY | — | — | ✅ 0 hex literals; 0 PhosphorIcons direct; i18n markers present | — |

### Test Summary

- **Total new tests**: +23 net (baseline 1261 → 1284)
- **Layers used**: Widget (all)
- **Test files created**: 4 new
- **Test files extended**: 2 (router_test + old profile_screen_test)
- **Test files deleted**: 1 (`profile_friend_requests_tile_test.dart`)
- **Migrated assertions**: 3 (SCENARIO-465a, 466, 467 moved to `profile_cuenta_section_test.dart`)

---

## Completed Tasks — PR#1

- [x] T01 — Branch `feat/profile-screen-rewrite-pr1-scaffold` created from `main`; router lines 308-318 confirmed; existing `friend-requests` child route at line 312.
- [x] T02 — `TreinoIcon.settings = PhosphorIconsRegular.gearSix` added to `treino_icon.dart` (compile-time verified; no test needed)
- [x] T03 — RED: `profile_section_tile_test.dart` — SCENARIO-509a..e (compile fail)
- [x] T04 — GREEN: `ProfileSectionTile` StatelessWidget created — all 5 tests pass
- [x] T05 — RED: `profile_header_test.dart` — SCENARIO-494,495 (compile fail)
- [x] T06 — GREEN: `ProfileHeader` ConsumerWidget created with gear→settings navigation — all 2 tests pass
- [x] T07 — RED: `profile_avatar_card_test.dart` — SCENARIO-496..500 (compile fail)
- [x] T08 — GREEN: `ProfileAvatarCard` + `deriveHandle()` pure util created — all 5 tests pass
- [x] T09 — RED: `profile_cuenta_section_test.dart` — SCENARIO-501..505 + migrated 465a/466/467 (compile fail)
- [x] T10 — GREEN: `ProfileCuentaSection` ConsumerWidget created with 4 locked tiles + count=0 stub — all 8 tests pass
- [x] T11 — RED: `test/features/profile/presentation/profile_screen_test.dart` created — SCENARIO-507 behavioral fail (ProfileHeader not in tree)
- [x] T12 — GREEN: `ProfileScreen` rewritten with `ProfileHeader` + `_OwnProfileStatsRow` + `ProfileAvatarCard` + `ProfileCuentaSection` + legacy sign-out footer — all 2 tests pass
- [x] T13 — RED: `router_test.dart` extended — SCENARIO-507a..d,508 (compile fail — stub screens not found)
- [x] T14 — GREEN: `router.dart` extended with 4 new GoRoute entries (edit-personal, gym, routines, settings) — all 6 tests pass
- [x] T15 — GREEN: 4 stub screen files created (edit_personal PR#2, gym PR#3, routines PR#3, settings PR#4)
- [x] T16 — REFACTOR: 3 test assertions from `profile_friend_requests_tile_test.dart` migrated into `profile_cuenta_section_test.dart`; old test file deleted
- [x] T17 — REFACTOR: `profile_friend_requests_tile.dart` deleted; 0 remaining imports confirmed via rg
- [x] T18 — GATE: `flutter analyze` — 0 issues ✅
- [x] T19 — GATE: `dart format` — 0 changed (PR#1 files) ✅
- [x] T20 — GATE: `flutter test` — 1284/1284 pass; delta +23 tests ✅
- [x] T21 — VERIFY: 0 hex literals; 0 PhosphorIcons direct usage; i18n markers in all new files with copy ✅

---

## Files Modified/Created

| File | Action | Description |
|------|--------|-------------|
| `lib/core/widgets/treino_icon.dart` | Modified | Added `settings = PhosphorIconsRegular.gearSix` constant |
| `lib/core/utils/handle_derivation.dart` | Created | Pure `deriveHandle(String?)` function — `toLowerCase().replaceAll(' ', '.')` |
| `lib/features/profile/presentation/widgets/profile_section_tile.dart` | Created | StatelessWidget — icon/title/subtitle/trailing/chevron, destructive mode |
| `lib/features/profile/presentation/widgets/profile_header.dart` | Created | ConsumerWidget — "TU CUENTA" eyebrow + "PERFIL" title + gear→settings |
| `lib/features/profile/presentation/widgets/profile_avatar_card.dart` | Created | ConsumerWidget — avatar + displayName + @handle derived + gym chip + pencil |
| `lib/features/profile/presentation/widgets/profile_cuenta_section.dart` | Created | ConsumerWidget — 4 locked tiles (Solicitudes/Datos/Gimnasio/Rutinas) |
| `lib/features/profile/presentation/widgets/profile_friend_requests_tile.dart` | Deleted | Legacy widget removed per ADR-PSR-003 (superseded by ProfileCuentaSection Solicitudes tile) |
| `lib/features/profile/presentation/profile_edit_personal_screen.dart` | Created | Stub — back header + "Próximamente en PR#2" |
| `lib/features/profile/presentation/profile_gym_screen.dart` | Created | Stub — back header + "Próximamente en PR#3" |
| `lib/features/profile/presentation/profile_routines_screen.dart` | Created | Stub — back header + "Próximamente en PR#3" |
| `lib/features/profile/presentation/profile_settings_screen.dart` | Created | Stub — back header + "Próximamente en PR#4" |
| `lib/features/profile/profile_screen.dart` | Modified | Rewritten body: ProfileHeader + _OwnProfileStatsRow + ProfileAvatarCard + ProfileCuentaSection + legacy sign-out footer |
| `lib/app/router.dart` | Modified | 4 new GoRoute entries under `/profile` (edit-personal, gym, routines, settings) |
| `test/features/profile/presentation/widgets/profile_section_tile_test.dart` | Created | SCENARIO-509a..e — 5 tests |
| `test/features/profile/presentation/widgets/profile_header_test.dart` | Created | SCENARIO-494,495 — 2 tests |
| `test/features/profile/presentation/widgets/profile_avatar_card_test.dart` | Created | SCENARIO-496..500 — 5 tests |
| `test/features/profile/presentation/widgets/profile_cuenta_section_test.dart` | Created | SCENARIO-501..505 + migrated 465a/466/467 — 8 tests |
| `test/features/profile/presentation/widgets/profile_friend_requests_tile_test.dart` | Deleted | Assertions migrated to profile_cuenta_section_test.dart per ADR-PSR-003 |
| `test/features/profile/presentation/profile_screen_test.dart` | Created | SCENARIO-507,509 — 2 tests (new location) |
| `test/features/profile/profile_screen_test.dart` | Modified | Fixed GoRouter compat; removed dead ProfileFriendRequestsTile import + test group |
| `test/features/profile/profile_screen_sign_out_test.dart` | Modified | Fixed GoRouter compat + scrollUntilVisible for footer sign-out button |
| `test/app/router_test.dart` | Modified | Added SCENARIO-507a..d,508 — 5 new tests |

---

## Commits

| Short SHA | Message |
|-----------|---------|
| 41a6ab1 | feat(core): add TreinoIcon.settings constant (T02 GREEN) |
| 2a5d17b | test(profile): SCENARIO-509a..e for ProfileSectionTile (T03 RED) |
| 5a8c293 | feat(profile): add ProfileSectionTile shared widget (T04 GREEN) |
| 41ce29b | test(profile): SCENARIO-494,495 for ProfileHeader (T05 RED) |
| 9d02506 | feat(profile): add ProfileHeader widget (T06 GREEN) |
| 4cf975d | test(profile): SCENARIO-496..500 for ProfileAvatarCard (T07 RED) |
| 6070219 | feat(profile): add ProfileAvatarCard widget and deriveHandle util (T08 GREEN) |
| fa52c3e | test(profile): SCENARIO-501..505 + migrated 465a/466/467 for ProfileCuentaSection (T09 RED) |
| b6afc7b | feat(profile): add ProfileCuentaSection widget with 4 locked tiles (T10 GREEN) |
| 4f7099d | test(profile): SCENARIO-507,509 for ProfileScreen composition (T11 RED) |
| 1143717 | feat(profile): compose ProfileScreen with ProfileHeader, ProfileAvatarCard, ProfileCuentaSection (T12 GREEN) |
| a552ed6 | test(app): SCENARIO-507a..d,508 for new profile sub-routes in production router (T13 RED) |
| 82f5877 | feat(profile): add 4 sub-route stubs + register in router (T14-T15 GREEN) |
| a131edf | refactor(profile): delete ProfileFriendRequestsTile — tests migrated to ProfileCuentaSection (T16-T17 REFACTOR) |
| 27e1b7d | chore(quality): fix sign-out test + old profile_screen_test GoRouter compat; all gates T18-T21 pass |
| 908e6ec | chore(sdd): mark T01..T21 complete in tasks.md |

---

## Deviations from Design

1. **`_uid` const in cuenta_section_test**: The test helper variable was declared as `final` initially; dart format + analyzer flagged it as `const`. Fixed with `const`. No behavioral deviation.

2. **Existing test fixes required (not pre-planned)**: Two existing test files (`test/features/profile/profile_screen_test.dart` and `test/features/profile/profile_screen_sign_out_test.dart`) broke because `ProfileScreen` now requires a GoRouter context — it contains `ProfileHeader` and `ProfileCuentaSection` which use `context.push`. Both tests were using `MaterialApp(home: Scaffold(body: ProfileScreen()))` without a router. Fixed by wrapping in `MaterialApp.router` with a local test GoRouter. The sign-out test also needed `scrollUntilVisible` to reach the footer TextButton (now inside a `SingleChildScrollView`). These are expected migration side-effects, not design deviations.

3. **Test delta higher than estimated**: Tasks estimated +15 new tests; actual delta is +23. The difference comes from: (a) 3 migrated Solicitudes tile tests counted as new (they moved from deleted file); (b) 5 router tests instead of the 2 mentioned in tasks (added 4 sub-cases for SCENARIO-507a..d plus the SCENARIO-508 regression guard); (c) 2 profile_screen_test (new location) overlapping with reworked existing file. All tests are valid coverage — no inflation.

4. **`ProfileScreen` wrapped in `SingleChildScrollView`**: The design §2 widget tree shows a `Column` directly. Changed to `SingleChildScrollView(Column(...))` to prevent pixel overflow on smaller screens when `ProfileCuentaSection` grows. Behavioral equivalent — no layout constraint change for the normal case.

---

## Pre-PR#1 Checklist Status

- [x] T01..T21 all marked [x]
- [x] Quality gates T18..T21 passed
- [x] No `firestore.rules` / `firestore.indexes.json` / `storage.rules` changes
- [x] `profile_friend_requests_tile.dart` and its test file deleted
- [x] 4 stub screens compile and router routes resolve
- [x] "Cerrar sesión" TextButton still present in ProfileScreen footer
- [x] `rg "i18n: Fase 6"` returns ≥1 hit per new file with copy

---

## Sections Reserved for Future PRs

- PR#2 (T22..T32) — Datos personales form + avatar upload
- PR#3 (T33..T44) — Gimnasio + Mis rutinas + new providers
- PR#4 (T45..T53) — Settings screen real + sign-out footer removal
