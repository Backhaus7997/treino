# Tasks — athlete-self-measurements

**Change**: `athlete-self-measurements`
**Artifact store**: hybrid (engram topic `sdd/athlete-self-measurements/tasks` + this file)
**TDD mode**: Strict — RED (failing test, confirmed failing against the CURRENT rule/code) MUST be
committed before the GREEN edit that flips it, per `rules-hardening`'s stack (`scripts/rules_test/`,
NOT `functions/src/__tests__/`, which uses the Admin SDK and bypasses rules).
**Scenario namespace**: S1–S12 (rules, `design.md` §10.1) / T1–T6 (Dart, `design.md` §10.2), REQ-ASM-01..09
**Env note (ALL rules-test runs)**: `export JAVA_HOME="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"`
before `scripts/test_rules.sh` (JDK 21 required, `openjdk@21` is brew-installed but unlinked).
**Hard gate**: PR2 tasks are BLOCKED until PR1 is merged AND `firebase deploy --only firestore:rules`
has actually run against the target project. Widget/provider tests use `fake_cloud_firestore`, which does
NOT enforce rules — they will pass locally even if PR1's rule is not live. Shipping PR2 before the rule is
deployed means real self-log writes fail with `permission-denied` in production.

---

## Pre-flight

- [ ] **0.1** Confirm the `session_shares`/`profile_shares` dual-`get()` idiom used in the new read branch is
      NOT new — it is the exact shape already live at `firestore.rules:838-839` (the `setLogs` list gate).
      Reuse it verbatim; do not reinvent the null-safety/`exists()` pattern.
- [ ] **0.2** Confirm no `firestore.indexes.json` change and no new Cloud Function anywhere in this change
      (design §0/§8, ADR-ASM-1/ADR-ASM-2). If any task below appears to need either, STOP — that is a
      design deviation, not a task-level judgment call.

---

## PR1 — Rules + rules-tests (ships FIRST, alone)

**Files:** `firestore.rules` measurements block (`create` at `:992-996`, `read` at `:984-986`), new
`scripts/rules_test/measurements-self-log.test.js` (sibling to `reviews-links.test.js` /
`coach-collections-role.test.js` — same harness: `PROJECT_ID='treino-test-rules'`, firestore-only
`initializeTestEnvironment`, port 8080, `beforeAll`/`afterAll`/`afterEach clearFirestore`). **Zero client
changes.**

### Create rule — REQ-ASM-01 (S1, S2, S3)

- [ ] **1.1** `[RED]` `[REQ-ASM-01][SCENARIO-ASM-01A / S1]` In `measurements-self-log.test.js`, add a
      `seedShare(collection, athleteId, trainerId)` helper (`withSecurityRulesDisabled`) for later reuse.
      Write SCENARIO-ASM-01A: authenticated athlete `U` creates `measurements/{id}` with
      `athleteId==U, recordedBy==U` → `assertSucceeds`. **Confirm this FAILS today** against
      `firestore.rules:992-996` (current rule requires `role=='trainer'`) — this is the RED checkpoint.
- [ ] **1.2** `[RED]` `[REQ-ASM-01][SCENARIO-ASM-01B / S2]` Athlete-role user `U` creates
      `measurements/{id}` with `athleteId==V` (`V≠U`), any `recordedBy` → `assertFails`. **Confirm this
      ALREADY denies today** (role check fails regardless) — AD-1 regression anchor, must stay denied
      through the GREEN step below (non-vacuity: proves the widened rule does not reopen the forge vector).
- [ ] **1.3** `[RED]` `[REQ-ASM-01][SCENARIO-ASM-01C / S3]` Trainer-role user creates
      `measurements/{id}` with `recordedBy==trainerUid`, any `athleteId` → `assertSucceeds`. **Confirm
      this ALREADY passes today** — legit-path anchor, must stay green.
- [ ] **1.4** `[GREEN]` `[REQ-ASM-01]` Edit `firestore.rules:992-996` measurements `create` to the dual
      OR-branch (design §3, verbatim):
      ```
      allow create: if request.auth != null
                    && request.resource.data.recordedBy == request.auth.uid
                    && request.resource.data.athleteId is string
                    && request.resource.data.athleteId.size() > 0
                    && (
                         request.resource.data.athleteId == request.auth.uid
                         || get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role == 'trainer'
                       );
      ```
      `recordedBy == uid` and the `athleteId` shape checks stay a SHARED precondition of both branches
      (short-circuit: self-logging athletes never hit the trainer role `get()`; forgers always do and fail).
- [ ] **1.5** `[GATE]` Re-run 1.1–1.3 — 1.1 flips `assertFails → assertSucceeds`; 1.2 and 1.3 stay exactly
      as they were (deny / allow respectively).

### Read rule — REQ-ASM-02, REQ-ASM-03, REQ-ASM-04 (S4–S10)

- [ ] **1.6** `[RED]` `[REQ-ASM-02][SCENARIO-ASM-02A/02B / S9, S10]` Two regression anchors, already
      passing today, must stay green through the GREEN step: trainer `T` reads a doc with
      `recordedBy==T` → `assertSucceeds` (author branch); athlete `U` reads a self-logged doc
      `athleteId==recordedBy==U` → `assertSucceeds` (subject branch).
- [ ] **1.7** `[RED]` `[REQ-ASM-03][SCENARIO-ASM-03A / S4]` Seed `session_shares/X={trainerId:T}` AND
      `profile_shares/X={trainerId:T}` (both via `withSecurityRulesDisabled`), plus a self-logged doc
      (`recordedBy==athleteId==X`). Trainer `T` reads it → `assertSucceeds`. **Confirm this FAILS today**
      (read rule has only 2 branches, both false for `T`) — RED checkpoint for the whole dual-gate branch.
- [ ] **1.8** `[RED]` `[REQ-ASM-03][SCENARIO-ASM-03B / S5]` Seed `session_shares/X={T}` only (no
      `profile_shares/X`). `T` reads the same self-logged doc → `assertFails`. **Confirm this ALREADY
      denies today** (branch 3 doesn't exist yet) — must stay denied after GREEN (proves the D3 consent
      conjunct is load-bearing, not the live-link alone).
- [ ] **1.9** `[RED]` `[REQ-ASM-03][SCENARIO-ASM-03C / S6]` Seed `profile_shares/X={T}` only (no
      `session_shares/X`). `T` reads → `assertFails`. Already denies today — must stay denied (proves the
      D2 live-link conjunct is load-bearing, not consent alone).
- [ ] **1.10** `[RED]` `[REQ-ASM-04][SCENARIO-ASM-04A / S7]` Seed `session_shares/X={trainerId:B}`
      (current) AND `profile_shares/X={trainerId:A}` (stale, pre-switch). OLD trainer `A` reads the
      self-logged doc → `assertFails`. Already denies today — MUST stay denied after GREEN. **This is
      the headline "no frozen trainer id" test (D2)** — do not let a future edit accidentally gate on
      `profile_shares` alone.
- [ ] **1.11** `[RED]` `[REQ-ASM-03][SCENARIO-ASM-03D / S8]` Neither `session_shares/X` nor
      `profile_shares/X` names `T`. `T` reads the self-logged doc → `assertFails`. Already denies —
      stays denied.
- [ ] **1.12** `[RED]` `[REQ-ASM-05][SCENARIO-ASM-05A / S11]` Consented+linked trainer `T` (both share
      docs seeded as in 1.7). Run the RAW list query `athleteId==X && recordedBy==X` (mirrors the shape
      `watchSelfLoggedForAthlete` will use in PR2 — no repo code needed yet, just the equivalent
      `.where().where().get()` call against the emulator) as `T` → `assertSucceeds`, returns the seeded
      doc. **Confirm this FAILS today** (list path, same missing branch 3) — RED checkpoint for the LIST
      path specifically (not just get-by-id).
- [ ] **1.13** `[RED]` `[REQ-ASM-05][SCENARIO-ASM-05B / S12]` Same raw list query run by a NON-consented
      (or non-linked) trainer → `assertFails` (whole list denied, not silently filtered). **Confirm this
      ALREADY denies today** — stays denied; proves the client (PR2 T2) must tolerate this deny, not
      expect a partial result.
- [ ] **1.14** `[GREEN]` `[REQ-ASM-02][REQ-ASM-03][REQ-ASM-04]` Edit `firestore.rules:984-986`
      measurements `read` to the 3-branch OR (design §4, verbatim):
      ```
      allow read: if request.auth != null
                  && (
                       request.auth.uid == resource.data.recordedBy
                       || request.auth.uid == resource.data.athleteId
                       || (
                            resource.data.recordedBy == resource.data.athleteId
                            && exists(/databases/$(database)/documents/session_shares/$(resource.data.athleteId))
                            && get(/databases/$(database)/documents/session_shares/$(resource.data.athleteId)).data.trainerId == request.auth.uid
                            && exists(/databases/$(database)/documents/profile_shares/$(resource.data.athleteId))
                            && get(/databases/$(database)/documents/profile_shares/$(resource.data.athleteId)).data.trainerId == request.auth.uid
                          )
                     );
      ```
      **Branch order is load-bearing** — comment this inline: branches 1 (author) and 2 (subject) MUST
      precede branch 3 so the author/subject short-circuit pays zero `get()` cost; only a trainer reading
      someone else's self-logged doc reaches the four `exists()`/`get()` calls (design §4, RD5).
- [ ] **1.15** `[GATE]` Re-run 1.6–1.13 — 1.7 and 1.12 flip `assertFails → assertSucceeds`; 1.6, 1.8, 1.9,
      1.10, 1.11, 1.13 stay in their original state (green allow / green deny respectively). Non-vacuity:
      every deny (1.8, 1.9, 1.10, 1.11, 1.13) is paired with the 1.7/1.12 allow.
- [ ] **1.16** `[GATE]` Full `scripts/rules_test/` suite green via `scripts/test_rules.sh` (with the JDK 21
      `JAVA_HOME` export above) — confirms `rules.test.js`, `coach-collections-role.test.js`,
      `reviews-links.test.js`, `chat-media-storage.test.js`, and the new
      `measurements-self-log.test.js` all pass together, no regression to pre-existing suites.
- [ ] **1.17** `[GATE]` `firebase deploy --only firestore:rules --dry-run --project treino-dev` compiles
      with no syntax errors (no `storage.rules` change in this PR, so `--only firestore:rules` alone is
      sufficient — unlike `rules-hardening`, which touched both).
- [ ] **1.18** `[MANUAL]` User's manual step: run `firebase deploy --only firestore:rules` to ship PR1.
      Do this only after 1.16 and 1.17 are green and the PR is merged. **PR2 cannot start real writes
      until this has actually run** (see the hard gate note at the top of this file).

---

## PR2 — Client (ships SECOND, blocked on PR1 merge + deploy)

**Files:** `lib/features/measurements/data/measurement_repository.dart`,
`lib/features/measurements/application/measurement_providers.dart`,
`lib/features/measurements/presentation/log_measurement_screen.dart`,
`lib/features/insights/presentation/measurements_screen.dart`, 3 ARB files. No rules changes.

### Repository — REQ-ASM-05 / T4

- [ ] **2.1** `[RED]` `[REQ-ASM-05][T4]` Create `test/features/measurements/data/measurement_repository_test.dart`
      (new file). Using `FakeFirebaseFirestore`, seed 3 docs for athlete `X`: (a) self-logged
      (`athleteId==X, recordedBy==X`), (b) trainer-recorded (`athleteId==X, recordedBy==trainerY`),
      (c) self-logged for a DIFFERENT athlete `Z`. Assert `repo.watchSelfLoggedForAthlete(X)` emits ONLY
      doc (a). **Confirm RED** — the method does not exist yet (compile failure).
- [ ] **2.2** `[GREEN]` `[REQ-ASM-05]` Add to `measurement_repository.dart`:
      ```dart
      /// Self-logged measurements for [athleteId] (athleteId == recordedBy == athleteId).
      /// Two equality filters, no orderBy — NO composite index required (mirrors
      /// [watchForTrainerAthlete]'s doc comment). Satisfies read branch 3 when the
      /// requesting trainer is consented+linked; caller merges with watchForTrainerAthlete.
      Stream<List<Measurement>> watchSelfLoggedForAthlete(String athleteId) {
        return _collection
            .where('athleteId', isEqualTo: athleteId)
            .where('recordedBy', isEqualTo: athleteId)
            .snapshots()
            .map((snap) => snap.docs.map(_fromDoc).whereType<Measurement>().toList());
      }
      ```
- [ ] **2.3** `[GATE]` Re-run 2.1 — GREEN.

### Provider merge — REQ-ASM-06, REQ-ASM-07 / T1, T2, T3

- [ ] **2.4** `[RED]` `[REQ-ASM-06][T1]` Extend `test/features/measurements/application/measurements_for_athlete_provider_test.dart`:
      seed 1 trainer-recorded doc (Q1 match) + 1 self-logged doc (Q2 match) for the same athlete `X`.
      Assert `measurementsForAthleteProvider(X)` resolves with BOTH, sorted ascending by `recordedAt`.
      **Confirm RED** — the provider currently only queries Q1, so the self-logged doc is missing.
- [ ] **2.5** `[RED]` `[REQ-ASM-06][T2]` Same file: make the self-logged query stream emit a
      `permission-denied` error (e.g. override `measurementRepositoryProvider` with a fake repo whose
      `watchSelfLoggedForAthlete` returns `Stream.error(FirebaseException(...))`). Assert the provider
      STILL yields Q1's rows — no error state, no stream teardown. **Confirm RED** — no merge/error-
      handling logic exists yet.
- [ ] **2.6** `[GREEN]` `[REQ-ASM-06]` Edit `measurementsForAthleteProvider` in `measurement_providers.dart`:
      watch Q1 (`watchForTrainerAthlete`, unchanged) AND Q2 (`watchSelfLoggedForAthlete`, NEW), with Q2
      wrapped `.handleError((_, __) => const <Measurement>[])` so a `permission-denied` degrades to an
      empty Q2 contribution instead of tearing down the merged stream. Merge Q1 ∪ Q2 (dedupe by `id`),
      sort ascending by `recordedAt` (existing contract).
- [ ] **2.7** `[GATE]` Re-run 2.4–2.5 — both GREEN.
- [ ] **2.8** `[RED]` `[REQ-ASM-07][T3]` Extend `test/features/measurements/application/own_measurements_provider_test.dart`:
      seed 1 self-logged + 1 trainer-recorded doc for the same athlete `U`. Assert
      `ownMeasurementsProvider(U)` returns BOTH. This is a **regression anchor** — behavior is unchanged
      by this PR, so it should ALREADY pass; write it explicitly as the REQ-ASM-07 non-regression proof.
- [ ] **2.9** `[GATE]` Confirm 2.8 passes with NO production change required (REQ-ASM-07: athlete vantage
      unchanged by design).

### I18n — must land before the widget GREEN steps below

- [ ] **2.10** `[I18n]` Add 2 keys to `lib/l10n/intl_es_AR.arb`, `lib/l10n/intl_es.arb`,
      `lib/l10n/intl_en.arb` with `@key` description blocks:
      - `measurementsSelfLogNotesHint` — es: "Notas (opcional)…" / en: "Notes (optional)…"
      - `measurementsAddSelfLog` — es: "Agregar medición" / en: "Add measurement" (tooltip/label for the
        MEDIDAS "+" affordance)
      Run `flutter gen-l10n` to regenerate `app_l10n.dart`; verify compile succeeds. **Must land before
      2.12 and 2.15**, which reference these keys.

### Form dual-mode — REQ-ASM-08 / T5

- [ ] **2.11** `[RED]` `[REQ-ASM-08][T5]` Create `test/features/measurements/presentation/log_measurement_screen_test.dart`
      (new file — none exists today). Pump `LogMeasurementScreen.selfLog()` in a `ProviderScope` with
      `currentUidProvider` overridden to `'athleteU'` and `measurementRepositoryProvider` overridden with
      a fake that captures the `Measurement` passed to `.add()`. Fill the weight field, tap GUARDAR,
      assert the captured `Measurement` has `recordedBy == 'athleteU' && athleteId == 'athleteU'`.
      **Confirm RED** — `.selfLog()` doesn't exist yet (compile failure).
- [ ] **2.12** `[GREEN]` `[REQ-ASM-08]` Edit `log_measurement_screen.dart` (design §6, ADR-ASM-6):
      - Add `enum _LogAuthorMode { trainerForAthlete, athleteSelf }`.
      - Change `athleteId` to `final String? athleteId;`; existing default ctor sets
        `_mode = _LogAuthorMode.trainerForAthlete` (unchanged behavior); add
        `const LogMeasurementScreen.selfLog({super.key}) : athleteId = null, _mode = _LogAuthorMode.athleteSelf;`.
      - In `_save()`, drop the implicit trainer-only framing: compute
        `final effectiveAthleteId = widget._mode == _LogAuthorMode.athleteSelf ? currentUid! : widget.athleteId!;`
        — self mode ALWAYS derives `athleteId` from `currentUidProvider`, never from a caller-supplied
        field. Assert `effectiveAthleteId == currentUid` before calling `.add()` in self mode (R5 defense
        in depth, mirrors REQ-ASM-01's rule-side pin).
      - `canSave`/`_save`'s existing `currentUid != null` check already covers both modes — confirm no
        change needed there (it was already role-neutral).
      - Notes hint switches on mode: self mode → `AppL10n.of(context).measurementsSelfLogNotesHint`;
        trainer mode keeps the existing hardcoded "Observaciones del entrenador…" (out of scope to
        migrate — spec only requires the NEW key go through AppL10n).
- [ ] **2.13** `[GATE]` Re-run 2.11 — GREEN.

### MEDIDAS affordance — REQ-ASM-09 / T6

- [ ] **2.14** `[RED]` `[REQ-ASM-09][T6]` Extend `test/features/insights/presentation/measurements_screen_test.dart`:
      pump `MeasurementsScreen(uid: ...)`, find the add ("+") affordance, tap it, pump, assert
      `LogMeasurementScreen` was pushed via a `fullscreenDialog: true` route. **Confirm RED** — no
      affordance exists today.
- [ ] **2.15** `[GREEN]` `[REQ-ASM-09]` Edit `measurements_screen.dart`:
      - Add an `IconButton(icon: Icon(TreinoIcon.plus), tooltip: l10n.measurementsAddSelfLog, onPressed: () => Navigator.of(context).push(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const LogMeasurementScreen.selfLog())))`
        to the `_Header` row (or an equivalent header action consistent with the palette).
      - Update the stale docstring (lines 26-30: "SOLO-LECTURA por ahora... hoy sólo un usuario con rol
        `trainer` puede CREAR mediciones...") — replace with an accurate note that self-log is now
        supported via the "+" affordance, referencing this change.
      - `ownMeasurementsProvider` is already a live stream — do NOT add a manual invalidate (spec note).
- [ ] **2.16** `[GATE]` Re-run 2.14 — GREEN.

### PR2 quality gate

- [ ] **2.17** `[GATE]` `flutter analyze` → 0 NEW issues (baseline is 42 pre-existing, per AGENTS.md).
- [ ] **2.18** `[GATE]` `dart format` on touched files ONLY (the 4 production files + 5 test files +
      3 ARB files listed above) — do not reformat unrelated files.
- [ ] **2.19** `[GATE]` `flutter test` — full suite green (new tests 2.1, 2.4, 2.5, 2.8, 2.11, 2.14 +
      no regressions elsewhere).
- [ ] **2.20** `[GATE]` Re-confirm PR1's rules suite is STILL green (`scripts/test_rules.sh` with the
      JDK 21 export) as a final cross-check before opening PR2 — no drift since PR1 merged.

---

## Review Workload Forecast

| Slice | Files touched | Est. changed lines | Chained PR |
|---|---|---|---|
| PR1 (rules + rules-tests) | `firestore.rules` create+read diff (~30-40 lines incl. comments), new `measurements-self-log.test.js` (~230-260 lines: harness + 12 scenarios) | **~260-300** | PR1 |
| PR2 (client) | `measurement_repository.dart` (+~15), `measurement_providers.dart` (~+20/-10), `log_measurement_screen.dart` (~+35/-10), `measurements_screen.dart` (~+20/-15), 3 ARB files (+~18) → production ~150-170; new `measurement_repository_test.dart` (~60), extended `measurements_for_athlete_provider_test.dart` (+~70), extended `own_measurements_provider_test.dart` (+~35), new `log_measurement_screen_test.dart` (~100-120), extended `measurements_screen_test.dart` (+~50) → tests ~315-335 | **~465-505** | PR2 |

**Totals:** ~725-805 changed lines across 2 PRs. PR1 stays comfortably under the 400-line budget on its
own. **PR2's production-only diff (~150-170 lines) is well under budget; the combined production+test
diff (~465-505) is over 400**, driven mainly by two new test files (repo + form) plus extensions to three
existing suites across data/application/presentation layers — the same pattern `exercise-progression`'s
PR1 hit (370 production / ~680 total) and still shipped as one PR, on the convention that the 400-line
budget is primarily a production-code signal, not a hard cap on test line count.

```text
Decision needed before apply: No
Chained PRs recommended: Yes
Chain strategy: stacked-to-main
400-line budget risk: Medium
```

- **Chained PRs recommended: Yes** — already the locked plan (proposal §7, design §12): PR1 (rules) then
  PR2 (client), not a fresh split decision.
- **Chain strategy: stacked-to-main`** — the ONLY strategy that fits here. PR2 depends on the PR1 rule
  being LIVE in the deployed Firestore project (§ hard gate above), not merely merged in git. A
  feature-branch-chain (tracker branch accumulating both PRs) would not get the rule live until the
  final merge, which breaks PR2's self-log writes for the entire review window. PR1 must merge to main
  AND be deployed (`firebase deploy --only firestore:rules`) before PR2 opens for real-environment
  testing.
- **400-line budget risk: Medium** — PR1 is Low risk (well under budget even at the high estimate). PR2
  is Low risk on production code alone but Medium overall once its 5 test files are counted; no further
  split is warranted because the plan is architecturally locked at 2 PRs (proposal §7 explicitly
  forecloses re-architecting the split) and PR2's four production files form one reviewable, cross-layer
  arc (repo → provider → form → screen) that would be harder to review split apart than together.
- **Decision needed before apply: No** — the split and ship order are already decided by proposal §7 /
  design §12; the only gate `sdd-apply` must honor is the hard dependency above (PR1 deployed before PR2
  ships real writes), which is a sequencing fact, not a delivery-strategy choice.

---

## Quality gate reminder (both PRs)

- `flutter analyze` → 0 NEW issues (baseline 42 pre-existing issues, per AGENTS.md — do not chase the
  baseline down in this change).
- `dart format .` scoped to touched files only.
- `flutter test` → green, including all new RED→GREEN tests above.
- Rules suite → green via `scripts/test_rules.sh` with
  `export JAVA_HOME="$(brew --prefix openjdk@21)/libexec/openjdk.jdk/Contents/Home"` set first.
