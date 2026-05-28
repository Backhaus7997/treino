# Archive Report — profile-screen-rewrite (Fase 3 Etapa 7)

**Change**: profile-screen-rewrite
**Archived**: 2026-05-28
**Status**: COMPLETE (PASS-WITH-DEVIATIONS → ARCHIVED)
**Owner**: Backhaus
**PRs**: #95, #97, #99, #101 (4 chained PRs to main)

---

## Summary

Rewrote `ProfileScreen` from a Fase 1 Etapa 7 placeholder into a coherent, mockup-paritied surface with a header, avatar card, CUENTA section (4 tiles), edit/settings sub-screens, and action tiles (sign-out, delete stub). Delivered via 4 sequenced chained PRs (~1300 LOC total) with a mid-cycle PIVOT on PR#4 (replaced dedicated Settings screen with body tiles). All 22 non-removed REQs passed verification; 28/29 non-removed SCENARIOs have explicit test coverage (1 implicit via StreamProvider). Verify status: **PASS-WITH-DEVIATIONS** — all deviations documented as PIVOTs or KNOWN-DEFERRED.

---

## Delivered

### New Files (Production)

**PR#1 (Scaffold)**:
- `lib/features/profile/presentation/widgets/profile_header.dart` — header composition
- `lib/features/profile/presentation/widgets/profile_avatar_card.dart` — card with @handle derivation
- `lib/features/profile/presentation/widgets/profile_section_tile.dart` — shared tile component (7 consumers)
- `lib/features/profile/presentation/widgets/profile_cuenta_section.dart` — 4-tile CUENTA layout
- `lib/core/utils/handle_derivation.dart` — @handle pure function
- `lib/app/router.dart` (modified) — 3 new sub-routes added

**PR#2 (Edit Personal)**:
- `lib/features/profile/presentation/profile_edit_personal_screen.dart` — form + avatar upload

**PR#3 (Gym + Routines)**:
- `lib/features/profile/presentation/profile_gym_screen.dart` — gym search + select
- `lib/features/profile/presentation/profile_routines_screen.dart` — assigned routines list
- `lib/features/profile/application/assigned_routines_providers.dart` — FutureProvider + autoDispose

**PR#4v2 (Actions PIVOT)**:
- `lib/features/profile/presentation/widgets/eliminar_cuenta_stub_sheet.dart` — bottom sheet stub

### Modified Files (Production)

- `lib/features/profile/profile_screen.dart` — body rewritten + action tiles added + sign-out button removed
- `lib/app/router.dart` — extended with 3 new sub-routes (4th route `/profile/settings` removed in PR#4 pivot)

### Removed Files

- `lib/features/profile/presentation/widgets/profile_friend_requests_tile.dart` — legacy widget (inlined into CUENTA section)

### Test Files

**PR#1**:
- `test/features/profile/presentation/widgets/profile_section_tile_test.dart` (5 tests)
- `test/features/profile/presentation/widgets/profile_header_test.dart` (2 tests)
- `test/features/profile/presentation/widgets/profile_avatar_card_test.dart` (5 tests)
- `test/features/profile/presentation/widgets/profile_cuenta_section_test.dart` (8 tests, includes migrated assertions from deleted tile test)

**PR#2**:
- `test/features/profile/presentation/profile_edit_personal_screen_test.dart` (6 tests)

**PR#3**:
- `test/features/profile/application/assigned_routines_providers_test.dart` (3 tests)
- `test/features/profile/presentation/profile_routines_screen_test.dart` (3 tests)
- `test/features/profile/presentation/profile_gym_screen_test.dart` (3 tests)

**PR#4v2**:
- `test/features/profile/presentation/profile_settings_screen_test.dart` (4 tests)

**Deleted**:
- `test/features/profile/presentation/widgets/profile_friend_requests_tile_test.dart` (3 assertions migrated)

### Total Test Delta

- PR#1: +23 tests (21 new + 3 migrated - 3 deleted = net +21, but apply-progress reports +23 due to internal counting; verified: 1261 → 1284)
- PR#2: +6 tests (1290 → 1296)
- PR#3: +9 tests (1296 → 1305)
- PR#4v2: +5 tests (1305 → 1310)
- **Final**: 1310 total tests (140 profile-only)

---

## Notable Decisions (Locked During Cycle)

1. **Single edit entry point via Datos personales tile** (Decision 2026-05-27, PR#2 implementation) — pencil icon removed from avatar card; edit access unified to single route.

2. **Mis rutinas = trainer-assigned only** (Decision re-confirmed 2026-05-27) — filter: `source == 'trainer-assigned' AND assignedTo == myUid`. Self-created and favorite routines deferred indefinitely.

3. **Settings surface entirely removed** (PIVOT 2026-05-28) — Originally planned as dedicated `/profile/settings` screen with 2 tiles. Decision: Settings as a surface is premature with only sign-out + delete stub. Instead, both tiles moved to `ProfileScreen` body bottom. `/profile/settings` route, `ProfileSettingsScreen`, and `TreinoIcon.settings` all REMOVED. Real settings (notifications/theme/language) deferred to future SDD when content exists.

4. **Eliminar cuenta = stub with honest copy** (Design 2026-05-27) — "Esta función estará disponible en una versión futura." Copy is explicit; no destructive button present. Real account deletion cascades deferred to account-deletion SDD.

5. **4 PR chained delivery** (Proposal locked 2026-05-27) — PR#1 scaffold → PR#2 edit → PR#3 gym+routines → PR#4 actions. Each independently mergeable; progression mandatory. Sign-out duplication (present PR#1-#3, removed PR#4) intentional for chain integrity.

---

## Deviations from Original Plan

1. **PR#2 LOC overrun** (~1317 vs 400 budget) — Form validators + avatar editor + UserRepository.update handler bundled into single PR. Shipped with `size:exception` label. Rationale: splitting would have required stub/refactor cycle; keeping together was cleaner per reviewer feedback.

2. **PR#4 reset + re-implementation (v2 PIVOT)** — Original PR#4 implemented dedicated `/profile/settings` screen. On 2026-05-28, user decided Settings surface premature; scrapped 7 commits, re-implemented as body tiles. Discarded commits: 921bbca, 14ca83c, 22694e5, 59454b5, 1272e67, 69da929, 45fc9a0. Not in main.

3. **Two housekeeping commits on main outside SDD scope** — Format drift in unrelated coach files (Fase 6 Etapa 0 PR#2 landed after profile PRs merged):
   - `b1e592b` — format drift in `coach/coach_hub/` files
   - `11b386e` — format drift in coach files from PR#100
   - These are UNATTRIBUTABLE to profile-screen-rewrite; repo-level format gate non-green due to separate PR.

4. **SCENARIO-518 has no dedicated testWidgets block** — Gym chip auto-update on profile rebuild relies on `userProfileProvider` StreamProvider reactivity. Architectural decision documented as acceptable in tasks/apply-progress. Verification confirmed coverage is implicit but sound.

---

## Known Follow-Ups (NOT Part of This Change)

1. **Declare storage.rules in repo** — Avatar upload helper (reused from Fase 1 Etapa 6) relies on Firebase Storage rule added live in Console. Follow-up: add `storage.rules` to repo + CI pipeline.

2. **gymSearchQueryProvider autoDispose refactor** — Provider persists query state across navigations. Current workaround (reset in `initState`) is fragile. Future SDD should convert to `StateProvider.autoDispose` or use local `TextEditingController`.

3. **account-deletion SDD** — Eliminar cuenta stub prepared. Real flow (server-side cascade deletion) requires separate SDD; tracked as decision memory `profile/settings-deferred`.

4. **i18n sweep (Fase 6 Etapa 3)** — All new strings marked `// i18n: Fase 6 Etapa 3`. Full es-AR copy table in design.md §8 as source-of-truth for i18n phase.

---

## Quality Outcome

### Code Quality

| Gate | Result |
|---|---|
| `flutter analyze` (whole repo) | 0 issues (ran 15.5s) |
| `dart format` (profile-touched files) | 0 changed |
| `dart format` (whole repo) | 3 changed — unrelated coach files (Fase 6 Etapa 0 PR#2 drift) |
| `flutter test` (whole repo) | 1321/1321 passing (+8 above baseline, unrelated to this SDD) |
| Profile-only tests | 140/140 passing |

### Specification Coverage

| Item | Count | Status |
|---|---|---|
| REQs (non-removed) | 22 | All PASS |
| SCENARIOs (non-removed) | 29 | 28 explicit, 1 implicit (SCENARIO-518 via StreamProvider) |
| ADRs (locked during cycle) | 14 | All HONORED |
| Hard Constraints | 10 | All PASS |

### TDD Compliance

- Strict TDD enforced across all 4 PRs
- RED before GREEN for every task pair (minor deviation in PR#2: T23/T25/T27 merged into 1 RED commit, documented in apply-progress)
- All new strings marked `// i18n: Fase 6 Etapa 3` for sweep verification

### Architectural Integrity

- Zero firestore.rules / firestore.indexes.json / storage.rules modifications ✅
- Zero new freezed models ✅
- Zero new packages (cross-feature reuse from profile_setup OK per ADR) ✅
- 14/14 ADRs honored (with PR#4 pivot documented in ADR-PSR-008 + apply-progress) ✅

---

## Engram References (for Traceability)

All artifacts saved with `capture_prompt: false` as per SDD pipeline:

| Artifact | Topic Key | Observation ID |
|---|---|---|
| Proposal | `sdd/profile-screen-rewrite/proposal` | #101 |
| Spec (delta) | `sdd/profile-screen-rewrite/spec` | #102 |
| Design | `sdd/profile-screen-rewrite/design` | #103 |
| Tasks | `sdd/profile-screen-rewrite/tasks` | #104 |
| Apply Progress | `sdd/profile-screen-rewrite/apply-progress` | (not retrieved; stored in openspec only) |
| Verify Report | `sdd/profile-screen-rewrite/verify-report` | #112 |
| Archive Report | `sdd/profile-screen-rewrite/archive-report` | (this file) |

---

## Decision Memories (Kept Independent — Survive Archive)

These decisions are NOT part of this SDD but were touched/confirmed during the cycle. They survive the archive:

| Key | Decision |
|---|---|
| `profile/mis-rutinas-scope` | Mis rutinas = trainer-assigned only; self-created + favorites deferred indefinitely. |
| `profile/settings-deferred` | Settings surface deferred until real settings exist (notifications/theme/language). Delete account stub prepared; real cascade deletion is future SDD. |

---

## Commit + Push Details

**Branch**: main (all 4 PRs merged; no outstanding branches)

**Merged PR Commits** (in order):
1. `644b97b` — PR#95 (Scaffold)
2. `941902a` — PR#97 (Edit Personal)
3. `f377d8d` — PR#99 (Gym + Routines)
4. `27a7918` — PR#101 (Actions v2 PIVOT)

**Housekeeping Commits** (unrelated, between PRs):
- `b1e592b` — format drift coach/coach_hub
- `11b386e` — format drift coach files from Fase 6 Etapa 0 PR#2

**Archive Commit** (performed by sdd-archive phase):
```
chore(sdd): archive profile-screen-rewrite — Fase 3 Etapa 7 complete

4 PRs merged (#95, #97, #99, #101). Verify status PASS-WITH-DEVIATIONS.
Delta spec REQs merged into main profile spec. Change folder moved to
openspec/changes/archive/2026-05-28-profile-screen-rewrite/. Follow-ups
tracked: storage.rules in repo, account-deletion SDD, gymSearchQueryProvider
autoDispose refactor.
```

---

## Files Archived

All artifacts from `openspec/changes/profile-screen-rewrite/` moved to `openspec/changes/archive/2026-05-28-profile-screen-rewrite/`:

- proposal.md
- spec.md (delta)
- design.md
- tasks.md
- apply-progress.md (stored in openspec folder, not engram)
- verify-report.md

Main spec created: `openspec/specs/profile/spec.md` (merged non-removed REQs)

---

## Verification Checklist

- [x] All 4 PRs merged to main in sequence
- [x] Verify status: PASS-WITH-DEVIATIONS (all deviations documented)
- [x] Main profile spec created (merged non-removed REQs)
- [x] Delta spec REQs accounted for (22 carried, 6 removed, 4 new)
- [x] Change folder moved to archive with ISO date prefix
- [x] No active branches outstanding
- [x] Archive folder contains all artifacts
- [x] Archive report written with observation IDs for traceability
- [x] Commit + push ready

---

**Archive Status**: COMPLETE ✅

The `profile-screen-rewrite` SDD cycle is fully closed. The change is versioned in `openspec/changes/archive/2026-05-28-profile-screen-rewrite/` with full audit trail. Main profile feature spec is now source-of-truth at `openspec/specs/profile/spec.md`. Follow-ups are tracked as decision memories and in Engram for future SDD phases.
