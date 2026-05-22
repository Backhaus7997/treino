# coach-agenda Specification

**Change**: `coach-agenda`
**Fase / Etapa**: Fase 5 · Etapa 6
**SCENARIO start**: 478 (last used: 477 in shared-with-trainer)

---

## Purpose

Asymmetric scheduling layer for the Coach module. A trainer publishes recurring weekly availability rules and date overrides; athletes book free slots immediately and atomically without a confirmation handshake. The system enforces a 24-hour cancellation cutoff at both the client layer and the Firestore rule layer.

Delivered in 3 chained PRs: PR1 (data layer), PR2 (athlete UI), PR3 (trainer UI).

---

## Capabilities

| Capability | Status | PR(s) |
|---|---|---|
| `coach-agenda-data` | NEW | PR1 |
| `coach-agenda-ui` | NEW | PR2, PR3 |
| `coach-link-lifecycle` | ANNOTATED (read-only dependency) | — |

---

## Requirements — Capability: `coach-agenda-data` (PR1)

---

### REQ-COACH-AGENDA-001: Domain model — AvailabilityRule

The `AvailabilityRule` model MUST have fields: `id` (String), `trainerId` (String), `dayOfWeek` (int 1–7, ISO: 1=Monday), `startHour` (int), `startMinute` (int), `endHour` (int), `endMinute` (int), `slotDurationMin` (int, enum values 30 | 60 | 90 | 120). All fields MUST round-trip through JSON without data loss.

#### SCENARIO-478: AvailabilityRule JSON round-trip

- GIVEN an `AvailabilityRule` with all required fields set
- WHEN serialized to JSON and deserialized back
- THEN all fields equal the originals and `slotDurationMin` remains one of `[30, 60, 90, 120]`

#### SCENARIO-479: AvailabilityRule slotDurationMin rejects invalid value

- GIVEN a JSON map with `slotDurationMin: 45`
- WHEN deserialized via `AvailabilityRule.fromJson`
- THEN deserialization throws an `AssertionError` or `ArgumentError`

---

### REQ-COACH-AGENDA-002: Domain model — AvailabilityOverride

The `AvailabilityOverride` model MUST have fields: `id` (String), `trainerId` (String), `date` (DateTime, date-only), `type` (enum `block | extra`). When `type == extra`, fields `startHour`, `startMinute`, `endHour`, `endMinute`, `slotDurationMin` MUST be present. When `type == block`, those time fields MUST be absent / null. All fields MUST round-trip through JSON without data loss.

#### SCENARIO-480: AvailabilityOverride block type JSON round-trip

- GIVEN an `AvailabilityOverride` with `type: block` and no time fields
- WHEN serialized to JSON and deserialized back
- THEN `type` is `OverrideType.block` and all time fields are null

#### SCENARIO-481: AvailabilityOverride extra type JSON round-trip

- GIVEN an `AvailabilityOverride` with `type: extra` and all time fields set
- WHEN serialized to JSON and deserialized back
- THEN `type` is `OverrideType.extra` and all time fields equal the originals

---

### REQ-COACH-AGENDA-003: Domain model — Appointment

The `Appointment` model MUST have fields: `id` (String, deterministic: `'{trainerId}_{startsAtMs}'`), `trainerId` (String), `athleteId` (String), `athleteDisplayName` (String, denormalized at write time), `startsAt` (DateTime UTC), `durationMin` (int), `status` (enum `confirmed | cancelled`). All fields MUST round-trip through JSON without data loss.

#### SCENARIO-482: Appointment JSON round-trip with status confirmed

- GIVEN an `Appointment` with `status: confirmed`
- WHEN serialized to JSON and deserialized back
- THEN all fields equal the originals and `status` is `AppointmentStatus.confirmed`

#### SCENARIO-483: AppointmentStatus enum wire encoding

- GIVEN `AppointmentStatus.cancelled`
- WHEN serialized via `toJson`
- THEN the result is the string `'cancelled'`

#### SCENARIO-484: Appointment deterministic id matches pattern

- GIVEN a trainer with id `'tA'` and a slot starting at Unix ms `1748000000000`
- WHEN an `Appointment` is constructed
- THEN `appointment.id == 'tA_1748000000000'`

---

### REQ-COACH-AGENDA-004: AvailabilityRepository — rule CRUD

`AvailabilityRepository` MUST expose:
- `Future<void> addRule(AvailabilityRule rule)` — writes to `coach_availability_rules/{rule.id}`
- `Future<void> updateRule(AvailabilityRule rule)` — merges by `rule.id`
- `Future<void> deleteRule(String trainerId, String ruleId)` — deletes the document
- `Stream<List<AvailabilityRule>> watchRules(String trainerId)` — real-time stream filtered by `trainerId`

#### SCENARIO-485: addRule persists document at correct path

- GIVEN a valid `AvailabilityRule` with `id: 'r1'` and `trainerId: 'tA'`
- WHEN `addRule(rule)` is called
- THEN a document exists at `coach_availability_rules/r1` with matching fields

#### SCENARIO-486: deleteRule removes document

- GIVEN a rule `r1` exists for trainer `tA`
- WHEN `deleteRule('tA', 'r1')` is called
- THEN no document exists at `coach_availability_rules/r1`

#### SCENARIO-487: watchRules emits only rules for the requesting trainer

- GIVEN trainer `tA` has 2 rules and trainer `tB` has 1 rule
- WHEN `watchRules('tA')` is observed
- THEN only the 2 rules for `tA` are emitted; trainer `tB`'s rule is absent

---

### REQ-COACH-AGENDA-005: AvailabilityRepository — override CRUD

`AvailabilityRepository` MUST expose:
- `Future<void> addOverride(AvailabilityOverride override)` — writes to `coach_availability_overrides/{override.id}`
- `Future<void> deleteOverride(String trainerId, String overrideId)` — deletes the document
- `Stream<List<AvailabilityOverride>> watchOverrides(String trainerId, DateTime from, DateTime to)` — real-time stream filtered by trainer + date range

#### SCENARIO-488: watchOverrides returns overrides within date range only

- GIVEN trainer `tA` has overrides on 2026-06-01 (block) and 2026-06-15 (extra)
- WHEN `watchOverrides('tA', 2026-06-01, 2026-06-10)` is observed
- THEN only the 2026-06-01 override is emitted

---

### REQ-COACH-AGENDA-006: AppointmentRepository — atomic booking

`AppointmentRepository.book(BookingRequest req)` MUST execute a Firestore `runTransaction` that: reads the deterministic doc at `appointments/{trainerId}_{startsAtMs}`, creates it if absent with `status: confirmed`, and throws `SlotAlreadyTakenException` if the document already exists (regardless of status). It MUST return the created `Appointment`.

#### SCENARIO-489: book — success path creates confirmed appointment

- GIVEN no document exists at `appointments/tA_1748000000000`
- WHEN `book(BookingRequest(trainerId: 'tA', athleteId: 'aB', startsAt: …, durationMin: 60))` is called
- THEN a document exists at `appointments/tA_1748000000000` with `status: 'confirmed'` and `athleteId: 'aB'`

#### SCENARIO-490: book — race conflict throws SlotAlreadyTakenException

- GIVEN a document already exists at `appointments/tA_1748000000000` with `status: confirmed`
- WHEN `book(BookingRequest(…))` is called by a second athlete
- THEN `SlotAlreadyTakenException` is thrown and no data is mutated

#### SCENARIO-491: book — cancelled slot is re-bookable (ADR-1 flip)

- GIVEN an `appointments/{trainerId}_{startsAtMs}` doc exists with `status: 'cancelled'` and a populated `cancellationLog` array
- WHEN a new athlete (different from `cancelledBy`) calls `book(trainerId, startsAtMs, ...)`
- THEN the Firestore transaction reads the doc, sees `status == 'cancelled'`, atomically updates `status` to `'confirmed'`, sets `athleteId` and `linkId` to the new athlete's values, sets `cancelledAt`/`cancelledBy` to null, and PRESERVES the existing `cancellationLog` array (appends nothing). Returns the new confirmed `Appointment`.

---

### REQ-COACH-AGENDA-007: AppointmentRepository — cancellation

`AppointmentRepository.cancel(String appointmentId, DateTime now)` MUST:
- Throw `CancellationTooLateException` if `appointment.startsAt.difference(now) < const Duration(hours: 24)`
- Otherwise update `status` to `cancelled` and return void

#### SCENARIO-492: cancel succeeds when more than 24h ahead

- GIVEN an appointment `startsAt` 48 hours from `now`
- WHEN `cancel(appointmentId, now)` is called
- THEN the document has `status: 'cancelled'`

#### SCENARIO-493: cancel throws CancellationTooLateException when less than 24h ahead

- GIVEN an appointment `startsAt` 12 hours from `now`
- WHEN `cancel(appointmentId, now)` is called
- THEN `CancellationTooLateException` is thrown and the document status is unchanged

---

### REQ-COACH-AGENDA-008: AppointmentRepository — queries

`AppointmentRepository` MUST expose:
- `Stream<List<Appointment>> watchForAthlete(String athleteId)` — returns at most the last 10 past appointments plus all current/future confirmed appointments, ordered `startsAt` ASC
- `Stream<List<Appointment>> watchForTrainer(String trainerId, DateTime from, DateTime to)` — all appointments (any status) for the trainer in the date range

#### SCENARIO-494: watchForAthlete returns last 10 past and all future

- GIVEN an athlete has 15 past confirmed appointments and 2 future confirmed appointments
- WHEN `watchForAthlete(athleteId)` is observed
- THEN the stream emits exactly 12 items: the 10 most recent past + 2 future

#### SCENARIO-495: watchForTrainer returns all statuses in date range

- GIVEN trainer `tA` has 1 confirmed and 1 cancelled appointment within the range, and 1 confirmed outside the range
- WHEN `watchForTrainer('tA', from, to)` is observed
- THEN exactly 2 appointments are emitted (both statuses inside range)

---

### REQ-COACH-AGENDA-009: Booking horizon

The system MUST NOT allow booking a slot that starts more than 28 days from now. `book(…)` MUST throw `BookingTooFarAheadException` when `req.startsAt > now + 28 days`.

#### SCENARIO-496: book throws BookingTooFarAheadException for slot 29 days out

- GIVEN `req.startsAt` is 29 days from `now`
- WHEN `book(req)` is called
- THEN `BookingTooFarAheadException` is thrown

---

### REQ-COACH-AGENDA-010: Riverpod providers

The file `lib/features/coach/application/agenda_providers.dart` MUST export:
- `availabilityRulesProvider(String trainerId)` — `StreamProvider`
- `availabilityOverridesProvider(String trainerId, DateTimeRange range)` — `StreamProvider`
- `appointmentsForAthleteProvider(String athleteId)` — `StreamProvider`
- `appointmentsForTrainerProvider(String trainerId, DateTimeRange range)` — `StreamProvider`

Each provider MUST invalidate when the underlying repository emits a new event.

---

## Requirements — Capability: `coach-agenda-ui` (PR2 — Athlete)

---

### REQ-COACH-AGENDA-011: Athlete entry point — gated on active link

`_LinkStateCard` in `athlete_coach_view.dart` MUST show a "VER AGENDA DEL PF" button only when `link.status == LinkStatus.active`. The button MUST NOT appear for pending, inactive, or absent links.

#### SCENARIO-497: VER AGENDA button visible when link is active

- GIVEN the athlete has an active link with a trainer
- WHEN `_LinkStateCard` is rendered
- THEN a button with text "VER AGENDA DEL PF" is visible

#### SCENARIO-498: VER AGENDA button absent when link is not active

- GIVEN the athlete has no active link (pending or no link)
- WHEN `_LinkStateCard` is rendered
- THEN no "VER AGENDA DEL PF" button is present

---

### REQ-COACH-AGENDA-012: Athlete agenda screen — calendar rendering

`AthleteAgendaScreen` at route `/coach/agenda` MUST render a `TableCalendar` widget showing the current month. Days that have at least one free slot MUST display a dot marker. Days with no free slots MUST display no marker.

#### SCENARIO-499: Calendar renders dot on days with free slots

- GIVEN the trainer has a rule for Tuesday with 2 free slots in the current month
- WHEN `AthleteAgendaScreen` is rendered
- THEN each such Tuesday shows a dot marker on the calendar

#### SCENARIO-500: Calendar renders no dot on days with no slots

- GIVEN the trainer has no rules
- WHEN `AthleteAgendaScreen` is rendered
- THEN no day shows a dot marker

---

### REQ-COACH-AGENDA-013: Day-slots bottom sheet

Tapping a day with free slots on the calendar MUST open `_DaySlotsSheet`, a bottom sheet listing all free time slots for that day as tappable chips. Tapping a chip MUST trigger a booking confirmation step. The sheet MUST display the message "Tu PF todavía no configuró horarios." when no free slots exist for that day.

#### SCENARIO-501: _DaySlotsSheet lists free slots for selected day

- GIVEN a day has two free slots at 09:00 and 10:00
- WHEN the athlete taps that day on the calendar
- THEN `_DaySlotsSheet` opens and displays two slot chips labeled "09:00" and "10:00"

#### SCENARIO-502: _DaySlotsSheet shows empty-state copy when no slots

- GIVEN a day has no free slots
- WHEN the athlete taps that day
- THEN `_DaySlotsSheet` shows the text "Tu PF todavía no configuró horarios."

---

### REQ-COACH-AGENDA-014: Booking confirmation and success

After the athlete taps a slot chip, a confirmation dialog MUST appear with the slot datetime. On confirm, `AppointmentRepository.book` MUST be called. On success, `_DaySlotsSheet` MUST close and `AthleteAgendaScreen` MUST show a success snackbar.

#### SCENARIO-503: Booking confirmation dialog shown on slot tap

- GIVEN `_DaySlotsSheet` is open with slot "09:00"
- WHEN the athlete taps the "09:00" chip
- THEN a confirmation dialog appears showing the slot datetime

#### SCENARIO-504: Successful booking closes sheet and shows snackbar

- GIVEN the confirmation dialog is shown for "09:00"
- WHEN the athlete confirms and `book(...)` succeeds
- THEN `_DaySlotsSheet` closes and a success snackbar is displayed

---

### REQ-COACH-AGENDA-015: Race conflict UX

When `book(...)` throws `SlotAlreadyTakenException`, `AthleteAgendaScreen` MUST show an error snackbar with the text "Ese horario fue reservado justo ahora." and the slot MUST be removed from the displayed free-slot list.

#### SCENARIO-505: Race conflict shows error toast and removes slot

- GIVEN the athlete taps a slot and `book(...)` throws `SlotAlreadyTakenException`
- WHEN the exception is caught
- THEN an error snackbar reads "Ese horario fue reservado justo ahora." and the slot chip is no longer shown

---

### REQ-COACH-AGENDA-016: Athlete past appointments list

Below the calendar, `AthleteAgendaScreen` MUST show a list of the athlete's past and upcoming appointments via `watchForAthlete`. The list MUST show at most 10 past items and all upcoming confirmed items, ordered chronologically. An empty state MUST be shown when no appointments exist.

#### SCENARIO-506: Past appointments list renders below calendar

- GIVEN the athlete has 3 confirmed past appointments
- WHEN `AthleteAgendaScreen` is rendered
- THEN a list of 3 appointment tiles appears below the calendar

#### SCENARIO-507: Past appointments list capped at 10

- GIVEN the athlete has 15 past confirmed appointments
- WHEN `AthleteAgendaScreen` is rendered
- THEN exactly 10 past appointment tiles are shown

---

### REQ-COACH-AGENDA-017: Athlete-side cancellation

Each appointment tile in the past/upcoming list MUST show a cancel button only when `startsAt.difference(DateTime.now()) > Duration(hours: 24)`. Tapping cancel MUST show a confirmation dialog; on confirm, `cancel(...)` is called. Success MUST refresh the list.

#### SCENARIO-508: Cancel button visible when >24h ahead

- GIVEN an upcoming appointment starting 48h from now
- WHEN the appointment tile is rendered
- THEN a cancel button is visible

#### SCENARIO-509: Cancel button absent when ≤24h ahead

- GIVEN an upcoming appointment starting 10h from now
- WHEN the appointment tile is rendered
- THEN no cancel button is visible

#### SCENARIO-510: Cancel confirm dialog → success refreshes list

- GIVEN the cancel button is tapped for an eligible appointment
- WHEN the athlete confirms in the dialog and `cancel(...)` succeeds
- THEN the appointment is removed from the upcoming list

---

### REQ-COACH-AGENDA-018: Athlete agenda empty state (no rules)

When the trainer has no `AvailabilityRule` documents, `AthleteAgendaScreen` MUST display the empty-state copy "Tu PF todavía no configuró horarios." in place of the calendar.

#### SCENARIO-511: Empty state shown when trainer has no rules

- GIVEN the active trainer has zero `AvailabilityRule` documents
- WHEN `AthleteAgendaScreen` is rendered
- THEN the text "Tu PF todavía no configuró horarios." is visible and no calendar widget is shown

---

## Requirements — Capability: `coach-agenda-ui` (PR3 — Trainer)

---

### REQ-COACH-AGENDA-019: Trainer AGENDA tab replaces placeholder

`TrainerCoachView` TabBarView index 2 MUST render `TrainerAgendaTab` instead of `_SubTabPlaceholder`. `TrainerAgendaTab` MUST show the trainer's own calendar with confirmed slots marked.

#### SCENARIO-512: AGENDA tab renders TrainerAgendaTab (not placeholder)

- GIVEN the trainer navigates to the AGENDA sub-tab in `TrainerCoachView`
- WHEN the tab renders
- THEN `TrainerAgendaTab` is displayed and no `_SubTabPlaceholder` is visible

---

### REQ-COACH-AGENDA-020: Availability editor screen access

`TrainerAgendaTab` MUST provide navigation to `AvailabilityEditorScreen`. The screen MUST list all existing rules grouped by day of week and allow adding, editing, and deleting rules.

#### SCENARIO-513: Tapping "Configurar horarios" opens AvailabilityEditorScreen

- GIVEN `TrainerAgendaTab` is rendered
- WHEN the trainer taps the "Configurar horarios" button
- THEN `AvailabilityEditorScreen` is pushed onto the navigation stack

---

### REQ-COACH-AGENDA-021: Rule management (add / edit / delete)

`AvailabilityEditorScreen` MUST allow the trainer to:
- Add a rule by specifying day-of-week, start time, end time, and slot duration (enum 30|60|90|120 min)
- Edit an existing rule (all fields modifiable)
- Delete a rule
Multiple rules per day MUST be allowed. Editing or deleting a rule MUST NOT retroactively cancel any already-confirmed appointments.

#### SCENARIO-514: Add rule persists new AvailabilityRule

- GIVEN `AvailabilityEditorScreen` is open with no existing rules
- WHEN the trainer fills the form (day: Monday, start: 09:00, end: 11:00, duration: 60) and taps save
- THEN a new `AvailabilityRule` document is persisted and appears in the editor list

#### SCENARIO-515: Edit rule updates only future availability

- GIVEN a rule exists for Monday 09:00–11:00 and an appointment exists for next Monday 09:00
- WHEN the trainer edits the rule to Monday 10:00–12:00
- THEN the existing appointment is unchanged and new slots use the updated hours

#### SCENARIO-516: Delete rule removes rule document

- GIVEN a rule `r1` exists for Monday
- WHEN the trainer taps delete for `r1` and confirms
- THEN `r1` is deleted from `coach_availability_rules` and no longer appears in the list

---

### REQ-COACH-AGENDA-022: Override management (block / extra)

`AvailabilityEditorScreen` MUST allow the trainer to add an override for a specific date:
- `block`: blocks all availability for that date (no additional time fields)
- `extra`: adds availability for that date (requires start time, end time, slot duration)
Overrides MUST be deletable. A block override MUST hide all rule-derived slots for that date from the athlete view.

#### SCENARIO-517: Add block override hides slots for that date

- GIVEN a Monday rule generates slots and the trainer adds a block override for an upcoming Monday
- WHEN `computeFreeSlots` is called for that Monday
- THEN no slots are returned for that date

#### SCENARIO-518: Add extra override adds slots for that date

- GIVEN no rules exist for a specific Saturday
- WHEN the trainer adds an extra override for that Saturday (10:00–12:00, 60 min)
- THEN two slots (10:00, 11:00) appear in `_DaySlotsSheet` for that date

#### SCENARIO-519: Delete override restores underlying rule slots

- GIVEN a block override exists for a Monday that would otherwise have 2 rule slots
- WHEN the trainer deletes the override
- THEN the 2 rule-derived slots reappear for that date

---

### REQ-COACH-AGENDA-023: Trainer calendar — slot visualization

`TrainerAgendaTab` MUST display a calendar where each day shows:
- Free slots (derived from rules/overrides minus confirmed appointments) in one visual style
- Booked slots (confirmed appointments with athlete display name) in a distinct visual style

#### SCENARIO-520: Booked slot shows athlete name

- GIVEN a confirmed appointment exists for trainer `tA` on 2026-06-10 at 09:00 with `athleteDisplayName: 'Juan P.'`
- WHEN the trainer taps 2026-06-10 in `TrainerAgendaTab`
- THEN a slot tile labeled "09:00 — Juan P." is visible

#### SCENARIO-521: Tapping booked slot opens athlete detail panel

- GIVEN the trainer taps the "09:00 — Juan P." slot tile
- WHEN the tile is tapped
- THEN a panel or dialog shows the athlete's name and appointment details

---

### REQ-COACH-AGENDA-024: Trainer-side cancellation

From the booked-slot detail, the trainer MUST be able to cancel an appointment. The same 24h cutoff MUST be enforced (`CancellationTooLateException`). On success, the slot MUST return to the free pool on the calendar.

#### SCENARIO-522: Trainer cancel — success when >24h ahead

- GIVEN a booked slot 48h from now is shown in the trainer's slot detail panel
- WHEN the trainer taps cancel and confirms
- THEN `cancel(...)` is called, the appointment status becomes `cancelled`, and the slot reappears as free on the calendar

---

### REQ-COACH-AGENDA-025: Trainer agenda empty state

When the trainer has no `AvailabilityRule` documents, `TrainerAgendaTab` MUST show the copy "Todavía no configuraste horarios. Tocá 'Configurar horarios' para empezar." and still show the "Configurar horarios" button.

#### SCENARIO-523: Trainer empty state shown with CTA visible

- GIVEN the trainer has zero `AvailabilityRule` documents
- WHEN `TrainerAgendaTab` is rendered
- THEN the text "Todavía no configuraste horarios. Tocá 'Configurar horarios' para empezar." is visible and the "Configurar horarios" button is accessible

---

### REQ-COACH-AGENDA-026: Rule edit does not invalidate existing bookings

When a trainer modifies a rule (hours, duration, or day), confirmed appointments that were booked under the previous rule configuration MUST retain their original `startsAt` and `status: confirmed`.

#### SCENARIO-524: Confirmed appointment survives rule endHour reduction

- GIVEN an appointment at 11:30 confirmed and the rule endHour is edited from 12:00 to 11:00
- WHEN `watchForTrainer(...)` is observed after the edit
- THEN the 11:30 appointment still has `status: confirmed`

---

## Requirements — Firestore Security Rules (emulator-deferred)

---

### REQ-COACH-AGENDA-027: Only the coach can write own availability rules

Firestore rules MUST allow writes to `coach_availability_rules/{ruleId}` only when `request.auth.uid == request.resource.data.trainerId`.

#### SCENARIO-525: Rule write rejected when trainerId ≠ auth.uid

- GIVEN user A attempts to write a rule with `trainerId: 'tB'`
- WHEN the rule write is evaluated by the Firestore emulator
- THEN the request is denied (`permission-denied`)

---

### REQ-COACH-AGENDA-028: Booking requires active coach-athlete link

Firestore rules for `appointments` MUST verify that a valid, active `coach_links` document exists for the `(trainerId, athleteId)` pair before allowing a create on `appointments/{docId}`. The rule MUST enforce `request.resource.data.athleteId == request.auth.uid`.

#### SCENARIO-526: Booking denied when no active link exists

- GIVEN user `aX` has no active link with trainer `tA`
- WHEN `aX` attempts to create `appointments/tA_1748000000000` with `athleteId: 'aX'`
- THEN the request is denied

---

### REQ-COACH-AGENDA-029: 24h cancellation cutoff enforced by Firestore rule

The Firestore rule for updating `appointments/{docId}` to `status: cancelled` MUST include the CEL guard:
`request.resource.data.startsAt.toMillis() - request.time.toMillis() > 86400000`

#### SCENARIO-527: Rule denies cancel when ≤24h ahead

- GIVEN an appointment `startsAt` is 10 hours in the future
- WHEN a client sends an update setting `status: cancelled`
- THEN the Firestore emulator denies the request

---

## Cross-Reference Index

| REQ | SCENARIOs |
|---|---|
| REQ-COACH-AGENDA-001 | 478, 479 |
| REQ-COACH-AGENDA-002 | 480, 481 |
| REQ-COACH-AGENDA-003 | 482, 483, 484 |
| REQ-COACH-AGENDA-004 | 485, 486, 487 |
| REQ-COACH-AGENDA-005 | 488 |
| REQ-COACH-AGENDA-006 | 489, 490, 491 |
| REQ-COACH-AGENDA-007 | 492, 493 |
| REQ-COACH-AGENDA-008 | 494, 495 |
| REQ-COACH-AGENDA-009 | 496 |
| REQ-COACH-AGENDA-010 | (provider contract — covered via integration in 489–495) |
| REQ-COACH-AGENDA-011 | 497, 498 |
| REQ-COACH-AGENDA-012 | 499, 500 |
| REQ-COACH-AGENDA-013 | 501, 502 |
| REQ-COACH-AGENDA-014 | 503, 504 |
| REQ-COACH-AGENDA-015 | 505 |
| REQ-COACH-AGENDA-016 | 506, 507 |
| REQ-COACH-AGENDA-017 | 508, 509, 510 |
| REQ-COACH-AGENDA-018 | 511 |
| REQ-COACH-AGENDA-019 | 512 |
| REQ-COACH-AGENDA-020 | 513 |
| REQ-COACH-AGENDA-021 | 514, 515, 516 |
| REQ-COACH-AGENDA-022 | 517, 518, 519 |
| REQ-COACH-AGENDA-023 | 520, 521 |
| REQ-COACH-AGENDA-024 | 522 |
| REQ-COACH-AGENDA-025 | 523 |
| REQ-COACH-AGENDA-026 | 524 |
| REQ-COACH-AGENDA-027 | 525 |
| REQ-COACH-AGENDA-028 | 526 |
| REQ-COACH-AGENDA-029 | 527 |

---

## Normative Tensions

1. **Cancelled-slot re-booking** (RESOLVED by design ADR-1): The deterministic ID `'{trainerId}_{startsAtMs}'` would mean a cancelled slot cannot be re-booked. Design ADR-1 LOCKED the flip semantics: the booking transaction reads the doc and if `status == 'cancelled'`, flips it back to `'confirmed'` (overwriting `athleteId`/`linkId`/`cancelledAt`/`cancelledBy`) while PRESERVING the `cancellationLog` array. SCENARIO-491 amended to reflect this. Firestore `allow update` rule for `appointments` MUST permit `cancelled → confirmed` flip when caller has an active link with the new athleteId.

2. **Rule edit and active bookings**: REQ-COACH-AGENDA-026 guarantees confirmed appointments survive rule changes, but the free-slot computation must ignore rule-deleted time windows when calculating future availability. The design phase MUST specify how `computeFreeSlots` handles an appointment whose slot no longer falls within any active rule (it should remain confirmed; only new bookings are blocked).
