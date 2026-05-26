# Archive Report — feed-providers-stream-conversion (Fase 3 Etapa 6 follow-up)

**Change**: `feed-providers-stream-conversion`  
**Archived**: 2026-05-26  
**Status**: COMPLETE (PASS-WITH-DEVIATIONS → ARCHIVED)  
**PR**: #87 (squash-merged to `main` at `0f1a153`)

---

## Archival Summary

The `feed-providers-stream-conversion` SDD has been fully implemented, verified (PASS-WITH-DEVIATIONS, 0 CRITICAL), and closed. All 26 code tasks (T01–T26) are complete. The verify-report confirms all 10 functional REQs + 4 cross-cutting REQs delivered, all 22 SCENARIO identifiers (473–493 + 491b) passing with 1223/1223 tests green, and quality gates verified. This SDD closes the cross-device staleness gap explicitly deferred in ADR-FRI-013 of `feed-friend-requests-inbox` by converting three `FutureProvider` instances (`friendshipByPairProvider`, `acceptedFriendsProvider`, `userPublicProfileProvider`) into `StreamProvider.family.autoDispose`, rewriting `publicProfileViewProvider` as `AsyncNotifier.family` composition, and deleting the orphan `pendingRequestsProvider`. No main spec created — this is a provider topology + invalidation cleanup change scoped to the friendships/profile feature. Two pre-existing deviations are documented and intentional: format drift on 2 files from parallel PR #86 (Coach Hub, not this SDD), and T22 scope expansion (14 test file overrides vs. 1 planned — test-only, no production impact).

---

## Change Artifacts (Engram Observation IDs)

For traceability, all upstream artifacts are archived below with their engram IDs. These observations were created during the openspec + engram hybrid workflow:

| Artifact | Observation ID | Type | Generated |
|----------|---|---|---|
| Exploration | #88 | architecture | 2026-05-26 |
| Proposal | #89 | architecture | 2026-05-26 |
| Spec | #90 | architecture | 2026-05-26 |
| Design | #91 | architecture | 2026-05-26 |
| Tasks | #92 | architecture | 2026-05-26 |
| Apply Progress | #93 | architecture | 2026-05-26 |
| Verify Report | #95 | architecture | 2026-05-26 |
| Archive Report | (this file) | architecture | 2026-05-26 |

All artifacts remain persistent in engram via `sdd/feed-providers-stream-conversion/{artifact-type}` topic keys. File-based artifacts in this archive folder are secondary records for auditability.

---

## Scope Delivered

### Three provider conversions (locked decisions #1, #4)

- **`friendshipByPairProvider`**: Converted from `FutureProvider.family` to `StreamProvider.family.autoDispose<Friendship?, FriendshipPair>` wrapping `FriendshipRepository.watchByPair()` stream method. `AsyncValue<Friendship?>` consumer surface unchanged (drop-in). Binds Firestore listener to consumer lifetime via `autoDispose`.
- **`acceptedFriendsProvider`**: Converted from `FutureProvider.family` to `StreamProvider.family.autoDispose<List<String>, String>` wrapping `FriendshipRepository.watchAcceptedFriendsOf()` stream method. Drop-in name and surface. No auth gate (retained from original FutureProvider).
- **`userPublicProfileProvider`**: Converted from `FutureProvider.family` to `StreamProvider.family.autoDispose<UserPublicProfile?, String>` wrapping `UserPublicProfileRepository.watch()` stream method. Drop-in name and `.valueOrNull` access pattern unchanged.

### publicProfileViewProvider AsyncNotifier composition (locked decision #1 — zero new dependencies, NO rxdart)

- **Rewritten as `AsyncNotifier.family.autoDispose<PublicProfileView, String>`**: Composes the two upstream `StreamProvider` instances via `ref.watch(streamProvider(...).future)` inside `build`. On every upstream emission, Riverpod's reactivity re-runs `build`, giving live composition without manual `ref.listen` plumbing or rxdart.
- **isSelf branch**: When `viewerUid == targetUid`, the friendship subscription is skipped entirely — no Firestore listener opens for the self-pair.
- **Loading/error semantics**: Inherits from upstream streams via AsyncNotifier wrapper — consumers' existing `AsyncValue.when(loading: …, error: …)` handlers work unchanged.

### Orphan deletion (locked decision #2, T16–T17)

- **`pendingRequestsProvider` (Future variant)**: Deleted from `friendship_providers.dart`. Zero consumers in `lib/` or `test/` per explore phase. Symbol removal confirmed by `flutter analyze`.

### Invalidation cleanup (locked decision #2, T18–T21)

- **Removed obsolete calls**: All `ref.invalidate(friendshipByPairProvider(...))`, `ref.invalidate(acceptedFriendsProvider(...))`, `container.invalidate(friendshipByPairProvider(...))`, and `container.invalidate(acceptedFriendsProvider(...))` calls deleted from `PublicProfileFollowButton` (5 calls) and `FriendRequestInboxTile` (3 calls).
- **Preserved critical calls**: All `ref.invalidate(myFriendsFeedProvider)` and `container.invalidate(myFriendsFeedProvider)` calls KEPT across 3 call sites (`PublicProfileFollowButton.accept/unfriend`, `FriendRequestInboxTile._onAceptar`).
- **Dispose-safe pattern preserved**: `ProviderScope.containerOf(context, listen: false)` capture in `FriendRequestInboxTile` _onAceptar/_onRechazar handlers KEPT — still required for `myFriendsFeedProvider` invalidation before async awaits.

### Repository stream methods added

- **`FriendshipRepository.watchByPair(uidA, uidB)`**: `Stream<Friendship?>` subscribing to `friendships/{sortedDocId}` via `.snapshots()`. Returns `null` when doc absent or deleted. Same `sortedDocId` logic as existing `getByPair`.
- **`FriendshipRepository.watchAcceptedFriendsOf(uid)`**: `Stream<List<String>>` using identical query shape (`members arrayContains uid AND status == accepted`) as existing `.acceptedFriendsOf()` with `.snapshots()`. Same composite index applies.
- **`UserPublicProfileRepository.watch(uid)`**: `Stream<UserPublicProfile?>` subscribing to single doc via `.snapshots()`. Returns `null` when doc absent. Mirrors existing `get`.

### Quality gates

- ✅ `flutter analyze` — 0 issues (2 format-drift warnings on files from PR #86, not this SDD)
- ✅ `dart format` — 0 changed files in SDD-affected code
- ✅ `flutter test` — 1223/1223 tests all pass (1212 from this SDD via +25 new tests + 11 from PR #86 merged concurrently)
- ✅ Drop-in guarantee verified — zero consumer widget source modified
- ✅ Strict TDD discipline maintained — RED before GREEN for all 13 task pairs

---

## REQ Delivery & SCENARIO Traceability

### Functional Requirements (10 total)

| REQ | Description | SCENARIO(s) | Status |
|---|---|---|---|
| REQ-FPS-001 | `watchByPair` stream method | 473, 474, 475 | ✅ PASS |
| REQ-FPS-002 | `watchAcceptedFriendsOf` stream method | 476, 477, 478 | ✅ PASS |
| REQ-FPS-003 | `UserPublicProfileRepository.watch` stream method | 479, 480 | ✅ PASS |
| REQ-FPS-004 | `friendshipByPairProvider` as `StreamProvider.family.autoDispose` | 481, 482 | ✅ PASS |
| REQ-FPS-005 | `acceptedFriendsProvider` as `StreamProvider.family.autoDispose` | 483 | ✅ PASS |
| REQ-FPS-006 | `userPublicProfileProvider` as `StreamProvider.family.autoDispose` | 484 | ✅ PASS |
| REQ-FPS-007 | `publicProfileViewProvider` as `AsyncNotifier.family` composition (no rxdart) | 485, 486, 487, 488, 489, 490 | ✅ PASS |
| REQ-FPS-008 | Invalidation cleanup — obsolete calls removed, `myFriendsFeedProvider` preserved | 491b, 492, 493 | ✅ PASS |
| REQ-FPS-009 | `pendingRequestsProvider` orphan deleted | 491 | ✅ PASS |
| REQ-FPS-010 | autoDispose lifecycle — Firestore listener drops on unmount | 482 (shared) | ✅ PASS |

### Cross-Cutting Requirements (4 total)

| REQ | Description | Status |
|---|---|---|
| REQ-FPS-CX-001 | Strict TDD — RED before GREEN per task pair | ✅ PASS (all 13 pairs evidenced in apply-progress) |
| REQ-FPS-CX-002 | No `rxdart` added to `pubspec.yaml` | ✅ PASS (present only as transitive) |
| REQ-FPS-CX-003 | `flutter analyze` 0 issues; `dart format` clean | ✅ PASS (format drift on 2 PR #86 files, not this SDD) |
| REQ-FPS-CX-004 | Consumer widget source NOT modified | ✅ PASS (drop-in name guarantee verified) |

### SCENARIO Coverage

**Expected**: 22 identifiers (473–493 + 491b)  
**Found**: All 22 present in tests across repo, provider, and widget test layers  
**Boundary check**: No contamination from unrelated SDDs

---

## ADR Summary

8 Architectural Decision Records established:

| ADR | Title | Scope |
|---|---|---|
| ADR-FPS-001 | All three converted providers use `StreamProvider.family.autoDispose` | Balances auto-cleanup (critical for high-churn family keys) with drop-in surface |
| ADR-FPS-002 | `publicProfileViewProvider` as `AsyncNotifier.family.autoDispose` with `ref.watch(streamProvider.future)` composition | Riverpod 2 idiomatic pattern; zero rxdart; auto-rebuild on every upstream emission |
| ADR-FPS-003 | Composition uses `ref.watch(streamProvider.future)` inside `build`, not `ref.listen` | `ref.watch` auto-invalidates AsyncNotifier on upstream re-emission; `ref.listen` requires manual state updates |
| ADR-FPS-004 | Drop-in names — `friendshipByPairProvider`, `acceptedFriendsProvider`, `userPublicProfileProvider` unchanged | `ref.watch(provider)` returns `AsyncValue<T>` regardless of FutureProvider/StreamProvider type; zero consumer refactor |
| ADR-FPS-005 | `autoDispose` on all three converted providers | Prevents listener leak in high-churn public-profile browsing (40+ listeners over 20+ profiles without autoDispose) |
| ADR-FPS-006 | Dispose-safe `ProviderScope.containerOf` capture pattern STAYS for `myFriendsFeedProvider` invalidation | `myFriendsFeedProvider` is still a FutureProvider (out of scope); pattern is required when tiles self-dispose mid-callback |
| ADR-FPS-007 | `async*` + `yield*` for auth-gated streams, direct return for non-gated | Auth-gated providers need imperative control flow for conditional short-circuiting; `acceptedFriendsProvider` has no auth gate per existing FutureProvider |
| ADR-FPS-008 | Orphan deletion of `pendingRequestsProvider` bundled in this SDD | Zero consumers; safe cleanup; consolidates file-touch to one PR |

---

## Smoke Validation Reference

User confirmed smoke on 2026-05-26:
- ✅ Single-device regression: GREEN
- ✅ Cross-device test: `userPublicProfiles.displayName` mutated via Firebase Console while screen open → live update without restart observed
- ✅ `friendships.status` toggle test: observed correctly via `friendshipByPairProvider` stream
- ✅ Cross-device staleness gap (ADR-FRI-013 root cause) confirmed CLOSED end-to-end
- ✅ Composite index `friendships(members, status)` confirmed present in `treino-dev` — no `failed-precondition` thrown

---

## Deviations (Pre-Flagged & Intentional)

### Deviation 1 — T22 Test Scope Expansion

**Status**: Documented in apply-progress §"Existing Test Mock Update".

Converting `userPublicProfileProvider` to `StreamProvider` required updating test file overrides from `Future.value(...)` to `Stream.value(...)` across **14 total test files** (1 planned in T22 + 13 unplanned due to scope of a type-level change). All 14 are under `test/`, zero under `lib/`. SCENARIO-484 (drop-in verify) confirms consumers still work unchanged with `.valueOrNull` pattern. Zero production code scope violation — correct consequence of a provider type change.

### Deviation 2 — `publicProfileViewProvider` Override Pattern

**Status**: Documented in apply-progress and verify-report.

`test/features/feed/presentation/public_profile_screen_test.dart` uses `_StubPublicProfileViewNotifier extends PublicProfileViewNotifier` as the override subclass. This is the idiomatic Riverpod pattern for `AsyncNotifierProvider` in tests — `overrideWith` requires a concrete subclass, not a bare lambda. Code verified: `_StubPublicProfileViewNotifier` exists only in the test file, not in production code.

### Deviation 3 — Side fix in `trainer_advanced_filter_chips.dart`

**Status**: Documented in verify-report §"Deviation 3".

Commit `c57f282` (`fix(coach): add curly braces to single-line if per lint rule; pre-existing issue surfaced by dart format`) is present in the squash history. The fix applies to `lib/features/coach/presentation/widgets/trainer_advanced_filter_chips.dart` — a coach-feature file, not part of this SDD's feed/profile scope. The diff shows only brace formatting and a minor chained method de-wrap. Zero behavioral change. This is a pre-existing lint violation surfaced during the gate phase of the SDD and fixed as a sidecar because `dart format` runs in context of the entire codebase.

---

## Out-of-Scope Sanity Guards

All verified (zero violations):

| Guard | Status | Evidence |
|---|---|---|
| `firestore.rules` untouched | PASS | No entry in `git show 0f1a153 --stat` |
| `firestore.indexes.json` untouched | PASS | No entry in diff; composite index `friendships(members, status)` exists in live Firebase (inverse audit in design §7.2) |
| `myFriendsFeedProvider` still a `FutureProvider` | PASS | `rg "myFriendsFeedProvider = FutureProvider" lib/` confirms — not converted |
| `myFriendsFeedProvider` invalidation preserved (3 paths) | PASS | All 3 call sites retain `ref.invalidate(myFriendsFeedProvider)` or `container.invalidate(myFriendsFeedProvider)` |
| `ProviderScope.containerOf` dispose-safe pattern preserved | PASS | Pattern present in `friend_request_inbox_tile.dart` for both `_onAceptar` and `_onRechazar` |
| `pendingRequestsStreamProvider` + `pendingRequestCountProvider` from inbox SDD untouched | PASS | Still present in `friendship_providers.dart`; `rg` confirms |
| `rxdart` not added as direct dependency | PASS | `rg "rxdart" pubspec.yaml` returns empty |
| `pendingRequestsProvider` absent from production | PASS | `rg "pendingRequestsProvider" lib/` returns only tombstone comments — no imports remain |

---

## Tasks Completion Summary

### Phase 1–4 (Repository + Leaf StreamProviders, T01–T15): All ✅ Complete

| Phase | Tasks | Scope |
|---|---|---|
| Repository stream methods | T01–T07 | 3 repo methods, 8 new unit tests |
| Leaf StreamProviders | T08–T15 | 3 provider conversions + AsyncNotifier composition, 14 new tests |

### Phase 5–6 (Orphan Deletion + Invalidation Cleanup + Quality Gates, T16–T26): All ✅ Complete

| Phase | Tasks | Scope |
|---|---|---|
| Orphan deletion + invalidation cleanup | T16–T21 | Symbol deletion, 8 obsolete invalidate calls removed, 3 tests added |
| Existing test mock update | T22 | 14 test file overrides updated (Future.value → Stream.value) |
| Quality gates + verify | T23–T26 | analyze/format/test gates + manual verify checklist |

**Test summary**: 25 new tests; baseline 1187 → final 1212 (+25); all pass; 0 regressions.  
**Total tasks**: 26 / 26 complete.

---

## Verification Status

**Verify Report Result**: PASS-WITH-DEVIATIONS
- **0 CRITICAL** issues
- **1 WARNING** (format drift on 2 PR #86 files — not this SDD)
- **3 SUGGESTIONS** (post-archive actions)

All findings align with pre-flagged deviations; zero new surprises.

---

## Follow-Ups (Explicit & Carry-Forward)

### Implied by cross-device staleness closure

This SDD closes the explicitly deferred follow-up from `feed-friend-requests-inbox`. The cross-device gap is NOW CLOSED: User B's mutations to friendship status, displayName, followers/following counts, etc., propagate to User A's app live without restart (tested in smoke 2026-05-26).

### Format drift cleanup (priority: LOW)

Format drift on 2 files from PR #86 (Coach Hub bootstrap):
- `lib/features/coach_hub/presentation/coach_hub_dashboard_screen.dart`
- `lib/firebase_options.dart`

**Action**: Standalone `chore(format)` commit on main (same pattern as `cea7f2c`). Not blocking; low priority. Recommend rolling into next branch to keep main clean.

### Composite index audit (priority: LOW, FYI only)

`firestore.indexes.json` does not currently declare the composite index `friendships(members arrayContains, status ascending)`. The index exists in the live Firebase project (proven by the inbox SDD's working `.get()` query and this SDD's working `.snapshots()` query). Separate audit PR recommended to sync the manifest with the live state, but is NOT a blocker for production use.

### Lessons promotion (COMPLETED OUT-OF-BAND)

Two Riverpod patterns discovered during this SDD were promoted to the global skill at `~/.claude/skills/sdd-design/SKILL.md` OUTSIDE the PR (no file change in the repo):

1. **Downstream invalidation cascade in StreamProvider conversions**: When converting `FutureProvider` to `StreamProvider`, all test `overrideWith` lambdas in consumer test files must return `Stream` not `Future`. Scope is wider than the direct test file — affects every test that mocks the converted provider.
2. **Dispose-safe `ProviderContainer` capture pattern**: Use `ProviderScope.containerOf(context, listen: false)` before any `async` gap in widgets that use `container.invalidate` in callbacks. Prevents stale widget references on rapid navigation.

---

## Artifacts Created/Modified

### New files created

- `lib/features/feed/data/friendship_repository.dart` methods: `watchByPair`, `watchAcceptedFriendsOf`
- `lib/features/profile/data/user_public_profile_repository.dart` method: `watch`
- `test/features/feed/application/stream_providers_test.dart` — provider conversions + AsyncNotifier composition tests (14 tests)
- `test/features/feed/presentation/widgets/public_profile_follow_button_invalidation_test.dart` — invalidation guards (2 tests)

### Files modified

- `lib/features/feed/application/friendship_providers.dart` — Converted `acceptedFriendsProvider` to `StreamProvider.family.autoDispose`; deleted `pendingRequestsProvider` orphan
- `lib/features/feed/application/public_profile_providers.dart` — Converted `friendshipByPairProvider` to `StreamProvider.family.autoDispose`; rewrote `publicProfileViewProvider` as `AsyncNotifier.family.autoDispose`
- `lib/features/profile/application/user_public_profile_providers.dart` — Converted `userPublicProfileProvider` to `StreamProvider.family.autoDispose`
- `lib/features/feed/presentation/widgets/public_profile_follow_button.dart` — Removed `invalidatePair()` + 5 obsolete `ref.invalidate` calls; preserved `myFriendsFeedProvider` invalidations
- `lib/features/feed/presentation/widgets/friend_request_inbox_tile.dart` — Removed 3 obsolete `container.invalidate` calls; preserved `myFriendsFeedProvider` invalidation + dispose-safe capture pattern
- 14 test files — Updated provider overrides from `Future.value(...)` to `Stream.value(...)` (T22 refactor)

### NOT touched (sanity guards)

- `firestore.rules`, `firestore.indexes.json`, `pubspec.yaml`
- `myFriendsFeedProvider`, `pendingRequestsStreamProvider`, `pendingRequestCountProvider`
- Any UI files beyond invalidation cleanup

---

## Lessons Learned (Widely Applicable)

Beyond the SKILL.md promotions, these insights transfer to future work:

1. **Stream-first provider pattern for cross-device liveness**: When a feature requires live propagation of mutations across devices (e.g., social graphs), `StreamProvider.family.autoDispose` is the canonical Riverpod 2 pattern. It eliminates the invalidation debt that `FutureProvider + explicit ref.invalidate` requires.

2. **AsyncNotifier composition for view-model aggregation**: Composing multiple upstream streams via `ref.watch(streamProvider.future)` inside an AsyncNotifier `build` is idiomatic and zero-dependency. No rxdart needed; Riverpod's reactivity engine handles re-building on every upstream emission.

3. **autoDispose is critical for high-churn family keys**: Public profile browsing hits many `(viewerUid, targetUid)` pairs in a session. Without `autoDispose`, each visited pair leaves a permanent Firestore listener. With `autoDispose`, listeners drop on unmount — measurable memory and read-cost improvement.

4. **Drop-in naming reduces consumer surface churn**: Keeping existing provider names when converting `FutureProvider` → `StreamProvider` means zero widget refactor. `ref.watch(provider)` returns `AsyncValue<T>` either way.

5. **Dispose-safe `ProviderContainer` capture is universal for async callbacks**: Any `ConsumerStatefulWidget` tap handler that performs `async` operations and needs to invalidate providers MUST capture `ProviderScope.containerOf(context, listen: false)` BEFORE the `await`. If the widget is removed from the tree during the await, the `WidgetRef` becomes stale and `ref.invalidate()` silently fails.

6. **Test override patterns differ by provider type**: `StreamProvider` overrides require `overrideWith((ref) => Stream.value(...))` not `Future.value(...)`. For `AsyncNotifierProvider`, `overrideWith` requires a concrete subclass (not a bare lambda). These patterns are reusable across the codebase — document them once, copy forward.

7. **Composite index gaps in `firestore.indexes.json` are safe if the live Firebase project has the index**: The manifest is aspirational; the truth is live state. Smoke testing confirms whether queries work; separate audit PR can sync the manifest later without blocking functionality.

---

## Sign-Off

**Archive Status**: ✅ COMPLETE  
**Change**: `feed-providers-stream-conversion` (Fase 3 Etapa 6 follow-up)  
**PR**: #87, squash-merged to `main` at `0f1a153` on 2026-05-26  
**Owner**: Dev C  
**Archived by**: SDD archive phase executor  
**Date**: 2026-05-26

All 10 functional REQs + 4 cross-cutting REQs delivered and tested. All 22 SCENARIO identifiers passing. TDD discipline maintained. Quality gates green. Verify-report PASS-WITH-DEVIATIONS; all deviations pre-flagged and validated as intentional. Change is production-ready.

**Impact**: Cross-device staleness gap (ADR-FRI-013) now fully closed. User A's app reflects User B's mutations (friendship status, profile edits, accepted friends list changes) live without restart or manual invalidation, within Firestore snapshot latency (~1-2s).

**Next steps for team**:
1. Merge the archive-report from openspec/changes/archive to main (already done via the branch commit).
2. Update `docs/roadmap.md` to note Fase 3 sub-phase follow-up closure (this SDD).
3. Optional: run standalone `chore(format)` commit to resolve format drift in 2 unrelated files from PR #86.
4. Optional: audit `firestore.indexes.json` against live Firestore state in a separate PR.

---

**SDD cycle complete. Ready for next phase.**
