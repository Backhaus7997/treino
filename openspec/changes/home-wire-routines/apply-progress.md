# Apply Progress — home-wire-routines

**Change**: `home-wire-routines`
**Branch**: `feat/home-wire-routines`
**Mode**: Strict TDD
**Date**: 2026-05-14

---

## TASK-001 — Test (RED): replace tap-no-op with navigation test ✅

**Commit**: `03b8fc3 test(home): replace EmpezarEntrenamientoCard tap no-op with navigation test`

- Removed existing `REQ-HOME-EMPEZAR-004: tap no-op — no exception, no navigation` from `test/features/home/widgets/empezar_entrenamiento_card_test.dart`
- Added new `REQ-HOME-WIRE-001: tap CTA navigates to /workout` using GoRouter mock pattern mirroring `routine_card_test.dart`
- Added `import 'package:go_router/go_router.dart';`
- Verified test FAILS as expected (RED phase) — `onPressed: null` doesn't navigate
- All other tests in the file (REQ-HOME-EMPEZAR-001..003 and -005) pass

## TASK-002 — Wire (GREEN): `onPressed: () => context.go('/workout')` ✅

**Commit**: `9876cef feat(home): wire EmpezarEntrenamientoCard CTA to /workout`

- Modified `lib/features/home/widgets/empezar_entrenamiento_card.dart`:
  - Added `import 'package:go_router/go_router.dart';`
  - Changed `onPressed: null` → `onPressed: () => context.go('/workout')`
  - Removed stale comment line `// CTA — onPressed is null until Etapa 5 wires navigation`
- All tests in `empezar_entrenamiento_card_test.dart` pass (GREEN phase)

## TASK-003 — Cleanup stale docstrings ✅

**Commit**: `e55a8fd chore(home): remove stale Etapa 5 docstrings`

- `lib/features/home/widgets/home_cta_button.dart`: removed "add isLoading in Etapa 5 wire" from class docstring
- `lib/features/home/widgets/esta_semana_card.dart`: removed "deferred to Etapa 5" from class docstring
- `grep -r 'Etapa 5' lib/features/home/` returns empty ✓
- Existing tests still pass

## Side commit — dart format fix on test file

**Commit**: `13697b9 style(home): apply dart format to empezar_entrenamiento_card_test`

- After TASK-001 commit, `dart format --set-exit-if-changed` flagged whitespace drift in the test file
- Re-formatted, committed separately as `style:` to keep work-unit history clean
- Not in the original task list but caught by TASK-004 gate

## TASK-004 — Quality gates ✅

**No commit — verification only.**

| Gate | Result |
|---|---|
| `flutter analyze` | **0 issues** |
| `dart format --set-exit-if-changed .` | **clean** |
| `flutter test` (full suite) | **385 passed, 1 skipped, 0 failures** |

### Smoke verification (MANUAL-OPTIONAL — for the user)

Steps if you want to verify visually before the PR:

1. `flutter run -d emulator-5554` (or any device)
2. Login si no estás
3. La app cae en `/home`
4. Tap "EMPEZAR ENTRENAMIENTO" pill mint
5. Tiene que navegar a `/workout`, mostrando la lista de plantillas (6 cards)
6. La bottom bar tiene que mostrar el tab Workout activo (highlighted)

---

## Summary

- 3 commits work-unit + 1 commit style fix = 4 commits total
- 4/4 tasks complete
- 385 tests passing, 0 regressions
- `flutter analyze` clean, `dart format` clean
- Ready for `sdd-verify`
