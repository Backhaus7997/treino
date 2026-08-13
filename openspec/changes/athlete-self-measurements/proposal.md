# Proposal: athlete-self-measurements

> Phase: propose · Change: `athlete-self-measurements` · Project: treino · Store: hybrid
> Depends on: none (no `sdd/athlete-self-measurements/explore` artifact — direct user intent)
> Status: ready for `sdd-spec` + `sdd-design` (parallel). **Design MUST resolve the central read-visibility decision (§4 D1) — this proposal deliberately does NOT pick a winner.**

---

## 1. Intent & motivation

**Problem.** Body measurements are COACH-owned. `firestore.rules:992-996` requires the creator to be `role == 'trainer'` (a residual of `rules-hardening` Slice C / AD-1), so an athlete WITHOUT a trainer cannot log their own weight/waist/body-fat. The whole read surface exists (`lib/features/insights/presentation/measurements_screen.dart`, read-only today) but it can only ever show data a PF entered. A solo user has an empty, un-fillable screen.

**Why now.** We want the Hevy-style loop: any athlete tracks their own anthropometry, no trainer required. The model and the form already exist — this is mostly an authorization + vantage-plumbing change, not a new feature build.

**The hard constraint (user-locked).** A linked trainer MUST still see the measurements an athlete self-logged. This is what makes it non-trivial: a naive "let athletes write" reopens the AD-1 forge vector AND makes the data invisible to the PF (see §3).

**Success looks like.** A user with no trainer opens MEDIDAS, taps "add", logs weight/circumferences, and sees the entry. A user WITH a linked trainer does the same, and the trainer sees those self-logged entries in the athlete's detail view — without the athlete being able to write measurements about anyone else.

---

## 2. Scope

### In scope

- **Widen `measurements` create** (`firestore.rules:992-996`) so an athlete can create a measurement about THEMSELVES (`athleteId == uid && recordedBy == uid`), as a new OR-branch alongside the existing trainer-role branch. Mirror the dual-branch pattern already used by `appointments` create (`rules-hardening` task 3.6: athlete-self-book branch OR trainer+role branch).
- **Make self-logged measurements readable by the linked trainer** — the central problem (§3). Requires BOTH a read-rule change AND a trainer-vantage query change.
- **Reuse `LogMeasurementScreen`** (`lib/features/measurements/presentation/log_measurement_screen.dart`) in an athlete-authored mode: `recordedBy = athleteUid`, drop the `trainerUid != null` gate for that mode, still call `measurementRepositoryProvider.add(...)`.
- **Add an "add measurement" affordance** to `measurements_screen.dart` (MEDIDAS) so the athlete can open the form.
- **Trainer-vantage read plumbing** — `measurementsForAthleteProvider` / `watchForTrainerAthlete` currently query `recordedBy == trainerUid` (`lib/features/measurements/application/measurement_providers.dart`, `lib/features/measurements/data/measurement_repository.dart`); that query structurally EXCLUDES self-logged docs (`recordedBy == athleteUid`). Reshape so the trainer sees athlete-authored rows too.
- **RED→GREEN rules tests** in `scripts/rules_test/` for the widened create + new read visibility.

### Out of scope (explicit)

- **Performance tests** stay trainer-only (`firestore.rules:1005-1024`). Professional assessments (CMJ, sprint, VO2max) are NOT athlete-writable. Only `measurements` change.
- **Editing/deleting the other party's measurements.** Existing update/delete pin `recordedBy == uid` (`firestore.rules:997-1002`) — each party edits only what they authored. No cross-party mutation.
- **Trainer-change historical migration.** What happens to already-self-logged docs when an athlete switches trainers is a KNOWN design risk (§5 R2), NOT a migration deliverable here.
- No new measurement fields — the model (`lib/features/measurements/domain/measurement.dart`, freezed, ~20 fields incl. `weightKg`/`fatPercentage`/`muscleMassKg`/circumferences/`notes`) is already complete.

---

## 3. Central architecture problem (design MUST resolve — no winner chosen here)

When an athlete self-logs, they are BOTH `recordedBy` AND `athleteId`. Two independent gaps open:

- **(A) Read-rule gap.** Current read (`firestore.rules:984-986`) is `recordedBy == uid || athleteId == uid`. For a self-logged doc both operands equal the athlete's uid → ONLY the athlete can read it. The linked trainer is denied.
- **(B) Query-vantage gap.** Even if the rule allowed it, the trainer's list query is `recordedBy == trainerUid`. A self-logged doc has `recordedBy == athleteUid`, so it never appears in the trainer's result set. The rule and the query must move together, or the trainer silently sees nothing.

### Candidate directions (tension laid out; DECISION deferred to `sdd-design`)

| # | Direction | Upside | Tension / open risk |
|---|-----------|--------|---------------------|
| C1 | **Denormalize current trainer id** onto the doc at write time (e.g. `sharedWithTrainerId`). Read rule adds `\|\| uid == resource.data.sharedWithTrainerId`; trainer query switches to `sharedWithTrainerId == trainerUid` (or `athleteId ==`). | One field, NO rule-time `get()`, cheap `list` queries — aligns with `rules-hardening` AD-1's explicit no-`get()`-on-coach-collections stance. | On trainer change, old docs still point at the OLD trainer (R2). Athlete must know the active trainer id at write time (needs the link). |
| C2 | **linkId-in-doc + `get()`** — the pattern `reviews` uses (`firestore.rules:1222-1227`: `${linkId}_${athleteId}` doc id + `get(/trainer_links/$(linkId))`). | Survives trainer change conceptually; no denormalized trainer id. | AD-1 explicitly REJECTED per-doc `get()` for coach collections (per-doc cost in `list` queries). `trainer_links` doc ids are AUTO-GENERATED (`firestore.rules:292-293`), so the deterministic-id trick reviews rely on doesn't transfer cleanly. |
| C3 | **Athlete-owned + membership check** — read rule authorizes any trainer holding an active `trainer_links` doc to the `athleteId` (relationship lookup). | No trainer-id denormalization; visibility follows the live link. | Same per-doc `get()` / `list`-query cost as C2; auto-generated link ids make "the" link non-deterministic to name in a rule. |

**Relevant existing asset for design:** `trainer_links` already carries an **athlete-controlled `sharedWithTrainer` privacy flag** (`firestore.rules:336-337` — only the athlete may flip it, the PF never can). Design should decide whether self-logged visibility RESPECTS this existing consent surface rather than inventing a new one.

**Create-rule constraint (all directions).** The widened create MUST let an athlete create ONLY about themselves. The athlete branch must pin `athleteId == request.auth.uid && recordedBy == request.auth.uid`; an athlete naming ANOTHER `athleteId` stays denied (do NOT reopen the AD-1 forge vector). Keep the existing trainer+role branch intact.

---

## 4. Key decisions deferred to design

| # | Deferred decision | Owner |
|---|-------------------|-------|
| D1 | **Read-visibility mechanism: C1 vs C2 vs C3.** THE central call. No winner chosen in this proposal. | `sdd-design` |
| D2 | **Trainer-change semantics.** Do already-self-logged docs become visible to a NEW trainer, stay with the old one, or go athlete-private? Mechanism (D1) drives the default answer. | `sdd-design` |
| D3 | **Consent surface.** Does self-logged→trainer visibility gate on the existing `sharedWithTrainer` flag, or is it unconditional for any active link? | `sdd-design` |
| D4 | **Trainer-vantage query reshape + index.** `recordedBy == trainerUid` → `athleteId ==` or `sharedWithTrainerId ==`; does the new query need a composite index? | `sdd-design` + `sdd-spec` |
| D5 | **`LogMeasurementScreen` dual-mode contract.** How the athlete-authored mode is signalled (nullable `trainerUid`? explicit mode enum?) and how the "add" affordance on MEDIDAS opens it. | `sdd-spec` |

---

## 5. Risks

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| R1 | **Widened create reopens the AD-1 forge vector** — a sloppy athlete branch lets an athlete write measurements about ANOTHER athlete. | **High** | Athlete branch pins `athleteId == uid && recordedBy == uid`. RED test: athlete forging a measurement for another `athleteId` MUST `assertFails`. Legit-path anchor: trainer create still `assertSucceeds`. |
| R2 | **Trainer-change historical visibility gap** (esp. C1 denormalization) — old self-logged docs point at the previous trainer; the new trainer can't see history. | Medium | OUT OF SCOPE to migrate. Flagged as D2 for an explicit design ruling; documented residual, not silently dropped. |
| R3 | **Per-doc `get()` cost on trainer `list` queries** (C2/C3). | Medium | AD-1 already weighed this against coach collections; design picks with that cost in view. |
| R4 | **Rule/query mismatch** — read rule widened but trainer query still `recordedBy ==` → PF silently sees nothing. | Medium | Scope item pairs rule + query (D4). Dart test: trainer vantage surfaces a self-logged doc via `fake_cloud_firestore`. |
| R5 | **Form regression** — `LogMeasurementScreen`'s `trainerUid != null` validation blocks athlete mode, or athlete-mode writes leak a null `recordedBy`. | Low | Widget test for athlete-authored mode; assert `recordedBy == athleteUid` on the produced payload. |

---

## 6. Testing / TDD

**Firestore rules (RED→GREEN, strict TDD in `scripts/rules_test/rules.test.js`).** Follows the same stack as `rules-hardening` Slice C.
- Env note: the suite needs **JDK 21** — `openjdk@21` is brew-installed but unlinked; `export JAVA_HOME="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"` before `scripts/test_rules.sh`.
- RED scenarios: (a) athlete self-create allowed; (b) athlete forging ANOTHER athlete's measurement denied (R1 / AD-1 regression); (c) linked trainer READS an athlete self-logged doc; (d) unlinked trainer CANNOT read it. Legit anchor: trainer create/read unchanged (must stay green).

**Dart.** `fake_cloud_firestore` for repo/provider — assert the reshaped trainer-vantage query (D4) surfaces self-logged docs and the athlete vantage is unchanged. Widget test for `LogMeasurementScreen` athlete-authored mode (R5).

Gate: `flutter analyze` 0 issues + `dart format .` + tests green (per AGENTS.md).

---

## 7. Review Workload Forecast

| Slice | Content | Est. |
|-------|---------|------|
| PR 1 — rules + rules-tests | `firestore.rules` measurements create+read diff, `scripts/rules_test/` RED→GREEN | ~120-180 |
| PR 2 — client | form dual-mode, MEDIDAS add affordance, trainer-vantage query reshape (repo+provider), Dart/widget tests, ARB keys | ~250-380 |

**Chained PRs recommended: Yes** (rules first, client second — client depends on the shipped rule). **400-line budget risk: Medium** — PR 2 approaches the budget; `sdd-tasks` confirms the split. **Decision needed before apply: Yes** — D1 (read-visibility mechanism) is a hard gate; the client query shape (D4) depends on it.

---

## 8. Handoff to next phases

- **`sdd-spec`** — formalize (mirroring `openspec/specs/*/spec.md` scenario style): widened create requirement (athlete-self branch + preserved trainer branch), trainer read-visibility requirement, trainer-vantage query contract (D4), form dual-mode behavior (D5). Reference `coach-collections-security` spec for scenario shape.
- **`sdd-design`** — **RESOLVE D1** (C1/C2/C3, with the AD-1 `get()`-cost tradeoff explicit), rule the trainer-change semantics (D2), the `sharedWithTrainer` consent question (D3), and the query reshape + index decision (D4). This is the architecture call the proposal deliberately left open.

Spec and design proceed in parallel; both depend only on this proposal. Design output gates the client query shape.
