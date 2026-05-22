# Exploration: shared-with-trainer

**Change**: `shared-with-trainer`
**Type**: Tech debt cleanup (NOT a numbered Fase 5 etapa)
**Project**: treino
**Artifact store**: hybrid (engram + openspec)
**Engram key**: `sdd/shared-with-trainer/explore`

---

## Problem Statement

The roadmap (`docs/roadmap.md:273`, Decision #4) documents `sharedWithTrainer: bool` on the `TrainerLink` model as required architecture:

> El campo va en el doc de `trainer_links/{linkId}`. Default `false`. El athlete (no el PF) lo puede toggle desde su tab Coach con vínculo active. Reglas: read by both members; write only by `athleteId`. Cuando `false` el PF ve solo el plan asignado + agenda; cuando `true` el PF también ve el historial completo (sessions + insights). Para Etapa 3 (link lifecycle): se setea el campo al crear el link. Para Etapa 6 (alumnos del trainer): la query del PF a `sessions/{athleteId}/*` se gate por este flag.

It was supposed to ship as part of Etapa 3 (`feat/coach-link-lifecycle`, PR #61) but didn't. Now we retrofit it before Etapa 6 (Agenda) starts. Without it: PFs have no path to see athlete session history, and the Etapa 6 query gate becomes a stickier refactor.

## Current State

**`TrainerLink` model** (`lib/features/coach/domain/trainer_link.dart`): 8 fields, none `sharedWithTrainer`.

**`TrainerLinkRepository`**: `request()` calls `ref.set(link.toJson())`. Once `@Default(false) bool sharedWithTrainer` is added to the freezed factory, every NEW link doc automatically gets `sharedWithTrainer: false` written at create time — no change to `request()` needed. Other methods (`accept`, `decline`, `terminate`, `cancel`) update specific fields and don't touch this.

**`trainer_links` Firestore rules** (`firestore.rules:99-104`): current update rule allows ANY member to mutate any non-immutable field. This would let the **trainer** toggle `sharedWithTrainer` — privacy violation. Must add an athlete-only constraint.

**`AthleteCoachView`** active-link state renders: `_TrainerHeader` (PF name/date) → `_ActionRow` (TERMINAR VÍNCULO button). The toggle goes between these, inside the existing card `Column`, visible only when `link.status == active`.

**`currentAthleteLinkProvider`**: already loads the active `TrainerLink` for the athlete. Toggle reads from it and calls a new `setSharedWithTrainer(linkId, value)` repo method + `ref.invalidate(currentAthleteLinkProvider)`. No new provider needed. It's a `FutureProvider` (not stream) → invalidate+reload pattern consistent with existing `_onTerminate`/`_onCancel`.

**Backfill pattern**: `scripts/backfill_routine_visibility.js` is the canonical reference — idempotent batched-write, reusable shape.

## Affected Areas

| File | Change |
|------|--------|
| `lib/features/coach/domain/trainer_link.dart` | Add `@Default(false) bool sharedWithTrainer` to freezed factory |
| `lib/features/coach/domain/trainer_link.freezed.dart` | Re-generated via `dart run build_runner build` |
| `lib/features/coach/domain/trainer_link.g.dart` | Re-generated |
| `lib/features/coach/data/trainer_link_repository.dart` | Add `setSharedWithTrainer(linkId, value)` method |
| `lib/features/coach/athlete_coach_view.dart` | Toggle widget inside `_LinkStateCard` active branch |
| `firestore.rules` | Extend `trainer_links` update rule (Shape 1) |
| `scripts/backfill_trainer_links_shared.js` | NEW — ~60 LOC, idempotent (Approach B) |
| `test/features/coach/domain/trainer_link_test.dart` | Add field to fixtures + round-trip test |
| `test/features/coach/data/trainer_link_repository_test.dart` | Assert field stamped on `request()`, new `setSharedWithTrainer` group |
| `test/features/coach/athlete_coach_view_test.dart` | Toggle visibility + persistence tests |
| `test/features/coach/data/firestore_rules_test.dart` | Stub SCENARIOs (emulator-deferred per Decision #25) |

## Approaches

| | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| A | Freezed default only | Zero ops work | Old docs lack field — Firestore `where('sharedWithTrainer', '==', true/false)` silently misses them. Etapa 6 gate breaks for pre-change links. | Low |
| **B** | **Default + backfill script** | **Every doc has explicit field. Queries correct. Etapa 6 gate trivial.** | One-time manual script run. Needs `sa-key.json`. | Low (+60 LOC) |
| C | Lazy backfill (stamp on toggle) | No ops work | Untouched old docs never get the field. Strictly worse than A. | Low (but wrong) |

**Recommendation: Approach B.** The backfill pattern is proven, the script is short, and it eliminates a silent time-bomb for Etapa 6.

## Firestore Rule Shape

**Recommended: Shape 1 — single `allow update` block with OR condition** (matches existing collection-style):

```js
allow update: if request.auth != null
    && (request.auth.uid == resource.data.trainerId
        || request.auth.uid == resource.data.athleteId)
    && request.resource.data.trainerId == resource.data.trainerId
    && request.resource.data.athleteId == resource.data.athleteId
    && request.resource.data.requestedAt == resource.data.requestedAt
    && (request.resource.data.sharedWithTrainer == resource.data.sharedWithTrainer
        || request.auth.uid == resource.data.athleteId);
```

Shape 2 (split clauses) relies on Firestore's implicit OR between multiple `allow update` blocks — semantically riskier to audit, deviates from existing single-block pattern.

## Open Questions for Propose

1. **Toggle placement**: inside the active-link card (between header and action button) vs. separate "Configuración" section below the card. Card placement simpler for v1.
2. **Toggle copy + confirmation dialog**: e.g., "Compartir mi historial con mi PF". Confirmation on enable (recommended). Confirmation on disable too?
3. **SCENARIO numbers** for new Firestore rule stubs (athlete can flip, trainer cannot, non-member cannot).
4. **Optimistic UI vs invalidate-reload**: invalidate is simpler and matches existing patterns; optimistic is nicer UX but adds complexity.

## Out of Scope

- Etapa 6 query gate (`where('sharedWithTrainer', '==', true)` in PF session reads).
- Trainer-side UI showing sharing state.
- Push/in-app notification on toggle.
- Granular sharing (date range, type filtering).
- `Routine.visibility == 'shared'` — unrelated, has its own semantics.

## Risks

1. `dart run build_runner build` MUST run after the model change before any widget compiles. Easy to forget if tasks don't call it out.
2. Firestore rule testing is emulator-deferred (Decision #25) — `flutter test` won't catch rule bugs. Rule shape needs careful manual review before deploy.
3. `currentAthleteLinkProvider` is a `FutureProvider` — toggle state requires invalidate+reload. Brief loading flash possible. Propose locks behavior.

## Ready for Proposal

Yes. Structural questions resolved (model shape, repo method shape, rule shape, backfill approach). Remaining items (copy, dialog flow, SCENARIO numbers) are product-level micro-decisions for propose.
