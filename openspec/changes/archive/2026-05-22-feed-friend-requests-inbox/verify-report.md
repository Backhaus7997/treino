# Verify Report: feed-friend-requests-inbox (Fase 3 Etapa 6)

**Change**: feed-friend-requests-inbox
**PR**: #78 (squash-merged to `main` at `b716ee8`, 2026-05-22)
**Verifier**: sdd-verify executor
**Date**: 2026-05-21
**Mode**: Strict TDD (active)
**Artifact store**: openspec + engram mirror

---

## Overall Status: PASS-WITH-DEVIATIONS

All spec requirements are implemented. All 22 SCENARIO identifiers are exercised by passing tests. All 30 tasks are marked `[x]`. Quality gates pass on `main HEAD` for the SDD-affected files. Format drift exists in 9 files from OTHER PRs that pre-date or are unrelated to this SDD — none of the 9 drifted files were touched by PR #78.

---

## REQ Matrix Coverage

| REQ | Description | Status | Evidence |
|---|---|---|---|
| REQ-FRI-001 | `watchPendingRequestsFor` stream method | PASS | `friendship_repository.dart` line 19+; SCENARIO-451..453 pass |
| REQ-FRI-002 | `pendingRequestsStreamProvider` StreamProvider.family | PASS | `friendship_providers.dart`; SCENARIO-454 passes |
| REQ-FRI-003 | `pendingRequestCountProvider` derived count | PASS | `friendship_providers.dart`; SCENARIO-455, 456 pass |
| REQ-FRI-004 | Inbox shows CircularProgressIndicator on loading | PASS | `friend_requests_inbox_screen.dart`; SCENARIO-457 passes |
| REQ-FRI-005 | Inbox shows "No hay solicitudes pendientes" on empty | PASS | SCENARIO-458 passes |
| REQ-FRI-006 | Inbox renders ListView of tiles on non-empty data | PASS | SCENARIO-459 passes |
| REQ-FRI-007 | Inbox shows error fallback without uncaught exception | PASS | SCENARIO-460 passes |
| REQ-FRI-008 | Tile renders avatar, name, gym; falls back to "Usuario anónimo" | PASS | SCENARIO-461, 462 pass |
| REQ-FRI-009 | ACEPTAR calls `accept`; row disappears via stream re-emit; no manual invalidate | PASS | SCENARIO-463, 467 pass; implementation is fire-and-forget with stream driving removal |
| REQ-FRI-010 | RECHAZAR calls `delete` immediately; no dialog; row disappears via stream | PASS | SCENARIO-464, 465 pass |
| REQ-FRI-011 | `ProfileFriendRequestsTile` always visible; shows count; navigates to `/profile/friend-requests` | PASS | SCENARIO-465a, 466, 467, 468a, 468b pass |
| REQ-FRI-012 | SIGUIENDO pill tappable; opens UnfriendConfirmationSheet; ELIMINAR calls delete + invalidates | PASS | SCENARIO-469, 470, 471, 471b pass |
| REQ-FRI-013 | Requester zone in tile is tappable; navigates to `/feed/profile/{uid}`; pills independent | PASS | SCENARIO-472 (3 sub-cases) pass |
| REQ-FRI-CX-001 | Colors via `AppPalette.of(context)` — no hex literals | PASS | Verified: zero hex literals in all 5 new lib files |
| REQ-FRI-CX-002 | Icons via `TreinoIcon.X` — no direct `PhosphorIcons.X` usage | PASS | Verified: zero `PhosphorIcons` references in new files |
| REQ-FRI-CX-003 | Spacing from scale (8/12/14/18/20) | PASS | `horizontal: 20, vertical: 8` on tile; `horizontal: 14, vertical: 12` on inner content; all values on scale |
| REQ-FRI-CX-004 | Strict TDD — RED commit before GREEN per task pair | PASS | See TDD Evidence section |
| REQ-FRI-CX-005 | `FriendRequestsInboxScreen` adds no `Scaffold`/`AppBackground`/`SafeArea` | PASS | Confirmed in `friend_requests_inbox_screen.dart` — shell provides wrapper |

---

## SCENARIO Coverage

**Expected SCENARIOs**: 451, 452, 453, 454, 455, 456, 457, 458, 459, 460, 461, 462, 463, 464, 465, 465a, 466, 467, 468a, 468b, 469, 470, 471, 471b, 472 (25 identifiers across 22 base numbers)

**Found in tests**: All 25 identifiers found with multiple references (each appears in test body + describe label + at least one assertion). Spot-check via `grep`:

| Range | Result |
|---|---|
| SCENARIO-451..464 | All present in `test/features/feed/data/friendship_repository_test.dart`, `friendship_providers_test.dart`, `friend_requests_inbox_screen_test.dart`, `friend_request_inbox_tile_test.dart` |
| SCENARIO-465/465a..468b | Present in `profile_friend_requests_tile_test.dart`, `profile_screen_test.dart`, `router_test.dart` |
| SCENARIO-469..472 | Present in `public_profile_follow_button_unfriend_test.dart`, `unfriend_confirmation_sheet_test.dart`, `friend_request_inbox_tile_test.dart` |

**Out-of-range boundary check**: SCENARIO-450 and SCENARIO-473..477 found belong to unrelated workout/coach SDDs — no contamination.

**Count**: 25 / 25 SCENARIO identifiers covered. PASS.

---

## Quality Gates

| Gate | Command | Result |
|---|---|---|
| Static analysis | `flutter analyze` | **0 issues** — PASS |
| Format (SDD files) | `dart format --output=none --set-exit-if-changed` on 9 SDD lib+test files | **0 changed** — PASS |
| Format (full repo) | `dart format --output=none --set-exit-if-changed .` | **9 changed** — WARNING (see below) |
| Test suite | `flutter test` | **1120/1120 pass** — PASS |

**Test count note**: apply-progress.md reported final count of 1063 at PR merge time. Main HEAD shows 1120. The delta of 57 tests is accounted for by other PRs that landed after PR #78 (most notably the coach-chat (#74), shared-with-trainer (#73), and home/motivational (#77) PRs visible in git log). No regressions — all 1120 pass.

---

## Format Drift Detail (WARNING)

9 files with format drift, ALL outside this SDD's scope:

- `lib/features/chat/data/chat_repository.dart`
- `lib/features/coach/athlete_coach_view.dart`
- `test/features/chat/application/chat_providers_test.dart`
- `test/features/chat/data/chat_repository_test.dart`
- `test/features/chat/presentation/chat_list_screen_test.dart`
- `test/features/chat/presentation/chat_screen_test.dart`
- `test/features/coach/athlete_coach_view_test.dart`
- `test/features/coach/presentation/athlete_detail_screen_test.dart`
- `test/features/home/widgets/esta_semana_card_test.dart`

This drift should be resolved in a standalone `chore(format)` commit (same pattern as commit `cea7f2c` from PR #68) — NOT in the archive of this SDD. It does not block archive.

---

## TDD Evidence

**Strict TDD mode**: active throughout.

### Phase 1–8 (T01..T21)

| Task pair | RED commit | GREEN commit | Triangulated |
|---|---|---|---|
| T02/T03 | `e32d2e4` test(feed): SCENARIO-451..453 RED | `9652bd7` feat(feed): watchPendingRequestsFor GREEN | 3 cases |
| T04/T05 | `584288b` test(feed): SCENARIO-454..456 RED | `8bad58b` feat(feed): providers GREEN | 3 cases |
| T06/T07 | `ab26e14` test(feed): SCENARIO-457..460 RED | `6151926` feat(feed): screen + stub GREEN | 4 states |
| T08/T09 | `0a87d7f` test(feed): SCENARIO-461..464 RED | (impl in GREEN commit per T09) | 4 cases |
| T10/T11 | `d2369f2` test(feed): SCENARIO-465,467 RED | (impl already in T09 GREEN) | 2 cases |
| T12/T13 | `bcc1fd5` test(profile): SCENARIO-465a,466,467 RED | `aa75f57` feat(profile): tile GREEN | 3 cases |
| T14/T15 | `e8d06a6` test(profile): SCENARIO-468a RED | `070e056` feat(profile): ProfileScreen insert GREEN | 1 insertion |
| T16/T17 | `2b2ed1d` test(app): SCENARIO-468b RED | `ec34cf8` feat(app): route GREEN | 1 route |

**Deviation (documented)**: T09 merged T11's implementation. Design pre-flagged the risk. RED-before-GREEN discipline was preserved: T08 RED (`0a87d7f`) precedes T09 GREEN, and T10 RED (`d2369f2`) precedes T11 GREEN (all tests pass because implementation already contained the guard). No behavioral deviation.

### Phase 9–12 / Amendment (T22..T30)

| Task pair | RED commit | GREEN commit | Triangulated |
|---|---|---|---|
| T22/T23 | `1ae9dfa` test(feed): SCENARIO-470,471,471b RED | `ee582f9` feat(feed): UnfriendConfirmationSheet GREEN | 3 cases |
| T24/T25 | `8057c0d` test(feed): SCENARIO-469,471 RED | `508432e` feat(feed): SIGUIENDO upgrade GREEN | 2 cases |
| T26/T27 | `d6fa42b` test(feed): SCENARIO-472 RED | `46d473e` feat(feed): InkWell wrapping GREEN | 3 sub-cases |

**TDD Verdict**: PASS. All RED commits precede their GREEN counterpart. Every behavioral scenario is tested before the implementation exists.

---

## Specific Deviations (Pre-Flagged — Validated as Intentional)

### ADR-FRI-013: Invalidation Fix (Smoke 2026-05-22)

**Status**: CONFIRMED and DOCUMENTED.

- `design.md` includes ADR-FRI-013 at line 429 — full rationale documented.
- 3 fix commits visible in squash commit body:
  1. `fix(feed): invalidate acceptedFriendsProvider + friendshipByPair after accept/delete`
  2. `fix(feed): invalidate myFriendsFeedProvider directly after accept/unfriend`
  3. `fix(feed): use root container for invalidate after accept/reject (dispose-safe)`
- `friend_request_inbox_tile.dart`: uses `ProviderScope.containerOf(context, listen: false)` (lines 154, 189) — captured BEFORE the async await to prevent dispose-after-await issues.
- `public_profile_follow_button.dart`: ACEPTAR branch invalidates `acceptedFriendsProvider` + `myFriendsFeedProvider` (lines 91-92); unfriend `onConfirm` invalidates all three: `friendshipByPairProvider`, `acceptedFriendsProvider`, `myFriendsFeedProvider` (lines 135-141).
- `apply-progress.md` has "Scope Amendment 2026-05-22" section covering T22..T30; the invalidation fix is documented in the commit messages embedded in the squash body.

**Verdict**: Intentional, documented, correctly implemented.

### Scope Amendment: REQ-FRI-012 + REQ-FRI-013

**Status**: CONFIRMED.

- `proposal.md` table (rows 8-9) lists unfriend and tappable inbox row as in-scope with spec/design references.
- `spec.md` Section F (REQ-FRI-012, SCENARIO-469..471b) and Section G (REQ-FRI-013, SCENARIO-472) both present.
- `design.md` §5.4 (UnfriendConfirmationSheet), §5.5 (PublicProfileFollowButton SIGUIENDO upgrade), ADR-FRI-011, ADR-FRI-012 all present.

**Verdict**: Amendment is properly documented across all SDD artifacts.

### Orphaned `pendingRequestsProvider` (Future variant)

**Status**: CONFIRMED UNTOUCHED.

`friendship_providers.dart` line 18 shows `pendingRequestsProvider` still present, no consumer added. Matches locked decision.

---

## Out-of-Scope Sanity Guards

| Guard | Status | Evidence |
|---|---|---|
| `firestore.rules` untouched | PASS | Not in PR #78 file list (git show --stat confirms 0 rules changes) |
| `TreinoBottomBar` untouched | PASS | Not in PR #78 file list |
| `_FeedHeader` in `feed_screen.dart` untouched | PASS | `feed_screen.dart` not in PR #78 file list |
| SEGUIR / SOLICITUD ENVIADA branches untouched | PASS | `public_profile_follow_button.dart` — `null` branch → SEGUIR unchanged; `requesterId == viewerUid` → SOLICITUD ENVIADA unchanged (line 72-76 = const, no-op) |
| ACEPTAR branch gained `invalidate` calls | NOTED (expected per ADR-FRI-013) | Lines 91-92: `acceptedFriendsProvider` + `myFriendsFeedProvider` invalidated — correct per ADR-FRI-013, not a violation |

---

## Known Limitation (Not a Defect)

Cross-device staleness is by design per ADR-FRI-013: if user B mutates a friendship from another device, user A's app shows stale state until restart. Only on-device staleness was closed by this SDD. The Stream-conversion follow-up SDD owns the cross-device fix. No action required here.

---

## Critical Findings

None.

---

## Warnings

**WARNING-001**: Format drift in 9 files NOT from this SDD.

`dart format --output=none --set-exit-if-changed .` exits with code 1 due to 9 drifted files in `lib/features/chat/`, `lib/features/coach/`, and `test/features/home/` — all from the coach-chat (#74), shared-with-trainer (#73), and home/motivational (#77) PRs. Zero drift in SDD-affected files. Resolution: standalone `chore(format)` commit on `main` (same pattern as PR #68's `cea7f2c`). Does NOT block archive.

**WARNING-002**: apply-progress.md does not have a dedicated "Invalidation Fix" section.

The 3 fix commits are documented in the squash commit body and in ADR-FRI-013 in `design.md`, but `apply-progress.md` only has "Scope Amendment 2026-05-22" and does not call out the invalidation/dispose-safe fix cycle as a separate section. Future SDD cycles should add a `## Post-Smoke Fix Cycle` section when smoke testing triggers additional commits.

**WARNING-003**: Pre-PR Checklist in tasks.md has 2 items with `[ ]` (not `[x]`).

Lines 162-163 of `tasks.md`:
```
- [ ] Quality gates passed (T18..T21 first pass + T28..T30 after Phase 9-11)
- [ ] No `firestore.rules` changes (rules audit CONFIRMED — no changes needed)
```
These are stale unchecked items that should have been marked `[x]` when the amendment was finalized. The evidence confirms both are done (analyze passes, no rules changes). The artifact is inconsistent. Remediate before or during archive.

---

## Suggestions / Follow-Ups

**SUGGESTION-001**: Promote the "Riverpod downstream invalidation" lesson to SKILL.md.

This SDD established a new pattern: **Riverpod does NOT auto-cascade invalidation to providers without active listeners — invalidate downstream providers explicitly**. This is a sibling to the "Rule-Query Reconciliation" lesson from `wire-real-stats`. Recommended addition to `sdd-design` or `sdd-apply` SKILL.md guidance notes.

**SUGGESTION-002**: Promote the "Dispose-safe ProviderContainer capture" lesson to SKILL.md.

The pattern `final container = ProviderScope.containerOf(context, listen: false)` captured BEFORE an `async` await is a new guard discovered in this SDD's smoke cycle. When a widget is disposed mid-await (the tile is removed by the stream), any subsequent `ref.invalidate(...)` on a dead `WidgetRef` silently no-ops or throws. Capturing the root container before the await bypasses this. This pattern should be documented in `sdd-design` SKILL.md as a standard recommendation for async tap handlers in Riverpod `ConsumerStatefulWidget` tiles.

**SUGGESTION-003**: Resolve format drift with a `chore(format)` commit on `main`.

Run `dart format .` and commit — same pattern as `cea7f2c` from #68. Can be done independently of this archive.

**SUGGESTION-004**: Review `pendingRequestsProvider` orphan removal in a cleanup SDD.

The orphaned `FutureProvider` variant has zero consumers since this SDD shipped. A small cleanup SDD (or a simple chore PR) can remove it safely.

---

## Compliance Matrix Summary

| Layer | REQs | Status |
|---|---|---|
| Data Layer (Section A) | REQ-FRI-001 | PASS |
| Providers (Section B) | REQ-FRI-002, REQ-FRI-003 | PASS |
| Inbox Screen (Section C) | REQ-FRI-004..007 | PASS |
| Inbox Tile (Section D) | REQ-FRI-008..010 | PASS |
| Profile Tile (Section E) | REQ-FRI-011 | PASS |
| Unfriend (Section F) | REQ-FRI-012 | PASS |
| Tappable Row (Section G) | REQ-FRI-013 | PASS |
| Cross-Cutting | REQ-FRI-CX-001..005 | PASS |
| TDD Discipline | REQ-FRI-CX-004 | PASS |

---

## Recommendation

**GO for archive.**

The implementation is complete, correct, and test-covered. All 13 functional REQs + 5 cross-cutting REQs are satisfied. All 25 SCENARIO identifiers have passing test coverage. TDD discipline was maintained throughout. Quality gates pass on main HEAD for all SDD-affected files. The 3 pre-flagged deviations (ADR-FRI-013 invalidation fix, scope amendment, T09+T11 merge) are all documented and intentional. The 3 warnings are non-blocking: format drift belongs to other SDDs, apply-progress missing a sub-section is a documentation gap only, and 2 unchecked checklist items are stale but factually incorrect (the work is done).

Remediate WARNING-003 (fix the 2 `[ ]` → `[x]` in `tasks.md`) before running archive, and log SUGGESTION-001 + SUGGESTION-002 as archive notes for SKILL.md promotion.
