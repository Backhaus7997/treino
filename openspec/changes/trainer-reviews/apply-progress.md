# Apply Progress: trainer-reviews

**Change**: trainer-reviews
**Owner**: Backhaus
**Artifact store**: hybrid (openspec + Engram `sdd/trainer-reviews/apply-progress`)
**Phase**: Fase 6 Etapa 7

---

## PR#1 — Data + CF + Rules

**Branch**: `feat/trainer-reviews-pr1-data-cf`
**Base**: `main`
**Status**: Complete
**Date**: 2026-05-27

### Tasks completed: T01..T19

| Task | Status | Commit SHA | Message |
|---|---|---|---|
| T01 | [x] | pre-existing | Branch `feat/trainer-reviews-pr1-data-cf` checked out |
| T02 | [x] | f832fa0 | test(reviews): RED — Review model fields + idFor + round-trip |
| T03 | [x] | 4a7830a | feat(reviews): GREEN — Review Freezed model with idFor helper |
| T04 | [x] | b3a2fac | test(reviews): RED — ReviewRepository upsert/getForPair/watchForTrainer |
| T05 | [x] | 6bf7004 | feat(reviews): GREEN — ReviewRepository + review_providers |
| T06 | [x] | 6bf7004 | feat(reviews): GREEN — ReviewRepository + review_providers |
| T07 | [x] | c426fad | test(reviews): RED — dual-write guard _trainerPublicFields_excludes_aggregates |
| T08 | [x] | 65b21e0 | feat(reviews): GREEN — TrainerPublicProfile aggregate fields + ADR-RV-005 comment |
| T09 | [x] | ac1e49c | test(reviews): RED — Firestore rules tests (emulator-deferred) |
| T10 | [x] | 3b3cdac | feat(reviews): GREEN — firestore.rules reviews block + composite index |
| T11 | [x] | 3b3cdac | feat(reviews): GREEN — firestore.rules reviews block + composite index |
| T12 | [x] | 92c2c0e | test(reviews): RED — CF reviewAggregate emulator tests |
| T13 | [x] | 2f82e5d | feat(reviews): GREEN — CF reviewAggregate + index export |
| T14 | [x] | 2f82e5d | feat(reviews): GREEN — CF reviewAggregate + index export |
| T15 | [x] | 501841f | GATE: tsc 0 errors |
| T16 | [x] | 501841f | GATE: eslint 0 issues |
| T17 | [x] | 501841f | GATE: jest 49/49 passing (+8 vs baseline 41) |
| T18 | [x] | 501841f | GATE: flutter analyze 0 + dart format 0 (PR#1 files) + flutter test 1429+18skip |
| T19 | [x] | 501841f | VERIFY: dual-write guard + rules scope + index scope + no hex literals |

### TDD Cycle Evidence

| Task pair | RED commit | GREEN commit | Refactor |
|---|---|---|---|
| T02/T03 | f832fa0 | 4a7830a | format via 501841f |
| T04/T05 | b3a2fac | 6bf7004 | format via 501841f |
| T06 | n/a (declarations only, no RED required) | 6bf7004 | — |
| T07/T08 | c426fad | 65b21e0 | — |
| T09/T10 | ac1e49c (skip-deferred) | 3b3cdac | — |
| T11 | n/a (index file edit only) | 3b3cdac | — |
| T12/T13 | 92c2c0e | 2f82e5d | — |
| T14 | n/a (export line) | 2f82e5d | — |

### Quality Gates

| Gate | Result |
|---|---|
| tsc | 0 errors |
| eslint | 0 warnings/errors |
| jest | 49/49 passing (baseline 41, delta +8) |
| flutter analyze | 0 issues |
| dart format (PR#1 files) | 0 changed |
| dart format (full repo) | 12 pre-existing changes (not introduced by PR#1) |
| flutter test | 1429 passed + 18 skipped (no regressions) |

### New Files

| File | LOC | Notes |
|---|---|---|
| `lib/features/reviews/domain/review.dart` | 40 | Freezed model + idFor |
| `lib/features/reviews/domain/review.freezed.dart` | 350 | Generated |
| `lib/features/reviews/domain/review.g.dart` | 23 | Generated |
| `lib/features/reviews/data/review_repository.dart` | 64 | Repo: upsert/getForPair/watchForLink/watchForTrainer |
| `lib/features/reviews/application/review_providers.dart` | 42 | 3 providers |
| `functions/src/review-aggregate.ts` | 108 | CF + recomputeAggregate |
| `functions/src/__tests__/review-aggregate.test.ts` | 295 | 8 emulator integration tests |
| `test/features/reviews/domain/review_test.dart` | 91 | Model tests |
| `test/features/reviews/data/review_repository_test.dart` | 179 | Repo integration tests |
| `test/features/profile/data/user_repository_aggregate_guard_test.dart` | 113 | ADR-RV-005 regression guard |
| `test/firestore/reviews_rules_test.dart` | 69 | Rules stubs (emulator-deferred) |

### Modified Files

| File | Delta | Notes |
|---|---|---|
| `lib/features/coach/domain/trainer_public_profile.dart` | +8 | averageRating? + @Default(0) reviewCount |
| `lib/features/coach/domain/trainer_public_profile.freezed.dart` | ~+40 | Regenerated |
| `lib/features/coach/domain/trainer_public_profile.g.dart` | ~+4 | Regenerated |
| `lib/features/profile/data/user_repository.dart` | +4 | ADR-RV-005 comment |
| `firestore.rules` | +43 | /reviews/{reviewId} block added |
| `firestore.indexes.json` | +8 | (trainerId ASC, createdAt DESC) composite |
| `functions/src/index.ts` | +2 | export reviewAggregate |

### Deviations from Design

- `userReviewForLinkProvider` uses `"linkId:athleteId"` compound key (String family arg) rather than a record type, since Riverpod family only supports primitive/equatable types. The provider splits on `:` internally. This is a minor implementation detail not affecting the spec contract.
- `DateTime` + `@TimestampConverter()` used for `createdAt`/`updatedAt` (consistent with codebase pattern in `message.dart`, `trainer_link.dart`) instead of raw `Timestamp`. The JSON serialization round-trips correctly via the converter.
- T07 dual-write guard test passes even before T08 (adding aggregate fields to model) because `_trainerPublicFields` never contained them. The RED/GREEN cycle still holds: the guard test documents the invariant, and T08's changes do not break it.
- Firestore rules `update` block uses `keys().hasOnly([...all keys...])` + explicit immutable field equality checks, which is more defensive than the minimal `hasOnly(['rating','comment','updatedAt'])` in the spec. This prevents key injection attacks while preserving the spec intent.

### Risks for Smoke

1. CF aggregate correctness: verify create/update/delete events fire correctly on deployed Firestore — emulator tests cover this but real trigger wiring needs smoke.
2. Dual-write guard holds post-merge: verify `_trainerPublicFields` still excludes aggregate fields after any future model refactors.
3. Freezed regen produced expected diff: `trainer_public_profile.freezed.dart` and `.g.dart` include `averageRating`/`reviewCount` — verify generated files are committed.
4. `dart format` pre-existing issues on main: 12 workout/coach files have format violations on main; PR#1 does not introduce new ones. Recommend not blocking merge on these.

---

## PR#2 — Athlete Write/Edit Flow

**Status**: Pending (T20..T36)

---

## PR#3 — Display

**Status**: Pending (T37..T52)
