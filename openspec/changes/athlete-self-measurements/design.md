# Technical Design: athlete-self-measurements

> Phase: design · Change: `athlete-self-measurements` · Project: treino · Store: hybrid
> Depends on: `sdd/athlete-self-measurements/proposal` (proposal.md, read in full — §3 central problem, §4 D1–D5).
> Pairs with: `sdd/athlete-self-measurements/spec` (REQ-ASM-*). Feeds: `sdd-tasks`.
> Resolves the deferred decisions the proposal deliberately left open: **D1** (read-visibility mechanism),
> **D2** (trainer-change semantics), **D3** (consent surface), **D4** (query reshape + index), **D5** (form dual-mode).
> The two PRODUCT decisions locked by the user (D3 = consent-gated; D2 = visibility follows the live link) are
> honored, not re-opened. This is the HOW.

---

## 0. VERDICT — the read-authorization mechanism

**Chosen mechanism: DUAL FIXED-PATH SHARE-DOC GATE.** A trainer may read an athlete's *self-logged* measurement
only when **both** existing per-athlete share docs name that trainer:

- `session_shares/{athleteId}` — the **live-link** signal, maintained by the existing Cloud Function
  `syncSessionShareOnTrainerLink` (`functions/src/sync-session-share.ts`) on every `trainer_links` write. Encodes
  "there is a currently-**active** link to trainer T." → satisfies **D2**.
- `profile_shares/{athleteId}` — the **consent** signal, written/deleted by the athlete via the existing
  "Compartir mis datos con mi entrenador" toggle (`ProfileShareToggleTile` → `ProfileShareRepository.grant/revoke`).
  This is the surface that **already shares the athlete's weight/height** (`bodyWeightKg`, `heightCm`) with the
  trainer. → satisfies **D3**.

Both are FIXED-path, per-athlete documents. The read rule does one `get()` to each; because a trainer's
measurement-history query is already scoped to a single `athleteId`, both paths are constant across the whole
list → Firestore caches each `get()` → **~2 document reads for the ENTIRE history list, not per-doc.** This is the
same idiom already live in production for the `setLogs` list gate (`firestore.rules:849-855`, exercise-progression
design §0 "linked lists → allowed"), so the cost profile is proven, not theoretical.

This directly beats the AD-1 objection (rules-hardening `design.md` AD-1, tasks 3.3/3.6): AD-1 rejected per-doc
`get()` on coach-collection **list** queries because the `get()` path there varied per document (e.g. a per-review
`linkId`), billing one extra read *per row*. Here the path is fixed by the query's own `athleteId` filter, so the
cost is O(1) for the list, not O(n). **We are not violating AD-1; we are using the one shape AD-1's cost argument
does not apply to.**

### The blocking finding the user must acknowledge (D3 field-name correction — product intent unchanged)

The user's D3 says to gate on "the `sharedWithTrainer` flag on the trainer_link (the same flag that today shares
profile weight/height)." **That field does not do what the instruction assumes, and cannot be used in a rule.**
Evidence gathered this phase:

1. **`sharedWithTrainer` is dead code.** It has ZERO callers. `TrainerLinkRepository.setSharedWithTrainer` is never
   invoked anywhere in `lib/`, and `lib/features/coach/application/trained_today_provider.dart:54-56` states it
   literally: *"The old `sharedWithTrainer == true` gate was DEAD — setSharedWithTrainer has zero callers, so the
   flag was always false."* Gating on it would gate every trainer read **OFF**, permanently.
2. **It is un-`get()`-able in a rule.** `trainer_links` doc ids are AUTO-GENERATED (`firestore.rules:291-293`), and
   rules cannot run queries. There is no deterministic path a rule can `get()` to find "the active link with
   `sharedWithTrainer == true` between athlete X and trainer T." (This is exactly why proposal C2/C3 are dead ends.)
3. **The surface that ACTUALLY shares weight/height today is `profile_shares/{athleteId}`** — a fixed-path,
   athlete-controlled doc (`grant`/`revoke`) whose body already carries `bodyWeightKg` + `heightCm`
   (`ProfileShareRepository`, `firestore.rules:812-831`). This *is* the "athlete-controlled consent that shares
   weight/height" the user is describing; the name in the instruction is just wrong.

**Resolution.** The design HONORS D3's product intent verbatim — consent-gated, athlete-controlled, reusing the
EXISTING surface that shares weight/height, inventing NO new consent surface — by mapping it to the concrete doc
that fulfils that description: `profile_shares/{athleteId}`. The product decision ("consent is required, via the
existing weight/height-sharing consent") stands and is not re-opened. Only the mis-identified field name is
corrected, with the evidence above. `sdd-tasks`/`sdd-apply` must not chase the literal `sharedWithTrainer` bool.

---

## 1. Architecture approach

**Pattern:** authorization + vantage-plumbing change, not a new feature. No new collection, no new model field, no
new Cloud Function, no new consent UI. We compose TWO existing fixed-path authorization documents into a read-rule
OR-branch, widen the create rule with a second OR-branch, and add one self-logged query on the trainer vantage.

```
                          measurements/{id}   (recordedBy, athleteId, ...)
                                   │
        ┌──────────────────────────┼───────────────────────────────────┐
   CREATE (widen)             READ (widen)                        QUERY (reshape D4)
   athlete-self OR            author OR subject OR                Q1 recordedBy==T & athleteId==X  (own, existing)
   trainer+role               (self-logged & consented-live-trainer)  Q2 athleteId==X & recordedBy==X   (self-logged, NEW)
                                   │                                        │  merge, Q2 error-tolerant
                                   │                                        ▼
                              gate reads TWO fixed docs:            measurementsForAthleteProvider
                              session_shares/{athleteId}  ◄── CF syncSessionShareOnTrainerLink (LIVE LINK, D2)
                              profile_shares/{athleteId}  ◄── athlete toggle grant/revoke     (CONSENT,  D3)
```

**Boundaries / ownership (all pre-existing, reused unchanged):**
- `session_shares/{athleteId}` — **CF-owned** (`sync-session-share.ts`). Auto-set to `{trainerId}` while the link
  is `active`; auto-deleted when the link leaves `active` (with the "belongs to a different trainer → skip delete"
  guard that makes trainer-switch race-safe). We add ZERO code here — we only *read* it in a new rule branch.
- `profile_shares/{athleteId}` — **athlete-client-owned** (`ProfileShareRepository`, `ProfileShareToggleTile`).
  Grant on opt-in, delete on opt-out; refreshed by `syncSharedProfile` CF on profile edits. We add ZERO code here.
- `measurements` rule + repository + `LogMeasurementScreen` + MEDIDAS screen — the only things this change edits.

---

## 2. D1 — Read-authorization: decision record

### 2.1 The predicate we need

A trainer T may read a self-logged measurement of athlete X iff **X currently has an active link to T (live link,
D2) AND X has consented to share personal data with T (consent, D3).** Expressed over fixed-path docs:

```
isSelfLogged(m)          := m.recordedBy == m.athleteId
liveLinkToRequester(X)   := exists(session_shares/X) && session_shares/X.trainerId == request.auth.uid
consentedToRequester(X)  := exists(profile_shares/X) && profile_shares/X.trainerId == request.auth.uid
trainerMayRead(m)        := isSelfLogged(m) && liveLinkToRequester(m.athleteId) && consentedToRequester(m.athleteId)
```

### 2.2 Why this beats the proposal's candidates and the prompt's alternatives

| Option | Security | `list`-query read cost | Write amplification | Staleness on link/consent change | Verdict |
|--------|----------|------------------------|---------------------|----------------------------------|---------|
| **CHOSEN: dual fixed-path get()** (`session_shares` + `profile_shares`) | Tight: self-logged only; requires BOTH live link AND consent to name T | **~2 reads for the whole list** (both paths fixed by the `athleteId` filter → cached; same as the live `setLogs` gate) | **None** — no per-measurement writes | **None for the live-link half** — CF revokes `session_shares` the instant the link leaves `active`; consent half tracked by the athlete toggle | ✅ |
| C1 — denormalize `sharedWithTrainerId` on each doc (proposal) | OK but frozen | 0 get() | Fan-out write to every measurement on link change | **Fails D2**: a NEW trainer cannot see OLD self-logged docs (frozen id) — user explicitly eliminated this | ❌ (violates D2) |
| C2 — `linkId`-in-doc + `get(trainer_links/$(linkId))` (reviews idiom) | OK | **per-doc get() → 1 read PER measurement** | none | survives change | ❌ AD-1 cost; auto-gen link ids break the deterministic-id trick |
| C3 — rule queries `trainer_links` for a membership | — | rules cannot query at all | — | — | ❌ impossible in rules |
| (a-variant) NEW `measurementShares/{athleteId}` doc + NEW CF | tight | ~1 read | CF writes on link/consent change | none | ❌ invents a new surface + new CF the user said to avoid; `session_shares`+`profile_shares` already ARE this |
| (d) accept per-doc get() | OK | per-doc cost | none | survives | ❌ AD-1 already rejected this class |

**Why require BOTH docs, not just `profile_shares`:** gating on `profile_shares` alone satisfies D3 but leaves a
D2 gap — `profile_shares.trainerId` is frozen at *consent time* (the toggle snapshots the then-active link's
trainer). On a trainer switch without a re-toggle it still names the OLD trainer, i.e. a "trainer id frozen at
consent time" — the same class of flaw D2 explicitly rejects ("NOT a trainer id frozen at write time"). Adding the
`session_shares` conjunct closes it: the CF removes `session_shares` for the old trainer the moment the link
terminates, so the stale old trainer is denied *even if* `profile_shares` still names them. The two docs together
express exactly "authorized (live link) AND consented" — the predicate the prompt's option (a) describes, composed
from infrastructure that already exists instead of a new doc/CF.

**Why gate only self-logged docs (`recordedBy == athleteId`):** a trainer must keep seeing their OWN professionally
recorded measurements via the plain author branch (`recordedBy == uid`), and a NEW trainer must NOT gain visibility
into a PREVIOUS trainer's professional measurements. Pinning branch 3 to `recordedBy == athleteId` scopes the new
visibility to precisely the athlete-authored rows the change is about, and nothing else.

---

## 3. Create rule (widened) — `firestore.rules` (v2), measurements block (`~983-1003`)

Current create (already role-hardened by rules-hardening Slice C, `firestore.rules:992-996`) is a single
trainer+role branch. Widen it to a dual OR-branch mirroring the `appointments` athlete-self-book / trainer+role
pattern (rules-hardening task 3.6). `recordedBy == uid` stays a shared precondition of BOTH branches, so a
self-logged doc is always `recordedBy == athleteId == uid`.

```
allow create: if request.auth != null
              && request.resource.data.recordedBy == request.auth.uid          // creator authors the doc (both branches)
              && request.resource.data.athleteId is string
              && request.resource.data.athleteId.size() > 0
              && (
                   // ── Athlete-self branch (NEW) ─────────────────────────────
                   // Athlete may log ONLY about themselves. Pins athleteId==uid,
                   // and (via the shared precondition) recordedBy==uid too.
                   request.resource.data.athleteId == request.auth.uid
                   // ── Trainer branch (UNCHANGED from Slice C / AD-1) ────────
                   || get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'trainer'
                 );
```

**Forge vector stays closed (R1 / AD-1).** An athlete-role user naming ANOTHER `athleteId`: athlete branch is false
(`athleteId != uid`); trainer branch evaluates the role `get()` → `'athlete' != 'trainer'` → false → **denied.**
The `||` short-circuits on the athlete-self branch, so a self-logging athlete never triggers the role `get()` and
does not need to be a trainer — while a forger always falls through to the role check and is rejected.

**update / delete: NO CHANGE** (`firestore.rules:997-1002`). Both already pin `recordedBy == uid` and immutable
`recordedBy`/`athleteId`. A self-logged doc has `recordedBy == athlete`, so the athlete edits/deletes their own and
the trainer cannot mutate it (and vice-versa) — the existing "each party edits only what it authored" invariant
already gives us the right behavior for self-logged docs for free.

---

## 4. Read rule (widened) — measurements block

```
allow read: if request.auth != null
            && (
                 request.auth.uid == resource.data.recordedBy        // 1. author (trainer OR athlete-self)
                 || request.auth.uid == resource.data.athleteId      // 2. subject athlete — own vantage (unchanged)
                 || (                                                // 3. consented + live-linked trainer, self-logged only (NEW)
                      resource.data.recordedBy == resource.data.athleteId
                      && exists(/databases/$(database)/documents/session_shares/$(resource.data.athleteId))
                      && get(/databases/$(database)/documents/session_shares/$(resource.data.athleteId)).data.trainerId == request.auth.uid
                      && exists(/databases/$(database)/documents/profile_shares/$(resource.data.athleteId))
                      && get(/databases/$(database)/documents/profile_shares/$(resource.data.athleteId)).data.trainerId == request.auth.uid
                    )
               );
```

**Ordering matters for cost.** Branches 1 and 2 are pure field comparisons (no `get()`). The athlete's own vantage
(branch 2, `athleteId == uid`) and the author (branch 1) short-circuit BEFORE branch 3, so they pay **zero**
document-read overhead. Only a trainer reading someone else's self-logged doc reaches branch 3's four
`exists()`/`get()` calls — two unique fixed paths → 2 cached reads for the whole list.

---

## 5. D4 — Trainer-vantage query reshape + index

`recordedBy == trainerUid` structurally excludes self-logged docs (`recordedBy == athleteUid`). We keep the
existing query for trainer-authored docs and ADD a second, self-logged query, then merge.

`MeasurementRepository`:
- **Q1 (existing) `watchForTrainerAthlete(trainerUid, athleteId)`** = `recordedBy == trainerUid && athleteId == X`.
  Every matched doc satisfies read-branch 1 → always list-satisfiable. Unchanged.
- **Q2 (NEW) `watchSelfLoggedForAthlete(athleteId)`** = `athleteId == X && recordedBy == X`. Every matched doc is
  self-logged (`recordedBy == athleteId`) → satisfies read-branch 3 when consented+linked, so the whole list is
  provable. Two equality filters, no `orderBy` (sort client-side) → **NO composite index required**
  (`firestore.indexes.json` unchanged — same rationale the existing `watchForTrainerAthlete` doc comment already
  states: multiple `==` filters use single-field indexes).

**Why NOT a single `athleteId == X` query for the trainer:** it would also match a PREVIOUS trainer's professional
docs (`recordedBy == oldTrainer`), which fail all three read branches for the new trainer → Firestore denies the
ENTIRE list (proposal R4). Splitting into Q1 (own) + Q2 (self-logged) keeps every query's result set provably
readable.

**Provider (`measurement_providers.dart`) `measurementsForAthleteProvider`** merges Q1 ∪ Q2, **Q2 error-tolerant**:
a non-consenting / non-linked athlete makes Q2 emit `permission-denied`; the provider must `.handleError` → `const
[]` so the trainer still sees their own Q1 rows instead of the stream tearing down. Sort by `recordedAt` ascending
client-side (existing contract of `MeasurementProgressChart`). The athlete vantage (`ownMeasurementsProvider`,
`athleteId == uid`) is **unchanged** — branch 2 covers every doc it returns.

---

## 6. D5 — `LogMeasurementScreen` dual-mode contract

Today the screen sets `recordedBy = ref.read(currentUidProvider)` — i.e. *the logged-in user*, already role-neutral.
Opened by an athlete with `athleteId == theirOwnUid`, it already produces a structurally correct self-logged doc
(`recordedBy == athleteId == uid`). The change is a small, explicit mode signal + copy, NOT a rewrite.

**Recommendation: an explicit mode via a named constructor + private enum (NOT a nullable `trainerUid`).** A nullable
`trainerUid` conflates "no session" with "athlete mode" and leaves the correctness of the self-logged invariant to a
runtime coincidence; a named constructor makes the two modes and their `athleteId` source unambiguous.

```dart
enum _LogAuthorMode { trainerForAthlete, athleteSelf }

class LogMeasurementScreen extends ConsumerStatefulWidget {
  /// Trainer logging FOR an athlete (existing behavior).
  const LogMeasurementScreen({super.key, required this.athleteId})
      : _mode = _LogAuthorMode.trainerForAthlete;

  /// Athlete logging their OWN measurement. athleteId is resolved from the
  /// authenticated uid at save time — the caller cannot inject someone else's.
  const LogMeasurementScreen.selfLog({super.key})
      : athleteId = null, _mode = _LogAuthorMode.athleteSelf;

  final String? athleteId;
  final _LogAuthorMode _mode;
}
```

- **`recordedBy`** = `currentUidProvider` in both modes (unchanged).
- **effective `athleteId`** = self mode → `currentUid`; trainer mode → `widget.athleteId!`. In self mode this
  guarantees `athleteId == recordedBy == uid`, exactly what the create rule's athlete branch requires (defense in
  depth: assert it before `add`).
- **Copy** switches on mode: title stays "Cargar medición"; notes hint "Observaciones del entrenador…" → a
  neutral "Notas (opcional)…" in self mode. New/adjusted strings go through AppL10n per project i18n convention
  (3 ARB files), `sdd-spec` owns the exact keys.

**MEDIDAS add affordance (`insights/presentation/measurements_screen.dart`).** The screen is read-only today
(its own docstring at lines 26-30 anticipates this change). Add a "+" affordance (header action or FAB consistent
with the palette) that pushes the self-log form:

```dart
Navigator.of(context).push(MaterialPageRoute(
  fullscreenDialog: true,
  builder: (_) => const LogMeasurementScreen.selfLog(),
));
```

`ownMeasurementsProvider(uid)` is a live stream, so a new entry surfaces automatically on save; no manual
invalidate required. Update the stale docstring (lines 26-30) that says only trainers can create.

---

## 7. D2 + consent bootstrapping — end-to-end walkthrough (verifying the mechanism delivers)

| Scenario | `session_shares/X` | `profile_shares/X` | Trainer T read of X's self-logged docs |
|----------|--------------------|--------------------|----------------------------------------|
| Solo athlete, no link | absent | absent | N/A — no trainer. Self-log create still works (create needs no link/consent). |
| Linked+active, NOT consented | `{T}` (CF) | absent | **Denied** (branch 3: `profile_shares` missing) — D3 consent required. |
| Consented but link paused/terminated | absent (CF removed) | `{T}` | **Denied** (branch 3: `session_shares` missing) — D2 live link required. |
| Linked+active AND consented | `{T}` | `{T}` | **Allowed** — sees FULL self-logged history (Q2 returns all; rule reads current docs). |
| **New trainer B after switch, once B active + re-consented** | `{B}` (CF repointed) | `{B}` (re-toggle) | **Allowed — B sees ALL pre-existing self-logged history.** ✅ D2. |
| Old trainer A after athlete switched to B | `{B}` | `{A}` (stale) or `{B}` | **A denied** (`session_shares` names B, not A) — CF live-link gate revokes A even before consent is re-toggled. |

**Consent bootstrapping (prompt point 5) confirmed:** a solo user self-logs freely (create branch needs neither
link nor consent). When they later link a trainer (CF writes `session_shares`) AND opt in (`profile_shares`), the
read rule — evaluated at READ time over the CURRENT share docs — authorizes the trainer over the athlete's ENTIRE
self-logged history, because Q2 is unbounded over `athleteId` and nothing about visibility is frozen at write time.
**D2 delivered: YES.**

---

## 8. Cloud Function / denormalization ownership

**No new Cloud Function, no denormalization onto measurements.** The mechanism reuses two CF/client-maintained docs
as-is:
- `session_shares/{athleteId}` is already fully maintained by `syncSessionShareOnTrainerLink`
  (`functions/src/sync-session-share.ts`) — it fires on every `trainer_links` write, sets on `active`, deletes on
  non-active, and has a trainer-switch guard. This is the CF the prompt asked us to check for; it exists and already
  owns the live-link half.
- `profile_shares/{athleteId}` is maintained by the athlete client (`grant`/`revoke`) and refreshed by
  `syncSharedProfile`. It owns the consent half.

**Optional future hardening (OUT OF SCOPE, documented not dropped):** a CF that repoints/revokes `profile_shares`
on link termination (mirroring `sync-session-share.ts`) would make the CONSENT pointer follow the live link too,
eliminating the stale-`profile_shares` window for the old trainer. It is unnecessary for correctness here because
the `session_shares` conjunct already revokes the old trainer's access on link termination; and it would also change
weight/height sharing semantics, so it belongs to a separate change if ever wanted.

---

## 9. ADR-style decisions

| ADR | Decision | Rationale | Rejected alternative |
|-----|----------|-----------|----------------------|
| ADR-ASM-1 | **Dual fixed-path gate** (`session_shares` ∧ `profile_shares`, both naming the requester) authorizes a trainer's read of a **self-logged** measurement. | Composes the existing CF-maintained live-link doc (D2) with the existing athlete consent doc (D3). Two cached `get()`s to fixed paths → ~2 reads per history list, not per-doc → does not trip AD-1's cost objection (that objection is about per-doc-varying `get()` paths). Same idiom already live for `setLogs` lists. | Per-doc `get(trainer_links)` (C2, AD-1 cost + auto-gen ids); rule-side membership query (C3, impossible); new `measurementShares` doc + new CF (invents a surface the user forbade). |
| ADR-ASM-2 | **Map D3's "sharedWithTrainer" to `profile_shares/{athleteId}`.** | `sharedWithTrainer` is dead (zero callers, always false — `trained_today_provider.dart:54-56`) and un-`get()`-able (auto-gen `trainer_links` ids). `profile_shares` IS the athlete-controlled surface that already shares weight/height. Honors D3's intent exactly; corrects only the field name. | Literal `sharedWithTrainer` bool → gates everything off, un-enforceable in rules. |
| ADR-ASM-3 | **Also require `session_shares`, not `profile_shares` alone.** | `profile_shares.trainerId` is frozen at consent time → stale-old-trainer window = the "frozen id" flaw D2 rejects. The CF-maintained `session_shares` conjunct revokes the old trainer on link termination → strict D2. | `profile_shares`-only gate → simpler, ~1 read, but D2-incomplete (old trainer keeps access until re-toggle). Documented as the runner-up. |
| ADR-ASM-4 | **Widen create as a dual OR-branch** (`athleteId==uid` OR `role=='trainer'`), `recordedBy==uid` shared precondition. | Mirrors the shipped `appointments` athlete-self-book / trainer+role pattern. `||` short-circuit means self-logging athletes skip the role `get()`; forgers always hit it and fail → AD-1 forge vector stays closed. | Separate athlete-only create rule → duplicates the block; loosening `athleteId` shape → reopens forge vector. |
| ADR-ASM-5 | **Trainer vantage = Q1 (own) + Q2 (self-logged) merged, Q2 error-tolerant; NO index.** | A single `athleteId==X` query is denied whenever a previous trainer's docs exist (list-satisfiability, R4). Two equality queries are each provable and need no composite index. | Single `athleteId==X` query (breaks list satisfiability + widens visibility to a prior trainer's professional docs). |
| ADR-ASM-6 | **Named-constructor dual-mode form** (`LogMeasurementScreen.selfLog()`), `athleteId` derived from `currentUid` in self mode. | Explicit mode; the athlete cannot inject another `athleteId`; guarantees the `athleteId==recordedBy==uid` self-logged invariant. | Nullable `trainerUid` — conflates "no session" with "athlete mode", leaves the invariant to coincidence. |

---

## 10. Test matrix

Firestore **rules** tests run against the emulator (`scripts/rules_test/rules.test.js`, RED→GREEN, JDK 21 per
proposal §6). Rules are NOT enforced by `fake_cloud_firestore`, so rule behavior lives here; Dart tests cover query
SHAPE, provider merge, and the form. Ship order: PR1 (rules + rules-tests) before PR2 (client), per proposal §7.

### 10.1 Rules (RED→GREEN — `scripts/rules_test/`, new `measurements-self-log.test.js` sibling)

| # | Scenario | Assert | RED today? |
|---|----------|--------|------------|
| S1 | Athlete creates own measurement (`athleteId==uid`, `recordedBy==uid`) | `assertSucceeds` | RED (role check denies) → GREEN |
| S2 | Athlete-role user forges a measurement for ANOTHER `athleteId` | `assertFails` | Stays denied — AD-1 regression anchor (non-vacuity) |
| S3 | Trainer creates for any athlete (`recordedBy==trainer`, role trainer) | `assertSucceeds` | Stays green — legit-path anchor |
| S4 | Consented+live-linked trainer READS a self-logged doc (`session_shares/X={T}`, `profile_shares/X={T}`, `recordedBy==X==athleteId`) | `assertSucceeds` | RED (branch 3 absent) → GREEN |
| S5 | Linked but NOT consented (`session_shares/X={T}`, no `profile_shares`) reads self-logged | `assertFails` | GREEN gate (D3 consent required) |
| S6 | Consented but link gone (`profile_shares/X={T}`, no `session_shares`) reads self-logged | `assertFails` | GREEN gate (D2 live link required) |
| S7 | Stale old trainer: `session_shares/X={B}`, `profile_shares/X={A}`; A reads self-logged | `assertFails` | GREEN gate (D2 no frozen id — the headline test) |
| S8 | Unlinked+unconsented trainer reads self-logged | `assertFails` | Stays denied |
| S9 | Trainer READS their OWN recorded doc (`recordedBy==T`) | `assertSucceeds` | Stays green — branch 1 anchor |
| S10 | Athlete READS their own self-logged doc | `assertSucceeds` | Stays green — branch 2 anchor |
| S11 | Consented+linked trainer LIST `athleteId==X && recordedBy==X` (Q2) | `assertSucceeds`, returns the self-logged rows | RED → GREEN (list path + cost idiom) |
| S12 | Non-consented trainer runs the same Q2 list | `assertFails` (whole list) | GREEN — proves the client must tolerate the denial |

Non-vacuity: every deny (S2/S5/S6/S7/S8/S12) is paired with a matching allow (S1/S3/S4/S9/S10/S11).

### 10.2 Dart (`fake_cloud_firestore` / widget)

| # | Test | Asserts |
|---|------|---------|
| T1 | `measurementsForAthleteProvider` merges Q1+Q2 | Seed one trainer-recorded + one athlete-self-logged doc for athlete X; provider surfaces BOTH, sorted by `recordedAt` (proposal R4 / D4). |
| T2 | Q2 error tolerance | When the self-logged stream errors (`permission-denied`), provider still yields Q1 rows (no teardown). |
| T3 | Athlete vantage unchanged | `ownMeasurementsProvider(uid)` returns self-logged + trainer-recorded for uid. |
| T4 | `MeasurementRepository.watchSelfLoggedForAthlete` shape | Query is `athleteId==X && recordedBy==X` (self-logged only; excludes trainer-recorded). |
| T5 | Form self-mode payload (proposal R5) | `LogMeasurementScreen.selfLog()` produces `Measurement` with `recordedBy == athleteUid == athleteId`. |
| T6 | MEDIDAS add affordance | Tapping "+" pushes `LogMeasurementScreen.selfLog()` (fullscreen dialog). |

Gate: `flutter analyze` 0 issues + `dart format .` + tests green (AGENTS.md).

---

## 11. Risks (design-level)

| # | Risk | Severity | Mitigation |
|---|------|----------|------------|
| RD1 | **Stale `profile_shares` for the OLD trainer** after a trainer switch without a re-toggle. | Low | The `session_shares` conjunct (ADR-ASM-3) revokes the old trainer on link termination regardless of stale consent → measurements are NOT exposed. Pre-existing weight/height sharing carries the same stale window (unchanged by this PR). Optional CF hardening documented §8. S7 is the guard. |
| RD2 | **Coupling measurement visibility to `session_shares` (the session-share doc).** | Low | Semantically correct: `session_shares` == "active link to T". A trainer already sees an athlete's sessions/weight when both share docs name them; measurements now join the same, single mental model ("your trainer sees your body data while linked + consented"). |
| RD3 | **Q2 `permission-denied` tears down the trainer stream** if not error-tolerant. | Medium | T2 asserts `.handleError → []`; provider merges Q1 ∪ Q2 so denial degrades to "own docs only". |
| RD4 | **List-satisfiability regression** if the trainer query is ever simplified to `athleteId==X`. | Medium | ADR-ASM-5 + code comment: keep Q1/Q2 split; a prior trainer's docs would deny a single `athleteId==X` list. S11/S12 exercise the list path. |
| RD5 | **`get()` cost creep** if branch 3 is ever reordered before branches 1/2. | Low | Branch ordering is load-bearing (author/subject short-circuit before any `get()`); noted in the rule comment. |
| RD6 | **D3 field-name misread propagates** — an implementer wires the literal `sharedWithTrainer` bool. | Medium (blocking until acknowledged) | §0 blocking finding + ADR-ASM-2; `sdd-tasks`/`sdd-apply` must gate on `profile_shares`, never `sharedWithTrainer`. User acknowledgment requested. |

---

## 12. Handoff

- **`sdd-spec`** — formalize: widened create (athlete-self branch + preserved trainer branch), the dual-share read
  requirement, the Q1+Q2 trainer-vantage contract (D4, no index), the form self-mode (D5), and the ARB keys. Encode
  S1–S12 / T1–T6 as scenarios.
- **`sdd-tasks`** — decompose into PR1 (rules + `measurements-self-log.test.js` RED→GREEN) and PR2 (repo Q2 +
  provider merge, form dual-mode, MEDIDAS affordance, Dart/widget tests, ARB). **Honor §0**: gate on
  `profile_shares` (+`session_shares`), NOT `sharedWithTrainer`. NO `firestore.indexes.json` change. NO new CF.
