# Verify Report: feed-providers-stream-conversion

**Change**: feed-providers-stream-conversion
**PR**: #87 — squash-merged to `main` at commit `0f1a153` on 2026-05-26
**Verifier**: sdd-verify executor
**Date**: 2026-05-21
**Mode**: Strict TDD (ACTIVE)
**Artifact store**: openspec + engram mirror

---

## Overall Status

**PASS WITH DEVIATIONS**

All 10 REQs covered, all 21 SCENARIOs (473–493 + 491b) exercised by passing tests, all 26 tasks marked `[x]`, and `flutter analyze` reports 0 issues. Two pre-existing deviations are documented and intentional: format drift on 2 files from the parallel PR #86 (not this SDD), and the T22 override-pattern scope that expanded from 1 to 14 test files — test-only, no production impact. Zero critical findings.

---

## REQ Matrix Coverage

| REQ | Description | Tasks | SCENARIOs | Status |
|---|---|---|---|---|
| REQ-FPS-001 | `FriendshipRepository.watchByPair` Stream | T02, T03 | 473, 474, 475 | PASS |
| REQ-FPS-002 | `FriendshipRepository.watchAcceptedFriendsOf` Stream | T04, T05 | 476, 477, 478 | PASS |
| REQ-FPS-003 | `UserPublicProfileRepository.watch` Stream | T06, T07 | 479, 480 | PASS |
| REQ-FPS-004 | `friendshipByPairProvider` as `StreamProvider.family.autoDispose` | T08, T09 | 481, 482 | PASS |
| REQ-FPS-005 | `acceptedFriendsProvider` as `StreamProvider.family.autoDispose` | T10, T11 | 483 | PASS |
| REQ-FPS-006 | `userPublicProfileProvider` as `StreamProvider.family.autoDispose` | T12, T13 | 484 | PASS |
| REQ-FPS-007 | `publicProfileViewProvider` as `AsyncNotifier.family` — no rxdart | T14, T15 | 485, 486, 487, 488, 489, 490 | PASS |
| REQ-FPS-008 | Invalidation cleanup — obsolete calls removed, `myFriendsFeedProvider` preserved | T18, T19, T20, T21 | 491b, 492, 493 | PASS |
| REQ-FPS-009 | `pendingRequestsProvider` orphan deleted | T16, T17 | 491 | PASS |
| REQ-FPS-010 | autoDispose lifecycle — Firestore listener drops on unmount | T08, T09 | 482 (shared) | PASS |
| REQ-FPS-CX-001 | Strict TDD — RED before GREEN per pair | T02..T21 | — | PASS |
| REQ-FPS-CX-002 | No `rxdart` in `pubspec.yaml` | T23 | — | PASS |
| REQ-FPS-CX-003 | `flutter analyze` 0 issues; `dart format` clean | T23, T24 | — | PASS (with note) |
| REQ-FPS-CX-004 | Consumer widget source NOT modified | T12, T13, T26 | 484 | PASS |

---

## SCENARIO Coverage

| Range | Expected | Found in `test/` | Status |
|---|---|---|---|
| 473–478 | 6 | 6 (friendship_repository_test.dart) | PASS |
| 479–480 | 2 | 2 (user_public_profile_repository_test.dart) | PASS |
| 481–490 | 10 | 10 (stream_providers_test.dart) | PASS |
| 491 | 1 | 1 (stream_providers_test.dart / analyze gate) | PASS |
| 491b | 1 | 1 (public_profile_follow_button_invalidation_test.dart) | PASS |
| 492 | 1 | 1 (public_profile_follow_button_invalidation_test.dart) | PASS |
| 493 | 1 | 1 (friend_request_inbox_tile_test.dart) | PASS |
| **Total** | **22** | **22** | **PASS** |

All 22 SCENARIO IDs (473–493 + 491b) confirmed present by `rg` grep across `test/`. All 1223 tests pass (1212 from this SDD + 11 added by PR #86 Coach Hub, which merged concurrently).

---

## Quality Gates

| Gate | Command | Result | Notes |
|---|---|---|---|
| Static analysis | `flutter analyze` | **0 issues** | Clean |
| Format check | `dart format --output=none --set-exit-if-changed .` | **2 files drifted** | `lib/features/coach_hub/presentation/coach_hub_dashboard_screen.dart` + `lib/firebase_options.dart` — both last touched by PR #86 (Coach Hub), NOT by this SDD. Exit code 0 from `dart` but non-zero from `--set-exit-if-changed`. Pre-existing from parallel PR. |
| Test suite | `flutter test` | **1223/1223 PASS** | apply-progress documented 1212; +11 from PR #86 merged concurrently. 0 regressions. |

---

## Strict TDD Evidence

Apply-progress documents RED→GREEN pairs for all implementation tasks:

| Pair | RED commit | GREEN commit | Evidence |
|---|---|---|---|
| T02/T03 | `cb506c2` — test compile-fails (method absent) | `ec23c43` — method added, 7 tests pass | ✅ |
| T04/T05 | `cb506c2` (same batch) | `ec23c43` (same batch) | ✅ |
| T06/T07 | `7187e4a` — test compile-fails | `b2af3f6` — method added, 2 tests pass | ✅ |
| T08/T10/T12/T14 | `66ec4a5` — compile-fails (FutureProvider ≠ StreamProvider) | `0927645` — all 14 tests pass | ✅ |
| T16/T17 | `3f49f96` — tombstone comment (static RED) | `958bc7c` — symbol deleted, analyze confirms | ✅ |
| T18/T19 | `77847a8` — invalidation guard tests written | `9588dc8` — obsolete calls removed, tests pass | ✅ |
| T20/T21 | `3e0af54` — SCENARIO-493 guard written | `5c2fa32` — obsolete calls removed, tests pass | ✅ |

All RED commits precede their GREEN counterparts in the squash history as individual commits within PR #87.

---

## Task Completion

All 26 tasks (T01–T26) are marked `[x]` in `tasks.md`. Confirmed against apply-progress completed-tasks section. Zero incomplete tasks.

---

## Specific Deviation Validation

### Deviation 1 — T22 broader scope (13 extra test files)
CONFIRMED INTENTIONAL. Converting `userPublicProfileProvider` to `StreamProvider` required `Stream.value(...)` overrides across 14 total test files (1 planned + 13 unplanned). Grep of the PR stat confirms all 14 are under `test/`, none under `lib/`. Zero production code changed. NOT a scope violation — correct consequence of a type-level change.

### Deviation 2 — `publicProfileViewProvider` override pattern
CONFIRMED INTENTIONAL. `test/features/feed/presentation/public_profile_screen_test.dart` uses `_StubPublicProfileViewNotifier extends PublicProfileViewNotifier` as the override subclass. This is the idiomatic Riverpod pattern for `AsyncNotifierProvider` in tests — `overrideWith` requires a concrete subclass, not a bare lambda. Code verified: `_StubPublicProfileViewNotifier` exists only in the test file, not in production code.

### Deviation 3 — Side fix in `trainer_advanced_filter_chips.dart`
CONFIRMED DOCUMENTED. Commit `c57f282` (`fix(coach): add curly braces to single-line if per lint rule; pre-existing issue surfaced by dart format`) is present in the squash history and is lint-only (curly braces added, no logic changed). The fix applies to `lib/features/coach/presentation/widgets/trainer_advanced_filter_chips.dart` — a coach-feature file, not a feed/profile file. The diff shows only brace formatting and a minor chained method de-wrap. Zero behavioral change.

---

## Out-of-Scope Sanity Guards

| Guard | Status | Evidence |
|---|---|---|
| `firestore.rules` untouched | PASS | `git show 0f1a153 --stat` shows no `firestore.rules` entry |
| `firestore.indexes.json` untouched | PASS | `git show 0f1a153 --stat` shows no `firestore.indexes.json` entry |
| `myFriendsFeedProvider` still a `FutureProvider` | PASS | `rg` confirms declaration: `final myFriendsFeedProvider = FutureProvider<List<Post>>((ref) async {` |
| `myFriendsFeedProvider` invalidation preserved (3 paths) | PASS | `rg "invalidate(myFriendsFeedProvider" lib/` returns 4 files: `public_profile_follow_button.dart`, `friend_request_inbox_tile.dart`, `create_post_notifier.dart`, `post_workout_notifier.dart` |
| `ProviderScope.containerOf` dispose-safe pattern preserved | PASS | `rg` confirms 2 occurrences in `friend_request_inbox_tile.dart` (for `_onAceptar` and `_onRechazar`) |
| `lib/features/coach/...` untouched by this SDD | PASS | Only `trainer_advanced_filter_chips.dart` lint fix (pre-existing, not SDD scope) |
| `rxdart` not added as direct dependency | PASS | `rg "rxdart" pubspec.yaml` returns empty; present in `pubspec.lock` as transitive only |
| `pendingRequestsProvider` absent from production | PASS | `rg "pendingRequestsProvider" lib/` returns only tombstone comments |

---

## Smoke Validation Reference

User confirmed smoke on 2026-05-26:
- Single-device regression: GREEN
- Cross-device test: `userPublicProfiles.displayName` mutated via Firebase Console while screen open → live update without restart observed
- `friendships.status` toggle test: observed correctly via `friendshipByPairProvider` stream
- Cross-device staleness gap (ADR-FRI-013 root cause) confirmed CLOSED end-to-end
- Composite index `friendships(members, status)` confirmed present in `treino-dev` — no `failed-precondition` thrown

---

## Lessons Promotion

Two Riverpod patterns discovered during this SDD were promoted to the global skill at `~/.claude/skills/sdd-design/SKILL.md` OUTSIDE the PR (no file change in the repo):

1. **Downstream invalidation cascade**: When converting `FutureProvider` to `StreamProvider`, all test `overrideWith` lambdas in consumer test files must return `Stream` not `Future`. Scope is wider than the direct test file — affects every test that mocks the converted provider.
2. **Dispose-safe `ProviderContainer` capture**: Use `ProviderScope.containerOf(context, listen: false)` before any `async` gap in widgets that use `container.invalidate` in callbacks. Prevents `FlutterError: A BuildContext was used after being disposed` on rapid navigation.

---

## Critical Findings

None.

---

## Warnings

1. **Format drift on 2 files from PR #86** — `lib/features/coach_hub/presentation/coach_hub_dashboard_screen.dart` and `lib/firebase_options.dart` are not dart-format-clean. Both are owned by the Coach Hub bootstrap PR (#86), not by this SDD. `dart format --set-exit-if-changed` exits 1 on main due to this drift. A follow-up `chore(format)` commit (like `cea7f2c` done previously) should be raised against the Coach Hub track before the next PR opens.

2. **T22 scope documentation gap** — apply-progress.md says "14 test files" in the completed-tasks section but "13 additional test files" in the Deviations section. Minor inconsistency (14 total = 1 planned + 13 additional). No functional impact; archive phase should normalize the language.

---

## Suggestions / Follow-ups

1. **chore(format)**: Apply `dart format .` to the 2 drifted files from PR #86 in a standalone commit on `main`. Low priority but keeps the gate meaningful for future PRs.
2. **keepAlive follow-up**: Spec NFR mentions monitoring for loading flicker on rapid navigate-back. If smoke surfaces it, a `keepAlive` follow-up for `publicProfileViewProvider` is the escalation path — tracked here, not blocking.
3. **Composite index production smoke**: Dev environment (`treino-dev`) confirmed, but production environment composite index should be verified once promoted to prod.

---

## Recommendation

**GO for archive.** Zero critical findings. All 10 REQs covered, all 22 SCENARIOs pass, 1223/1223 tests green, `flutter analyze` 0 issues. The 2 deviations are fully documented, test-only, and intentional. Format drift exists on `main` but is attributable to PR #86, not this SDD. Smoke validation confirmed cross-device staleness fix end-to-end.
