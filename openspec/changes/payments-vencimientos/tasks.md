# Tasks: payments-vencimientos

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines | PR1: ~200–280 lines; PR2: ~280–350 lines |
| 400-line budget risk | Medium (each PR within budget; risk if Freezed regen is verbose) |
| Chained PRs recommended | Yes |
| Suggested split | PR1 (Dart + rules + indexes) → PR2 (CF + jest/emulator tests) |
| Delivery strategy | ask-on-risk |
| Chain strategy | feature-branch-chain |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: Medium

### Suggested Work Units

| Unit | Goal | Likely PR | Notes |
|------|------|-----------|-------|
| 1 | Dart `dueAt` + Vencido fix + coexistence gate + rules + indexes | PR1 | Base = feature/payments-vencimientos; safe, no CF dep, legacy fallback active |
| 2 | CF `generateDuePayments` + jest/emulator tests + index.ts export | PR2 | Base = PR1 branch; depends on Unit 1 merged or stacked |

---

## PR1 — Dart + Rules + Indexes [COMPLETE]

### Phase 1: RED — Write failing tests first (PR1)

- [x] 1.1 **[RED]** Write Dart unit test `test/features/payments/domain/payment_due_at_test.dart`: assert `Payment.fromJson` round-trips `dueAt` (non-null Timestamp → DateTime) and null without error. (REQ-VENC-10)
- [x] 1.2 **[RED]** Write Dart unit test for Vencido dueAt-present path (SCENARIO-VENC-08, SCENARIO-VENC-09): assert a pending payment with past `dueAt` is flagged vencido; future `dueAt` is not.
- [x] 1.3 **[RED]** Write Dart unit test for Vencido legacy null-dueAt fallback (SCENARIO-VENC-10, SCENARIO-VENC-11): assert pending+null-dueAt+createdAt before month-start → vencido; same-month → not.
- [x] 1.4 **[RED]** Write Dart unit test for coexistence gate (SCENARIO-VENC-12, SCENARIO-VENC-13): assert that when `athletePayments` contains any doc for `periodKey`, no virtual `CobroPendiente` is added; assert virtual charge IS added when none exists.
- [x] 1.5 **[RED]** Write Firestore rules test stub `test/firestore/payments_rules_test.dart` with skip annotation: (a) SCENARIO-VENC-14 dueAt update DENIED; (b) SCENARIO-VENC-15 markPaid ALLOWED. Emulator NOT available — tests skip.

### Phase 2: GREEN — Domain + Freezed

- [x] 2.1 Add `@TimestampConverter() DateTime? dueAt,` field to `lib/features/payments/domain/payment.dart` after `paidAt`; add json key `'dueAt'`. (REQ-VENC-10)
- [x] 2.2 Run `dart run build_runner build --delete-conflicting-outputs` from `treino/`; regen of `payment.freezed.dart` and `payment.g.dart` — 31 outputs, success.
- [x] 2.3 Verify task 1.1 tests pass (GREEN). Run `flutter analyze` — 0 issues on changed files.

### Phase 3: GREEN — Vencido Fix

- [x] 3.1 In `lib/features/coach_hub/presentation/sections/pagos/widgets/pagos_buckets_provider.dart` (~line 68), replaced the `createdAt`-only vencido expression with dueAt-based + legacy-fallback. (REQ-VENC-11)
- [x] 3.2 Verify tasks 1.2 and 1.3 tests pass (GREEN). Run `flutter analyze`.

### Phase 4: GREEN — Coexistence Gate

- [x] 4.1 In `lib/features/payments/application/pagos_por_cobrar_provider.dart` (mensual + semanal branches), replaced the `alreadyPaid` check (paid-only) with `hasDocForPeriod` (any status). (REQ-VENC-12)
- [x] 4.2 Verify tasks 1.4 tests pass (GREEN). Run `flutter analyze`.

### Phase 5: GREEN — Firestore Rules + Indexes

- [x] 5.1 Audit `lib/features/payments/data/payment_repository.dart` — confirmed `markPaid`/`markManyPaid`/`add` send only `{status, paidAt}` / full toJson (no `dueAt` mutation). (REQ-VENC-13)
- [x] 5.2 Replace the `payments` `update` rule block in `firestore.rules` (~lines 766–785) with field-level rule: `keys().hasOnly([...10 fields...])` + per-field equality including `dueAt` pinned equal-to-existing. (REQ-VENC-13)
- [x] 5.3 Append 3 composite indexes to `firestore.indexes.json`: `(trainerId ASC, status ASC, dueAt ASC)`, `(trainerId ASC, paidAt DESC)`, `(athleteId ASC, status ASC, dueAt ASC)`.
- [x] 5.4 Gate passed: `flutter analyze` 0 issues on MY files + `dart format` clean + `flutter test` 29 passed / 8 skipped (emulator). build_runner 31 outputs.

---

## PR2 — Cloud Function + Tests

### Phase 6: RED — Write failing jest tests first (PR2)

- [ ] 6.1 **[RED]** Create `functions/src/__tests__/generate-due-payments.test.ts` mirroring `notify-link-change.test.ts` test setup (emulator env `FIRESTORE_EMULATOR_HOST=127.0.0.1:8080`, `GCLOUD_PROJECT=treino-dev`, `admin.initializeApp({projectId},'test-gdp')`, seed/cleanup helpers). Write 8 SCENARIO-numbered test cases — all RED (import will fail since handler doesn't exist yet): (SCENARIO-VENC-02) mensual link → creates pending doc with correct id + last-day-of-month dueAt + periodKey; (SCENARIO-VENC-04) semanal link → creates pending doc with `YYYY-Www` periodKey + Sunday-end dueAt; (SCENARIO-VENC-05) idempotent 2nd run → `created:0`; (SCENARIO-VENC-07) skip when paid doc exists; (SCENARIO-VENC-06) skip when legacy auto-id pending doc exists for period; (SCENARIO-VENC-03) skip porSesion + suelto; skip when `athlete_billing` absent; (REQ-VENC-03) non-active link → not processed. (REQ-VENC-01 to REQ-VENC-08)
- [ ] 6.2 Confirm RED: run `npm test -- --testPathPattern=generate-due-payments` with emulator running; all 8 cases fail with import/not-found error.

### Phase 7: GREEN — Pure Handler

- [ ] 7.1 Create `functions/src/payments/generate-due-payments.ts`. Export `interface GenerateDueResult { created: number; skipped: number; scanned: number; }`. (REQ-VENC-07)
- [ ] 7.2 Implement ISO-week helpers inside the file (port Thursday/jan4 math exactly from `pagos_por_cobrar_provider.dart` lines 20-45): `isoWeekYear(d: Date): number` and `isoWeekNumber(d: Date): number`. (REQ-VENC-04)
- [ ] 7.3 Implement `periodKey` computation: mensual = `${y}-${String(m+1).padStart(2,'0')}`; semanal = `${isoWeekYear(now)}-W${String(isoWeekNumber(now)).padStart(2,'0')}`. (REQ-VENC-04)
- [ ] 7.4 Implement `dueAt` computation: mensual = `new Date(Date.UTC(y, m+1, 0, 23, 59, 59))`(last day of month); semanal = Sunday 23:59:59 UTC of the ISO week. (REQ-VENC-08)
- [ ] 7.5 Implement `export async function generateDuePaymentsHandler(app: admin.app.App, now: Date): Promise<GenerateDueResult>`. Algorithm: (1) query active `trainer_links`; (2) per link read `athlete_billing/${trainerId}_${athleteId}`, skip absent; (3) branch cadence — skip porSesion/suelto; (4) compute periodKey + dueAt; (5) field-existence check `payments.where(trainerId).where(athleteId).where(periodKey).limit(1)`; (6) if any doc → skipped++, continue; (7) else `payments.doc(id).create({...pending, dueAt: Timestamp.fromDate(dueAt), createdAt: FieldValue.serverTimestamp()})` with catch ALREADY_EXISTS → skipped++. (REQ-VENC-02, REQ-VENC-03, REQ-VENC-04, REQ-VENC-05, REQ-VENC-06)
- [ ] 7.6 Implement `concept` string: mensual = `Mensual {MesNombre} {year}` / semanal = `Semana {ww}` (reuse client string format for UI consistency). (REQ-VENC-04)

### Phase 8: GREEN — onSchedule Wrapper + Export

- [ ] 8.1 Add the `onSchedule` wrapper in `functions/src/payments/generate-due-payments.ts`: `export const generateDuePayments = onSchedule({ schedule:"0 3 * * *", timeZone:"America/Argentina/Buenos_Aires", region:"southamerica-east1" }, async () => { await generateDuePaymentsHandler(getApp(), new Date()); });` (REQ-VENC-01)
- [ ] 8.2 Add `export { generateDuePayments } from "./payments/generate-due-payments";` to `functions/src/index.ts`.
- [ ] 8.3 Run `npm run build` (tsc) in `functions/` — must compile with 0 errors.

### Phase 9: VERIFY + Gate (PR2)

- [ ] 9.1 Run `npm test -- --testPathPattern=generate-due-payments` with emulator running; all 8 cases GREEN. (SCENARIO-VENC-02 to SCENARIO-VENC-07 + REQ-VENC-03, REQ-VENC-07)
- [ ] 9.2 Run full functions test suite (`npm test`) — existing tests still green.
- [ ] 9.3 Run functions lint (`npm run lint`) — 0 errors.
- [ ] 9.4 Note in PR description: deploy is NOT part of this PR. User runs `firebase deploy --only functions,firestore:rules,firestore:indexes` from `treino/` after merge.

---

## Sequential Dependency Map

```
1.1–1.5 (RED) → 2.1–2.3 (GREEN domain) → 3.1–3.2 (GREEN buckets)
             → 4.1–4.2 (GREEN gate)
             → 5.1–5.4 (GREEN rules+indexes)
             ↓ [PR1 merged]
6.1–6.2 (RED CF tests) → 7.1–7.6 (GREEN handler) → 8.1–8.3 (wrapper+export) → 9.1–9.4 (verify)
```

Tasks within phases 3, 4, 5 can proceed in parallel after 2.3 is green.
Tasks within phase 7 (7.1–7.6) can proceed in parallel after 6.1 establishes the test structure.
