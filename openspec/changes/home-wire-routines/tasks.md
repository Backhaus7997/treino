# Tasks: home-wire-routines

**Change**: `home-wire-routines`
**Fase / Etapa**: Fase 2 · Etapa 5 (cierre)
**Branch**: `feat/home-wire-routines`
**Artifact store**: openspec

---

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~45 LOC (3 prod + ~40 test) |
| 400-line budget risk | Low |
| Chained PRs recommended | No |
| Suggested split | Single PR |
| Delivery strategy | ask-on-risk |
| Chain strategy | N/A |

Decision needed before apply: No
Chained PRs recommended: No
Chain strategy: pending
400-line budget risk: Low

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | All 4 tasks | PR 1 | Single PR on feat/home-wire-routines → main |

---

## Phase 1: RED — Replace failing test (REQ-HOME-WIRE-002)

- [ ] 1.1 In `test/features/home/widgets/empezar_entrenamiento_card_test.dart`, delete the test block `REQ-HOME-EMPEZAR-004: tap no-op — no exception, no navigation`.
- [ ] 1.2 In the same file, add `testWidgets('REQ-HOME-WIRE-001: tap navigates to /workout', ...)` using `MaterialApp.router(routerConfig: GoRouter(...))` with routes `/home` → `EmpezarEntrenamientoCard` and `/workout` → `Text('WORKOUT')`. Mirror `routine_card_test.dart:94-128` exactly.
- [ ] 1.3 Add `import 'package:go_router/go_router.dart';` to the test file if not already present.
- [ ] 1.4 Confirm file compiles AND the new test FAILS (expected — `onPressed: null` is still in place).

Done when: `flutter test test/features/home/widgets/empezar_entrenamiento_card_test.dart` compiles, 1 test fails.

**Commit**: `test(home): replace EmpezarEntrenamientoCard tap no-op with navigation test`

---

## Phase 2: GREEN — Wire onPressed (REQ-HOME-WIRE-001)

- [ ] 2.1 In `lib/features/home/widgets/empezar_entrenamiento_card.dart`, change `onPressed: null` to `onPressed: () => context.go('/workout')` (line ~99).
- [ ] 2.2 Add `import 'package:go_router/go_router.dart';` to that file if not already present.
- [ ] 2.3 Remove the stale comment `// CTA — onPressed is null until Etapa 5 wires navigation` (line ~96).
- [ ] 2.4 Update the class-level docstring to remove any "until Etapa 5" wording.

Done when: `flutter test test/features/home/widgets/empezar_entrenamiento_card_test.dart` reports all tests pass.

**Commit**: `feat(home): wire EmpezarEntrenamientoCard CTA to /workout`

> **Atomicity constraint (REQ-HOME-WIRE-002)**: Phase 1 and Phase 2 commits MUST land adjacently on the branch. Do NOT push between them — the repo has a failing test between commits, which is expected for Strict TDD but must not reach CI independently.

---

## Phase 3: Cleanup — Remove stale Etapa 5 docstrings (REQ-HOME-WIRE-003, REQ-HOME-WIRE-004)

- [ ] 3.1 In `lib/features/home/widgets/home_cta_button.dart`, remove the doc note referencing "add isLoading in Etapa 5 wire".
- [ ] 3.2 In `lib/features/home/widgets/esta_semana_card.dart`, remove the doc note referencing "deferred to Etapa 5".
- [ ] 3.3 Verify: no file under `lib/features/home/` references "Etapa 5" (run `grep -r 'Etapa 5' lib/features/home/` — must return no matches).

Done when: grep returns empty, no functional change, existing tests still pass.

**Commit**: `chore(home): remove stale Etapa 5 docstrings`

---

## Phase 4: Quality Gates

- [ ] 4.1 `flutter analyze` → must report 0 issues.
- [ ] 4.2 `dart format --output=none --set-exit-if-changed .` → must be clean; auto-fix with `dart format .` if needed, then re-run.
- [ ] 4.3 `flutter test` → all tests pass (0 failures, 0 errors). Net count: same as pre-change (1 test deleted, 1 added).
- [ ] 4.4 **MANUAL-OPTIONAL smoke**: open app → navigate to `/home` → tap "EMPEZAR ENTRENAMIENTO" → verify `/workout` loads PlantillasSection with routines → verify bottom bar shows Workout tab as active.

Done when: analyze 0, format clean, tests green. Smoke step is manual/optional — document result in apply-progress if performed.

> No commit for this phase — it is a verification step only.

---

## Task Order (sequential — no parallelism)

```
Phase 1 (RED) → Phase 2 (GREEN) → Phase 3 (cleanup) → Phase 4 (quality gates)
```

Phase 2 depends on Phase 1 (Strict TDD pair). Phase 3 is independent of Phase 2 functionally but logically follows. Phase 4 is always last.

---

## Files in scope

| File | Change type |
|------|-------------|
| `test/features/home/widgets/empezar_entrenamiento_card_test.dart` | Modify — delete 1 test, add 1 test (Phase 1) |
| `lib/features/home/widgets/empezar_entrenamiento_card.dart` | Modify — 1-line wire + remove comment + update docstring (Phase 2) |
| `lib/features/home/widgets/home_cta_button.dart` | Modify (cosmetic) — docstring only (Phase 3) |
| `lib/features/home/widgets/esta_semana_card.dart` | Modify (cosmetic) — docstring only (Phase 3) |

**Not touched**: `router.dart`, `home_screen.dart`, `home_screen_test.dart`, any provider, any other widget.
