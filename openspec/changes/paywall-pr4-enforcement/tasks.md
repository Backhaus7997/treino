# Tasks: paywall-pr4-enforcement (Fase 7, PR4 — server-side promotion gate)

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | ~1300-1700 total (S1 350-450, S2 450-550, S3 250-350, S4 250-350) |
| ACTUAL slices 1-2 | Slice 1: **1297** vs 350-450 forecast. Slice 2: **998** vs 450-550. Ratio consistente **~2.2x** — el forecast contaba solo produccion, los tests son el grueso. APLICAR ese factor a S3/S4 antes de implementar. |
| 400-line budget risk | High |
| Chained PRs recommended | Yes |
| Suggested split | PR1a→PR1b→PR1c→PR2a→PR2b→PR2c→PR3→PR4 (strictly linear) |
| Delivery strategy | ask-on-risk |
| Chain strategy | feature-branch-chain (decided in proposal D5) |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

### Suggested Work Units

Tracker branch: `feat/paywall-pr4-enforcement` (accumulates integration; only this merges to `main`, after PR4).

| Unit | Goal | Branch | Base | Issue / label |
|---|---|---|---|---|
| PR1a | H1 TS↔Dart parity fix + shared golden fixture (+ SDD artifacts) | `fix/coach-weighted-load-parity` | tracker | ISSUE-1, `type:fix` |
| PR1b | `syncTrainerLoad` transactional gate helper + fake-tx double | `feat/coach-weighted-load-gate-helper` | PR1a branch | ISSUE-1b, `type:feature` |
| PR1c | `linkLoadReconcile` trigger + `index.ts` export | `feat/coach-weighted-load-reconcile-trigger` | PR1b branch | ISSUE-1c, `type:feature` |
| PR2a | subscription-inactive paywall branch (`reason` + `_ReactivateBox`) | `feat/coach-paywall-subscription-inactive` | PR1c branch | ISSUE-2a, `type:feature` |
| PR2b | `acceptTrainerLink` callable + `index.ts` export | `feat/coach-accept-trainer-link-callable` | PR2a branch | ISSUE-2b, `type:feature` |
| PR2c | Dart promotion service + both accept callsites + drop `repository.accept` | `feat/coach-accept-migrate-callsites` | PR2b branch | ISSUE-2c, `type:feature` |
| PR3 | `resumeTrainerLink` CF, both resume callsites (H2, H4), drop `.resume()` | `feat/coach-resume-trainer-link-gate` | PR2c branch | ISSUE-3, `type:feature` |
| PR4 | `firestore.rules` split clause, test flips, `test:rules` regex fix (H3), comment cleanup | `fix/infra-firestore-rules-promotion-lock` | PR3 branch | ISSUE-4, `type:fix` |

Strictly linear — each slice merges leaving the system consistent and deployable; PR2/PR3 don't touch `firestore.rules`, so old app builds keep working.

## Slice 1 — Transactional core + H1 parity fix + reconciliation trigger

Branch `fix/coach-weighted-load-parity` · base tracker · ~350-450 lines

- [x] 1.1 Create `functions/src/subscriptions/weighted-load-cases.json` — 12 golden cases (empty=0, active=1, paused=0.5, pending=0, terminated=0, dedupe a+t=1, dedupe a+p=1, blocked-active excluded=0, **blocked-active+entitled-paused same athlete=0.5 [H1]**, 6a+2p=7.0, 6a+1p=6.5, 15p=7.5).
- [x] 1.2 [RED][LOCAL] `functions/src/__tests__/weighted-load.test.ts` reads fixture — fails today (TS dedupes before filtering `blocked`, H1).
- [x] 1.3 [GREEN][LOCAL] Fix `functions/src/subscriptions/weighted-load.ts:63-64` — filter `blocked` BEFORE dedupe (matches Dart, the correct order per ADR-5).
- [x] 1.4 [LOCAL] `test/features/coach/domain/weighted_load_parity_test.dart` reads same fixture — regression pin, passes immediately (Dart already correct order).
- [x] 1.5 [RED][LOCAL] `functions/src/__tests__/promote-link.test.ts` — hand-rolled fake tx (throws on `get` after `update`/`set`); precondition ladder (not-found, permission-denied, wrong-status, link-blocked, already-active no-op) + gate boundary (7.0 passes / 7.5 blocks) + `promotionDenialReason` plan-limit vs subscription-inactive incl. free-tier edge.
- [x] 1.6 [GREEN][LOCAL] Implement `functions/src/subscriptions/promote-link.ts` — `syncTrainerLoad(app, input)`, `PromotionIntent`/`SyncTrainerLoadInput`/`SyncTrainerLoadResult`, reads-before-writes order per design D-1, `promotionDenialReason`.
- [x] 1.6b [RED+GREEN][LOCAL] **Found during apply**: the gate wrote only `status:'active'`, dropping the transition fields the client methods wrote — `acceptedAt` (accept) and `pausedAt: FieldValue.delete()` (resume). Silent data regression: `trainer_coach_view.dart:403` renders `acceptedAt ?? requestedAt`, so a missing stamp degrades to the request date instead of failing. Fixed in `promote-link.ts` keyed off `expectedFromStatus`; 3 tests added (accept stamps, resume clears + preserves acceptedAt, reconciliation touches nothing). Test double extended with `Timestamp`/`FieldValue` sentinels.
- [~] 1.7 [WRITTEN, CI-VERIFIED ONLY] [RED][EMULATOR-CI — Java 21, not runnable locally] `functions/src/__tests__/promote-link.emulator.test.ts` — reads-before-writes vs real Firestore + concurrency (`Promise.allSettled`, plan1 limit 7, 6 active + 2 pending, exactly 1 fulfilled / 1 `resource-exhausted`, final load 7, `--runInBand`, projectId `treino-rules-test`).
- [~] 1.8 [PENDING CI] [GREEN][EMULATOR-CI] Confirm 1.7 green against 1.6 in CI — do not block local apply flow on this.
- [x] 1.9 [RED][LOCAL] Reconciliation trigger tests — idempotent (run twice, same value), missing `users/{trainerId}` doc → warn + no throw.
- [x] 1.10 [GREEN][LOCAL] Implement `functions/src/subscriptions/link-load-reconcile.ts` — `onDocumentWritten`, calls `syncTrainerLoad(app,{trainerId,promotion:null})`, catch+log never rethrow (mirrors `link-aggregate.ts`), log `{event:'link-promoted-observed'}` when `before.status!=='active' && after.status==='active'` (adoption metric, used in M.4).
- [x] 1.11 Export `linkLoadReconcile` in `functions/src/index.ts`.
- [x] 1.12 [QUALITY GATE] `flutter analyze` 0 issues · `dart format .` · `flutter test` green · `npm --prefix functions test` green (local suites only).
- [ ] 1.13 [MANUAL] Open PR #1 against tracker branch, link ISSUE-1 (`status:approved`, `type:fix`).

## Slice 2 — `acceptTrainerLink` gate end-to-end

Partido en PR2a/PR2b/PR2c (ver mapa arriba) · base PR1c · **998 lineas reales**

- [x] 2.1 [RED][LOCAL] Widget test — `plan_limit_paywall.dart` additive `reason`/`subscriptionStatus`; `_ReactivateBox` branch (subscription-inactive copy is a placeholder, TODO pending product review); existing 3 callsites (`paywall_preview_screen.dart:47/55/63`) still compile untouched.
- [x] 2.2 [GREEN][LOCAL] Implement additive signature + `_ReactivateBox` in `.../facturacion_planes/plan_limit_paywall.dart` (~80-100 lines, per D-2).
- [x] 2.3 [RED][LOCAL] `functions/src/__tests__/accept-trainer-link.test.ts` — onCall wrapper, auth/App Check passthrough, calls `syncTrainerLoad` with `expectedFromStatus:'pending'`.
- [x] 2.4 [GREEN][LOCAL] Implement `functions/src/subscriptions/accept-trainer-link.ts` (`southamerica-east1`, `enforceAppCheck:true`), log `{event:'link-promoted-cf'}` on success.
- [x] 2.5 Export `acceptTrainerLink` in `functions/src/index.ts`.
- [x] 2.6 [RED][LOCAL] Dart unit tests (mocktail) — `FirebaseFunctionsException` → `sealed LinkPromotionFailure` mapping; Android `Map<Object?,Object?>` details cast gotcha, field-by-field parse, never throws.
- [x] 2.7 [GREEN][LOCAL] Implement `lib/features/coach/data/trainer_link_promotion_service.dart` — `sealed LinkPromotionFailure`/`PlanLimitReached`/`$Precondition`/`$Unavailable` (plain Dart, Hard Constraint #3), `accept(linkId)`.
- [x] 2.8 Register provider in `lib/features/coach_hub/application/cf_providers.dart` (reuse `cloudFunctionsProvider`).
- [x] 2.9 [RED][LOCAL] Widget test — `trainer_dashboard_tab.dart` accept callsite: 3 branches (PlanLimitReached→paywall, $Precondition/$Unavailable→snackbars), `_busy` always resets, `mounted` guard.
- [x] 2.10 [GREEN][LOCAL] Migrate `lib/features/coach/presentation/trainer_dashboard_tab.dart:423` off `TrainerLinkRepository.accept`.
- [x] 2.11 [RED][LOCAL] Widget test — `coach_hub_dashboard_screen.dart` accept callsite: same 3 branches + 2 new l10n keys.
- [x] 2.12 [GREEN][LOCAL] Migrate `.../sections/dashboard/coach_hub_dashboard_screen.dart:1218`.
- [x] 2.13 Delete `TrainerLinkRepository.accept` from `lib/features/coach/data/trainer_link_repository.dart` — any missed callsite is now a compile error (D-4 safety net).
- [x] 2.14 [QUALITY GATE] `flutter analyze` 0 issues · `dart format .` · `flutter test` green · `npm --prefix functions test` green (local suites).
- [ ] 2.15 [MANUAL] Open PR #2 targeting PR1 branch, link ISSUE-2 (`status:approved`, `type:feature`), 📍PR2 dependency diagram, confirm diff excludes PR1 changes.

## Slice 3 — `resumeTrainerLink` gate end-to-end (H2 + H4)

Branch `feat/coach-resume-trainer-link-gate` · base PR2 branch · ~250-350 lines

- [ ] 3.1 [RED][LOCAL] `functions/src/__tests__/resume-trainer-link.test.ts` — onCall wrapper, `expectedFromStatus:'paused'`.
- [ ] 3.2 [GREEN][LOCAL] Implement `functions/src/subscriptions/resume-trainer-link.ts`, log `{event:'link-promoted-cf'}`.
- [ ] 3.3 Export `resumeTrainerLink` in `functions/src/index.ts`.
- [ ] 3.4 [RED][LOCAL] Extend service tests — `resume(linkId)` mapping (reuses 2.6 sealed failures).
- [ ] 3.5 [GREEN][LOCAL] Add `resume(linkId)` to `trainer_link_promotion_service.dart`.
- [ ] 3.6 [RED][LOCAL] Widget test — `trainer_coach_view.dart` resume callsite: `_confirmAndRun` gains `onFailure` hook, 3 branches, `mounted` guard.
- [ ] 3.7 [GREEN][LOCAL] Migrate `lib/features/coach/trainer_coach_view.dart:312` (H2 — 4th callsite, missed by proposal).
- [ ] 3.8 [RED][LOCAL] Widget test — `_RowActions` (`alumnos_screen.dart:692`) as `ConsumerStatefulWidget` with `_busy` (H4); resume callsite 3 branches, `context.mounted` guard, fire-and-forget removed.
- [ ] 3.9 [GREEN][LOCAL] Convert `_RowActions` to `ConsumerStatefulWidget`; migrate `.../sections/alumnos/alumnos_screen.dart:711`.
- [ ] 3.10 Delete `TrainerLinkRepository.resume` from `trainer_link_repository.dart`.
- [ ] 3.11 [QUALITY GATE] `flutter analyze` 0 issues · `dart format .` · `flutter test` green · `npm --prefix functions test` green (local suites).
- [ ] 3.12 [MANUAL] Open PR #3 targeting PR2 branch, link ISSUE-3 (`status:approved`, `type:feature`), 📍PR3.

## Slice 4 — Rules lock (SOLO-RULES, irreversible)

Branch `fix/infra-firestore-rules-promotion-lock` · base PR3 branch · ~250-350 lines. Merging this PR does NOT deploy — deploy is gated by the manual runbook below.

- [ ] 4.1 [RED][EMULATOR-CI — not runnable locally] Update `functions/src/__tests__/trainer-links-paywall-rules.test.ts` — flip accept `assertSucceeds`→`assertFails` (SCENARIO-917), add resume `assertFails` (SCENARIO-918), add →`pending` from active/paused/terminated `assertFails` for any actor (SCENARIO-921), regression-pin pause/terminate/decline/cancel/sharedWithTrainer `assertSucceeds` (919/920), pin entitlement/blockedAt/blockedReason CF-write-only unaffected (SCENARIO-922).
- [ ] 4.2 [GREEN][EMULATOR-CI] Rewrite `firestore.rules:517-541` — split clause per design D-4 (unchanged/terminated/paused-by-trainer allowed; `active` and `pending` denied for every actor). Verify 4.1 in CI only.
- [ ] 4.3 [LOCAL, verifiable via `jest --listTests`] Fix `functions/package.json` `test:rules` regex (H3) — replace 15-name alternation with suffix pattern `jest --forceExit "-rules\.test\.ts$"`; confirm `template-publishing-rules` now appears.
- [ ] 4.4 Rewrite stale "PR4" comments in `firestore.rules:494-530`.
- [ ] 4.5 [QUALITY GATE] `flutter analyze` 0 issues (sanity, no Dart touched) · `npm --prefix functions test` local suites green · `jest --listTests` shows all `-rules` suites · full `test:rules` emulator run green in CI.
- [ ] 4.6 [MANUAL] Open PR #4 targeting PR3 branch, link ISSUE-4 (`status:approved`, `type:fix` — closes REQ-COACH-LINK-017 hardening gap), 📍PR4.

## Manual Deploy Runbook (human, sequenced — after PR1-PR3 merged)

> 🚨 **Every `[MANUAL]` step below hits PRODUCTION.** `prod` and `treino-dev` are
> the same and only Firebase project — real users. A bare `firebase deploy` with
> no `--project` goes there too: `.firebaserc` fills in `"default":
> "treino-dev"` silently, so the target never appears on screen. This runbook is
> **human-run, with explicit sign-off** — an agent does NOT execute these.
> See [openspec/AGENTS.md](../../AGENTS.md) · #826.

- [ ] M.1 [MANUAL — 🚨 PRODUCTION, do NOT run unattended] `firebase deploy --only functions:linkLoadReconcile,functions:acceptTrainerLink,functions:resumeTrainerLink --project prod` — explicit filters (bare `--only functions` prunes functions absent from `index.ts`). Verify via `firebase functions:list --project prod` (southamerica-east1).
- [ ] M.2 [MANUAL] Smoke on debug build: accept 1 pending, resume 1 paused, pause 1 active → `users/{T}.weightedLoad` moves in all 3.
- [ ] M.3 [MANUAL] Release app to stores with slices 2+3 client changes (iOS review 1-3 days).
- [ ] M.4 [MANUAL] Adoption gate, no new instrumentation (reuses 1.10/2.4/3.2 log lines). Over a 7-day Cloud Logging window: `adoption = 1 − (observed − cf) / observed`, `observed`=count `{event:'link-promoted-observed'}`, `cf`=count `{event:'link-promoted-cf'}`. Proceed only when adoption ≥95% sustained 7 consecutive days AND ≥7 days since M.3.
- [ ] M.5 [MANUAL — 🚨 PRODUCTION, do NOT run unattended] Merge PR #4 if pending. Save current rules (`git show HEAD~1:firestore.rules > rules.prev`). Deploy: `firebase deploy --only firestore:rules --project prod`. This locks out every app build older than M.3 — see the accepted risk below.
- [ ] M.6 [MANUAL] Post-deploy smoke (<10 min): accept via CF succeeds; direct client write to `status:'active'` denied. Monitor `permission-denied` rate 24h.
- [ ] M.R [MANUAL — rollback if needed] Redeploy `rules.prev` (single file, instant) — restores client accept/resume.

**Accepted risk**: no min-app-version enforcement exists (verified — no `minVersion`/Remote Config in `lib/`). After M.5, builds older than M.3 lose `accept`/`resume` permanently until updated; M.4's gate bounds that population to ≤5%. Non-crashing: falls back to the existing generic `permission-denied` snackbar.
