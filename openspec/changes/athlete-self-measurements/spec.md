# Spec: athlete-self-measurements

> Phase: spec · Change: `athlete-self-measurements` · Project: treino · Store: hybrid
> Depends on: `proposal.md`, `design.md` (read in full — D1–D5 resolved by design, formalized here).
> This is a **full spec** — no prior `measurements` domain spec exists under `openspec/specs/`.
> Design's test matrix (§10: rules S1–S12, Dart T1–T6) is encoded 1:1 below as `REQ-ASM-*` / `SCENARIO-ASM-*`.
> Status: ready for `sdd-tasks`

---

## Purpose

Widen the `measurements` collection so an athlete without a trainer can self-log anthropometry
(weight, circumferences, body-fat, etc.) via the existing `LogMeasurementScreen` and model, while a
linked, consenting trainer keeps seeing those self-logged rows. This is an authorization +
vantage-plumbing change: no new collection, no new model field, no new Cloud Function.

### Out of Scope

- **Performance tests** (CMJ, sprint, VO2max) stay trainer-only; unaffected by this change.
- **Cross-party edit/delete.** Update/delete stay pinned to `recordedBy == uid`; no requirement here
  changes that each party edits only what they authored.
- **Trainer-change historical migration.** No backfill/migration of pre-existing self-logged docs;
  visibility is re-evaluated live against current share docs (see REQ-ASM-04), not migrated.

---

## Domain: Security — Firestore `measurements` Rules

### REQ-ASM-01: Widened create — athlete self-log branch (NEW), trainer branch preserved

The `measurements` create rule MUST accept a request when EITHER: (a) the requester is
authenticated, `recordedBy == request.auth.uid`, and `athleteId == request.auth.uid` (new
athlete-self branch — an athlete may only self-log about themselves), OR (b) the existing
trainer branch holds (`role == 'trainer'`), unchanged. `recordedBy == request.auth.uid` MUST be a
shared precondition of both branches. An authenticated athlete naming a DIFFERENT `athleteId` MUST
be denied regardless of role (AD-1 forge-vector regression).

> Test type: **emulator-only**

#### SCENARIO-ASM-01A: Athlete creates own measurement (happy path)

- GIVEN an authenticated athlete with uid `U`
- WHEN they create a `measurements` doc with `athleteId == U` and `recordedBy == U`
- THEN the create succeeds

#### SCENARIO-ASM-01B: Athlete forging another athlete's measurement is denied (AD-1 regression anchor)

- GIVEN an authenticated athlete-role user with uid `U`
- WHEN they attempt to create a `measurements` doc with `athleteId == V` (`V ≠ U`)
- THEN the create is denied, regardless of `recordedBy`

#### SCENARIO-ASM-01C: Trainer create is unchanged (legit-path anchor)

- GIVEN an authenticated user with `role == 'trainer'`
- WHEN they create a `measurements` doc with `recordedBy` equal to their own uid, for any `athleteId`
- THEN the create succeeds, exactly as before this change

---

### REQ-ASM-02: Author and subject read branches are unchanged

The existing `recordedBy == uid` (author) and `athleteId == uid` (subject) read branches MUST
continue to authorize reads exactly as before this change; neither is affected by the new
trainer-visibility branch (REQ-ASM-03).

> Test type: **emulator-only**

#### SCENARIO-ASM-02A: Trainer reads their own recorded doc

- GIVEN a doc with `recordedBy` equal to trainer `T`'s uid
- WHEN `T` requests to read it
- THEN the read succeeds (author branch)

#### SCENARIO-ASM-02B: Athlete reads their own self-logged doc

- GIVEN a self-logged doc with `athleteId == recordedBy == U`
- WHEN athlete `U` requests to read it
- THEN the read succeeds (subject branch)

---

### REQ-ASM-03: Trainer read of a self-logged measurement requires BOTH a live link AND consent

For a self-logged doc (`recordedBy == athleteId`), the read rule MUST additionally authorize a
trainer `T` iff BOTH fixed-path documents name `T`: `session_shares/{athleteId}.trainerId == T`
(live link) AND `profile_shares/{athleteId}.trainerId == T` (consent). Both conditions are
REQUIRED — either alone MUST deny. This gate MUST NOT reference the `sharedWithTrainer` boolean
field on `trainer_links` under any circumstance: it has zero writers and is always `false`
(ADR-ASM-2); gating on it would deny every trainer, permanently.

> Test type: **emulator-only**

#### SCENARIO-ASM-03A: Consented + live-linked trainer reads a self-logged doc

- GIVEN athlete `X` has `session_shares/X.trainerId == T` and `profile_shares/X.trainerId == T`
- AND a doc with `recordedBy == athleteId == X`
- WHEN trainer `T` requests to read it
- THEN the read succeeds

#### SCENARIO-ASM-03B: Linked but not consented is denied

- GIVEN `session_shares/X.trainerId == T` exists, `profile_shares/X` does NOT exist
- WHEN trainer `T` requests to read `X`'s self-logged doc
- THEN the read is denied

#### SCENARIO-ASM-03C: Consented but link gone is denied

- GIVEN `profile_shares/X.trainerId == T` exists, `session_shares/X` does NOT exist
- WHEN trainer `T` requests to read `X`'s self-logged doc
- THEN the read is denied

#### SCENARIO-ASM-03D: Unlinked and unconsented trainer is denied

- GIVEN neither `session_shares/X` nor `profile_shares/X` names trainer `T`
- WHEN trainer `T` requests to read `X`'s self-logged doc
- THEN the read is denied

---

### REQ-ASM-04: Visibility follows the CURRENT trainer, never one frozen at consent time

Trainer read-authorization for self-logged docs MUST be evaluated against the CURRENT
`session_shares` doc, not a trainer id frozen at a prior consent event. When an athlete switches
trainers, a previous trainer whose `profile_shares` entry is stale MUST lose access the moment
`session_shares` stops naming them, even if `profile_shares` has not been re-toggled.

> Test type: **emulator-only**

#### SCENARIO-ASM-04A: Stale old trainer is denied after the athlete switches trainers

- GIVEN athlete `X` switched trainers: `session_shares/X.trainerId == B` (current), and
  `profile_shares/X.trainerId == A` (stale, from before the switch)
- WHEN old trainer `A` requests to read `X`'s self-logged doc
- THEN the read is denied — the live-link conjunct naming `B` (not `A`) blocks `A` even while
  `profile_shares` is stale

---

## Domain: Data — Trainer-Vantage Measurement Query

### REQ-ASM-05: Trainer vantage MUST split into own (Q1) + self-logged (Q2) queries; no single `athleteId==X` query, no composite index

The trainer-vantage read path MUST keep two equality-only queries: Q1 (existing, unchanged)
`recordedBy == trainerUid AND athleteId == X`; Q2 (NEW) `athleteId == X AND recordedBy == X`
(self-logged only). A single `athleteId == X` query MUST NOT be used — it would also match a
PREVIOUS trainer's professional docs under the same athlete, which fail every read branch for the
CURRENT trainer and cause Firestore to deny the entire list (list-satisfiability). Neither query
MAY require a composite index — both use single-field equality filters only, with client-side
sorting.

> Test type: **emulator-only** (list behavior) + **unit** (query shape)

#### SCENARIO-ASM-05A: Consented+linked trainer's Q2 list succeeds and returns self-logged rows

- GIVEN trainer `T` is live-linked and consented for athlete `X` (both share docs name `T`)
- WHEN `T` runs the self-logged query `athleteId == X AND recordedBy == X`
- THEN the list succeeds and returns `X`'s self-logged docs

#### SCENARIO-ASM-05B: Non-consented trainer's Q2 list is denied in full

- GIVEN trainer `T` is NOT consented (or not linked) for athlete `X`
- WHEN `T` runs the same self-logged query
- THEN the entire list is denied (`permission-denied`), not silently filtered

#### SCENARIO-ASM-05C: `watchSelfLoggedForAthlete` query shape

- GIVEN the repository builds the self-logged query for athlete `X`
- WHEN the query is inspected
- THEN it filters `athleteId == X AND recordedBy == X` only, with no `orderBy` clause and no
  dependency on a composite index

---

### REQ-ASM-06: Trainer-vantage provider merges Q1 ∪ Q2, with Q2 error-tolerant

`measurementsForAthleteProvider` MUST merge the results of Q1 and Q2 into a single, ascending
`recordedAt`-sorted list. A `permission-denied` error from Q2 (non-consenting or non-linked
athlete) MUST NOT tear down the merged stream — the provider MUST degrade to Q1-only results
instead of throwing or emitting an error state.

> Test type: **unit**

#### SCENARIO-ASM-06A: Merged vantage shows both trainer-recorded and self-logged rows

- GIVEN athlete `X` has one trainer-recorded doc (matched by Q1) and one self-logged doc (matched
  by Q2)
- WHEN `measurementsForAthleteProvider` resolves for trainer `T`
- THEN both docs appear in the result, ordered ascending by `recordedAt`

#### SCENARIO-ASM-06B: Q2 permission-denied does not tear down the trainer's stream

- GIVEN the self-logged query (Q2) errors with `permission-denied`
- WHEN `measurementsForAthleteProvider` resolves
- THEN the provider still yields the Q1 (trainer-recorded) rows instead of throwing or emitting an
  error state

---

### REQ-ASM-07: Athlete's own vantage is unchanged

`ownMeasurementsProvider(uid)` (`athleteId == uid`) and its underlying rule branch (REQ-ASM-02B)
MUST continue to return both self-logged and trainer-recorded docs for that athlete, unaffected by
this change.

> Test type: **unit**

#### SCENARIO-ASM-07A: Own vantage returns both self-logged and trainer-recorded docs

- GIVEN athlete `U` has a self-logged doc and a trainer-recorded doc, both with `athleteId == U`
- WHEN `ownMeasurementsProvider(U)` resolves
- THEN both docs are returned

---

## Domain: UI — Self-Log Form & MEDIDAS Affordance

### REQ-ASM-08: `LogMeasurementScreen.selfLog()` produces a self-authored, self-attributed payload

`LogMeasurementScreen` MUST expose a named constructor `LogMeasurementScreen.selfLog()`, distinct
from the existing trainer-mode constructor. In self mode, the effective `athleteId` MUST be
derived from the authenticated uid — never from caller-supplied input — so the produced payload
always satisfies `recordedBy == athleteId == currentUid` (defense in depth alongside REQ-ASM-01).

> Test type: **widget**

#### SCENARIO-ASM-08A: Self-mode payload is self-authored and self-attributed

- GIVEN an athlete with uid `U` opens `LogMeasurementScreen.selfLog()`
- WHEN they fill and submit the form
- THEN the produced `Measurement` has `recordedBy == U` AND `athleteId == U`

---

### REQ-ASM-09: MEDIDAS screen exposes a self-log affordance

`measurements_screen.dart` (MEDIDAS) MUST render an "add" affordance that pushes
`LogMeasurementScreen.selfLog()` as a fullscreen dialog. No manual list refresh MAY be required —
`ownMeasurementsProvider` is a live stream and a new entry surfaces automatically on save.

> Test type: **widget**

#### SCENARIO-ASM-09A: Tapping the add affordance opens the self-log form

- GIVEN the athlete is on the MEDIDAS screen
- WHEN they tap the add ("+") affordance
- THEN `LogMeasurementScreen.selfLog()` is pushed as a fullscreen dialog

---

## I18n Requirements

New/changed strings for the self-log mode MUST go through `AppL10n` (3 ARB files:
`intl_es_AR.arb`, `intl_es.arb`, `intl_en.arb`). No hardcoded Spanish literals in the touched
widgets.

| Key | Purpose |
|-----|---------|
| `measurementsSelfLogNotesHint` | Notes field hint in self-log mode ("Notas (opcional)…"), replacing the trainer-mode "Observaciones del entrenador…" copy |
| `measurementsAddSelfLog` | Label/tooltip for the MEDIDAS "add" affordance |

(Form title "Cargar medición" is unchanged and reused across both modes — no new key needed.)

---

## Test Classification Summary

| REQ | Description | Test Type | Design Ref |
|-----|-------------|-----------|------------|
| REQ-ASM-01 | Widened create (athlete-self + trainer) | emulator-only | S1, S2, S3 |
| REQ-ASM-02 | Author/subject read unchanged | emulator-only | S9, S10 |
| REQ-ASM-03 | Dual-gate trainer read of self-logged docs | emulator-only | S4, S5, S6, S8 |
| REQ-ASM-04 | Visibility follows the current trainer | emulator-only | S7 |
| REQ-ASM-05 | Q1/Q2 split, no single query, no index | emulator-only + unit | S11, S12, T4 |
| REQ-ASM-06 | Provider merge, Q2 error-tolerant | unit | T1, T2 |
| REQ-ASM-07 | Athlete vantage unchanged | unit | T3 |
| REQ-ASM-08 | Self-log form payload | widget | T5 |
| REQ-ASM-09 | MEDIDAS add affordance | widget | T6 |

Gate: `flutter analyze` 0 issues + `dart format .` + tests green (AGENTS.md). Rules tests require
JDK 21 (`scripts/test_rules.sh`, per proposal §6).

---

## Handoff

`sdd-tasks` — decompose per proposal §7 review-workload forecast: **PR1** = REQ-ASM-01 through
REQ-ASM-04 (`firestore.rules` diff + `scripts/rules_test/measurements-self-log.test.js`,
RED→GREEN). **PR2** = REQ-ASM-05 through REQ-ASM-09 (repository Q2, provider merge, form
dual-mode, MEDIDAS affordance, ARB keys). Gate on `profile_shares` (+ `session_shares`), never the
dead `sharedWithTrainer` bool (ADR-ASM-2). No `firestore.indexes.json` change. No new Cloud
Function.
