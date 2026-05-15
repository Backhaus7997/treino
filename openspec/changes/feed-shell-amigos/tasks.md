# Tasks — feed-shell-amigos

**Change**: `feed-shell-amigos`
**Fase / Etapa**: Fase 3 · Etapa 2
**Artifact store**: `openspec`
**TDD**: Strict — every code-touching task is a RED test → GREEN implementation pair.
**Delivery**: Single PR (no chaining). Production LOC well within 400-line budget.
**Commit style**: Conventional Commits (no AI attribution).

---

## Task list

---

### TASK-001 — Add `TreinoIcon.dotsThree` and `TreinoIcon.verified` constants

**Strict TDD**: No (mechanical addition — no behavior to test; SCENARIO-188/189 are validated as part of TASK-007a which pumps `TreinoIcon.dotsThree` directly).

**Files**:
- `lib/core/widgets/treino_icon.dart`

**REQ refs**: REQ-FEED-ICON-001 (SCENARIO-188, SCENARIO-189)

**Done when**: `flutter analyze` reports zero errors referencing `TreinoIcon.dotsThree` or `TreinoIcon.verified` after the addition.

**Commit**: `feat(core/icon): add TreinoIcon.dotsThree and verified constants`

**Notes**: Add under a `// Feed / social` comment block after the existing action constants. No test file needed — the constants are compile-time validated. `dotsThree` → `PhosphorIconsRegular.dotsThreeVertical`; `verified` → `PhosphorIconsFill.sealCheck`.

---

### TASK-002a — RED: Update `post_test.dart` with SCENARIO-133..137

**Strict TDD**: Yes — RED (compile error until TASK-002b is done).

**Files**:
- `test/features/feed/domain/post_test.dart`

**REQ refs**: REQ-FEED-POST-001 (SCENARIO-133, SCENARIO-134, SCENARIO-135, SCENARIO-136, SCENARIO-137)

**Done when**: `flutter test test/features/feed/domain/post_test.dart` produces compile errors referencing `authorDisplayName` as a missing required named parameter on 3 existing fixtures, and the 5 new scenario tests are written and fail.

**Commit**: `test(feed/post): add SCENARIO-133..137 — author fields roundtrip + resilience`

**Notes**:
- Update the 3 existing `Post(...)` fixture calls to include `authorDisplayName: 'Test'` and `authorAvatarUrl: null` — they'll compile only after TASK-002b.
- Add 5 new tests: roundtrip (SCENARIO-133), missing `authorDisplayName` → `'Anónimo'` (SCENARIO-134), `null` avatar in map (SCENARIO-135), missing avatar key (SCENARIO-136), compile-gate comment (SCENARIO-137 — verifiable via `flutter analyze` after 002b).
- This commit intentionally does NOT compile green. That is the TDD red state.

---

### TASK-002b — GREEN: Amend `Post` model + run `build_runner` + fix all fixture sites

**Strict TDD**: Yes — GREEN for TASK-002a.

**Files**:
- `lib/features/feed/domain/post.dart`
- `lib/features/feed/domain/post.freezed.dart` (generated)
- `lib/features/feed/domain/post.g.dart` (generated)
- `test/features/feed/data/post_repository_test.dart` (fixture update if it constructs `Post(...)`)
- `test/features/feed/application/post_providers_test.dart` (fixture update if it constructs `Post(...)`)
- `scripts/seed_posts.js`

**REQ refs**: REQ-FEED-POST-001 (SCENARIO-133..137), REQ-FEED-SEED-001

**Done when**: `flutter test test/features/feed/domain/post_test.dart` green; `flutter analyze` reports 0 issues; `post.freezed.dart` + `post.g.dart` are regenerated.

**Commit**: `feat(feed/post): denormalize authorDisplayName + authorAvatarUrl on Post`

**Notes**:
- Add `required String authorDisplayName` and `required String? authorAvatarUrl` to the `Post` freezed class in the order specified in design §7.1.
- Override `Post.fromJson` with the manual map-pre-processing approach (design §7.2) — do NOT use `@Default`.
- Add the one-line denormalization comment above the two new fields (REQ-FEED-POST-001).
- Run `dart run build_runner build --delete-conflicting-outputs` after editing `post.dart`.
- Run `flutter analyze` to find all remaining `Post(...)` fixture call sites missing `authorDisplayName` and fix them in this same commit.
- Update `scripts/seed_posts.js` in this same commit (design §7.3): add `authorDisplayName` (always) + `authorAvatarUrl` (some null, some URLs) to every seed post object.
- **Depends on**: TASK-002a written first.

---

### TASK-003a — RED: Write `feed_screen_providers_test.dart`

**Strict TDD**: Yes — RED.

**Files**:
- `test/features/feed/application/feed_screen_providers_test.dart` (new)

**REQ refs**: REQ-FEED-ENUM-001 (SCENARIO-138, SCENARIO-139), REQ-FEED-PROVIDER-001 (SCENARIO-140, SCENARIO-141, SCENARIO-142, SCENARIO-143)

**Done when**: file exists with 6 test cases; `flutter test` fails because `feedSegmentProvider` and `myFriendsFeedProvider` do not exist yet.

**Commit**: `test(feed): add SCENARIO-138..143 — feedSegmentProvider + myFriendsFeedProvider`

**Notes**:
- SCENARIO-138: `ProviderContainer` default state is `FeedSegment.amigos`.
- SCENARIO-139: state update via `.notifier` works.
- SCENARIO-140: happy path — auth + friends + posts chain.
- SCENARIO-141: no friends → empty list, no crash.
- SCENARIO-142: unauthenticated (`auth == null`) → empty list.
- SCENARIO-143: structural — `myFriendsFeedProvider` is a plain `FutureProvider`, not a family (no `List<String>` cache-key issue). Assert via `is FutureProvider<List<Post>>`.
- Use `MockUser` from `mocktail`; override `authStateChangesProvider`, `acceptedFriendsProvider`, `feedForFriendsProvider` (see design §8.2).
- **Depends on**: TASK-002b (Post model must have `authorDisplayName` for fixture construction).

---

### TASK-003b — GREEN: Create `FeedSegment` enum + `feed_screen_providers.dart`

**Strict TDD**: Yes — GREEN for TASK-003a.

**Files**:
- `lib/features/feed/domain/feed_segment.dart` (new)
- `lib/features/feed/application/feed_screen_providers.dart` (new)

**REQ refs**: REQ-FEED-ENUM-001 (SCENARIO-138, SCENARIO-139), REQ-FEED-PROVIDER-001 (SCENARIO-140..143)

**Done when**: `flutter test test/features/feed/application/feed_screen_providers_test.dart` green.

**Commit**: `feat(feed): add FeedSegment enum + feedSegmentProvider + myFriendsFeedProvider`

**Notes**:
- `feed_segment.dart`: `enum FeedSegment { amigos, gym, public }` (~10 LOC).
- `feed_screen_providers.dart`: `feedSegmentProvider` (StateProvider) + `myFriendsFeedProvider` (FutureProvider) with the exact 3-step composition from design §4.2. Short-circuit on `auth == null` and `friendUids.isEmpty`.
- No other providers go in this file (REQ-FEED-ENUM-001 constraint).
- **Depends on**: TASK-003a written first.

---

### TASK-004a — RED: Write `post_avatar_test.dart`

**Strict TDD**: Yes — RED.

**Files**:
- `test/features/feed/presentation/widgets/post_avatar_test.dart` (new)

**REQ refs**: REQ-FEED-AVATAR-001 (SCENARIO-180), REQ-FEED-AVATAR-002 (SCENARIO-181, SCENARIO-182, SCENARIO-183, SCENARIO-184)

**Done when**: file exists with 5 test cases; `flutter test` fails because `PostAvatar` does not exist.

**Commit**: `test(feed): add SCENARIO-180..184 — PostAvatar CachedNetworkImage + initials fallback`

**Notes**:
- Use `_wrap(widget)` helper (no providers needed).
- SCENARIO-180: URL present → `find.byType(CachedNetworkImage)` finds ≥1, no `Image.network`.
- SCENARIO-181..183: URL null + various displayNames → correct initial character or `'?'`.
- SCENARIO-184: gradient decoration contains `palette.accent` and `palette.highlight`.
- **Depends on**: TASK-002b (Post model available for import context, though PostAvatar takes plain String params).

---

### TASK-004b — GREEN: Create `PostAvatar` widget

**Strict TDD**: Yes — GREEN for TASK-004a.

**Files**:
- `lib/features/feed/presentation/widgets/post_avatar.dart` (new)

**REQ refs**: REQ-FEED-AVATAR-001, REQ-FEED-AVATAR-002

**Done when**: `flutter test test/features/feed/presentation/widgets/post_avatar_test.dart` green.

**Commit**: `feat(feed): add PostAvatar widget with CachedNetworkImage + initial fallback`

**Notes**:
- API: `PostAvatar({ required String authorDisplayName, required String? authorAvatarUrl, double size = 40 })`.
- When URL non-null: `ClipOval` → `CachedNetworkImage` with `_InitialFallback` as `placeholder` and `errorWidget`.
- When URL null: `ClipOval` → `_InitialFallback` directly.
- `_computeInitial`: empty or `'Anónimo'` → `'?'`; else `.characters.first.toUpperCase()`.
- Gradient: `LinearGradient(topLeft → bottomRight, [palette.accent, palette.highlight])`.
- No HEX literals; no `Image.network`.
- **Depends on**: TASK-004a written first.

---

### TASK-005a — RED: Write `feed_empty_state_test.dart`

**Strict TDD**: Yes — RED.

**Files**:
- `test/features/feed/presentation/widgets/feed_empty_state_test.dart` (new)

**REQ refs**: REQ-FEED-EMPTY-001 (SCENARIO-185, SCENARIO-186, SCENARIO-187)

**Done when**: file exists with 3 test cases; `flutter test` fails because `FeedEmptyState` does not exist.

**Commit**: `test(feed): add SCENARIO-185..187 — FeedEmptyState copy + icon + absence`

**Notes**: Use `_wrap(widget)`. No provider overrides needed.

---

### TASK-005b — GREEN: Create `FeedEmptyState` widget

**Strict TDD**: Yes — GREEN for TASK-005a.

**Files**:
- `lib/features/feed/presentation/widgets/feed_empty_state.dart` (new)

**REQ refs**: REQ-FEED-EMPTY-001

**Done when**: `flutter test test/features/feed/presentation/widgets/feed_empty_state_test.dart` green.

**Commit**: `feat(feed): add FeedEmptyState widget`

**Notes**:
- Zero params. `static const _kCopy = 'Aún no hay posts de tus amigos'` (no trailing period, exact match for SCENARIO-185).
- Layout: `Center → Column(mainAxisSize: min)` → `Icon(TreinoIcon.users, size: 48, color: palette.textMuted)` → `SizedBox(height: 12)` → `Text(_kCopy, ...)`.
- No HEX literals.
- **Depends on**: TASK-005a written first.

---

### TASK-006a — RED: Write `feed_segment_pills_test.dart`

**Strict TDD**: Yes — RED.

**Files**:
- `test/features/feed/presentation/widgets/feed_segment_pills_test.dart` (new)

**REQ refs**: REQ-FEED-PILLS-001 (SCENARIO-159), REQ-FEED-PILLS-002 (SCENARIO-160), REQ-FEED-PILLS-003 (SCENARIO-161, SCENARIO-162), REQ-FEED-PILLS-004 (SCENARIO-163, SCENARIO-164, SCENARIO-165)

**Done when**: file exists with 7 test cases; `flutter test` fails because `FeedSegmentPills` does not exist.

**Commit**: `test(feed): add SCENARIO-159..165 — FeedSegmentPills order, style, opacity, tap`

**Notes**:
- Use `_wrapProvider(widget, overrides)` for all tests (widget reads `feedSegmentProvider`).
- SCENARIO-161/162: use `find.ancestor(of: find.text('MI GYM'), matching: find.byType(Opacity))` and assert `opacity == 0.4`.
- SCENARIO-163..165: tap text label, `pumpAndSettle`, then assert `container.read(feedSegmentProvider)` state.
- **Depends on**: TASK-003b (FeedSegment enum and feedSegmentProvider must exist).

---

### TASK-006b — GREEN: Create `FeedSegmentPills` widget

**Strict TDD**: Yes — GREEN for TASK-006a.

**Files**:
- `lib/features/feed/presentation/widgets/feed_segment_pills.dart` (new)

**REQ refs**: REQ-FEED-PILLS-001..004

**Done when**: `flutter test test/features/feed/presentation/widgets/feed_segment_pills_test.dart` green.

**Commit**: `feat(feed): add FeedSegmentPills widget with opacity-disabled gym/public`

**Notes**:
- `FeedSegmentPills` is a `ConsumerWidget` (reads + writes `feedSegmentProvider`).
- Private `_Pill(label, isActive, onTap)` inside the same file. Do NOT import from `LevelFilterPills` — copy the pill visual per ADR-FS-3.
- MI GYM and PÚBLICO: `Opacity(opacity: 0.4, child: _Pill(..., onTap: null))`.
- Pill inter-item gap: `SizedBox(width: 8)`. Pill internal padding: `h:14 v:8`. Radius: `BorderRadius.circular(20)`.
- Wrap the `Row` in `SingleChildScrollView(scrollDirection: horizontal, physics: ClampingScrollPhysics())`.
- **Depends on**: TASK-006a written first.

---

### TASK-007a — RED: Write `post_card_test.dart`

**Strict TDD**: Yes — RED.

**Files**:
- `test/features/feed/presentation/widgets/post_card_test.dart` (new)

**REQ refs**: REQ-FEED-POSTCARD-001 (SCENARIO-166, SCENARIO-167, SCENARIO-168), REQ-FEED-POSTCARD-002 (SCENARIO-169), REQ-FEED-POSTCARD-003 (SCENARIO-170, SCENARIO-171, SCENARIO-172), REQ-FEED-POSTCARD-004 (SCENARIO-173, SCENARIO-174), REQ-FEED-POSTCARD-005 (SCENARIO-175), REQ-FEED-POSTCARD-006 (SCENARIO-176, SCENARIO-177), REQ-FEED-POSTCARD-007 (SCENARIO-178, SCENARIO-179)

**Done when**: file exists with 14 test cases; `flutter test` fails because `PostCard` does not exist.

**Commit**: `test(feed): add SCENARIO-166..179 — PostCard structure, nav, stats, author tap`

**Notes**:
- Use `_wrap` for most tests; `_wrapRouter` only for SCENARIO-171 (chip navigation).
- Define `makePost(...)` factory helper at the top of the file.
- SCENARIO-171: assert `find.text('detail-r1')` after tapping the chip and `pumpAndSettle`.
- SCENARIO-175: inspect the outermost `Container` decoration — `borderRadius`, `color`, and `border` must match.
- SCENARIO-168: use regex `RegExp(r'[Hh]ace\s+\d+\s*h')` to match the relative time string.
- **Depends on**: TASK-002b (Post model), TASK-004b (PostAvatar imported by PostCard).

---

### TASK-007b — GREEN: Create `PostCard` widget

**Strict TDD**: Yes — GREEN for TASK-007a.

**Files**:
- `lib/features/feed/presentation/widgets/post_card.dart` (new)

**REQ refs**: REQ-FEED-POSTCARD-001..007

**Done when**: `flutter test test/features/feed/presentation/widgets/post_card_test.dart` green.

**Commit**: `feat(feed): add PostCard with routine chip and stats stub`

**Notes**:
- API: `PostCard({ required Post post, VoidCallback? onAuthorTap })`.
- Include private `_RoutineTagChip(tag)`, `_relativeTime(DateTime)`, and `_formatMeta(String?, DateTime)` as per design §3.5–3.6 and §8.5 Risk A.
- Overflow `IconButton(icon: Icon(TreinoIcon.dotsThree), onPressed: null)` — stub per REQ-FEED-POSTCARD-006.
- Stats row uses `'— kg'`, `'— min'`, `'— ej.'` with inline comment `// Stub: real stats wired in Fase 4.`
- No HEX literals. No `PhosphorIcons.*` direct usage.
- Author tap: `GestureDetector(onTap: onAuthorTap, behavior: HitTestBehavior.opaque)`.
- **Depends on**: TASK-007a written first, TASK-004b (PostAvatar).

---

### TASK-008a — RED: Write `feed_screen_test.dart`

**Strict TDD**: Yes — RED.

**Files**:
- `test/features/feed/presentation/feed_screen_test.dart` (new)

**REQ refs**: REQ-FEED-SCREEN-001 (SCENARIO-144..149), REQ-FEED-SCREEN-002 (SCENARIO-150..152), REQ-FEED-SCREEN-003 (SCENARIO-153..154), REQ-FEED-SCREEN-004 (SCENARIO-155..156), REQ-FEED-SCREEN-005 (SCENARIO-157..158)

**Done when**: file exists with 15 test cases; `flutter test` fails because `FeedScreen` is still the old placeholder.

**Commit**: `test(feed): add SCENARIO-144..158 — FeedScreen header, pills, states`

**Notes**:
- Use `_wrapProvider` throughout; override `feedSegmentProvider` + `myFriendsFeedProvider` directly (not the chain — see design §8.2 pattern split).
- SCENARIO-147: pump `FeedScreen` in `MaterialApp(home: Scaffold(body: FeedScreen()))`, then assert `find.byType(Scaffold)` finds exactly 1 (the outer wrapper) and `find.byType(AppBackground)` finds 0.
- SCENARIO-155: use `pump()` only (NOT `pumpAndSettle`) to catch the loading state before it settles.
- Loading override: `myFriendsFeedProvider.overrideWith((ref) async { await Completer().future; return []; })`.
- Error override: `myFriendsFeedProvider.overrideWith((ref) => Future.error(Exception('net')))`.
- **Depends on**: TASK-006b (FeedSegmentPills), TASK-007b (PostCard), TASK-005b (FeedEmptyState), TASK-003b (providers).

---

### TASK-008b — GREEN: Rewrite `FeedScreen`

**Strict TDD**: Yes — GREEN for TASK-008a.

**Files**:
- `lib/features/feed/feed_screen.dart`

**REQ refs**: REQ-FEED-SCREEN-001..005

**Done when**: `flutter test test/features/feed/presentation/feed_screen_test.dart` green.

**Commit**: `feat(feed): wire FeedScreen shell with AMIGOS segment functional`

**Notes**:
- Full rewrite of `lib/features/feed/feed_screen.dart`: drops placeholder, becomes `ConsumerWidget`.
- Compose private `_FeedHeader` + `FeedSegmentPills` + `Expanded(child: switch (segment) { ... })`.
- `_FeedHeader`: `Row` with title `'FEED'` (Barlow Condensed 700 28pt) + `IconButton(TreinoIcon.search, onPressed: null)` + `IconButton(TreinoIcon.plus, onPressed: null)`.
- `_AmigosBody`: private `ConsumerWidget` reading `myFriendsFeedProvider` with `.when(data/loading/error)`.
- No `Scaffold`, `AppBackground`, or `SafeArea` introduced (REQ-FEED-SCREEN-001 SCENARIO-147).
- Spacing: outer `Padding(horizontal: 20)`, top `SizedBox(20)`, header→pills `SizedBox(14)`, pills→body `SizedBox(14)`.
- **Depends on**: TASK-008a written first; all widget tasks (004b, 005b, 006b, 007b) and provider task (003b) must be complete.

---

### TASK-009 — Update `seed_posts.js`

**Strict TDD**: No (script update, no Flutter test).

**Files**:
- `scripts/seed_posts.js`

**REQ refs**: REQ-FEED-SEED-001

**Done when**: every post object in the seed script has an `authorDisplayName` string and an `authorAvatarUrl` (either a URL string or `null`). At least 2 posts have non-null avatar URLs and at least 2 have `null` (covering both avatar branches).

**Commit**: `feat(scripts): seed posts with denormalized author fields`

**Notes**:
- This is already partially handled in TASK-002b (same commit per design §10 step 2). If done there, mark this task as merged into TASK-002b and skip the separate commit.
- If the seed script was NOT updated in TASK-002b, do it here. Either way the script must be correct before TASK-010.
- Suggested name/URL mapping: design §7.3.

---

### TASK-010 — Manual: re-run seed against `treino-dev`

**Strict TDD**: No (manual verification step — not a code change).

**Files**: (none)

**REQ refs**: REQ-FEED-SEED-001 (success criterion #13 in proposal)

**Done when**: `node scripts/seed_posts.js` (or equivalent CLI invocation) completes without error against Firestore `treino-dev`; Firestore console shows all seed post documents contain `authorDisplayName` field.

**Notes**:
- Requires the Firebase service account JSON in place from Etapa 1.
- Not a commit — document outcome in apply-progress.
- Run AFTER TASK-009 is committed.

---

### TASK-011 — Quality gates: analyze, format, full test suite

**Strict TDD**: No (gate verification).

**Files**: (none — all files already written)

**REQ refs**: All REQs (blanket gate)

**Done when**:
1. `dart format --set-exit-if-changed .` exits 0 (no formatting drift).
2. `flutter analyze` exits 0 (zero issues).
3. `flutter test` exits 0 — all feed tests green, no regression across the 418 baseline tests. Target: ~476 passing tests (418 baseline + ~58 new/updated).

**Notes**:
- Run in this order: format → analyze → test.
- If any test fails, fix it before marking done. Do not open the PR until this gate is clean.
- Not a commit — document gate result in apply-progress.

---

## Dependency graph

```
TASK-001  (independent)
   │
TASK-002a → TASK-002b ─────────────────────────┐
                │                               │
         TASK-003a → TASK-003b                  │
                │         │                     │
         TASK-006a → TASK-006b                  │
                                 TASK-004a → TASK-004b ─┐
                                 TASK-005a → TASK-005b   │
                                                          │
                         TASK-007a → TASK-007b ──────────┘
                                │
                         TASK-008a → TASK-008b
                                │
                         TASK-009 → TASK-010
                                │
                         TASK-011
```

**Parallelizable pairs** (can be developed concurrently by separate devs/branches, merged in order):
- `TASK-004a/b` (PostAvatar) and `TASK-005a/b` (FeedEmptyState) are independent of each other — both only require TASK-002b.
- `TASK-006a/b` (FeedSegmentPills) is independent of `TASK-004a/b` and `TASK-005a/b`.

**Sequential bottlenecks**:
- TASK-002b must be done before all widget task RED steps — it introduces the required `Post` constructor param that all fixtures depend on.
- TASK-008b (FeedScreen rewrite) is the final integration point; it blocks until TASK-003b, 004b, 005b, 006b, and 007b are all green.

---

## Review Workload Forecast

| Metric | Value |
|---|---|
| Estimated production LOC | ~290 |
| Estimated test LOC | ~1 080 |
| Estimated total diff | ~1 370 LOC across 17 files |
| Files changed | ~17 (6 new lib + 2 modified lib + 2 generated + 7 new test + 2 modified test) |
| 400-line production budget risk | Low (production is ~290 LOC) |
| Chained PRs recommended | No |
| Decision needed before apply | No — proceed to sdd-apply |

> Note: total diff exceeds 400 lines when tests are counted. Per the delivery strategy and proposal §8, the 400-line budget applies to **production code only**. Test LOC are excluded from the PR size gate. Reviewer effort is manageable because the test files mirror the widget structure 1-to-1 and follow established patterns.
