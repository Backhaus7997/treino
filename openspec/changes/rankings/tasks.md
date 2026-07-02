# Tasks: Per-Gym Rankings (rachas / volumen / main lifts)

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~1450-1650 total (5 slices) |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR 1 → PR 2 → PR 3 → PR 4 → PR 5 (see Suggested Work Units) |
| Delivery strategy | ask-on-risk |
| Chain strategy | pending |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: pending
400-line budget risk: High

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Profile model fields + indexes | PR 1 | ~150-200 LOC. Base: main (or tracker branch if feature-branch-chain). Low risk, additive-only. |
| 2 | Family map + finish() denorm | PR 2 | ~350-420 LOC incl. idempotency tests. Base: PR 1. **HIGH RISK** — borderline on budget alone. |
| 3 | Opt-in toggle + backfill | PR 3 | ~300-380 LOC incl. backfill tests. Base: PR 2. |
| 4 | Ranking queries + UI + route | PR 4 | ~450-550 LOC (screen + 3 providers + widget tests). Base: PR 3. **Largest slice — may need its own sub-split (providers vs UI).** |
| 5 | Docs flip | PR 5 | ~5-10 LOC. Base: PR 4. Trivial, could ride with PR 4 instead if reviewer prefers fewer hops. |

## Phase 1: Model + Indexes (Slice 1 — PR 1)

- [x] 1.1 RED: `test/features/profile/domain/user_public_profile_test.dart` — add cases for `rankingOptIn` default `false`, `lifetimeVolumeKg` default `0`, `bestSquatKg/bestBenchKg/bestDeadliftKg` nullable/default, round-trip `toJson`/`fromJson` (spec: Collection Schema scenario "Opted-out athlete has no ranking metrics").
- [x] 1.2 GREEN: Modify `lib/features/profile/domain/user_public_profile.dart` — add `@Default(false) bool rankingOptIn`, `@Default(0) num lifetimeVolumeKg`, `num? bestSquatKg`, `num? bestBenchKg`, `num? bestDeadliftKg`.
- [x] 1.3 Run `dart run build_runner build --delete-conflicting-outputs` to regen `user_public_profile.freezed.dart` / `.g.dart`.
- [x] 1.4 Modify `firestore.indexes.json` — add 5 composite indexes: `(gymId ASC, rankingOptIn ASC, racha DESC)`, `(gymId ASC, rankingOptIn ASC, lifetimeVolumeKg DESC)`, `(gymId ASC, rankingOptIn ASC, bestSquatKg DESC)`, `(gymId ASC, rankingOptIn ASC, bestBenchKg DESC)`, `(gymId ASC, rankingOptIn ASC, bestDeadliftKg DESC)`.
- [x] 1.5 Quality gate: `flutter analyze` 0 issues, `dart format .`, `flutter test test/features/profile/domain/user_public_profile_test.dart` green.
- [x] 1.6 Operator note: after merge, run `firebase deploy --only firestore:indexes` — indexes build asynchronously; do NOT gate PR merge on index build completion, but Slice 4 queries will fail until they're ready. **NOT YET DEPLOYED — deferred to operator step, tracked in apply-progress.**

## Phase 2: Family Map + Session-Finish Denormalization (Slice 2 — PR 2, HIGH RISK)

- [x] 2.1 **VERIFY family membership against catalog before writing code**: confirmed ids in `docs/video-catalog-audit/NUEVO-catalogo.json` are `squat-barra` ("Sentadilla (Barra)"), `bench-press-barra` ("Press de banca (Barra)"), `deadlift-barra` ("Peso muerto (Barra)" — convencional), `sumo-deadlift-barra` ("Peso muerto sumo (Barra)"). **CORRECTION vs design.md**: design's placeholder id `deadlift-sumo` does NOT exist in the catalog — the real id is `sumo-deadlift-barra`. Deadlift family = `{deadlift-barra, sumo-deadlift-barra}` (max of the two, per LOCKED decision). Squat/bench = single-id sets.
- [x] 2.2 RED: `test/features/gym_rankings/domain/main_lift_family_map_test.dart` — cases: `squat-barra` matches squat family; `bench-press-barra` matches bench family; `deadlift-barra` AND `sumo-deadlift-barra` both match deadlift family (returns max of the two); dumbbell/multipower/machine variants (e.g. `squat-multipower`, `bench-press-mancuerna`) do NOT match any family; `romanian-deadlift-barra`/`stiff-leg-deadlift-barra` (rumano/stiff) do NOT match deadlift family; empty/no-match logs → `familyMaxWeight` returns `null`.
- [x] 2.3 GREEN: Create `lib/features/gym_rankings/domain/main_lift_family_map.dart` — `enum MainLift { squat, bench, deadlift }`, `const kMainLiftFamilies = <MainLift, Set<String>>{...}` (ids from 2.1), `double? familyMaxWeight(MainLift lift, List<SetLog> logs)`.
- [x] 2.4 RED: `test/features/workout/data/session_repository_test.dart` — add cases (fake_cloud_firestore) per spec `gym-rankings`/`user-public-profiles-layer` scenarios: (a) opt-in ON + finish → `lifetimeVolumeKg` increments by `totalVolumeKg` over the recompute window; (b) opt-in ON + new squat PR → `bestSquatKg` raised to new max; (c) opt-in ON + lower-weight session → `bestSquatKg` unchanged (max-merge, not overwrite); (d) opt-in OFF → none of the 4 ranking fields written/changed; (e) **idempotency**: simulate retry of the same finished session (re-invoke the best-effort block for session S) → `lifetimeVolumeKg` reflects `totalVolumeKg` exactly once, `best<Lift>Kg` unchanged by the retry.
- [x] 2.5 GREEN: Modify `lib/features/workout/data/session_repository.dart` `finish()` — inside the existing best-effort try block (session_repository.dart:99-130), after computing `completedList`/`racha`: read `rankingOptIn` from the athlete's own profile; if `true`, RECOMPUTE `lifetimeVolumeKg = Σ completedList.totalVolumeKg` over the SAME `completedList` window (no new full-collection read), read setLogs for those sessions (new per-session setLogs read, bounded to the same window), compute `familyMaxWeight` per `MainLift` via `kMainLiftFamilies`, merge `best<Lift>Kg = max(stored, thisWindowMax)`; call `pubRepo.updateCounters` with the additional fields only when opted in.
- [x] 2.6 Quality gate: `flutter analyze` 0 issues, `dart format .`, `flutter test test/features/gym_rankings/domain/main_lift_family_map_test.dart test/features/workout/data/session_repository_test.dart` green.

## Phase 3: Opt-In Toggle + Backfill (Slice 3 — PR 3)

- [ ] 3.1 RED: `test/features/profile/data/user_public_profile_repository_test.dart` — add cases for `setRankingOptIn(uid, true)` merges `rankingOptIn: true` without clobbering other fields; a clear-helper resets `lifetimeVolumeKg`/`best<Lift>Kg` to `0`/absent and `rankingOptIn: false`.
- [ ] 3.2 GREEN: Modify `lib/features/profile/data/user_public_profile_repository.dart` — add `setRankingOptIn(String uid, bool value)` and a clear-on-disable helper (both via existing `updateCounters` merge path).
- [ ] 3.3 RED: `test/features/profile/application/ranking_optin_controller_test.dart` — cases per `gym-rankings` spec scenarios: ENABLE computes `lifetimeVolumeKg` = Σ over own session history and `bestSquatKg/bestBenchKg/bestDeadliftKg` from own SetLog history (reuse `aggregateExerciseProgression` per family, 0 if no matching lifts) in one client-side pass; DISABLE clears all 4 fields; ENABLE does NOT recompute `racha` (already denormalized).
- [ ] 3.4 GREEN: Create `lib/features/profile/application/ranking_optin_controller.dart` — `enableRankingOptIn(uid)` (backfill via own session/SetLog history, family map from Phase 2) and `disableRankingOptIn(uid)` (clear via 3.2 helper).
- [ ] 3.5 Quality gate: `flutter analyze` 0 issues, `dart format .`, `flutter test test/features/profile/data/user_public_profile_repository_test.dart test/features/profile/application/ranking_optin_controller_test.dart` green.

## Phase 4: Ranking Queries + UI + Route (Slice 4 — PR 4)

- [ ] 4.1 RED: `test/features/gym_rankings/application/ranking_providers_test.dart` — per-dimension query providers (streak/volume/squat/bench/deadlift) with `ProviderScope.overrides`: correct ordering (desc by metric), gym scoping (excludes other gyms), excludes non-opted-in athletes, excludes `kNoGymId`/null gym, empty-gym returns empty list (not error).
- [ ] 4.2 GREEN: Create `lib/features/gym_rankings/application/ranking_providers.dart` — Riverpod providers per dimension: `userPublicProfiles.where(gymId==myGym).where(rankingOptIn==true).orderBy(<metric>, desc).limit(N)`.
- [ ] 4.3 RED: `test/features/gym_rankings/presentation/rankings_screen_test.dart` — widget tests: 3 dimensions render (rachas/volumen/lifts), lift sub-split (squat/bench/deadlift), loading/error/empty states, uses `AppPalette.of(context)` (no hex) and `TreinoIcon.X` (no `PhosphorIcons`) per project standards.
- [ ] 4.4 GREEN: Create `lib/features/gym_rankings/presentation/rankings_screen.dart` — 3-dimension screen reusing existing list/card patterns.
- [ ] 4.5 Modify `lib/app/router.dart` — add `/profile/rankings` GoRoute (sibling of `edit-personal`/`gym`/`routines`) and an opt-in toggle entry point in ProfileScreen wired to `ranking_optin_controller` (Phase 3).
- [ ] 4.6 Quality gate: `flutter analyze` 0 issues, `dart format .`, `flutter test test/features/gym_rankings/ test/app/router_test.dart` (or equivalent router test path) green.

## Phase 5: Docs (Slice 5 — PR 5)

- [ ] 5.1 Modify `docs/product.md` line 55 — remove `Ranking (global, semanal, mensual, gym)` from the "Out of scope — NO implementar" list (per-gym opt-in ranking is now implemented; global/semanal/mensual variants remain genuinely out of scope — clarify the line rather than deleting the whole bullet if any of those sub-variants are still excluded).
- [ ] 5.2 Quality gate: `dart format .` (docs-only, no analyze/test impact expected).

## Rules Applied

- Every impl task preceded by its RED (failing test) task in the same slice — Strict TDD.
- `build_runner` regen included wherever `@freezed`/`@Default` fields change (Phase 1 only — no other slice touches freezed models).
- Composite indexes flagged as an operator/deploy step (`firebase deploy --only firestore:indexes`), separate from code merge, since indexes build asynchronously and Slice 4 depends on them being ready before ranking queries return correct results in production.
- HIGH-RISK tasks called out: 2.1 (family-map catalog-id verification — one correction found and applied), 2.4/2.5 (idempotent recompute — no-double-count + opt-in on/off), 3.3/3.4 (enable-backfill over full history).
