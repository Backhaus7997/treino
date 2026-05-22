# Tasks: Coach Agenda (Fase 5 · Etapa 6)

**Change**: `coach-agenda`
**Strict TDD**: ACTIVE (`flutter test`)
**Delivery**: Chained PRs — `ask-on-risk`
**PR1 branch**: `feat/coach-agenda-data` (base: `main`)
**PR2 branch**: `feat/coach-agenda-ui-athlete` (base: `feat/coach-agenda-data` after merge)
**PR3 branch**: `feat/coach-agenda-ui-trainer` (base: `feat/coach-agenda-data` after merge; parallelizable with PR2 after PR1 lands)

---

## Review Workload Forecast

| Field | Value |
|-------|-------|
| Estimated changed lines — PR1 | ~400–650 (prod ~400 + tests ~250) |
| Estimated changed lines — PR2 | ~300–500 (prod ~300 + tests ~200) |
| Estimated changed lines — PR3 | ~400–600 (prod ~400 + tests ~200) |
| Estimated changed lines — total | ~1100–1750 |
| 400-line budget risk — PR1 | **High** — transaction logic + 4 domain models + 2 repos; likely needs `size:exception` |
| 400-line budget risk — PR2 | Medium — 3 new screens/widgets; within budget if table_calendar config is lean |
| 400-line budget risk — PR3 | **High** — AvailabilityEditorScreen is complex; likely needs `size:exception` |
| Chained PRs recommended | Yes |
| Suggested split | PR1 (`feat/coach-agenda-data`) → PR2 (`feat/coach-agenda-ui-athlete`) ∥ PR3 (`feat/coach-agenda-ui-trainer`) |
| Delivery strategy | `ask-on-risk` |
| Chain strategy | `feature-branch-chain` |
| Decision needed before apply | Yes |

Decision needed before apply: Yes
Chained PRs recommended: Yes
Chain strategy: feature-branch-chain
400-line budget risk: High

> **ACTION REQUIRED before apply starts**: PR1 (~650 LOC) and PR3 (~600 LOC) exceed the 400-line budget. Under `ask-on-risk` strategy you must choose one of:
> - **`size:exception`** — keep each as a single oversized PR with maintainer approval (note it in the PR description)
> - **Further split** — split PR1 into domain models + repositories, or PR3 into editor screen + calendar view
>
> Recommended: flag both PR1 and PR3 with `size:exception` in their PR descriptions. The chained-PR structure already limits blast radius. Confirm before `sdd-apply` is launched.

### Suggested Work Units

| Unit | Goal | Branch | Base | Notes |
|------|------|--------|------|-------|
| PR1 | Data layer: models + repos + providers + rules | `feat/coach-agenda-data` | `main` | ~650 LOC; `size:exception` recommended |
| PR2 | Athlete UI: agenda screen + booking flow | `feat/coach-agenda-ui-athlete` | `feat/coach-agenda-data` (post-merge main) | ~500 LOC; within budget |
| PR3 | Trainer UI: agenda tab + editor screen | `feat/coach-agenda-ui-trainer` | `feat/coach-agenda-data` (post-merge main) | ~600 LOC; `size:exception` recommended; parallelizable with PR2 |

---

## PR1: Coach Agenda — Data Layer

> Branch `feat/coach-agenda-data` from `main`. Self-contained; no UI consumer. Fully mergeable standalone.
> **Cross-PR conflict risk**: `firestore.rules` may conflict with Dev C (Etapa 5 chat feature). Coordinate merge timing.

---

### T01 [x] [DOCS] Amend SCENARIO-491 in spec — ADR-1 flip semantics

> Status: ✅ Done — commit b0c18f9

- **Files**: `openspec/changes/coach-agenda/spec.md` (MODIFY); Engram `sdd/coach-agenda/spec` (#117 via mem_save with topic_key)
- **SCENARIOs**: SCENARIO-491
- **REQs**: REQ-COACH-AGENDA-006
- **Description**: Replace SCENARIO-491 body. New text:
  - GIVEN: a confirmed `appointment` exists at `appointments/tA_1748000000000` with `status: 'cancelled'` (post-cancellation by a previous athlete; `cancellationLog` array has ≥1 entry)
  - WHEN: a new athlete calls `book(BookingRequest(trainerId: 'tA', athleteId: 'aC', startsAt: …))` for the same slot
  - THEN: `bookAppointment` runs a Firestore transaction that atomically flips `status` to `'confirmed'` with the new `athleteId` AND appends a new record to the existing `cancellationLog` array
  - RESULT: booking succeeds; no exception thrown; `Appointment` with `status: confirmed` and `athleteId: 'aC'` is returned
  - SIDE EFFECTS: `cancellationLog` array retains all previous entries (actor uid, timestamp, reason)
  Document as "Amendment — ADR-1 flip semantics" in a comment block above the scenario.
- **Acceptance**: Both `spec.md` and Engram spec reflect the new SCENARIO-491 text. Commit: `docs(sdd): amend SCENARIO-491 to ADR-1 flip semantics`.

---

### T02 [x] [CHORE] Branch creation + pubspec update

> Status: ✅ Done — commit fe08a0b (pubspec) + branch feat/coach-agenda-data created


- **Files**: `pubspec.yaml` (MODIFY)
- **Description**: Checkout `feat/coach-agenda-data` from `main`. Add `table_calendar: ^3.2.0` to `pubspec.yaml` under `dependencies`. Run `flutter pub get` and verify it resolves cleanly (check `pubspec.lock` for exact resolved version). Confirm `flutter test` baseline green. Create test directories: `test/features/coach/domain/`, `test/features/coach/data/`, `test/features/coach/application/`.
- **Acceptance**: `git branch` shows `feat/coach-agenda-data`; `pubspec.lock` contains `table_calendar` at a 3.2.x version; `flutter test` exits 0.

---

### T03 [x] [RED] Unit tests — domain models (AvailabilityRule + AvailabilityOverride)

> Status: ✅ Done — commit 1a10d22

- **Files**: `test/features/coach/domain/availability_rule_test.dart` (NEW); `test/features/coach/domain/availability_override_test.dart` (NEW)
- **SCENARIOs**: 478, 479, 480, 481
- **REQs**: REQ-COACH-AGENDA-001, REQ-COACH-AGENDA-002
- **Description**: Write failing tests:
  1. `AvailabilityRule` JSON round-trip — all fields preserved, `slotDurationMin` stays valid — SCENARIO-478.
  2. `AvailabilityRule.fromJson` with `slotDurationMin: 45` → throws `AssertionError` or `ArgumentError` — SCENARIO-479.
  3. `AvailabilityOverride` block type round-trip — `type: block`, time fields null — SCENARIO-480.
  4. `AvailabilityOverride` extra type round-trip — `type: extra`, all time fields preserved — SCENARIO-481.
  Models undefined → tests fail with `Error`.
- **Acceptance**: Both test files exit non-zero; 4 test cases total declared.

---

### T04 [x] [GREEN+CODEGEN] Implement AvailabilityRule + AvailabilityOverride models

> Status: ✅ Done — commit 40fbd42 (freezed sealed union with `type` discriminator, slotDurationMin @Assert guard)

- **Files**: `lib/features/coach/domain/availability_rule.dart` (NEW + `.g.dart`); `lib/features/coach/domain/availability_override.dart` (NEW + `.g.dart`)
- **REQs**: REQ-COACH-AGENDA-001, REQ-COACH-AGENDA-002
- **Description**: Implement both as `@freezed` classes. `AvailabilityRule`: fields per spec; assert `[30, 60, 90, 120].contains(slotDurationMin)` in constructor. `AvailabilityOverride`: freezed sealed union with `.block({id, trainerId, date})` and `.extra({id, trainerId, date, startHour, startMinute, endHour, endMinute, slotDurationMin})` — discriminated by `type` field in JSON (ADR-6). Run `flutter pub run build_runner build --delete-conflicting-outputs`.
- **Acceptance**: All 4 tests in T03 green; `flutter analyze` 0 issues on new files.

---

### T05 [1] [RED] Unit tests — Appointment model

- **Files**: `test/features/coach/domain/appointment_test.dart` (NEW)
- **SCENARIOs**: 482, 483, 484
- **REQs**: REQ-COACH-AGENDA-003
- **Description**: Write failing tests:
  1. `Appointment` JSON round-trip, `status: confirmed` — SCENARIO-482.
  2. `AppointmentStatus.cancelled.toJson()` returns string `'cancelled'` — SCENARIO-483.
  3. Appointment constructed with `trainerId: 'tA'`, `startsAt` ms `1748000000000` → `id == 'tA_1748000000000'` — SCENARIO-484.
  Model undefined → tests fail.
- **Acceptance**: Test file exits non-zero; 3 test cases declared.

---

### T06 [1] [GREEN+CODEGEN] Implement Appointment model + AgendaExceptions

- **Files**: `lib/features/coach/domain/appointment.dart` (NEW + `.g.dart`); `lib/features/coach/domain/agenda_exceptions.dart` (NEW)
- **REQs**: REQ-COACH-AGENDA-003
- **Description**: `Appointment`: `@freezed` with deterministic `id` = `'${trainerId}_${startsAt.millisecondsSinceEpoch}'` computed in factory; `status` enum `AppointmentStatus { confirmed, cancelled }` with `toJson`/`fromJson`. `agenda_exceptions.dart`: define `SlotAlreadyTakenException`, `CancellationTooLateException`, `BookingTooFarAheadException`. Run codegen. Argentina UTC-3 note: `// TZ hardcoded UTC-3 Argentina — see ADR-7; revisit for TZ migration`.
- **Acceptance**: All 3 tests in T05 green.

---

### T07 [1] [RED] Unit tests — `computeFreeSlots` pure function

- **Files**: `test/features/coach/application/compute_free_slots_test.dart` (NEW)
- **SCENARIOs**: 517 (block override), 518 (extra override), 519 (delete override), derived REQ-026 (rule-edit survivor), 500 (no rules → empty)
- **REQs**: REQ-COACH-AGENDA-002, REQ-COACH-AGENDA-022, REQ-COACH-AGENDA-026
- **Description**: Write failing tests (pure Dart — no Firestore):
  1. Block override for date → `computeFreeSlots(...)` returns `[]`.
  2. Extra override for Saturday (10:00–12:00, 60 min) → returns `[10:00, 11:00]`.
  3. Block override deleted (not present) → rule-derived slots re-appear.
  4. Appointment at 11:30 remains confirmed when rule `endHour` reduced to 11:00 (appointment not added to free list, but function doesn't touch existing appointments — free slots use updated rule).
  5. No rules, no overrides → returns `[]`.
  Function undefined → tests fail.
- **Acceptance**: Test file exits non-zero; 5 test cases declared.

---

### T08 [1] [GREEN] Implement `computeFreeSlots`

- **Files**: `lib/features/coach/application/compute_free_slots.dart` (NEW)
- **REQs**: REQ-COACH-AGENDA-002, REQ-COACH-AGENDA-022
- **Description**: Pure function `List<DateTime> computeFreeSlots(DateTime date, List<AvailabilityRule> rules, List<AvailabilityOverride> overrides, List<Appointment> appointments)`. Algorithm per ADR-2: (1) if `block` override for `date` → return `[]`; (2) build `SplayTreeSet<DateTime>` from rules for weekday (emit minute-precision UTC slots per ADR-7); (3) add `extra` override slots (SplayTreeSet dedupes); (4) subtract confirmed appointments by exact `startsAt`; (5) Argentina TZ comment on slot construction. O(R*S + O + A).
- **Acceptance**: All 5 tests in T07 green.

---

### T09 [1] [RED] Unit tests — AvailabilityRepository

- **Files**: `test/features/coach/data/availability_repository_test.dart` (NEW)
- **SCENARIOs**: 485, 486, 487, 488
- **REQs**: REQ-COACH-AGENDA-004, REQ-COACH-AGENDA-005
- **Description**: Using `fake_cloud_firestore`. Write failing tests:
  1. `addRule(rule)` → doc at `coach_availability_rules/r1` with matching fields — SCENARIO-485.
  2. `deleteRule('tA', 'r1')` → doc at `coach_availability_rules/r1` no longer exists — SCENARIO-486.
  3. `watchRules('tA')` with tA×2 rules + tB×1 rule → emits only tA's 2 rules — SCENARIO-487.
  4. `watchOverrides('tA', 2026-06-01, 2026-06-10)` with overrides on Jun-01 and Jun-15 → emits only Jun-01 override — SCENARIO-488.
  Repository undefined → tests fail.
- **Acceptance**: Test file exits non-zero; 4 test cases declared.

---

### T10 [1] [GREEN] Implement AvailabilityRepository

- **Files**: `lib/features/coach/data/availability_repository.dart` (NEW)
- **REQs**: REQ-COACH-AGENDA-004, REQ-COACH-AGENDA-005
- **Description**: Concrete `FirestoreAvailabilityRepository` implementing `AvailabilityRepository`. Collections: `coach_availability_rules`, `coach_availability_overrides`. `watchRules`: Firestore query `.where('trainerId', isEqualTo: trainerId)`. `watchOverrides`: query by `trainerId` + `date >= from && date <= to` (Firestore range on `date` field stored as Timestamp). `addOverride`/`deleteOverride` per spec.
- **Acceptance**: All 4 tests in T09 green.

---

### T11 [1] [RED] Unit tests — AppointmentRepository (booking)

- **Files**: `test/features/coach/data/appointment_repository_booking_test.dart` (NEW)
- **SCENARIOs**: 489, 490, 491 (amended), 496
- **REQs**: REQ-COACH-AGENDA-006, REQ-COACH-AGENDA-009
- **Description**: Using `fake_cloud_firestore`. Write failing tests:
  1. `book(req)` — no prior doc → creates `appointments/tA_1748000000000` with `status: confirmed`, `athleteId` set — SCENARIO-489.
  2. `book(req)` — doc exists with `status: confirmed` → throws `SlotAlreadyTakenException`, no mutation — SCENARIO-490.
  3. `book(req)` — doc exists with `status: cancelled` (has `cancellationLog` entry) → FLIPS `status` to `confirmed` with new `athleteId`, APPENDS to `cancellationLog` — **amended SCENARIO-491 per ADR-1**.
  4. `book(req)` with `startsAt` 29 days out → throws `BookingTooFarAheadException` — SCENARIO-496.
  Repository undefined → tests fail.
- **Acceptance**: Test file exits non-zero; 4 test cases declared.

---

### T12 [1] [GREEN] Implement AppointmentRepository — booking transaction (ADR-5 + ADR-1)

- **Files**: `lib/features/coach/data/appointment_repository.dart` (NEW, partial — `book` + helpers)
- **REQs**: REQ-COACH-AGENDA-006, REQ-COACH-AGENDA-009
- **Description**: `book(BookingRequest req)`: (1) assert 28-day horizon; (2) `runTransaction`: `txn.get(docRef)` → if exists AND `status == confirmed` → throw `SlotAlreadyTakenException`; if exists AND `status == cancelled` → build payload preserving prior `cancellationLog` + appending new entry + flipping `status` to `confirmed` + updating `athleteId`/`athleteDisplayName` → `txn.set(docRef, payload)`; if absent → `txn.set(docRef, newPayload)`. SDK retries up to 5× on contention. `BookingRequest` asserts minute-precision per ADR-7.
  **⚠ HIGHEST-COMPLEXITY BLOCK — flag for apply**: transaction must implement ADR-5 + ADR-1 exactly. Reads MUST precede writes (1 read / 1 write per Firestore SDK contract).
- **Acceptance**: All 4 tests in T11 green.

---

### T13 [1] [RED] Unit tests — AppointmentRepository (cancellation + queries)

- **Files**: `test/features/coach/data/appointment_repository_cancel_test.dart` (NEW); `test/features/coach/data/appointment_repository_query_test.dart` (NEW)
- **SCENARIOs**: 492, 493, 494, 495
- **REQs**: REQ-COACH-AGENDA-007, REQ-COACH-AGENDA-008
- **Description**: Write failing tests:
  1. `cancel(appointmentId, now)` — 48h ahead → doc has `status: cancelled` — SCENARIO-492.
  2. `cancel(appointmentId, now)` — 12h ahead → throws `CancellationTooLateException`, status unchanged — SCENARIO-493.
  3. `watchForAthlete(athleteId)` — 15 past + 2 future confirmed → emits exactly 12 items (10 past + 2 future) — SCENARIO-494.
  4. `watchForTrainer('tA', from, to)` — 1 confirmed + 1 cancelled in range + 1 outside → emits exactly 2 — SCENARIO-495.
- **Acceptance**: Both test files exit non-zero; 4 test cases total declared.

---

### T14 [1] [GREEN] Complete AppointmentRepository — cancel + queries

- **Files**: `lib/features/coach/data/appointment_repository.dart` (MODIFY — add `cancel`, `watchForAthlete`, `watchForTrainer`)
- **REQs**: REQ-COACH-AGENDA-007, REQ-COACH-AGENDA-008
- **Description**: `cancel`: fetch doc, check 24h cutoff (throw `CancellationTooLateException` if ≤24h), update `status: cancelled`. `watchForAthlete`: query `athleteId == athleteId`, order `startsAt ASC`; client-side split past (limit 10, most recent) + future (all confirmed). `watchForTrainer`: Firestore range query `trainerId + startsAt between from and to`.
- **Acceptance**: All 4 tests in T13 green.

---

### T15 [1] [RED] Provider tests — `agenda_providers.dart`

- **Files**: `test/features/coach/application/agenda_providers_test.dart` (NEW)
- **SCENARIOs**: REQ-COACH-AGENDA-010 (provider contract)
- **REQs**: REQ-COACH-AGENDA-010
- **Description**: Using `ProviderContainer` with fake repo overrides. Write failing tests:
  1. `availabilityRulesProvider('tA')` with repo emitting `[rule1, rule2]` → state is `AsyncData([rule1, rule2])`.
  2. `availabilityOverridesProvider(OverridesKey('tA', range))` → emits override list.
  3. `appointmentsForAthleteProvider('aB')` → emits athlete appointment list.
  4. `appointmentsForTrainerProvider(TrainerRangeKey('tA', range))` → emits trainer appointment list.
  5. All 4 providers are `StreamProvider.autoDispose.family` — verify via type assertion.
  Provider file undefined → tests fail.
- **Acceptance**: Test file exits non-zero; 5 test cases declared.

---

### T16 [1] [GREEN] Implement `agenda_providers.dart`

- **Files**: `lib/features/coach/application/agenda_providers.dart` (NEW); private key wrappers `_OverridesKey`, `_TrainerRangeKey`, `_SlotKey` as freezed classes in the same file or a `agenda_provider_keys.dart` companion
- **REQs**: REQ-COACH-AGENDA-010
- **Description**: 4 `StreamProvider.autoDispose.family` providers per ADR-3 + spec. Freezed key wrappers for value-equality (ADR-3). Add `freeSlotsProvider` as derived sync `Provider` watching rules + overrides + appointments, calling `computeFreeSlots`. Run codegen for key wrappers.
- **Acceptance**: All 5 tests in T15 green.

---

### T17 [1] [MOD] `firestore.rules` — 3 new collection blocks + 24h CEL

- **Files**: `firestore.rules` (MODIFY); `scripts/rules_test/rules.test.js` (MODIFY — add skipped stubs)
- **SCENARIOs**: 525, 526, 527
- **REQs**: REQ-COACH-AGENDA-027, REQ-COACH-AGENDA-028, REQ-COACH-AGENDA-029
- **Description**: Add 3 new `match` blocks:
  1. `coach_availability_rules/{ruleId}`: `allow read: if request.auth != null`; `allow write: if request.auth.uid == request.resource.data.trainerId`.
  2. `coach_availability_overrides/{overrideId}`: `allow read: if request.auth != null`; `allow write: if request.auth.uid == request.resource.data.trainerId`.
  3. `appointments/{docId}`: `allow read: if request.auth != null`; `allow create: if request.auth.uid == request.resource.data.athleteId && exists(/databases/$(database)/documents/coach_links/$(request.resource.data.trainerId + '_' + request.auth.uid)) && get(/databases/$(database)/documents/coach_links/$(request.resource.data.trainerId + '_' + request.auth.uid)).data.status == 'active'`; `allow update: if request.auth.uid == resource.data.athleteId && (request.resource.data.status == 'cancelled' && request.resource.data.startsAt.toMillis() - request.time.toMillis() > 86400000) || (request.resource.data.status == 'confirmed' && exists(...active link...))`.
  Add emulator-skipped stubs in `rules.test.js` for SCENARIO-525, 526, 527 per Decision #25 pattern.
  **Cross-PR conflict risk**: coordinate with Dev C on `firestore.rules` merge timing.
- **Acceptance**: Rules blocks present with correct CEL; stubs compile and are skipped (not failing); existing rules unchanged.

---

### T18 [1] [MOD] Register `agenda` route in `router.dart`

- **Files**: `lib/app/router.dart` (MODIFY)
- **REQs**: REQ-COACH-AGENDA-011, REQ-COACH-AGENDA-012
- **Description**: Under `/coach` ShellRoute, add `GoRoute(path: 'agenda', pageBuilder: (ctx, state) => _noAnim(AthleteAgendaScreen(trainerId: state.extra as String)))`. Import stub `AthleteAgendaScreen` (can be empty widget for now — PR2 fills it). This task lands in PR1 so the route exists before PR2 tests navigate to it.
- **Acceptance**: `flutter analyze` 0 issues; existing routes unbroken.

---

### T19 [1] [QA] PR1 quality gate

- **Files**: none (command-only)
- **Description**: Run `flutter analyze` (0 issues), `dart format .` (no unformatted files), `flutter test` (full suite green including all PR1 tests). BLOCKER — do not open PR1 until all three exit 0.
- **Acceptance**: All three commands exit 0.

---

## PR2: Coach Agenda — Athlete UI

> Branch `feat/coach-agenda-ui-athlete` from `feat/coach-agenda-data` (or rebased onto merged `main` after PR1 lands).
> PR2 tasks MUST NOT begin until PR1 is merged.
> **Cross-PR conflict risk**: `athlete_coach_view.dart` may also be touched by Dev C (Etapa 5). Coordinate merge timing.

---

### T20 [2] [CHORE] Branch + `agenda_strings.dart`

- **Files**: `lib/features/coach/presentation/agenda_strings.dart` (NEW)
- **REQs**: ADR-4 (all locked strings)
- **Description**: Checkout `feat/coach-agenda-ui-athlete` from merged `main`. Create test directories: `test/features/coach/presentation/`. Create `agenda_strings.dart` with all locked ADR-4 constants: `slotTakenRace`, `cancelTooLate`, `bookingTooFar`, `athleteEmptyNoRules`, `trainerEmptyNoRules`, `confirmBooking(date, time)`, `confirmCancel`, `bookingSuccess`, `cancelSuccess`, `genericError`, `verAgendaButton`. No inline strings in widget `build` methods.
- **Acceptance**: File compiles; `flutter analyze` 0 issues.

---

### T21 [2] [RED] Widget tests — `_LinkStateCard` "VER AGENDA DEL PF" button

- **Files**: `test/features/coach/presentation/athlete_coach_view_agenda_test.dart` (NEW)
- **SCENARIOs**: 497, 498
- **REQs**: REQ-COACH-AGENDA-011
- **Description**: Write failing tests:
  1. `_LinkStateCard` rendered with `link.status == active` → button with text `'VER AGENDA DEL PF'` visible — SCENARIO-497.
  2. `_LinkStateCard` rendered with `link.status == pending` (or no link) → no `'VER AGENDA DEL PF'` button — SCENARIO-498.
  Button not yet added → tests fail.
- **Acceptance**: Test file exits non-zero; 2 test cases declared.

---

### T22 [2] [GREEN] Inject "VER AGENDA DEL PF" in `_LinkStateCard`

- **Files**: `lib/features/coach/athlete_coach_view.dart` (MODIFY)
- **REQs**: REQ-COACH-AGENDA-011
- **Description**: In `_LinkStateCard.build`, add `if (link.status == LinkStatus.active) ElevatedButton(onPressed: () => context.push('/coach/agenda', extra: link.trainerId), child: Text(AgendaStrings.verAgendaButton))`. Position between `_ShareToggle` and `_ActionRow` per design.
- **Acceptance**: Both tests in T21 green; existing `athlete_coach_view` tests remain green.

---

### T23 [2] [RED] Widget tests — `AthleteAgendaScreen` calendar rendering

- **Files**: `test/features/coach/presentation/athlete_agenda_screen_test.dart` (NEW)
- **SCENARIOs**: 499, 500, 511
- **REQs**: REQ-COACH-AGENDA-012, REQ-COACH-AGENDA-018
- **Description**: Write failing tests:
  1. Provider emitting 2 free slots on a Tuesday → corresponding day shows a dot marker (`calendarBuilders.markerBuilder` emits a widget) — SCENARIO-499.
  2. No rules → no day has dot marker — SCENARIO-500.
  3. No rules → `AthleteAgendaScreen` shows `'Tu PF todavía no configuró horarios.'` and no `TableCalendar` widget — SCENARIO-511.
  Screen undefined → tests fail.
- **Acceptance**: Test file exits non-zero; 3 test cases declared.

---

### T24 [2] [GREEN] Implement `AthleteAgendaScreen` skeleton + calendar

- **Files**: `lib/features/coach/presentation/athlete_agenda_screen.dart` (NEW)
- **REQs**: REQ-COACH-AGENDA-012, REQ-COACH-AGENDA-018
- **Description**: `AthleteAgendaScreen(String trainerId)` `ConsumerWidget`. Watch `availabilityRulesProvider(trainerId)`. Empty state: if no rules → show `AgendaStrings.athleteEmptyNoRules`. Otherwise render `TableCalendar` (via `table_calendar: ^3.2.0`) with `calendarBuilders.markerBuilder` showing a dot for days with free slots (derived from `freeSlotsProvider`). Use `AppPalette.of(context)`, `TreinoIcon.X`. All copy from `AgendaStrings`.
- **Acceptance**: All 3 tests in T23 green.

---

### T25 [2] [RED] Widget tests — `_DaySlotsSheet`

- **Files**: `test/features/coach/presentation/day_slots_sheet_test.dart` (NEW)
- **SCENARIOs**: 501, 502
- **REQs**: REQ-COACH-AGENDA-013
- **Description**: Write failing tests:
  1. `_DaySlotsSheet` with 2 free slots at 09:00, 10:00 → bottom sheet shows two `ActionChip` widgets labeled `'09:00'` and `'10:00'` — SCENARIO-501.
  2. `_DaySlotsSheet` with empty slot list → shows text `'Tu PF todavía no configuró horarios.'` — SCENARIO-502.
  Widget undefined → tests fail.
- **Acceptance**: Test file exits non-zero; 2 test cases declared.

---

### T26 [2] [GREEN] Implement `_DaySlotsSheet`

- **Files**: `lib/features/coach/presentation/widgets/day_slots_sheet.dart` (NEW)
- **REQs**: REQ-COACH-AGENDA-013
- **Description**: `_DaySlotsSheet` bottom sheet widget. Props: `List<DateTime> slots`, `Function(DateTime) onSlotTap`. Renders `ActionChip` per slot with label `HH:mm` (local time). Empty state: `AgendaStrings.athleteEmptyNoRules`. On chip tap: call `onSlotTap(slot)`.
- **Acceptance**: Both tests in T25 green.

---

### T27 [2] [RED] Widget tests — booking confirmation + success + race conflict

- **Files**: `test/features/coach/presentation/athlete_agenda_screen_test.dart` (MODIFY — add test group)
- **SCENARIOs**: 503, 504, 505
- **REQs**: REQ-COACH-AGENDA-014, REQ-COACH-AGENDA-015
- **Description**: Write failing tests:
  1. Tap slot chip → confirmation `AlertDialog` appears with slot datetime — SCENARIO-503.
  2. Confirm dialog + `book(...)` succeeds → sheet closes + success `SnackBar` visible — SCENARIO-504.
  3. Confirm dialog + `book(...)` throws `SlotAlreadyTakenException` → error `SnackBar` with `'Ese horario fue reservado justo ahora. Probá con otro.'` + slot chip gone from sheet — SCENARIO-505.
  Booking logic not yet wired → tests fail.
- **Acceptance**: 3 new test cases exit non-zero.

---

### T28 [2] [GREEN] Wire booking flow in `AthleteAgendaScreen`

- **Files**: `lib/features/coach/presentation/athlete_agenda_screen.dart` (MODIFY); `lib/features/coach/presentation/widgets/day_slots_sheet.dart` (MODIFY — pass callback)
- **REQs**: REQ-COACH-AGENDA-014, REQ-COACH-AGENDA-015
- **Description**: On calendar day tap → open `_DaySlotsSheet`. On chip tap → `showDialog` confirmation with `AgendaStrings.confirmBooking(date, time)`. On confirm → call `AppointmentRepository.book(req)`. On `SlotAlreadyTakenException` → show error snackbar + remove slot from local state. On success → close sheet + show `AgendaStrings.bookingSuccess` snackbar.
- **Acceptance**: All 3 tests in T27 green.

---

### T29 [2] [RED] Widget tests — past appointments list

- **Files**: `test/features/coach/presentation/athlete_agenda_screen_test.dart` (MODIFY — add test group)
- **SCENARIOs**: 506, 507
- **REQs**: REQ-COACH-AGENDA-016
- **Description**: Write failing tests:
  1. 3 past confirmed appointments → 3 appointment tiles below calendar — SCENARIO-506.
  2. 15 past confirmed appointments → exactly 10 tiles shown — SCENARIO-507.
  List not yet rendered → tests fail.
- **Acceptance**: 2 new test cases exit non-zero.

---

### T30 [2] [GREEN] Render past appointments list in `AthleteAgendaScreen`

- **Files**: `lib/features/coach/presentation/athlete_agenda_screen.dart` (MODIFY)
- **REQs**: REQ-COACH-AGENDA-016
- **Description**: Watch `appointmentsForAthleteProvider(athleteId)`. Render `ListView` of `_AppointmentTile` widgets below the calendar. `AsyncLoading` → spinner; `AsyncError` → error text; empty → empty state text; data → tile list. `_AppointmentTile` shows `startsAt` formatted + duration.
- **Acceptance**: Both tests in T29 green.

---

### T31 [2] [RED] Widget tests — athlete-side cancellation

- **Files**: `test/features/coach/presentation/athlete_agenda_screen_test.dart` (MODIFY — add test group)
- **SCENARIOs**: 508, 509, 510
- **REQs**: REQ-COACH-AGENDA-017
- **Description**: Write failing tests:
  1. Upcoming appointment 48h out → `_AppointmentTile` shows cancel button — SCENARIO-508.
  2. Upcoming appointment 10h out → cancel button absent — SCENARIO-509.
  3. Tap cancel → confirm dialog → `cancel(...)` succeeds → appointment removed from list — SCENARIO-510.
  Cancel logic not yet wired → tests fail.
- **Acceptance**: 3 new test cases exit non-zero.

---

### T32 [2] [GREEN] Wire cancellation in `_AppointmentTile`

- **Files**: `lib/features/coach/presentation/athlete_agenda_screen.dart` (MODIFY — update `_AppointmentTile`)
- **REQs**: REQ-COACH-AGENDA-017
- **Description**: `_AppointmentTile`: show cancel `IconButton` only when `appointment.startsAt.difference(DateTime.now()) > const Duration(hours: 24)`. On tap → `showDialog` confirmation → call `AppointmentRepository.cancel(id, DateTime.now())` → on success show `AgendaStrings.cancelSuccess` snackbar; on `CancellationTooLateException` show `AgendaStrings.cancelTooLate` snackbar.
- **Acceptance**: All 3 tests in T31 green.

---

### T33 [2] [QA] PR2 quality gate

- **Files**: none (command-only)
- **Description**: Run `flutter analyze` (0 issues), `dart format .`, `flutter test` (full suite green — PR1 + PR2 tests). BLOCKER — do not open PR2 until all three exit 0.
- **Acceptance**: All three commands exit 0.

---

## PR3: Coach Agenda — Trainer UI

> Branch `feat/coach-agenda-ui-trainer` from `feat/coach-agenda-data` (or rebased onto merged `main` after PR1 lands).
> PR3 is parallelizable with PR2 after PR1 lands.
> **Cross-PR conflict risk**: `trainer_coach_view.dart` may conflict with Dev C (Etapa 5). Coordinate merge timing.

---

### T34 [3] [CHORE] Branch `feat/coach-agenda-ui-trainer`

- **Files**: none
- **Description**: Checkout `feat/coach-agenda-ui-trainer` from merged `main` (after PR1 lands). Confirm `flutter test` baseline green. Create test directories: `test/features/coach/presentation/trainer/`.
- **Acceptance**: `git branch` shows `feat/coach-agenda-ui-trainer`; `flutter test` exits 0.

---

### T35 [3] [RED] Widget tests — `TrainerAgendaTab` replaces placeholder + empty state

- **Files**: `test/features/coach/presentation/trainer/trainer_agenda_tab_test.dart` (NEW)
- **SCENARIOs**: 512, 523
- **REQs**: REQ-COACH-AGENDA-019, REQ-COACH-AGENDA-025
- **Description**: Write failing tests:
  1. `TrainerCoachView` TabBarView index 2 → `TrainerAgendaTab` rendered, no `_SubTabPlaceholder` — SCENARIO-512.
  2. `TrainerAgendaTab` with no rules → shows `'Todavía no configuraste horarios. Tocá \'Configurar horarios\' para empezar.'` AND `'Configurar horarios'` button visible — SCENARIO-523.
  Widget undefined + placeholder still in place → tests fail.
- **Acceptance**: Test file exits non-zero; 2 test cases declared.

---

### T36 [3] [GREEN] Implement `TrainerAgendaTab` skeleton + replace placeholder

- **Files**: `lib/features/coach/presentation/trainer_agenda_tab.dart` (NEW); `lib/features/coach/trainer_coach_view.dart` (MODIFY — idx 2 → `TrainerAgendaTab()`)
- **REQs**: REQ-COACH-AGENDA-019, REQ-COACH-AGENDA-025
- **Description**: `TrainerAgendaTab(ConsumerWidget)`. Watch `availabilityRulesProvider(trainerId)`. Empty state: `AgendaStrings.trainerEmptyNoRules` + `'Configurar horarios'` `ElevatedButton` that pushes `AvailabilityEditorScreen`. In `trainer_coach_view.dart`: replace `_SubTabPlaceholder` at index 2 with `TrainerAgendaTab()`.
- **Acceptance**: Both tests in T35 green; existing `trainer_coach_view` tests remain green.

---

### T37 [3] [RED] Widget tests — `AvailabilityEditorScreen` rule management

- **Files**: `test/features/coach/presentation/trainer/availability_editor_screen_test.dart` (NEW)
- **SCENARIOs**: 513, 514, 515, 516
- **REQs**: REQ-COACH-AGENDA-020, REQ-COACH-AGENDA-021
- **Description**: Write failing tests:
  1. Tapping `'Configurar horarios'` from `TrainerAgendaTab` → `AvailabilityEditorScreen` pushed — SCENARIO-513.
  2. Fill form (day: Monday, start: 09:00, end: 11:00, duration: 60) + save → `addRule(...)` called + rule appears in list — SCENARIO-514.
  3. Edit rule to 10:00–12:00 → existing confirmed appointment at 09:00 unchanged in `watchForTrainer` stream — SCENARIO-515.
  4. Tap delete on `r1` + confirm → `deleteRule(...)` called + `r1` not in list — SCENARIO-516.
  Screen undefined → tests fail.
- **Acceptance**: Test file exits non-zero; 4 test cases declared.

---

### T38 [3] [GREEN] Implement `AvailabilityEditorScreen` — rules section

- **Files**: `lib/features/coach/presentation/availability_editor_screen.dart` (NEW, partial — rules only)
- **REQs**: REQ-COACH-AGENDA-020, REQ-COACH-AGENDA-021
- **Description**: `AvailabilityEditorScreen(ConsumerWidget)`. Watch `availabilityRulesProvider(trainerId)`. Rules list grouped by day of week. Add-rule form: day picker, time pickers, slot duration dropdown (30|60|90|120). Save → `AvailabilityRepository.addRule(...)`. Edit → `updateRule(...)`. Delete → confirmation dialog → `deleteRule(...)`. REQ-026: editing a rule does NOT cancel confirmed appointments (rule change only affects future `computeFreeSlots`; appointments are immutable).
- **Acceptance**: All 4 tests in T37 green.

---

### T39 [3] [RED] Widget tests — override management (block + extra)

- **Files**: `test/features/coach/presentation/trainer/availability_editor_screen_test.dart` (MODIFY — add test group)
- **SCENARIOs**: 517, 518, 519
- **REQs**: REQ-COACH-AGENDA-022
- **Description**: Write failing tests:
  1. Add block override for a Monday → `computeFreeSlots` returns `[]` for that date — SCENARIO-517.
  2. Add extra override for Saturday (10:00–12:00, 60 min) → `computeFreeSlots` returns `[10:00, 11:00]` — SCENARIO-518.
  3. Delete block override → 2 rule-derived slots reappear — SCENARIO-519.
  Override section not yet implemented → tests fail.
- **Acceptance**: 3 new test cases exit non-zero.

---

### T40 [3] [GREEN] Add override management section to `AvailabilityEditorScreen`

- **Files**: `lib/features/coach/presentation/availability_editor_screen.dart` (MODIFY — add overrides section)
- **REQs**: REQ-COACH-AGENDA-022
- **Description**: Add overrides list section below rules. Add-override form: date picker, type selector (block|extra); if extra: start/end time pickers + duration. `addOverride(...)` / `deleteOverride(...)` via `AvailabilityRepository`. Per ADR-6 freezed sealed union.
- **Acceptance**: All 3 tests in T39 green.

---

### T41 [3] [RED] Widget tests — trainer calendar slot visualization

- **Files**: `test/features/coach/presentation/trainer/trainer_agenda_tab_test.dart` (MODIFY — add test group)
- **SCENARIOs**: 520, 521, 524
- **REQs**: REQ-COACH-AGENDA-023, REQ-COACH-AGENDA-026
- **Description**: Write failing tests:
  1. Confirmed appointment on 2026-06-10 09:00 with `athleteDisplayName: 'Juan P.'` → tapping June 10 shows `'09:00 — Juan P.'` tile — SCENARIO-520.
  2. Tap `'09:00 — Juan P.'` tile → detail panel/dialog with athlete name and appointment details visible — SCENARIO-521.
  3. Rule `endHour` reduced from 12 to 11; appointment at 11:30 confirmed → `watchForTrainer` still emits appointment with `status: confirmed` — SCENARIO-524.
  Calendar view not yet implemented → tests fail.
- **Acceptance**: 3 new test cases exit non-zero.

---

### T42 [3] [GREEN] Implement trainer calendar view in `TrainerAgendaTab`

- **Files**: `lib/features/coach/presentation/trainer_agenda_tab.dart` (MODIFY — add calendar + slot detail)
- **REQs**: REQ-COACH-AGENDA-023, REQ-COACH-AGENDA-026
- **Description**: Watch `appointmentsForTrainerProvider(TrainerRangeKey(trainerId, range))` + `freeSlotsProvider`. Render `TableCalendar` with two visual styles: free slots (dot/marker) vs booked slots (distinct color badge). On day tap → open `_TrainerDaySheet` listing free + booked slots. Booked slot tile: `'HH:mm — athleteDisplayName'`. Tap → show detail dialog with cancel option. REQ-026: rule edits do not affect displayed confirmed appointments.
- **Acceptance**: All 3 tests in T41 green.

---

### T43 [3] [RED] Widget tests — trainer-side cancellation

- **Files**: `test/features/coach/presentation/trainer/trainer_agenda_tab_test.dart` (MODIFY — add test group)
- **SCENARIOs**: 522
- **REQs**: REQ-COACH-AGENDA-024
- **Description**: Write failing tests:
  1. Booked slot 48h out → detail dialog shows cancel button → confirm → `cancel(...)` called → slot reappears as free on calendar — SCENARIO-522.
  Cancellation not yet wired in trainer view → test fails.
- **Acceptance**: 1 new test case exits non-zero.

---

### T44 [3] [GREEN] Wire trainer-side cancellation

- **Files**: `lib/features/coach/presentation/trainer_agenda_tab.dart` (MODIFY — detail dialog cancel action)
- **REQs**: REQ-COACH-AGENDA-024
- **Description**: In booked-slot detail dialog: cancel button calls `AppointmentRepository.cancel(id, DateTime.now(), byUid: trainerUid)`. On success → snackbar + slot reappears in free pool (stream auto-emits). On `CancellationTooLateException` → snackbar `AgendaStrings.cancelTooLate`. 24h cutoff enforced both client-side (button visibility check: `startsAt.difference(now) > 24h`) and Firestore rules (CEL from T17).
- **Acceptance**: Test in T43 green.

---

### T45 [3] [QA] PR3 quality gate

- **Files**: none (command-only)
- **Description**: Run `flutter analyze` (0 issues), `dart format .`, `flutter test` (full suite green — PR1 + PR3 tests). BLOCKER — do not open PR3 until all three exit 0.
- **Acceptance**: All three commands exit 0.

---

## Post-Merge Operations (deferred — document only)

### T46 [POST] Deploy Firestore rules

- **Files**: none (command-only)
- **Description**: After PR1 merges to `main`: `cd scripts && node deploy_rules.js`. This deploys the 3 new collection rules + 24h CEL guard to production Firestore. Must be executed by team member with Firebase Admin access.
- **Acceptance**: `firebase deploy --only firestore:rules` exits 0; no existing rules regressed.

---

### T47 [POST] No-backfill rationale (document)

- **Files**: `docs/roadmap.md` (MODIFY — add note in Fase 5 · Etapa 6 section)
- **Description**: Document: "No data backfill required — `coach_availability_rules`, `coach_availability_overrides`, and `appointments` are all new collections with no legacy data." Also note ADR-1 asymmetric divergence (cancelled-slot flip semantics). Commit: `docs(roadmap): coach-agenda post-merge no-backfill note`.
- **Acceptance**: Note present in `docs/roadmap.md`; `flutter analyze` unaffected.

---

## Goal-Backward Coverage

### REQ → SCENARIO → Task mapping

| REQ | SCENARIO(s) | RED task | GREEN task |
|-----|-------------|----------|------------|
| REQ-COACH-AGENDA-001 | 478, 479 | T03 | T04 |
| REQ-COACH-AGENDA-002 | 480, 481 | T03 | T04 |
| REQ-COACH-AGENDA-003 | 482, 483, 484 | T05 | T06 |
| REQ-COACH-AGENDA-004 | 485, 486, 487 | T09 | T10 |
| REQ-COACH-AGENDA-005 | 488 | T09 | T10 |
| REQ-COACH-AGENDA-006 | 489, 490, 491* | T11 | T12 |
| REQ-COACH-AGENDA-007 | 492, 493 | T13 | T14 |
| REQ-COACH-AGENDA-008 | 494, 495 | T13 | T14 |
| REQ-COACH-AGENDA-009 | 496 | T11 | T12 |
| REQ-COACH-AGENDA-010 | (provider contract) | T15 | T16 |
| REQ-COACH-AGENDA-011 | 497, 498 | T21 | T22 |
| REQ-COACH-AGENDA-012 | 499, 500 | T23 | T24 |
| REQ-COACH-AGENDA-013 | 501, 502 | T25 | T26 |
| REQ-COACH-AGENDA-014 | 503, 504 | T27 | T28 |
| REQ-COACH-AGENDA-015 | 505 | T27 | T28 |
| REQ-COACH-AGENDA-016 | 506, 507 | T29 | T30 |
| REQ-COACH-AGENDA-017 | 508, 509, 510 | T31 | T32 |
| REQ-COACH-AGENDA-018 | 511 | T23 | T24 |
| REQ-COACH-AGENDA-019 | 512 | T35 | T36 |
| REQ-COACH-AGENDA-020 | 513 | T37 | T38 |
| REQ-COACH-AGENDA-021 | 514, 515, 516 | T37 | T38 |
| REQ-COACH-AGENDA-022 | 517, 518, 519 | T39 | T40 |
| REQ-COACH-AGENDA-023 | 520, 521 | T41 | T42 |
| REQ-COACH-AGENDA-024 | 522 | T43 | T44 |
| REQ-COACH-AGENDA-025 | 523 | T35 | T36 |
| REQ-COACH-AGENDA-026 | 524 | T41 | T42 |
| REQ-COACH-AGENDA-027 | 525 | T17 (emulator-skipped) | T17 |
| REQ-COACH-AGENDA-028 | 526 | T17 (emulator-skipped) | T17 |
| REQ-COACH-AGENDA-029 | 527 | T17 (emulator-skipped) | T17 |

*SCENARIO-491 amended in T01 per ADR-1.

All SCENARIOs 478–527 land in specific tasks. No orphan SCENARIOs.

**SCENARIO-525, 526, 527 (Firestore rules)**: covered by emulator-skipped stubs per Decision #25. Stubs compile and are skipped (not failing) in `flutter test`.

---

## Task Summary

| Section | Tasks | Focus |
|---------|-------|-------|
| PR1 — DOCS | T01 | Amend SCENARIO-491 (spec + engram) |
| PR1 — CHORE | T02 | Branch + pubspec + table_calendar |
| PR1 — RED/GREEN (AvailabilityRule + AvailabilityOverride) | T03–T04 | Domain models test cycle |
| PR1 — RED/GREEN (Appointment + exceptions) | T05–T06 | Domain model test cycle |
| PR1 — RED/GREEN (computeFreeSlots) | T07–T08 | Pure-function test cycle |
| PR1 — RED/GREEN (AvailabilityRepository) | T09–T10 | Repo CRUD test cycle |
| PR1 — RED/GREEN (AppointmentRepository book) | T11–T12 | Atomic transaction test cycle (ADR-5 + ADR-1) |
| PR1 — RED/GREEN (AppointmentRepository cancel + queries) | T13–T14 | Cancel + query test cycle |
| PR1 — RED/GREEN (agenda_providers) | T15–T16 | Provider graph test cycle |
| PR1 — MOD (firestore.rules) | T17 | 3 new collections + 24h CEL |
| PR1 — MOD (router stub) | T18 | Agenda route stub |
| PR1 — QA | T19 | analyze + format + full suite |
| **PR1 total** | **19** | |
| PR2 — CHORE | T20 | Branch + agenda_strings.dart |
| PR2 — RED/GREEN (VER AGENDA button) | T21–T22 | Entry-point test cycle |
| PR2 — RED/GREEN (AthleteAgendaScreen calendar) | T23–T24 | Calendar render test cycle |
| PR2 — RED/GREEN (_DaySlotsSheet) | T25–T26 | Bottom sheet test cycle |
| PR2 — RED/GREEN (booking flow) | T27–T28 | Booking + race conflict test cycle |
| PR2 — RED/GREEN (past appointments list) | T29–T30 | List render test cycle |
| PR2 — RED/GREEN (athlete cancellation) | T31–T32 | Cancel flow test cycle |
| PR2 — QA | T33 | analyze + format + full suite |
| **PR2 total** | **14** | |
| PR3 — CHORE | T34 | Branch |
| PR3 — RED/GREEN (TrainerAgendaTab skeleton) | T35–T36 | Tab replace + empty state test cycle |
| PR3 — RED/GREEN (AvailabilityEditorScreen rules) | T37–T38 | Rule management test cycle |
| PR3 — RED/GREEN (override management) | T39–T40 | Override CRUD test cycle |
| PR3 — RED/GREEN (trainer calendar visualization) | T41–T42 | Calendar + slot detail test cycle |
| PR3 — RED/GREEN (trainer cancellation) | T43–T44 | Cancel flow test cycle |
| PR3 — QA | T45 | analyze + format + full suite |
| **PR3 total** | **12** | |
| Post-merge | T46–T47 | Rules deploy + no-backfill doc |
| **Grand total** | **47** | |

Execution order within each PR is strictly sequential. Each RED MUST be observed failing before its GREEN. Each GREEN MUST be confirmed passing before the next RED.

---

## Dependency Notes

- PR2 and PR3 are BLOCKED until PR1 is merged to `main`.
- PR2 and PR3 are independently parallelizable with each other after PR1 lands.
- Within PR1: T01→T02→T03→T04→T05→T06→T07→T08→T09→T10→T11→T12→T13→T14→T15→T16→T17→T18→T19 (sequential).
- Within PR2: T20→T21→T22→T23→T24→T25→T26→T27→T28→T29→T30→T31→T32→T33 (sequential).
- Within PR3: T34→T35→T36→T37→T38→T39→T40→T41→T42→T43→T44→T45 (sequential).
- T12 (booking transaction) is the highest-complexity task — allocate extra review time. ADR-5 + ADR-1 must be implemented exactly as designed. Flag for apply.
- T17 (`firestore.rules`) must land in PR1 before any UI testing can exercise the Firestore path. Coordinate with Dev C merge order.
- T18 (router stub) lands in PR1 so PR2 `context.push('/coach/agenda', ...)` does not break compile-time checks.
- **Cross-PR conflict risk**: `athlete_coach_view.dart` (T22/PR2) and `trainer_coach_view.dart` (T36/PR3) both overlap with Dev C's Etapa 5 chat feature. Coordinate merge timing to avoid painful conflicts.

---

*Generated by sdd-tasks — 2026-05-22*
