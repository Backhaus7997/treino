# Tasks: wire-real-stats (Fase 4 Etapa 6)

**Change**: wire-real-stats
**Branch**: feat/wire-real-stats (tracker; 4 stacked PRs merge to main)
**Strategy**: Chained PRs — stacked-to-main
**Artifact store**: hybrid

---

## Review Workload Forecast

| Field | PR#1 | PR#2 | PR#3 | PR#4 |
|---|---|---|---|---|
| Estimated changed lines | ~235 | ~255 | ~385 | ~370 |
| 400-line budget risk | Low | Low | Medium | Medium |
| Chained PRs recommended | Yes | Yes | Yes | Yes |
| Suggested split | standalone PR | depends on PR#1 | depends on PR#2 | standalone in behavior |
| Decision | proceed | proceed | proceed (no size:exception) | proceed |

Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: Medium

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|---|---|---|---|
| 1 | Home — streak + monthSessionsCount wire | PR#1 | base: main; includes shared streak util |
| 2 | Own profile stats row | PR#2 | base: main after PR#1 merged; reuses streak util |
| 3 | Public profile counter denormalization | PR#3 | base: main after PR#2 merged; BREAKING change to delete() |
| 4 | Check-in feature + Firestore rules | PR#4 | base: main after PR#3 merged; emulator run mandatory |

---

## Risk Resolutions (pre-verified)

| Risk | Resolution |
|---|---|
| SCENARIO baseline | user-public-profiles spec ends at SCENARIO-297; wire-real-stats baseline 298 is CONFIRMED correct |
| gymNameFromId | EXISTS — referenced in feed-create-search design (C.3) as reusable helper; no task needed |
| TreinoIcon.mapPin | EXISTS at lib/core/widgets/treino_icon.dart line 27; no task needed |
| FriendshipRepository.delete callers | FOUND 1 prod caller: none in UI (SIGUIENDO pill is non-tappable); 1 test caller at test/features/feed/data/friendship_repository_test.dart:203; both updated in PR#3 T19 |
| inGym param | METHOD parameter only; no persisted field; tasks use createTodayCheckIn(uid, {required bool inGym, String? gymId, String? gymName}) |
| Streak shared helper | DECIDED: extract to lib/core/utils/streak_calculator.dart in PR#2 (ADR-WRS-08); PR#1 keeps inline _computeStreak then PR#2 lifts it; tests DRY from PR#2 onward |
| SetOptions(merge: true) | Already canonical in UserPublicProfileRepository.set() (per user-public-profiles design A.2); PR#3 tasks confirm usage |
| Cross-feature write test strategy | Each cross-feature write has: success path test + injected-exception failure path test (swallowed + logged); tasks call both out explicitly |

---

## PR#1 — Home Wire (~235 LOC)

**Branch**: feat/wire-real-stats-pr1
**Base**: main
**REQs covered**: REQ-WRH-001..009, REQ-WRA-001..006

### Phase 1: Foundation

- [x] T01 — SETUP: verify clean working tree on feat/wire-real-stats-pr1 (git status clean, no stale generated files)
- [x] T02 — RED: create `test/core/utils/streak_calculator_test.dart`; write failing tests for `_computeStreak` inline function (SCENARIO-300 trained today, SCENARIO-301 not yet today, SCENARIO-302 gap resets, SCENARIO-303 zero sessions); use fixed `DateTime` clock injection via `now` param
- [x] T03 — RED: extend `test/features/insights/domain/weekly_insights_test.dart` (or create); add SCENARIO-298 (omitted fields default to 0) and SCENARIO-299 (fields present) for DTO roundtrip
- [x] T04 — GREEN: add `streak: int` and `monthSessionsCount: int` fields to `lib/features/insights/domain/weekly_insights.dart` (hand-written @immutable, NOT Freezed per ADR-WRS-04); extend `copyWith`, `==`, `hashCode`; SCENARIO-298 and SCENARIO-299 must pass

### Phase 2: Core Implementation

- [x] T05 — RED: create `test/features/insights/application/insights_providers_streak_test.dart`; write failing tests for `weeklyInsightsProvider` streak computation covering SCENARIO-300..303 plus dedup (same-day multiple sessions count once) and timezone floor; inject fake `SessionRepository` returning seeded sessions; pass `now` as provider override
- [x] T06 — RED: create `test/features/insights/application/insights_providers_month_test.dart`; write SCENARIO-304 (4 this month, 6 prior months → monthSessionsCount == 4) plus boundary: session exactly at month boundary local time
- [x] T07 — GREEN: extend `lib/features/insights/application/insights_providers.dart`; add inline `_computeStreak(Iterable<Session> sessions, {required DateTime now}) → int`; compute `streak` and `monthSessionsCount` inside `weeklyInsightsProvider`; SCENARIO-300..304 must pass

### Phase 3: Integration & Widget

- [x] T08 — RED: create `test/features/home/widgets/esta_semana_card_test.dart`; write 5 failing widget tests: loading state (SCENARIO-305), data state renders all stats (SCENARIO-306), streak copy trained-today variant (SCENARIO-307), streak copy not-yet-today variant (SCENARIO-308), error state fallback (SCENARIO-309); use `ProviderScope` with weeklyInsightsProvider override
- [x] T09 — RED: add SCENARIO-310 (card tap navigates to /home/insights) to the widget test file; use `MockGoRouter` or `GoRouter.of` stub
- [x] T10 — GREEN: convert `lib/features/home/widgets/esta_semana_card.dart` to `ConsumerWidget`; implement `AsyncValue.when` branching with `_Skeleton`, `_Loaded`, `_ErrorFallback` subtrees; RachaPill + StreakBig + StreakSubtext + DayStrip + MiniStat(SEMANA) + MiniStat(MES) + BodySilhouettePlaceholder + tap-to-insights GestureDetector; colors via `AppPalette.of(context)`; icons via `TreinoIcon.X`; spacing from scale only
- [x] T11 — VERIFY: SCENARIO-305..310 all pass; no hex literals; no PhosphorIcons direct usage

### Phase 4: Gates

- [x] T12 — GATE: `flutter analyze` — 0 issues
- [x] T13 — GATE: `dart format --output=none --set-exit-if-changed .` — 0 changed
- [x] T14 — GATE: `flutter test` — all passing (includes SCENARIO-298..310)

**PR#1 task count**: 14 tasks | **Estimated LOC**: ~235 | **Budget risk**: Low

---

## PR#2 — Own Profile Stats (~255 LOC)

**Branch**: feat/wire-real-stats-pr2
**Base**: main (after PR#1 merged + rebased)
**REQs covered**: REQ-WRP-001..010, REQ-WRA-001..006

### Phase 1: Foundation

- [ ] T15 — SETUP: create branch from post-PR#1 main; confirm `_computeStreak` exists inline in insights_providers.dart
- [ ] T16 — RED: create `test/core/utils/k_formatter_test.dart`; write failing tests for `kFormat(num v)`: SCENARIO-313 (92000 → "92k"), SCENARIO-314 (750 → "750"), SCENARIO-315 (1000 → "1k"), boundary 999 → "999", 0 → "0", 1499 → "1k", negative → "-1" (or "0" per design decision)
- [ ] T17 — GREEN: create `lib/core/utils/number_format.dart`; implement `kFormat(num v) → String`; SCENARIO-313..315 must pass
- [ ] T18 — GREEN: LIFT streak algorithm — create `lib/core/utils/streak_calculator.dart` with exported `computeStreak(Iterable<Session> sessions, {required DateTime now}) → int`; update `insights_providers.dart` to call `computeStreak(...)` instead of inline `_computeStreak`; re-run `flutter test` (no regressions)

### Phase 2: Core Implementation

- [ ] T19 — RED: create `lib/features/profile/domain/user_session_stats.dart` (named hand-written @immutable DTO per ADR-WRS-07: `{int totalSessions, double totalVolumeKg, int streak}`)
- [ ] T20 — RED: create `test/features/profile/application/profile_stats_providers_test.dart`; write failing tests for `userSessionStatsProvider`: SCENARIO-311 (143 sessions, 92000 kg total), SCENARIO-312 (new user → all zeros), streak reuses `computeStreak`; inject fake `SessionRepository` via ProviderContainer override; test null uid returns null provider result
- [ ] T21 — GREEN: create `lib/features/profile/application/profile_stats_providers.dart`; implement `userSessionStatsProvider` as `FutureProvider.autoDispose<UserSessionStats?>`; reads `currentUidProvider` + `sessionRepositoryProvider`; computes `totalSessions`, `totalVolumeKg` (fold over `session.totalVolumeKg` for finished), `streak` via `computeStreak`; returns null when uid is null; SCENARIO-311..312 must pass

### Phase 3: Integration & Widget

- [ ] T22 — RED: create or extend `test/features/profile/presentation/profile_screen_test.dart`; write 4 failing tests: SCENARIO-316 (data state renders SESIONES/VOLUMEN KG in accent, RACHA in highlight), SCENARIO-317 (loading → '--'), SCENARIO-318 (error → '--', no exception thrown), SCENARIO-319 (sign-out button always visible regardless of stats state)
- [ ] T23 — GREEN: modify `lib/features/profile/profile_screen.dart`; prepend `_OwnProfileStatsRow` ConsumerWidget above existing PERFIL content; `_OwnProfileStatsRow` reads `userSessionStatsProvider` and renders 3-stat row with `AsyncValue.when`; loading=shimmer/"--"; error="--"; data=real values; SESIONES+VOLUMEN KG use `palette.accent`, RACHA uses `palette.highlight`; sign-out ALWAYS visible; NO Scaffold/AppBackground/SafeArea added; spacing 8/12/14/18/20 only; SCENARIO-316..319 must pass

### Phase 4: Gates

- [ ] T24 — GATE: `flutter analyze` — 0 issues
- [ ] T25 — GATE: `dart format --output=none --set-exit-if-changed .` — 0 changed
- [ ] T26 — GATE: `flutter test` — all passing (includes SCENARIO-311..319)

**PR#2 task count**: 12 tasks | **Estimated LOC**: ~255 | **Budget risk**: Low

---

## PR#3 — Public Profile Cross-Feature Writes (~385 LOC)

**Branch**: feat/wire-real-stats-pr3
**Base**: main (after PR#2 merged + rebased)
**REQs covered**: REQ-WRX-001..010, REQ-WRA-001..006
**CONSTRAINT**: NO Firestore rules changes in this PR (PR#4 owns rules)

### Phase 1: Foundation — Model & Repository

- [ ] T27 — SETUP: create branch from post-PR#2 main; confirm `kFormat` and `computeStreak` are available from core/utils
- [ ] T28 — RED: add SCENARIO-320 to `test/features/profile/domain/user_public_profile_test.dart` (or create); test `UserPublicProfile.fromJson()` with no counter fields → all 4 new fields are null; test with all fields present → values correct; test existing non-counter fields are preserved
- [ ] T29 — GREEN: add 4 nullable int fields to `lib/features/profile/domain/user_public_profile.dart` (Freezed): `workoutsCount: int?`, `racha: int?`, `followersCount: int?`, `followingCount: int?`; run `dart run build_runner build --delete-conflicting-outputs`; regenerate `.freezed.dart` and `.g.dart`; SCENARIO-320 must pass
- [ ] T30 — RED: add partial-update tests to `test/features/profile/data/user_public_profile_repository_test.dart` (or create); verify `set()` with `SetOptions(merge: true)` writes only provided counter fields without clobbering others; verify null fields serialize as absent (not null) to avoid overwriting previous values

### Phase 2: Breaking Change — FriendshipRepository.delete()

- [ ] T31 — ENUM CALLERS: confirm all callers of `FriendshipRepository.delete()` before modifying signature; KNOWN callers: (1) `test/features/feed/data/friendship_repository_test.dart:203` — `await repo.delete('aaa_bbb')`; no UI production callers found (SIGUIENDO pill is non-tappable stub); document any additional callers found during apply
- [ ] T32 — RED: update `test/features/feed/data/friendship_repository_test.dart` SCENARIO-128 to use new signature `repo.delete('aaa_bbb', 'aaa')`; test must FAIL (signature not yet changed)
- [ ] T33 — RED: add SCENARIO-323 test to `test/features/feed/data/friendship_repository_test.dart`: `delete(friendshipId, myUid)` triggers self-refresh write to `userPublicProfiles/{myUid}` (decrement followersCount/followingCount); injected `UserPublicProfileRepository` receives the write; test must FAIL
- [ ] T34 — RED: add failure-swallowed test for SCENARIO-323: when `UserPublicProfileRepository` throws, `delete()` still resolves without rethrowing; error is logged via `developer.log`
- [ ] T35 — GREEN: update `FriendshipRepository.delete(String friendshipId, String myUid)` signature in `lib/features/feed/data/friendship_repository.dart`; inject optional `UserPublicProfileRepository? publicProfileRepository`; after Firestore delete, perform self-refresh counter write (self-only per ADR-WRS-12) wrapped in try/catch + `developer.log`; import `dart:developer`; SCENARIO-128 (updated), SCENARIO-323 (success + failure) must pass

### Phase 3: Cross-Feature Writes — SessionRepository & FriendshipRepository.accept()

- [ ] T36 — RED: add cross-feature write tests to `test/features/workout/data/session_repository_test.dart` (or create): SCENARIO-321 success path — `finish()` executes successfully AND `userPublicProfiles/{uid}` receives a merged write with `workoutsCount` and `racha`; inject `UserPublicProfileRepository` via closure
- [ ] T37 — RED: add SCENARIO-321 failure path: when public profile write throws, session is still marked finished (primary op succeeds); exception is swallowed; `developer.log` receives the error message
- [ ] T38 — GREEN: modify `lib/features/workout/data/session_repository.dart`; after session doc finalized, compute `workoutsCount` (count all finished for uid) and `racha` (via `computeStreak`); write to `userPublicProfiles/{uid}` via injected optional `UserPublicProfileRepository`; wrap in try/catch + `developer.log`; import `dart:developer`; `followerCountResolver` closure injected for follow counts (ADR-WRS-13 avoids cross-feature import); SCENARIO-321 success+failure must pass
- [ ] T39 — RED: add cross-feature write tests for `FriendshipRepository.accept()`: SCENARIO-322 success — after accept, `userPublicProfiles/{myUid}` receives self-refresh write; SCENARIO-322 failure — when write throws, `accept()` resolves without rethrowing; `developer.log` receives error
- [ ] T40 — GREEN: modify `lib/features/feed/data/friendship_repository.dart` `accept()` method; inject optional `UserPublicProfileRepository?`; after status update, perform self-refresh counter write for myUid only (ADR-WRS-12); try/catch + `developer.log`; SCENARIO-322 success+failure must pass

### Phase 4: DTO & Widget Pass-Through

- [ ] T41 — RED: create or extend `test/features/feed/domain/public_profile_view_test.dart`; verify `PublicProfileView` carries `workoutsCount?`, `racha?`, `followersCount?`, `followingCount?`; legacy construction without these fields still works (nullable defaults)
- [ ] T42 — GREEN: add 4 nullable int fields to `lib/features/feed/domain/public_profile_view.dart`; extend `copyWith`, `==`, `hashCode` (or regenerate if Freezed)
- [ ] T43 — RED: update `test/features/feed/application/public_profile_providers_test.dart`; add test: `publicProfileViewProvider` sources 4 counter fields from `userPublicProfileProvider(uid)` and passes them through to `PublicProfileView`
- [ ] T44 — GREEN: update `lib/features/feed/application/public_profile_providers.dart` `publicProfileViewProvider` to pass `workoutsCount`, `racha`, `followersCount`, `followingCount` from `publicProfile` into `PublicProfileView`; no new Firestore reads
- [ ] T45 — RED: create `test/features/feed/presentation/widgets/public_profile_stats_row_test.dart`; write SCENARIO-324 (real values 89/23/412/284 display in correct columns), SCENARIO-325 (null → "0"), verify `kFormat` applied to WORKOUTS/SEGUIDORES/SIGUIENDO, RACHA is raw integer
- [ ] T46 — GREEN: modify `lib/features/feed/presentation/widgets/public_profile_stats_row.dart`; add 4 `int?` constructor parameters; render null as '0'; apply `kFormat` to workoutsCount, followersCount, followingCount; RACHA displays raw value; accent color preserved; SCENARIO-324..325 must pass
- [ ] T47 — WIRE: update `lib/features/feed/presentation/public_profile_screen.dart` to pass `workoutsCount`, `racha`, `followersCount`, `followingCount` from `view` to `PublicProfileStatsRow(...)`; no new logic

### Phase 5: Gates

- [ ] T48 — GATE: `flutter analyze` — 0 issues
- [ ] T49 — GATE: `dart format --output=none --set-exit-if-changed .` — 0 changed
- [ ] T50 — GATE: `flutter test` — all passing; verify SCENARIO-320..325 pass; verify cross-feature failure tests pass (success + failure paths for SCENARIO-321..323)

**PR#3 task count**: 24 tasks | **Estimated LOC**: ~385 | **Budget risk**: Medium (no size:exception needed)

---

## PR#4 — Check-in Feature + Rules (~370 LOC)

**Branch**: feat/wire-real-stats-pr4
**Base**: main (after PR#3 merged + rebased)
**REQs covered**: REQ-WRC-001..010, REQ-WRA-001..006
**MANDATORY**: emulator rules test run before PR open

### Phase 1: Foundation — Model

- [ ] T51 — SETUP: create branch from post-PR#3 main; confirm `TreinoIcon.mapPin` exists (VERIFIED at line 27 of treino_icon.dart — no action needed); confirm `gymNameFromId` helper is importable (VERIFIED from feed-create-search design C.3 — no action needed)
- [ ] T52 — RED: create `test/features/check_in/domain/check_in_test.dart`; write failing tests: `dateKey` zero-padding (SCENARIO-326 partial: year padLeft(4), month padLeft(2), day padLeft(2)); `CheckIn.fromJson()` roundtrip with all fields; `CheckIn.fromJson()` with null gymId/gymName
- [ ] T53 — GREEN: create `lib/features/check_in/domain/check_in.dart` (Freezed); fields: `uid: String`, `date: String`, `checkedInAt: Timestamp`, `gymId: String?`, `gymName: String?`; static `dateKey(DateTime localDate) → String` with zero-padded YYYY-MM-DD; run `dart run build_runner build --delete-conflicting-outputs`; SCENARIO-326 must pass

### Phase 2: Repository & Providers

- [ ] T54 — RED: create `test/features/check_in/data/check_in_repository_test.dart`; write failing tests: SCENARIO-327 (getTodayForUser → null when no doc), SCENARIO-328 (getTodayForUser → CheckIn when doc exists), SCENARIO-329 (createTodayCheckIn upserts doc with correct fields including gymId/gymName when inGym: true), idempotency test (createTodayCheckIn called twice → single doc, returns existing on second call)
- [ ] T55 — GREEN: create `lib/features/check_in/data/check_in_repository.dart`; implement `getTodayForUser(String uid) → Future<CheckIn?>` (reads `/users/{uid}/checkIns/{dateKey}`); implement `createTodayCheckIn(String uid, {required bool inGym, String? gymId, String? gymName}) → Future<CheckIn>` (read-then-set pattern: return existing if doc present; set with `{uid, date, checkedInAt, gymId, gymName}` where gymId/gymName null when inGym: false); SCENARIO-327..329 must pass
- [ ] T56 — RED: create `test/features/check_in/application/check_in_providers_test.dart`; write failing tests: `todayCheckInProvider` returns null when no check-in exists; `todayCheckInProvider` returns CheckIn when doc exists; auth gate: unauthenticated returns null; `checkInNotifierProvider.confirm()` invalidates `todayCheckInProvider`
- [ ] T57 — GREEN: create `lib/features/check_in/application/check_in_providers.dart`; implement `checkInRepositoryProvider`, `todayCheckInProvider` (FutureProvider.autoDispose returns today's check-in or null, auth-gated), `checkInNotifierProvider` (AsyncNotifierProvider with `confirm(String? gymId, String? gymName)` method that calls repo + invalidates todayCheckInProvider); SCENARIO-327..329 provider layer must pass

### Phase 3: Dialog & FeedScreen Trigger

- [ ] T58 — RED: create `test/features/check_in/presentation/check_in_dialog_test.dart`; write failing tests: SCENARIO-333 (gymId non-null, gymName "Smart Fit" → subtext includes gym name), SCENARIO-334 (gymId null → neutral subtext), "NO" button calls `Navigator.pop` (SCENARIO-338 partial), "SÍ, ENTRÉ" button calls notifier confirm (SCENARIO-337 partial)
- [ ] T59 — GREEN: create `lib/features/check_in/presentation/check_in_dialog.dart`; `CheckInDialog` is a `ConsumerWidget`; Dialog > Padding(20) > Column [Icon(TreinoIcon.mapPin, size: 48, color: palette.accent), header "¿ESTÁS EN EL GYM HOY?", contextual subtext (with gymName or neutral), Row[NO button (outlined) | SÍ ENTRÉ button (accent fill)]]; NO taps notifier with inGym: false then pops; SÍ taps notifier with inGym: true + gymId/gymName from userProfile + gymName from gymNameFromId; create `lib/features/check_in/presentation/check_in_strings.dart` for all UI copy; colors via AppPalette; icons via TreinoIcon; spacing 8/12/14/18/20 only; SCENARIO-333..334 must pass
- [ ] T60 — RED: create `test/features/feed/presentation/feed_screen_check_in_test.dart`; write failing tests: SCENARIO-335 (todayCheckInProvider null + session flag false → dialog shown), SCENARIO-336 (todayCheckInProvider has existing CheckIn → dialog NOT shown), once-per-session guard (dialog shown → flag set → FeedScreen remount does NOT show dialog again without container reset)
- [ ] T61 — GREEN: convert `lib/features/feed/feed_screen.dart` to `ConsumerStatefulWidget`; add `initState` with `addPostFrameCallback(_maybeShowCheckIn)`; `_maybeShowCheckIn`: if session flag true → skip; await `todayCheckInProvider.future`; if not null → skip; set session flag = true; `showDialog(CheckInDialog)`; session-scoped flag is a `StateProvider<bool>` (process-lifetime); SCENARIO-335..336 must pass

### Phase 4: Firestore Rules

- [ ] T62 — SETUP: add rules block to `firestore.rules` (insert after sessions block): `match /users/{uid}/checkIns/{date} { allow read, write: if request.auth != null && request.auth.uid == uid; }` (REQ-WRC-004)
- [ ] T63 — SETUP: add 3 SCENARIO tests to `scripts/rules_test/rules.test.js` (after SCENARIO-271): SCENARIO-272 (owner can create own check-in), SCENARIO-273 (non-owner cannot read another user's checkIn), SCENARIO-274 (non-owner cannot write another user's checkIn)
- [ ] T64 — MANDATORY: run rules tests against local Firestore Emulator: `npx firebase-tools emulators:start --only firestore` + `npm test` in `scripts/rules_test/`; all 14+ scenarios (SCENARIO-268..274) MUST PASS; document results in PR description

### Phase 5: Gates & Deploy

- [ ] T65 — GATE: `flutter analyze` — 0 issues
- [ ] T66 — GATE: `dart format --output=none --set-exit-if-changed .` — 0 changed
- [ ] T67 — GATE: `flutter test` — all passing (includes SCENARIO-326..338)
- [ ] T68 — MANDATORY pre-PR: deploy updated rules to treino-dev: `npx firebase-tools deploy --only firestore:rules --project treino-dev`

**PR#4 task count**: 18 tasks | **Estimated LOC**: ~370 | **Budget risk**: Medium (no size:exception needed)

---

## Coverage Matrix

| REQ ID | Tasks |
|---|---|
| REQ-WRH-001 | T03, T04 |
| REQ-WRH-002 | T02, T05, T07 |
| REQ-WRH-003 | T06, T07 |
| REQ-WRH-004 | T08, T10 |
| REQ-WRH-005 | T08, T10 (skeleton) |
| REQ-WRH-006 | T08, T10 (_Loaded subtree) |
| REQ-WRH-007 | T08, T10 (_ErrorFallback) |
| REQ-WRH-008 | T09, T10 (tap → /home/insights) |
| REQ-WRH-009 | T08, T10 (trained-today/not-yet variants) |
| REQ-WRP-001 | T20, T21 |
| REQ-WRP-002 | T20, T21 (totalSessions count) |
| REQ-WRP-003 | T20, T21 (totalVolumeKg fold) |
| REQ-WRP-004 | T18, T21 (shared computeStreak) |
| REQ-WRP-005 | T16, T17 |
| REQ-WRP-006 | T22, T23 |
| REQ-WRP-007 | T22, T23 (accent/highlight colors) |
| REQ-WRP-008 | T22, T23 (loading → '--') |
| REQ-WRP-009 | T22, T23 (error → '--') |
| REQ-WRP-010 | T22, T23 (sign-out preserved) |
| REQ-WRX-001 | T28, T29 |
| REQ-WRX-002 | T30, T35 (merge writes) |
| REQ-WRX-003 | T36, T37, T38 |
| REQ-WRX-004 | T39, T40 |
| REQ-WRX-005 | T32, T33, T34, T35 |
| REQ-WRX-006 | T41, T42 |
| REQ-WRX-007 | T43, T44 |
| REQ-WRX-008 | T45, T46 |
| REQ-WRX-009 | T45, T46 (null → '0') |
| REQ-WRX-010 | T37, T34, T39, T40 (failure paths: logged, not rethrown) |
| REQ-WRC-001 | T52, T53 |
| REQ-WRC-002 | T54, T55 |
| REQ-WRC-003 | T56, T57 |
| REQ-WRC-004 | T62, T63, T64 |
| REQ-WRC-005 | T58, T59 |
| REQ-WRC-006 | T60, T61 |
| REQ-WRC-007 | T58, T59 (SÍ ENTRÉ path) |
| REQ-WRC-008 | T58, T59 (NO path) |
| REQ-WRC-009 | T59 (gymNameFromId in dialog) |
| REQ-WRC-010 | T63, T64 |
| REQ-WRA-001 | T10, T23, T46, T59 (AppPalette.of — all UI tasks) |
| REQ-WRA-002 | T10, T59 (TreinoIcon.X — all UI tasks) |
| REQ-WRA-003 | T10, T23, T46, T59 (spacing scale enforced) |
| REQ-WRA-004 | T02..T11, T16..T22, T28..T46, T52..T61 (TDD tasks) |
| REQ-WRA-005 | T10, T23, T59, T61 (no Scaffold/AppBackground/SafeArea added) |
| REQ-WRA-006 | T28, T29 (nullable additive fields) |

---

## Hard Constraints (inherited from spec)

1. NO modify `UserPublicProfile` model in PR#1 or PR#2 — PR#3 owns it (T29)
2. NO modify Firestore rules in PR#1, #2, #3 — PR#4 owns it (T62)
3. NO Cloud Functions — all writes are client-side
4. All colors via `AppPalette.of(context)` — no hex literals
5. All icons via `TreinoIcon.X` — no `PhosphorIcons.X` direct usage
6. Spacing from scale only: 8 / 12 / 14 / 18 / 20 px
7. Strict TDD per PR: RED → GREEN order enforced
8. Freezed regen: `dart run build_runner build --delete-conflicting-outputs`

## Artifacts
- File: openspec/changes/wire-real-stats/tasks.md
- Engram: sdd/wire-real-stats/tasks
