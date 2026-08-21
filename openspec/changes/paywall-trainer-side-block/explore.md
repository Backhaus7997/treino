## Exploration: PF-side write enforcement when trainer_links.entitlement == 'blocked'

### Current State

`trainer_links/{linkId}.entitlement` (`'entitled'|'blocked'`) exists today and is CF-write-only (`firestore.rules` ~547-549). Its **only** consumer is `functions/src/subscriptions/weighted-load.ts` (`computeWeightedLoad` excludes `blocked` links from the weighted-load sum). **Nothing in the repo writes `entitlement: 'blocked'` yet** — there is no downgrade/reconciliation job that sets it. `linkLoadReconcile` (`functions/src/subscriptions/link-load-reconcile.ts`, `onDocumentWritten` on `trainer_links/{linkId}`) only recomputes `users/{trainerId}.weightedLoad` for display and is explicitly documented as non-gating ("reconciliation is not a gate ... always writes regardless"). The `createPreapproval`/`mpWebhook`/downgrade/reactivation Cloud Functions referenced in rules comments do **not exist** in `functions/src` — they are forward-looking placeholders.

### 1. Action Inventory (PF write surface on a linked athlete)

| Collection | Rule location | Authorization today |
|---|---|---|
| `routines` (trainer-assigned/template) | `firestore.rules:127-409` | `assignedBy == auth.uid` only. Create branch 1 has **no role check and no trainer_links reference at all** — no `linkId` field exists on the doc. |
| `nutrition_plans/{trainerId}_{athleteId}` | `firestore.rules:2000-2019` | `trainerId == auth.uid` only. |
| `measurements` | `firestore.rules:1638-1759` | create: `recordedBy==uid` + (self OR `role=='trainer'`); no trainer_links check. |
| `performance_tests` | `firestore.rules:1763-1842` | `recordedBy==uid` + `role=='trainer'`; no trainer_links check. |
| `athlete_notes` | `firestore.rules:1902-1940` | `trainerId==auth.uid`, docId `{trainerId}_{athleteId}`; no trainer_links check. |
| `athlete_files` | `firestore.rules:1947-1966` | Same pattern, no trainer_links check. |
| `follow_up_entries` | `firestore.rules:1972-1994` | Same pattern, no trainer_links check. |
| `athlete_billing` | `firestore.rules:1846-1898` | `trainerId==auth.uid` + `role=='trainer'`; no trainer_links check. |
| `payments` | `firestore.rules:2022-2095` | `trainerId==auth.uid` + `role=='trainer'`; no trainer_links check. |
| `appointments` | `firestore.rules:1566-1627` | create: athlete self-book OR (`trainerId==auth.uid` + `role=='trainer'`); no trainer_links check. |
| `coach_availability_rules/overrides` | `firestore.rules:1542-1558` | `trainerId==auth.uid` only. |
| `chats` (+ `messages`) | `firestore.rules:1240-1430` | **Only collection with a real `get()` on `trainer_links/{linkId}`**, via optional `linkId` field in the payload (`chatCreateOk` / `senderMayPost`). Message READ stays membership-only by explicit design ("el lado que perdió la escritura conserva la conversación entera"). |
| `reviews` | `firestore.rules:2124-2156` | create does `get(trainer_links/{linkId})`, requires `status in ['active','paused']`. Athlete-authored, not a PF write on the athlete. |

### 2. Which Collections Gate via `trainer_links`

Only **2 of ~12** PF-write collections reference `trainer_links` via `get()`: `chats/create` (conditionally) and `reviews/create`. Every other collection authorizes purely by `trainerId`/`assignedBy`/`recordedBy == auth.uid` (+ role check on the newer, hardened ones) and never inspects link status/entitlement.

**Architectural consequence**: adding `&& entitlement != 'blocked'` is cheap only for chats/reviews (extend an existing `get()`). For the other 10 collections there is no `linkId` to piggyback on, and `trainer_links` doc IDs are **auto-generated** (explicitly, to allow multiple historical links per pair) — so rules cannot do `get(/trainer_links/$(trainerId + '_' + athleteId))` the way `athlete_billing`/`athlete_notes` do for their own deterministic IDs. Gating those 10 requires a new mechanism:
- (a) a deterministic per-pair index doc (e.g. `trainer_link_index/{trainerId}_{athleteId}` mirroring current entitlement, written transactionally by whatever CF sets `entitlement:'blocked'`), or
- (b) a denormalized `blockedAthleteIds` set on `users/{trainerId}` (cheap — a `get()` on the trainer's own doc is already paid by several rules for the role check), or
- (c) writing `linkId`/`entitlement` onto each sub-resource at create time (schema change, doesn't retroactively cover existing docs).

### 3. Read/Write Asymmetry

Hypothesis validated, with one nuance called out explicitly by the codebase itself: all athlete-facing READ rules (routines by `assignedTo`, sessions/setLogs via `session_shares`, measurements via `session_shares`+`profile_shares`, chat messages, appointments) are untouched by `status`/`entitlement` today and must stay that way. `chats` messages READ is explicitly membership-only "SIN CAMBIOS" specifically so blocking a side never deletes history (`firestore.rules:1404-1406`) — this is the precedent to copy. Trainer-authored-only collections (`athlete_notes`, `athlete_files`, `follow_up_entries`, `nutrition_plans`) are invisible to the athlete by design, so the read/write question doesn't even apply to them.

### 4. RISK — Where Blocking the PF Could Hurt the Athlete (read this first)

- **Routines** READ (`firestore.rules:149-165`) allows `assignedTo == auth.uid` unconditionally — already decoupled from `trainer_links`. Safe, **provided** the enforcement change only touches the routines CREATE/UPDATE paths 3/4 (trainer edits), never the read branch.
- **Sessions/setLogs** read-gate via `session_shares` (`firestore.rules:1470-1491`) is an independent opt-in doc, unrelated to `trainer_links.status/entitlement` — safe.
- **Measurements** self-logged-by-athlete branch reads via `session_shares`+`profile_shares` (`firestore.rules:1723-1730`) — also independent — safe.
- **Chats** read rule is membership-based and not proposed to change — confirmed safe precedent.
- **Real risk zone**: any future implementation that reuses `get(trainer_links/{linkId})` inside a READ rule (instead of scoping strictly to CREATE/UPDATE) is the actual danger. None exist today, but the design MUST explicitly forbid entitlement checks inside `allow read` clauses — otherwise an athlete could lose visibility into a routine/plan the instant their PF gets blocked. **This is the #1 guardrail for design.md.**
- **Secondary risk**: `routines` UPDATE path 3 (trainer edits a trainer-assigned plan) has zero trainer_links reference today. If gating is added via a new per-pair index doc, a stale/missing index doc makes `get()` fail closed (deny) — silently blocking legitimate edits. Any new index doc must be written transactionally alongside `entitlement` to avoid drift.

### 5. UI Surface (currently zero entitlement/blocked exposure anywhere)

Grep confirms `entitlement`/`blockedAt`/`blockedReason` exist only in `lib/features/coach/domain/trainer_link.dart` (+ generated files) and `lib/features/coach/domain/weighted_load.dart` (calculation only). No screen renders them today.

- **Web roster**: `lib/features/coach_hub/presentation/sections/alumnos/alumnos_screen.dart` — already has a composite-state pattern (`AlumnoEstado {activo, conDeuda, pausado, inactivo}` derived by `estadoForLink()`, ~lines 41-91) plus `RosterFiltro` chips — natural slot for `AlumnoEstado.bloqueado` + a filter chip + `p.danger` color (matching `conDeuda`).
- **Web detail**: `lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart`.
- **Web plan-limit prior art** (reuse copy/pattern): `lib/features/coach_hub/presentation/sections/facturacion_planes/{paywall_preview_screen.dart, keep_students_screen.dart, pricing_screen.dart}` — `PlanLimitReason.subscriptionInactive` already surfaced in the alumnos flow (`alumnos_screen.dart:988-989`).
- **Mobile roster**: `lib/features/coach/trainer_coach_view.dart` (`TrainerCoachView`, `ListView.separated` ~line 169, already branches on `TrainerLinkStatus.paused` at line 284).
- **Mobile detail**: `lib/features/coach/presentation/athlete_detail_screen.dart`.

### 6. Detection Mechanism — What Exists, What's Missing

- `linkLoadReconcile` (`functions/src/subscriptions/link-load-reconcile.ts`) — `onDocumentWritten` on `trainer_links/{linkId}`, southamerica-east1, idempotent full-recompute via `syncTrainerLoad(app, {trainerId, promotion: null})`. Closest analog for "detect overage on a link write", but by design it never blocks/writes entitlement.
- `notifyOverduePayments` (`functions/src/payments/notify-overdue-payments.ts`) — `onSchedule` daily cron (10:00 ART), iterates active `trainer_links`, per-link query pattern. Closest analog for a **scheduled** excess-detection sweep.
- **The actual gap**: no trigger exists on `users/{uid}` for subscription changes. `effectiveWeightLimit` depends on `users/{trainerId}.subscription`; a subscription lapsing (MP webhook — not yet implemented) shrinks the limit **without touching any `trainer_links` doc**, so `linkLoadReconcile`'s trigger would never fire in that scenario.
- **Recommendation**: need both (a) a new trigger on `users/{uid}` scoped to `subscription` field changes — mirroring `linkLoadReconcile`'s transactional idiom via `syncTrainerLoad`, but adding the actual blocking decision (which excess links to flip to `entitlement:'blocked'`, product policy for tie-breaking e.g. newest-active-first) — and (b) a daily scheduled sweep (mirrors `notifyOverduePayments`) as a drift safety net. Do not repurpose `linkLoadReconcile` itself — it fires on the wrong event and is documented as intentionally non-gating; a new function under `subscriptions/` is cleaner.

### 7. Forecast (x2.2 historical underestimate factor applied)

| Area | Raw estimate | Adjusted (×2.2) |
|---|---|---|
| `firestore.rules` | 60-100 | 130-220 |
| `functions/` (new entitlement-writer CF + scheduled sweep + index-doc maintenance) | 150-250 | 330-550 |
| UI móvil (`lib/features/coach/`) | 60-100 | 130-220 |
| UI web (`lib/features/coach_hub/`) | 80-130 | 175-285 |
| Tests (rules emulator + CF unit/emulator + widget) | 200-350 | 440-770 |
| **Total** | **550-930** | **~1200-2050** |

Clearly over the 400-line PR review budget — chained/stacked PR slices required. Suggested split: PR-A (subscription-change entitlement-writer CF + scheduled sweep + their tests), PR-B (chats/reviews gate extension — cheap, already has `get()`), PR-C (mobile UI), PR-D (web UI), PR-E (the 10 ownership-only collections, once the index-doc design from AD below is resolved).

### Recommendation

Scope the first slice to (1) the subscription-change → entitlement-writer CF + tests, (2) the daily reconciliation sweep, (3) read-only UI surfacing on both rosters (zero enforcement risk). Defer actual write-blocking in rules to a second slice; within that slice, do chats+reviews first (cheap), then tackle the 10 ownership-only collections once the per-pair lookup design is decided.

### Risks
- Adding entitlement checks inside a READ rule anywhere would strip an athlete of access to their own data — must be explicitly forbidden in design.md (section 4).
- 10 of 12 relevant collections have no cheap path to `trainer_links` lookup — the index-doc/denormalization decision blocks most of the write-enforcement scope and must be resolved before `sdd-tasks` sizes that slice.
- No subscription-change trigger exists yet — without it, entitlement drifts silently whenever a trainer's paid limit shrinks outside of a `trainer_links` write.
- Forecast likely exceeds a single PR by ~3-5x; delivery strategy decision needed before `sdd-apply`.

### Ready for Proposal
Yes — scope is clear enough for `sdd-propose`, but the proposal MUST explicitly resolve: (a) which of the 10 ownership-only collections get blocked in v1 vs. deferred, (b) the index-doc design for cheap trainer_links lookups by pair, (c) the guardrail that entitlement checks never enter a READ rule.
