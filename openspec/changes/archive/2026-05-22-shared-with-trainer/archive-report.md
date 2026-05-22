# Archive Report — shared-with-trainer

**Change**: `shared-with-trainer`  
**Archived**: 2026-05-22  
**Status**: COMPLETE (PASS WITH WARNINGS → ARCHIVED)  
**PR**: #73 (commit `fa42aa4`, merged to `main`)

---

## Archival Summary

The `shared-with-trainer` change has been fully implemented, verified (PASS WITH WARNINGS, 0 CRITICAL), and closed. All code tasks (T01–T15) are complete. Post-archive operations (T16–T17) are documented as carry-forward actions.

**Main spec created**: `openspec/specs/coach-link-lifecycle.md` — consolidated single source of truth for the `coach-link-lifecycle` capability with all 14 REQs (REQ-COACH-LINK-001..014) from Fase 5.

---

## Change Artifacts (Engram Observation IDs)

For traceability, all upstream artifacts are archived below with their engram IDs:

| Artifact | Observation ID | Type | Generated |
|----------|---|---|---|
| Exploration | #104 | architecture | 2026-05-22 12:43:41 |
| Proposal | #109 | architecture | 2026-05-22 12:46:08 |
| Spec | #110 | architecture | 2026-05-22 12:51:25 |
| Design | — | (not created) | — |
| Tasks | #111 | architecture | 2026-05-22 13:04:45 |
| Apply Progress | #112 | architecture | 2026-05-22 13:06:33 (stale — T01–T15 done, not reflected) |
| Verify Report | #113 | architecture | 2026-05-22 13:38:06 |
| Archive Report | (this file) | architecture | 2026-05-22 |

---

## Spec Consolidation

### Source Spec (Delta)
- **File**: `openspec/changes/shared-with-trainer/spec.md`
- **Scope**: ANNOTATED capability `coach-link-lifecycle` with 14 new REQs (REQ-COACH-LINK-001..014) and SCENARIO-464..477
- **Requirements**: All marked MUST strength

### Main Spec (Created)
- **File**: `openspec/specs/coach-link-lifecycle.md`
- **Content**: Consolidated full specification for the `coach-link-lifecycle` capability
  - 14 requirements (REQ-COACH-LINK-001 through REQ-COACH-LINK-014)
  - 14 scenarios (SCENARIO-464 through SCENARIO-477)
  - Domain invariants (5 key rules)
  - Out-of-scope deferred items (5 items deferred to Etapa 6 / future)
  - Source attribution: all 14 REQs tagged "Fase 5" for traceability

### Merge Action
No merge needed — the delta spec is the full specification for this annotated capability. Main spec was created by consolidating the delta spec content into a standalone domain spec file.

---

## Tasks Completion

| Task | Type | Status | Notes |
|------|------|--------|-------|
| T01 | CHORE | ✅ | Branch setup |
| T02 | RED | ✅ | SCENARIO-464, 465 (domain tests) |
| T03 | GREEN | ✅ | Add `@Default(false) bool sharedWithTrainer` to `TrainerLink` |
| T04 | CODEGEN | ✅ | `dart run build_runner build --delete-conflicting-outputs` |
| T05 | VERIFY | ✅ | Domain tests green |
| T06 | RED | ✅ | SCENARIO-466, 467, 468 (repo tests) |
| T07 | GREEN | ✅ | `setSharedWithTrainer` implemented |
| T08 | VERIFY | ✅ | Repo tests green |
| T09 | RED | ✅ | SCENARIO-469–474 (widget tests) |
| T10 | GREEN | ✅ | `_ShareToggle` added to `_LinkStateCard` in `athlete_coach_view.dart` |
| T11 | VERIFY | ✅ | Widget tests green |
| T12 | RED | ✅ | SCENARIO-475–477 (firestore rules stubs) |
| T13 | MOD | ✅ | `firestore.rules` Shape 1 update block |
| T14 | CHORE | ✅ | `scripts/backfill_trainer_links_shared.js` created |
| T15 | QA | ✅ | analyze + format + full suite green |
| T16 | OPS | ⏳ | **CARRY-FORWARD**: `cd scripts && node deploy_rules.js` (post-archive) |
| T17 | OPS | ⏳ | **CARRY-FORWARD**: `cd scripts && node backfill_trainer_links_shared.js` (post-T16) |

**Status**: 15/15 code tasks complete. 2/2 ops tasks pending (post-merge gates).

---

## Verification Status

**Verify Report Result**: PASS WITH WARNINGS
- 0 CRITICAL issues
- 2 WARNINGS
- 1 SUGGESTION

### WARNINGS (Carry-Forward)

**W-01 — Batch size discrepancy**
- Spec says: "commits in batches of 500"
- Code: `if (batchCount === 400)` in `scripts/backfill_trainer_links_shared.js`
- Impact: Safe (400 < 500 Firestore limit). Idempotency unaffected.
- Action: Can be corrected before T17 runs, or left as-is (both are safe).

**W-02 — Post-merge ops not yet executed**
- T16 (deploy rules) and T17 (backfill) have not yet run.
- Production rules are still at pre-Shape-1 version.
- Existing `trainer_links` docs may lack `sharedWithTrainer` field.
- Action: Run T16 then T17 post-archive (see "Post-Archive Operations" below).

### SUGGESTION

**S-01 — apply-progress stale**
- The apply-progress artifact (#112) still shows T02–T15 as "Pending" (never updated after apply).
- Functional impact: None. Code is on `main`.
- Action: Optional refresh before archiving for accuracy.

---

## Post-Archive Operations (MUST BE RUN BY USER)

**These two operations are NOT part of the PR and must be run AFTER merging to main and archiving.**

### T16: Deploy Firestore Rules

```bash
cd scripts
node deploy_rules.js
```

**Acceptance**:
- Diff shows only the `trainer_links` update block change.
- Deployment to `treino-dev` succeeds.
- Manual smoke test: attempt to flip `sharedWithTrainer` as trainer → denied by rule.

### T17: Run Backfill (AFTER T16)

```bash
cd scripts
node backfill_trainer_links_shared.js
```

**Acceptance**:
- All `trainer_links` docs in Firestore now have explicit `sharedWithTrainer` field.
- Re-run is idempotent (no writes on second pass).

---

## Dependencies and Etapa 6 Gate

**Etapa 6 (Agenda + PF) Dependency**: This change is a prerequisite for Etapa 6. The `sharedWithTrainer` field is the privacy gate that Etapa 6 will use to filter PF session reads:

```dart
// Etapa 6 query (not in this change):
query.where('sharedWithTrainer', '==', true);
```

The corresponding `sessions/{athleteId}/*` Firestore rule extension is also deferred to Etapa 6.

**Current State**: The field, repo method, athlete-facing toggle, and rule shape are ready. Etapa 6 only needs to add the query filter and the session read rule.

---

## Scope Verification

### Correctly Implemented (In Scope)
- ✅ Model: `@Default(false) bool sharedWithTrainer` in `TrainerLink` freezed factory
- ✅ Repo: `setSharedWithTrainer(linkId, value)` — single-field update, no `updatedAt`
- ✅ UI: `SwitchListTile` toggle in `_LinkStateCard`, active-link only
- ✅ Rule: Shape 1 with athlete-only OR clause on `sharedWithTrainer` change
- ✅ Backfill: Idempotent script in `scripts/backfill_trainer_links_shared.js`
- ✅ Tests: All 14 SCENARIOs (464–477) across 4 test files + emulator stubs
- ✅ Quality: `flutter analyze` 0 issues, `dart format .` clean, `flutter test` 1045 passed

### Correctly Deferred (Out of Scope)
- ✅ Etapa 6 query gate on PF session reads
- ✅ Trainer-side UI indicator
- ✅ Push / in-app notification on toggle
- ✅ Granular sharing (date ranges, per-routine)
- ✅ Optimistic UI on toggle (invalidate + reload used instead)

---

## Archived Files

All SDD artifacts have been moved to `openspec/changes/archive/2026-05-22-shared-with-trainer/`:

- `explore.md` — exploration phase findings
- `proposal.md` — proposal and approach locks
- `spec.md` — delta specification (14 REQs, 14 SCENARIOs)
- `tasks.md` — 17-task breakdown (15 code + 2 ops carry-forward)
- `verify-report.md` — verification result (PASS WITH WARNINGS)
- `archive-report.md` — this file

---

## Final Checklist

- [x] Verify report read (PASS WITH WARNINGS, 0 CRITICAL)
- [x] Main spec created: `openspec/specs/coach-link-lifecycle.md`
- [x] Delta spec consolidated into main spec (14 REQs preserved)
- [x] Change folder moved to archive with ISO date prefix
- [x] All 6 artifacts copied to archive folder
- [x] Carry-forward actions documented (T16 + T17)
- [x] Etapa 6 dependency noted
- [x] Archive report saved to engram and file

---

## SDD Cycle Complete

The `shared-with-trainer` change has successfully transitioned through all phases:

1. **Exploration** → identified approach and risks
2. **Proposal** → locked approach B (default + backfill) and scope
3. **Spec** → defined 14 REQs and 14 SCENARIOs
4. **Design** → merged into proposal (not separate phase needed)
5. **Tasks** → broke down into 17 tasks (15 code + 2 ops)
6. **Apply** → all code tasks implemented (PR #73, commit `fa42aa4`, merged to `main`)
7. **Verify** → passed with 0 CRITICAL, 2 WARNINGS, 1 SUGGESTION
8. **Archive** → consolidated specs, moved folder, documented carry-forward

**Status**: Ready for Etapa 6 to consume the `sharedWithTrainer` field as a privacy gate.

---

**Archived**: 2026-05-22  
**Generated by**: sdd-archive (hybrid mode — engram + openspec)
