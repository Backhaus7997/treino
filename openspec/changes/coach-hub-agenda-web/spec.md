# Coach Hub Agenda Web — Specification
# Change: coach-hub-agenda-web | Artifact: spec | Store: hybrid

## Purpose

Introduce full-parity web agenda for the Coach Hub, replacing the ProximamenteScreen placeholder.
Delivered as three chained PRs: PR1 (Ver turnos) → PR2 (Nueva Sesión) → PR3 (Disponibilidad).
All new files MUST live under `coach_hub/presentation/sections/agenda/`.
No backend, domain, or mobile changes. Hardcoded Spanish + `// i18n` everywhere.

---

## PR1 — Ver turnos (read-only)

### Requirement: REQ-AGW-101 Calendar renders with week default and month toggle

The system MUST display a `table_calendar` widget defaulting to week view.
The system MUST provide a toggle to switch to month view.
The system MUST render booking dots on days that have at least one appointment.
`// i18n` comments MUST accompany every hardcoded Spanish string.

#### SCENARIO-101-A: Calendar loads with appointments

- GIVEN a trainer has appointments in the current week
- WHEN `AgendaWebScreen` mounts
- THEN the calendar shows in week view AND booking dots appear on appointment days

#### SCENARIO-101-B: Month toggle switches view

- GIVEN the calendar is in week view
- WHEN the trainer taps the month-toggle control
- THEN the calendar switches to month view showing all days of that month

#### SCENARIO-101-C: Trainer with no appointments at all

- GIVEN a trainer has zero appointments
- WHEN `AgendaWebScreen` mounts
- THEN the calendar shows with no booking dots AND the day list shows an empty-state widget

---

### Requirement: REQ-AGW-102 Day selection shows appointment list

The system MUST show the appointments for the selected day as a vertical card list (`_AgendaWebDayList`).
Each card MUST display: start time, athlete name, and duration.
The system MUST show an empty-state widget when the selected day has no appointments.

#### SCENARIO-102-A: Day with appointments selected

- GIVEN a trainer has two appointments on Tuesday
- WHEN the trainer selects Tuesday in the calendar
- THEN `_AgendaWebDayList` renders two cards, each showing time + athlete name + duration

#### SCENARIO-102-B: Day with no appointments selected

- GIVEN a trainer has no appointments on Wednesday
- WHEN the trainer selects Wednesday
- THEN an empty-state widget is displayed instead of cards

---

### Requirement: REQ-AGW-103 Appointment detail dialog

The system MUST open an `AlertDialog` with appointment details when a card is tapped.
The dialog MUST NOT use `showModalBottomSheet`.

#### SCENARIO-103-A: Tap appointment card

- GIVEN the day list shows an appointment card
- WHEN the trainer taps the card
- THEN an `AlertDialog` appears showing full appointment detail (athlete, time, duration, note)

#### SCENARIO-103-B: Dismiss dialog

- GIVEN the detail `AlertDialog` is open
- WHEN the trainer taps the dismiss / close action
- THEN the dialog closes and the day list is visible again

**Test surface (PR1):** widget tests on `AgendaWebScreen`; override `trainerAppointmentsStreamProvider` with a fake; assert calendar presence, booking dots, day list cards, empty state, detail dialog open/close.

---

## PR2 — Nueva Sesión (create)

### Requirement: REQ-AGW-201 Nueva Sesión dialog

The system MUST show a "Nueva Sesión" button on `AgendaWebScreen`.
Tapping it MUST open `_NewSessionDialog` via `showDialog<bool>`.
The dialog MUST contain: athlete picker, date field, time field, duration selector.
Duration options MUST be drawn from the allowed set: {30, 60, 90, 120} minutes.

#### SCENARIO-201-A: Open dialog

- GIVEN the trainer is on the agenda web screen
- WHEN the trainer taps "Nueva Sesión" // i18n
- THEN `_NewSessionDialog` opens as an `AlertDialog`

#### SCENARIO-201-B: Validation — missing required fields

- GIVEN `_NewSessionDialog` is open
- WHEN the trainer taps submit without selecting an athlete, date, or time
- THEN submission is blocked AND inline validation errors are shown for each missing field

#### SCENARIO-201-C: Duration selector shows allowed set

- GIVEN `_NewSessionDialog` is open
- WHEN the trainer opens the duration selector
- THEN only {30, 60, 90, 120} min options are available

---

### Requirement: REQ-AGW-202 Session creation calls repository and updates calendar

The system MUST call `appointmentRepository.createByTrainer` on valid submission.
On success the dialog MUST close and the new appointment MUST appear in the calendar/day list.
Recurring session creation is DEFERRED (out of scope for PR2).

#### SCENARIO-202-A: Successful creation

- GIVEN all fields are valid
- WHEN the trainer submits `_NewSessionDialog`
- THEN `createByTrainer(trainerId, athleteId, athleteDisplayName, startsAt, durationMin)` is called
- AND the dialog closes
- AND the new appointment card appears in the day list for the selected date

#### SCENARIO-202-B: Repository error

- GIVEN the repository returns a failure
- WHEN the trainer submits
- THEN the dialog stays open AND an error message is shown (hardcoded Spanish + `// i18n`)

**Test surface (PR2):** widget tests on `_NewSessionDialog`; override `appointmentRepositoryProvider` fake; assert form validation + correct `createByTrainer` args + dialog close on success + error display on failure.

---

## PR3 — Disponibilidad (availability editor)

### Requirement: REQ-AGW-301 Recurring rule list and CRUD

The system MUST display a list of the trainer's recurring availability rules.
Each rule MUST show: day of week, start time, end time, slot duration.
The system MUST allow adding, updating, and deleting rules inline (no route push).
`slotDurationMin` MUST be one of {30, 60, 90, 120}.
`dayOfWeek` MUST follow ISO 8601 (1 = Monday … 7 = Sunday).
The system MUST show an empty-state widget when no rules exist.

#### SCENARIO-301-A: Empty state — no rules

- GIVEN a trainer has no recurring rules
- WHEN the trainer opens the Disponibilidad panel
- THEN an empty-state widget is shown with a prompt to add the first rule

#### SCENARIO-301-B: Add rule

- GIVEN the trainer fills in day, window (start + end), and slot duration
- WHEN the trainer confirms add
- THEN `availabilityRepository.addRule(trainerId, rule)` is called
- AND the new rule appears in the list

#### SCENARIO-301-C: Update rule

- GIVEN a rule exists in the list
- WHEN the trainer edits and confirms
- THEN `availabilityRepository.updateRule(trainerId, rule)` is called
- AND the list reflects the updated values

#### SCENARIO-301-D: Delete rule

- GIVEN a rule exists in the list
- WHEN the trainer confirms deletion
- THEN `availabilityRepository.deleteRule(trainerId, ruleId)` is called
- AND the rule is removed from the list

---

### Requirement: REQ-AGW-302 Override editor — block and extra windows

The system MUST allow adding and deleting availability overrides.
An override MUST be either `block` (day-off) or `extra` (one-off extra window).
Deleting an override MUST call `availabilityRepository.deleteOverride(trainerId, overrideId)`.

#### SCENARIO-302-A: Add block override (day-off)

- GIVEN the trainer selects a date and chooses "Bloquear día" // i18n
- WHEN the trainer confirms
- THEN `availabilityRepository.addOverride(trainerId, override{type:block})` is called
- AND the blocked day appears in the overrides list

#### SCENARIO-302-B: Add extra window

- GIVEN the trainer selects a date, start time, and end time
- WHEN the trainer confirms "Ventana extra" // i18n
- THEN `availabilityRepository.addOverride(trainerId, override{type:extra})` is called

#### SCENARIO-302-C: Delete override

- GIVEN an override exists in the list
- WHEN the trainer taps delete and confirms
- THEN `availabilityRepository.deleteOverride(trainerId, overrideId)` is called
- AND the override is removed from the list

**Test surface (PR3):** widget tests overriding `availabilityRulesStreamProvider` and `overridesStreamProvider` fakes + `availabilityRepositoryProvider` fake; assert add/update/delete rule; assert block/extra override add/delete; assert empty state.

---

## Cross-cutting constraints (all PRs)

| # | Constraint |
|---|-----------|
| C-1 | All files MUST be under `coach_hub/presentation/sections/agenda/` |
| C-2 | NO `Scaffold` — `CoachHubScaffold` provides the shell (ADR-CHW-005) |
| C-3 | Use `AppPalette.of(context)` — MUST NOT hardcode hex colors |
| C-4 | Use `TreinoIcon.X` — MUST NOT use Phosphor or other icon packs |
| C-5 | Widgets MUST be `ConsumerStatefulWidget`; page-local state `autoDispose+family` |
| C-6 | Strings hardcoded Spanish + `// i18n`; MUST NOT call `AppL10n` |
| C-7 | Dialogs MUST use `showDialog` / `AlertDialog`; MUST NOT use `showModalBottomSheet` |
| C-8 | MUST NOT modify mobile files; SCENARIO-510 time-bomb is untouched |
| C-9 | `dart analyze` must return 0 errors; `dart format` applied; all tests green before merge |
| C-10 | Each PR MUST be independently shippable (PR1 closes placeholder; PR2/PR3 build on it) |

## Out of scope

- Recurring session creation UI (deferred post-PR2)
- Free-slot suggestion UI
- Any AppL10n / i18n infrastructure
- Any mobile file changes
- Any Firestore rule changes
- Any backend / domain / repository changes
