# Apply Progress — feed-create-search

## PR#1 — DONE (`feat/feed-create-post`)

**Branch**: `feat/feed-create-post`
**Completed**: 2026-05-15
**TDD Mode**: Strict (RED → GREEN for each work unit)

### Tasks

| Task | Status | Notes |
|---|---|---|
| T01 | [x] | `palette.danger = Color(0xFFE53935)` added to AppPalette (constructor, mintMagenta, copyWith, lerp) |
| T02 | [x] | `TreinoIcon.dumbbell`, `chevronLeft`, `chevronRight` added under `// Feed / social` |
| T03 | [x] | Notifier test file created with full test suite (merged T03+T04+T05+T06 into one commit) |
| T04 | [x] | setText/canSubmit/char-limit tests — SCENARIO-221..223 |
| T05 | [x] | submit success + gym-gate tests — SCENARIO-227, SCENARIO-231 |
| T06 | [x] | error path + isSubmitting guard — SCENARIO-228, SCENARIO-229 |
| T07 | [x] | Screen form structure test — SCENARIO-220 |
| T08 | [x] | PUBLICAR enabled/disabled + char counter + privacy default — SCENARIO-221..224 |
| T09 | [x] | Gym pill disabled + routine stub — SCENARIO-225, SCENARIO-226 |
| T10 | [x] | CANCELAR + spinner + error inline — SCENARIO-228..230 |
| T11 | [x] | `create_post_notifier.dart` — CreatePostState + CreatePostNotifier + createPostNotifierProvider |
| T12 | [x] | `create_post_screen.dart` — ConsumerStatefulWidget body, header, pills, counter, error |
| T13 | [x] | Plus button in `feed_screen.dart` wrapped in GestureDetector → `context.push('/feed/create')` |
| T14 | [x] | `GoRoute(path: 'create')` added under `/feed` in `router.dart` |
| T15 | [x] | `flutter analyze` → 0 issues |
| T16 | [x] | `dart format` → 0 changed files |
| T17 | [x] | `flutter test` → 565 tests passing (538 baseline + 12 notifier + 15 screen) |

### TDD Cycle Evidence

| Work Unit | RED commit | GREEN commit | Tests |
|---|---|---|---|
| T01/T02 token precursors | (no test needed — token addition) | b65c6ec | analyze-clean |
| T03-T06 CreatePostNotifier | 07c8c66 (file fails to compile) | cc2d0f9 | 12 passing |
| T07-T10 CreatePostScreen | 139dd3c (file fails to compile) | a0cfaf3 | 15 passing |
| T13/T14 integration | (no test — manual verify) | e08ddc2 | — |

### Deviations

1. **`characters` package added to pubspec.yaml** — `text.characters.length` (grapheme cluster count per design) requires explicit dep. Package was transitive-only. Deviation: `characters: ^1.3.0` added to `dependencies`.

2. **`isSubmitting` set FIRST in `submit()`** — Design said "auth gate first", but setting `isSubmitting=true` before the first `await` is necessary to prevent double-tap (and makes the SCENARIO-228 test pass with a `Completer`-backed auth stream). Defensive-in-depth improvement.

3. **Tasks T03-T06 and T07-T10 merged** — Design described separate stub/RED/RED/RED tasks but in practice all test content was written in two commits (one per test file). The commits are: skeleton+full tests for notifier, skeleton+full tests for screen. Both confirmed RED (compile failure) before implementation.

4. **SCENARIO-232 (keyboard scroll) not tested** — As documented in the spec, keyboard scroll is not testable via widget test. Deferred to manual smoke test.

5. **`_CreatePostBody` uses `ConsumerStatefulWidget`** — Design said `ConsumerWidget`. `ConsumerStatefulWidget` was needed to hold `TextEditingController`. This is a natural Riverpod pattern and does not affect behavior.

### Quality Gates

| Gate | Result |
|---|---|
| `flutter analyze` | 0 issues |
| `dart format` | 0 changed files |
| `flutter test` | 565 passed, 0 failed |

### Files Created/Modified

| File | Action | LOC (approx) |
|---|---|---|
| `lib/app/theme/app_palette.dart` | Modified | +11 |
| `lib/core/widgets/treino_icon.dart` | Modified | +4 |
| `lib/features/feed/application/create_post_notifier.dart` | Created | ~120 |
| `lib/features/feed/presentation/create_post_screen.dart` | Created | ~280 |
| `lib/features/feed/feed_screen.dart` | Modified | +6 |
| `lib/app/router.dart` | Modified | +5 |
| `pubspec.yaml` | Modified | +1 (`characters: ^1.3.0`) |
| `test/features/feed/application/create_post_notifier_test.dart` | Created | ~370 |
| `test/features/feed/presentation/create_post_screen_test.dart` | Created | ~420 |

### Commits

| Hash | Message |
|---|---|
| b65c6ec | feat(theme): add palette.danger token and TreinoIcon.dumbbell/chevronLeft/chevronRight |
| 07c8c66 | test(feed): SCENARIO-221..229/231 for CreatePostNotifier [RED] |
| cc2d0f9 | feat(feed): add CreatePostNotifier with form state and submit flow [GREEN] |
| 139dd3c | test(feed): SCENARIO-220..226/228..230 for CreatePostScreen [RED] |
| a0cfaf3 | feat(feed): add CreatePostScreen with privacy pills, char counter, routine stub [GREEN] |
| e08ddc2 | feat(feed): wire plus button to /feed/create and register GoRoute |

### Deferred (SCENARIO-232)

SCENARIO-232 (keyboard scroll) is NOT testable via widget test. Manual smoke test required before merge: open the Create Post screen on a physical device/simulator, open keyboard, verify that PUBLICAR is reachable by scrolling.

---

## PR#2 — PENDING

Tasks T18-T37 will be implemented on branch `feat/feed-search-users` AFTER PR#1 merges to `main`.

(This section will be filled by the PR#2 apply run.)
