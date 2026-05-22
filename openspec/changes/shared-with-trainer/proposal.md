# Proposal: shared-with-trainer

## Intent

Retrofit the `TrainerLink.sharedWithTrainer: bool` field that was architecturally decided (roadmap Decision #4) but never shipped in Etapa 3. This field is the privacy gate Etapa 6 will consume to gate PF reads on `sessions/{athleteId}/*`. Without it now, Etapa 6 has nothing rule-enforceable to query against. We ship the model, repo method, athlete-facing toggle, Firestore update rule, and a one-time backfill so every existing doc has an explicit value. This change does NOT gate any actual reads — that is Etapa 6.

## Scope

### In Scope
- Model: add `@Default(false) bool sharedWithTrainer` to `TrainerLink` freezed factory + regenerate `.freezed.dart` / `.g.dart`.
- Repository: add `Future<void> setSharedWithTrainer(String linkId, bool value)` — focused single-field update via `docRef.update({'sharedWithTrainer': value})`. No `updatedAt` (matches existing repo convention — none of the other update methods write one).
- UI: `SwitchListTile`-style toggle inside `_LinkStateCard` between `_TrainerHeader` and `_ActionRow`, visible only when `link.status == active`. Reuses the existing `_confirm()` helper (line 259 of `athlete_coach_view.dart`).
- Firestore rule: extend the `trainer_links/{linkId}` update rule with an athlete-only OR on `sharedWithTrainer` change (Shape 1 from explore, verbatim below).
- Backfill: `scripts/backfill_trainer_links_shared.js`, idempotent, copy-adapted from `backfill_routine_visibility.js`.
- Tests: SCENARIO-464 through SCENARIO-477 across 4 test files (domain, repo, widget, rules-stub).

### Out of Scope
- Etapa 6 query gate (`where('sharedWithTrainer', '==', true)` on PF session reads) — that IS Etapa 6.
- Trainer-side UI indicator ("Atleta compartió/no compartió") — Etapa 6.
- Push / in-app notification on toggle — Fase 6.
- Granular sharing (date ranges, per-routine, etc.) — out of scope forever in this shape.
- Optimistic UI on the toggle — explicit choice for v1. Invalidate + reload `currentAthleteLinkProvider` consistent with `_onTerminate` / `_onCancel`.

## Capabilities

### New Capabilities
- None.

### Modified Capabilities
- `coach-link-lifecycle`: adds `sharedWithTrainer` field to the link aggregate + repo method + athlete-only write rule. Delta spec required.

## Approach

**Approach B from explore (locked):** freezed `@Default(false)` + one-time idempotent backfill script. The `request()` repo method calls `ref.set(link.toJson())` so all NEW links will get `sharedWithTrainer: false` written explicitly once the field exists in the factory. The backfill stamps explicit `false` on every pre-existing doc — required so Firestore equality queries in Etapa 6 work correctly (absent field ≠ explicit value).

### Repo method semantics (Q4 locked)
Focused single-field `setSharedWithTrainer(String linkId, bool value)` calling `docRef.update({'sharedWithTrainer': value})`. NO `updatedAt`. Verified `trainer_link_repository.dart` — none of `accept` / `decline` / `cancel` / `terminate` write an `updatedAt` field. We match the established convention. Minimum surface for the new rule clause to validate.

### Toggle UX (Q1 locked, Rioplatense Spanish)
- **Toggle label**: `Compartir historial con mi PF`
- **Subtitle**: `Tu PF va a poder ver tus sesiones pasadas, volumen y racha.`
- **Confirmation on ENABLE only**: title `Compartir historial`, body `¿Seguro? Tu PF va a poder ver todas tus sesiones, volumen y racha. Podés desactivarlo cuando quieras.` Buttons reuse the existing `_confirm()` helper which already returns `Cancelar` / `Confirmar`. We override action label to `Compartir` by adapting/inlining the helper — minor edit, see design phase.
- **Disable: no dialog**. Disabling is a privacy-restore action, lower stakes. Friction would punish the recovery path. Aligned with general UX heuristic: confirm destructive/expanding actions, not narrowing ones.

### Dialog widget (Q3 locked)
Reuse the existing `_confirm(context, title, body)` helper at `athlete_coach_view.dart:259`. It's already palette-aware, uses `Barlow`/`BarlowCondensed`, matches the link-termination dialog visually. For the enable case we extend it with an optional `confirmLabel` parameter (default `Confirmar`, override to `Compartir`). Tiny refactor, no new widget file.

### State refresh (locked from explore Q5)
`currentAthleteLinkProvider` (FutureProvider) is invalidated after `setSharedWithTrainer` returns, identical pattern to `_onTerminate` / `_onCancel`. The toggle reads `link.sharedWithTrainer` directly from the already-watched provider. No new provider.

### Firestore rule (Shape 1 verbatim)

```
allow update: if request.auth != null
    && (request.auth.uid == resource.data.trainerId
        || request.auth.uid == resource.data.athleteId)
    && request.resource.data.trainerId == resource.data.trainerId
    && request.resource.data.athleteId == resource.data.athleteId
    && request.resource.data.requestedAt == resource.data.requestedAt
    && (request.resource.data.sharedWithTrainer == resource.data.sharedWithTrainer
        || request.auth.uid == resource.data.athleteId);
```

Deployed via `scripts/deploy_rules.js` (REST API path — Firebase CLI unavailable per existing convention).

## Affected Areas

| Area | Impact | Description |
|------|--------|-------------|
| `lib/features/coach/domain/trainer_link.dart` | Modified | Add `@Default(false) bool sharedWithTrainer` |
| `lib/features/coach/domain/trainer_link.freezed.dart` | Regenerated | `dart run build_runner build --delete-conflicting-outputs` |
| `lib/features/coach/domain/trainer_link.g.dart` | Regenerated | Same codegen step |
| `lib/features/coach/data/trainer_link_repository.dart` | Modified | Add `setSharedWithTrainer(linkId, value)` |
| `lib/features/coach/athlete_coach_view.dart` | Modified | Add toggle widget + extend `_confirm()` with optional confirm label |
| `firestore.rules` | Modified | Extend `trainer_links/{linkId}` update rule (Shape 1) |
| `scripts/backfill_trainer_links_shared.js` | New | Idempotent Admin SDK backfill, ~60 LOC |
| `test/features/coach/domain/trainer_link_test.dart` | Modified | SCENARIO-464, 465 — round-trip + default |
| `test/features/coach/data/trainer_link_repository_test.dart` | Modified | SCENARIO-466..469 — field stamped on request + setSharedWithTrainer behavior |
| `test/features/coach/athlete_coach_view_test.dart` | Modified | SCENARIO-470..474 — toggle visibility/value/dialog flow |
| `test/features/coach/data/firestore_rules_test.dart` | Modified | SCENARIO-475..477 — emulator-deferred stubs (athlete OK, trainer denied, non-member denied) |

SCENARIO range reserved: **464–477** (14 scenarios).

## PR Strategy

**Single PR recommended.** Estimated 250–350 LOC total:
- Model + codegen: ~20 LOC hand + ~150 regenerated (excluded from review-line budget per project convention — generated files)
- Repo method: ~10 LOC
- Toggle widget + dialog helper extension: ~80 LOC
- Rule update: ~3 LOC
- Backfill script: ~60 LOC
- Tests across 4 files: ~150 LOC

Effective review surface (excluding regenerated freezed/g.dart): **~300 LOC** — within the 400-line budget.

**Fallback if apply exceeds 400 LOC**: chained PRs as `feat/shared-with-trainer-core` (model + repo + rule + backfill + non-UI tests) → `feat/shared-with-trainer-ui` (toggle + dialog + widget tests). Decision deferred to `sdd-tasks` Review Workload Forecast.

**Branch target**: `feat/shared-with-trainer` off `main`.

## Risks

| Risk | Likelihood | Mitigation |
|------|------------|------------|
| `build_runner` not run after freezed change → compile error | Med | Explicit task entry in `sdd-tasks` for `dart run build_runner build --delete-conflicting-outputs`. Pre-apply checklist verifies. |
| Rule deploy via `deploy_rules.js` fails or partial | Low | Script is established (used in prior etapas). Deploy to `treino-dev` first, smoke test, confirm before merge. |
| Backfill script requires `sa-key.json` not present in env | Med | Document in PR description. Backfill is dev-only for now; prod stays N/A until prod env exists. |
| Trainer accidentally sees toggle | Low | `_LinkStateCard` is private to `athlete_coach_view.dart`; `trainer_coach_view.dart` does NOT import or render it (verified). Toggle is naturally invisible to trainer. |
| Confirmation dialog blocks emulator widget test | Med | Widget tests must pump and dismiss the dialog explicitly. SCENARIO-472 covers this path. |
| OR clause in Firestore rule subtly allows trainer to flip when other fields unchanged | Low | Rule shape says `sharedWithTrainer == old OR uid == athleteId`. If trainer attempts to flip, first half fails (`new != old`), second half fails (uid is trainerId). Combined: denied. Stub SCENARIO-476 covers this. |

## Rollback Plan

If the change ships broken:
1. **Revert PR** on `main` (single PR makes this clean).
2. **Revert rule deploy**: re-run `scripts/deploy_rules.js` after `git checkout main -- firestore.rules` — restores the previous update rule. Field stays in docs but goes dormant (model still deserializes via `@Default(false)`, just no UI to toggle, no rule to gate).
3. **Backfilled data**: stays in Firestore as `false`. Harmless — Etapa 6 hasn't shipped, no consumer reads it. No data deletion needed.
4. **Codegen rollback**: `git checkout main -- lib/features/coach/domain/trainer_link.{freezed,g}.dart` reverts cleanly since regenerated files are committed.

## Dependencies

- `dart run build_runner build --delete-conflicting-outputs` available locally (it is — used throughout the project).
- `sa-key.json` in `scripts/` for backfill (dev environment).
- `scripts/deploy_rules.js` operational (used in Etapa 3 and Etapa 4 — confirmed working).
- This change is itself a **dependency for Etapa 6** (PF session-read gate). Mark in roadmap.

## Success Criteria

- [ ] All 14 SCENARIOs (464–477) green via `flutter test`.
- [ ] `flutter analyze` reports 0 issues.
- [ ] `dart format .` clean.
- [ ] `firestore.rules` deployed to `treino-dev` via `scripts/deploy_rules.js`.
- [ ] `scripts/backfill_trainer_links_shared.js` run on `treino-dev`; diag query confirms 100% of `trainer_links` docs have explicit `sharedWithTrainer` field.
- [ ] Toggle visible end-to-end in `AthleteCoachView` when link is `active`; invisible when `pending` or absent.
- [ ] Smoke test: trainer attempting to flip the field via direct Firestore write is denied by rule (manual emulator or console check).
- [ ] Branch `feat/shared-with-trainer` merged to `main`. Etapa 6 unblocked.

## Open Follow-ups for spec/design

- `sdd-spec`: lock the exact `_confirm()` extension signature — add `String confirmLabel = 'Confirmar'` parameter, or split into a new helper `_confirmEnable()`. Spec phase decides.
- `sdd-design`: confirm whether the toggle widget is inlined in `_LinkStateCard` (matches `_ActionRow` private-widget pattern) or extracted to a new private `_ShareToggle` widget. Recommend the latter for testability (widget test can pump `_ShareToggle` in isolation).
- `sdd-tasks`: order tasks so codegen happens BEFORE any code that depends on the new field compiles. Suggested order: (1) model + codegen, (2) repo method, (3) rule + deploy, (4) backfill script, (5) UI + dialog, (6) tests last.
