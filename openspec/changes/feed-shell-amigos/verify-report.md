# Verify Report — feed-shell-amigos

**Change**: `feed-shell-amigos`
**Branch**: `feat/feed-shell-amigos` (17 commits on top of main)
**Date**: 2026-05-15
**Verifier**: sdd-verify executor

---

## Summary

- REQs: 18, Pass: 17, Fail: 0 (1 spec-doc stale — code and tests correct)
- Tasks: 21, Done: 17 code tasks + TASK-009 merged into TASK-002b, TASK-010 manual VERIFIED, TASK-011 PARTIAL (analyze green, tests green, **format FAILS**)
- Findings: CRITICAL=1, WARNING=3, SUGGESTION=1
- Ready to ship: **NO** — CRITICAL format gate must pass before merge

---

## Findings

### CRITICAL

**CRIT-01 — dart format gate fails (TASK-011)**

`dart format --output=none --set-exit-if-changed .` exits 1. Eight files have
formatting drift:

- `lib/features/feed/presentation/widgets/feed_segment_pills.dart`
- `lib/features/feed/presentation/widgets/post_avatar.dart`
- `lib/features/feed/presentation/widgets/post_card.dart`
- `test/features/feed/application/feed_screen_providers_test.dart`
- `test/features/feed/domain/post_test.dart`
- `test/features/feed/presentation/feed_screen_test.dart`
- `test/features/feed/presentation/widgets/post_avatar_test.dart`
- `test/features/feed/presentation/widgets/post_card_test.dart`

**Fix**: run `dart format .` and amend or commit the formatting changes before
opening the PR. This is a one-command fix with zero logic risk.

---

### WARNING

**WARN-01 — spec.md REQ-FEED-PILLS-003 stale (opacity deviation not reflected)**

`spec.md` REQ-FEED-PILLS-003 and SCENARIO-161/162 still read "Opacity(0.4)" but
the post-smoke-test decision switched to full opacity (matching the mockup). The
test file (`feed_segment_pills_test.dart`) was updated correctly — tests assert
`findsNothing` for Opacity ancestors and they pass. However, `spec.md` was never
amended. This creates a misleading paper trail where the spec says one thing and
the code + tests say another.

**Fix**: update REQ-FEED-PILLS-003 and SCENARIO-161/162 in `spec.md` to reflect
the final decision ("renders at full opacity; disabled state communicated by
inactive fill color, not opacity"). Low priority but should happen before archiving.

**WARN-02 — SCENARIO-189 (TreinoIcon.verified) has no runtime pump test**

`TreinoIcon.verified` is defined in `treino_icon.dart` and compiles cleanly, but
no test pumps `Icon(TreinoIcon.verified)` as SCENARIO-189 specifies. SCENARIO-188
(`TreinoIcon.dotsThree`) is implicitly covered by SCENARIO-176 in
`post_card_test.dart` (`find.byIcon(TreinoIcon.dotsThree)` finds exactly one
widget). SCENARIO-189 has no analogous coverage because `verified` is not yet used
in any production widget.

The spec maps both scenarios to `test/features/feed/core/treino_icon_test.dart`
which does not exist.

**Impact**: low — the constant is compile-time valid and the spec note for TASK-001
explicitly acknowledges "no test file needed — compile-time validated." Still, the
explicit scenario contract in spec.md is unmet.

**Fix**: either add a minimal `treino_icon_test.dart` with the two pump tests, or
document the deviation in the archive report. Recommend doing it now (5 LOC).

**WARN-03 — authorAvatarUrl declared required String? (stricter than spec intent)**

The spec says `authorAvatarUrl: String?` (nullable, optional). The implementation
declares it `required String? authorAvatarUrl` — callers cannot omit the parameter,
they must explicitly pass `null`. This is technically spec-conformant (the field IS
nullable) but imposes a slightly stricter call site contract than a default-null
param. All fixture files have been updated and all tests pass, so there is no
runtime issue.

This is a documentation-level mismatch only. The design phase chose explicit
`required` to surface the null acknowledgment at every call site, which is a
defensible choice for a social-media model field. No action required, but worth
noting for future Post extension.

---

### SUGGESTION

**SUGG-01 — FeedScreen uses SizedBox(height: 18) between pills and body**

`feed_screen.dart` line 27 uses `SizedBox(height: 18)` between `FeedSegmentPills`
and the `Expanded` body. The design spec (`§8b` / task notes) says `SizedBox(14)`
for both spacings (header→pills and pills→body). The value 18 is in the canonical
spacing set `{8, 12, 14, 18, 20}` so this is not a convention violation, but it
deviates from the design spec's stated 14px. Visual smoke test confirmed acceptable.

---

## Re-run results

| Gate | Result | Notes |
|---|---|---|
| `flutter analyze` | PASS — 0 issues | Clean in 3.4s |
| `flutter test test/features/feed/` | PASS — 88 tests, 0 failures | All SCENARIO-133..189 except 189 (see WARN-02) |
| `flutter test` (full) | PASS — 474 tests, 1 skipped, 0 failures | Baseline preserved + new feed tests |
| `dart format --set-exit-if-changed .` | **FAIL** — 8 files changed | See CRIT-01 |

---

## Scenario coverage matrix

| Scenarios | REQ | Status |
|---|---|---|
| SCENARIO-133..137 | REQ-FEED-POST-001 | PASS |
| SCENARIO-138..139 | REQ-FEED-ENUM-001 | PASS |
| SCENARIO-140..143 | REQ-FEED-PROVIDER-001 | PASS |
| SCENARIO-144..149 | REQ-FEED-SCREEN-001 | PASS |
| SCENARIO-150..152 | REQ-FEED-SCREEN-002 | PASS |
| SCENARIO-153..154 | REQ-FEED-SCREEN-003 | PASS |
| SCENARIO-155..156 | REQ-FEED-SCREEN-004 | PASS |
| SCENARIO-157..158 | REQ-FEED-SCREEN-005 | PASS |
| SCENARIO-159 | REQ-FEED-PILLS-001 | PASS |
| SCENARIO-160 | REQ-FEED-PILLS-002 | PASS |
| SCENARIO-161..162 | REQ-FEED-PILLS-003 | PASS (deviation: full opacity — tests updated, spec.md not) |
| SCENARIO-163..165 | REQ-FEED-PILLS-004 | PASS |
| SCENARIO-166..168 | REQ-FEED-POSTCARD-001 | PASS |
| SCENARIO-169 | REQ-FEED-POSTCARD-002 | PASS |
| SCENARIO-170..172 | REQ-FEED-POSTCARD-003 | PASS |
| SCENARIO-173..174 | REQ-FEED-POSTCARD-004 | PASS |
| SCENARIO-175 | REQ-FEED-POSTCARD-005 | PASS |
| SCENARIO-176..177 | REQ-FEED-POSTCARD-006 | PASS |
| SCENARIO-178..179 | REQ-FEED-POSTCARD-007 | PASS |
| SCENARIO-180 | REQ-FEED-AVATAR-001 | PASS |
| SCENARIO-181..184 | REQ-FEED-AVATAR-002 | PASS |
| SCENARIO-185..187 | REQ-FEED-EMPTY-001 | PASS |
| SCENARIO-188 | REQ-FEED-ICON-001 | PASS (implicit via SCENARIO-176) |
| SCENARIO-189 | REQ-FEED-ICON-001 | WARNING — no runtime pump test |

---

## Task completion

| Task | Status | Notes |
|---|---|---|
| TASK-001 | DONE | `dotsThree` + `verified` in treino_icon.dart |
| TASK-002a | DONE | RED test commit present |
| TASK-002b | DONE | `@Default('Anónimo')` deviation from design's manual fromJson; functional parity confirmed |
| TASK-003a | DONE | RED test commit present |
| TASK-003b | DONE | FeedSegment enum + both providers |
| TASK-004a | DONE | RED test commit present |
| TASK-004b | DONE | PostAvatar widget |
| TASK-005a | DONE | RED test commit present |
| TASK-005b | DONE | FeedEmptyState widget |
| TASK-006a | DONE | RED test commit present |
| TASK-006b | DONE | FeedSegmentPills widget (no Opacity, full opacity — post-smoke fix) |
| TASK-007a | DONE | RED test commit present |
| TASK-007b | DONE | PostCard widget |
| TASK-008a | DONE | RED test commit present |
| TASK-008b | DONE | FeedScreen rewrite |
| TASK-009 | DONE — merged into TASK-002b commit | seed_posts.js has author meta map |
| TASK-010 | MANUAL-VERIFIED | User confirmed smoke test green post firebase deploy |
| TASK-011 | PARTIAL | analyze green, tests green; format FAILS (CRIT-01) |

---

## Scope discipline

Changed files (17 commits, 20 files):

All within expected scope:
- `lib/features/feed/` — 8 files (domain, application, presentation, root screen)
- `lib/core/widgets/treino_icon.dart` — icon constants only
- `lib/features/feed/domain/post.freezed.dart` + `post.g.dart` — codegen regen, cosmetic
- `test/features/feed/` — 7 test files (new + updated)
- `scripts/seed_posts.js` — author meta added

No modifications to:
- `lib/features/profile/` — clean
- `lib/features/workout/` — clean
- `lib/features/home/` — clean
- `lib/features/auth/` — clean
- `pubspec.yaml` — no new dependencies

---

## Service account leak (P0)

- `scripts/treino-dev-service-account*.json` is in `.gitignore`
- Pattern confirmed in `.gitignore`
- Zero matches in `git log main..HEAD` diff
- **CLEAN**

---

## Documented deviations (all accepted)

| # | Deviation | Classification |
|---|---|---|
| D1 | Post model uses `@Default('Anónimo')` instead of manual fromJson override | GOOD — avoids freezed redirect collision; SCENARIO-134 confirms correct behavior |
| D2 | Plus button styled as mint circle button | GOOD — mockup alignment |
| D3 | Pills at full opacity (no Opacity wrapper) | GOOD — mockup alignment; tests updated; spec.md not updated (WARN-01) |
| D4 | SizedBox(height: 18) between pills and body (design said 14) | SUGGESTION — within canonical set, smoke-confirmed acceptable |

---

## Conclusion

All 88 feed tests pass. All 474 project tests pass. `flutter analyze` is clean.
**One blocking gate remains: `dart format .` must be run and the 8 affected files
committed before opening the PR.** After that single fix, the branch is clean for
review.

**Verdict: PASS WITH WARNINGS — merge-blocked by CRIT-01 (format drift only).**

Pending before PR:
1. `dart format .` + commit (CRIT-01 — mandatory)
2. Update spec.md REQ-FEED-PILLS-003 + SCENARIO-161/162 wording (WARN-01 — recommended before archive)
3. Add 5-line `treino_icon_test.dart` for SCENARIO-189 (WARN-02 — optional but closes the scenario gap)
