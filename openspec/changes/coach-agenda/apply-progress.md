# Apply Progress: coach-agenda — PR1 (data layer)

**Change**: `coach-agenda`
**PR scope**: PR1 = data layer (T01–T19 from tasks.md)
**Branch**: `feat/coach-agenda-data` (base: `main`)
**Strict TDD**: ACTIVE (`flutter test`)
**Delivery**: `size:exception` APPROVED by user (~650 LOC)
**Started**: 2026-05-22

---

## Status

In progress.

## PR1 Tasks

| # | Task | Status | Commit |
|---|------|--------|--------|
| T01 | [DOCS] Amend SCENARIO-491 → ADR-1 flip | ✅ done | b0c18f9 |
| T02 | [CHORE] Branch + pubspec table_calendar + pub get | ⏳ next | — |
| T03 | [RED] Domain tests AvailabilityRule + AvailabilityOverride | ⏸ | — |
| T04 | [GREEN+CODEGEN] Implement Rule + Override @freezed | ⏸ | — |
| T05 | [RED] Domain tests Appointment | ⏸ | — |
| T06 | [GREEN+CODEGEN] Implement Appointment + Exceptions | ⏸ | — |
| T07 | [RED] Unit tests computeFreeSlots | ⏸ | — |
| T08 | [GREEN] Implement compute_free_slots.dart | ⏸ | — |
| T09 | [RED] Repo tests AvailabilityRepository CRUD | ⏸ | — |
| T10 | [GREEN] Implement FirestoreAvailabilityRepository | ⏸ | — |
| T11 | [RED] Repo tests AppointmentRepository booking | ⏸ | — |
| T12 | [GREEN] Implement book() — ADR-5 + ADR-1 ⚠ | ⏸ | — |
| T13 | [RED] Repo tests cancel + queries | ⏸ | — |
| T14 | [GREEN] Implement cancel + watchForAthlete + watchForTrainer | ⏸ | — |
| T15 | [RED] Provider tests | ⏸ | — |
| T16 | [GREEN] Implement agenda_providers.dart | ⏸ | — |
| T17 | [MOD] firestore.rules (3 collections + 24h CEL + flip rule) | ⏸ | — |
| T18 | [MOD] router.dart `/coach/agenda` route stub | ⏸ | — |
| T19 | [QA] flutter analyze + dart format + flutter test | ⏸ | — |

> Note: original tasks list T01–T19 in the tasks.md file. The orchestrator's PR1 scope is T01–T17; T18 and T19 are also gates for PR1 closure.

## TDD Cycle Evidence (filled as tasks complete)

| Task | Test File | Layer | Safety Net | RED | GREEN | TRIANGULATE | REFACTOR |
|------|-----------|-------|------------|-----|-------|-------------|----------|
| T01 | docs-only | N/A | N/A | N/A | N/A | N/A | N/A |

## PR Description (draft for user to push)

> **size:exception** APPROVED by maintainer. PR1 estimated ~650 LOC (prod ~400 + tests ~250) because it bundles 4 domain models, 2 repos, 1 pure compute function, Riverpod provider stack, and Firestore rules — splitting them creates non-shippable slices.

## Pending (PR2/PR3)

PR2 (athlete UI, T20–T33) and PR3 (trainer UI, T34–T45) are out of scope for this run. They block on PR1 merging to `main`.

## Risks discovered

(empty so far)
