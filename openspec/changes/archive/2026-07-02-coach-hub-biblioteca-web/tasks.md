# Tasks: coach-hub-biblioteca-web (Fase W5.3)

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | PR1 ~355 net · PR2 ~200 |
| 400-line budget risk | Medium (PR1 near budget; picker edit is negative) |
| Chained PRs recommended | Yes |
| Suggested split | PR1 (extraction + Ejercicios tab) → PR2 (Templates tab + route swap) |
| Delivery strategy | ask-on-risk |
| Chain strategy | feature-branch-chain |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: Medium

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Filter extraction + Ejercicios tab | PR1 | Base = feature/coach-hub-biblioteca-web; route stays on ProximamenteScreen |
| 2 | Templates tab + route swap | PR2 | Base = PR1 branch; Biblioteca goes live atomically |

---

## PR1 — Filter Extraction + Ejercicios Tab

### Phase 1.1 — Pure filter library (foundation; everything else depends on this)

- [x] 1.1.1 exercise_filter_test.dart — RED tests for foldSearch, exerciseMatchesFilters, ADR-RER-05
- [x] 1.1.2 exercise_filter.dart — GREEN (foldSearch + exerciseMatchesFilters + customToExercise)
- [x] 1.1.3 exercise_picker_sheet.dart refactor — delegate _matches

### Phase 1.2 — Web providers (depends on 1.1.2)

- [x] 1.2.1 biblioteca_providers_test.dart — RED tests
- [x] 1.2.2 biblioteca_providers.dart — GREEN (3 StateProviders + bibliotecaExercisesProvider)

### Phase 1.3 — Ejercicios tab widgets (depends on 1.2.2)

- [x] 1.3.1 ejercicios_tab_test.dart — RED tests
- [x] 1.3.2 exercise_grid_card.dart — GREEN
- [x] 1.3.3 biblioteca_filter_chips.dart — GREEN
- [x] 1.3.4 ejercicios_tab.dart — GREEN

### Phase 1.4 — Exercise detail dialog (depends on 1.3.2)

- [x] 1.4.1 ejercicios_tab_test.dart: tap exercise card → AlertDialog
- [x] 1.4.2 exercise_detail_dialog.dart — GREEN

### Phase 1.5 — Screen shell (completed in PR2 batch)

- [x] 1.5.1 biblioteca_web_screen_test.dart — RED tests (4 tests)
- [x] 1.5.2 biblioteca_web_screen.dart — GREEN (with real TemplatesTab, no placeholder)

### Phase 1.6 — PR1 gate

- [x] 1.6.1 flutter analyze 0 new issues, flutter test all pass

---

## PR2 — Templates Tab + Section Shell Wiring

### Phase 2.1 — Templates tab widgets (base = PR1 branch)

- [x] 2.1.1 templates_tab_test.dart — RED then GREEN (10 tests)
- [x] 2.1.2 template_grid_card.dart — GREEN
- [x] 2.1.3 template_detail_dialog.dart — GREEN
- [x] 2.1.4 templates_tab.dart — GREEN

### Phase 2.2 — Swap shell placeholder + route wiring (depends on 2.1.4)

- [x] 2.2.1 biblioteca_web_screen.dart created (with TemplatesTab, no placeholder needed)
- [x] 2.2.2 routes.dart — swap ProximamenteScreen → BibliotecaWebScreen; NO badgeProvider

### Phase 2.3 — PR2 gate

- [x] 2.3.1 sidebar_registry_test.dart — 8/8 green (badgeProvider isNull incl. biblioteca)
- [x] 2.3.2 flutter analyze 33 (baseline), flutter test 3099 passed / 49 skipped / 0 failed

---

## Summary

All tasks completed. PR1 (~355 net) + PR2 (~200) delivered both tabs, full predicate extraction with mobile guard tests, and route wiring. Mobile picker tests green. Sidebar test green (no badge added). All 3099 tests passing.
