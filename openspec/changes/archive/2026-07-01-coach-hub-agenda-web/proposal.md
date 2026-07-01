# Proposal: coach-hub-agenda-web

> Status: proposed · Artifact store: hybrid · Project: treino
> Decision: **LOCKED — full parity with mobile trainer agenda, delivered as a CHAIN of 3 PRs.**

## 1. Intent & Motivation

**Problem.** The web Coach Hub "Agenda" section is a placeholder (`ProximamenteScreen('Agenda')`,
`lib/features/coach_hub/presentation/sections/agenda/routes.dart:16`). A Personal Trainer (PF)
working from a browser cannot see, create, or manage sessions — they are forced back to mobile
(`TrainerAgendaTab`, `lib/features/coach/presentation/trainer_agenda_tab.dart:30`) for every
agenda action.

**Why now.** The Coach Hub web shell, router, and sidebar entry for `/agenda` are already wired
(`coach_hub_router.dart:103`, `sidebar_registry.dart:39`). The only missing piece is the real
screen. The domain layer (rules, overrides, appointments, free-slot computation) is mature and
shared, so the web work is **pure presentation** — no backend, model, or Firestore-rule changes.

**Success looks like.** The PF manages their entire agenda from the web with the SAME capabilities
they have on mobile:
- See a calendar (week default, month toggle) with booking dots.
- See the selected day's confirmed appointments.
- Create a session ("Nueva Sesión") → `appointmentRepository.createByTrainer`.
- Edit availability ("Mis horarios") → rules + overrides CRUD.
- Tap an appointment → detail.

**Decision (locked with user).** Deliver FULL parity, but split across **three chained PRs**
(PR1 → PR2 → PR3) to keep each within the ~400-line review budget and ship value incrementally.
This supersedes the exploration's "Option A now, B later, C maybe" recommendation: the target is C,
sequenced as A → A+B → A+B+availability.

## 2. Web adaptation principle (NOT literal reuse)

Reuse the **providers + domain** as-is; rebuild the **UI** for web idioms.

| Layer | Mobile (today) | Web (this change) |
|-------|----------------|-------------------|
| Domain / data | `appointment.dart`, `availability_*.dart`, `compute_free_slots.dart` | **Reused unchanged** |
| Providers | `agenda_providers.dart` (stream + repo providers) | **Reused unchanged** |
| Calendar | `table_calendar ^3.2.0` (`_TrainerCalendar`) | `table_calendar` again (web-OK) — new web widget |
| Day view | `DayTimeline` (hour grid, safe-area, 64px/hr) | **NOT portable** → new web day list/grid |
| New session | `showModalBottomSheet` | **NOT a web idiom** → `showDialog` / `AlertDialog` |
| Availability | `AvailabilityEditorScreen` (full-screen push) | embedded web editor (no separate route) |
| Detail | bottom sheet | `showDialog` / `AlertDialog` |

**Conventions (web Coach Hub).** Hardcoded Spanish + `// i18n` comments — NOT `AppL10n`.
`AppPalette.of(context)` (no hex). `TreinoIcon.X` (no Phosphor). `ConsumerStatefulWidget`, NO
`Scaffold`/`SafeArea` (the shell `CoachHubScaffold` provides it — ADR-CHW-005). Page-local state via
`autoDispose` + `family` providers.

**Files touched — ONLY under `coach_hub/presentation/sections/agenda/`.** This guarantees ZERO
collision with `feat/chat-web-v1` (which owns `sections/alumnos/alumno_detail_screen.dart`).

## 3. Per-PR scope

### PR1 — "Ver turnos" (read-only) · Shippable alone, closes the placeholder

Replace `ProximamenteScreen` with a real read-only agenda.

- **New UI**: `AgendaWebScreen` (`ConsumerStatefulWidget`, no Scaffold); `_AgendaWebCalendar`
  (`table_calendar`, week default / month toggle, booking dots from the appointment stream);
  `_AgendaWebDayList` (vertical card list of the selected day's confirmed appointments + empty
  state); appointment detail via `showDialog`/`AlertDialog`.
- **Providers reused (no change)**: `trainerAppointmentsStreamProvider(TrainerAppointmentsKey{trainerId, fromDate, toDate})`.
- **Domain reused (no change)**: `Appointment` (`startsAt` UTC, `durationMin`, `athleteDisplayName`, `status`).
- **Edit**: `sections/agenda/routes.dart` — point `/agenda` at `AgendaWebScreen`, drop the
  `ProximamenteScreen` import.
- **Target**: ≤ ~400 lines.

### PR2 — "Nueva Sesión" (create) · Builds on PR1

Add session creation from the web.

- **New UI**: "Nueva Sesión" button on `AgendaWebScreen`; `_NewSessionDialog`
  (`AlertDialog`): athlete picker + date + time + duration; loading/error/validation states.
- **Provider/repo reused (no change)**: `appointmentRepositoryProvider.createByTrainer(trainerId, athleteId, athleteDisplayName, startsAt, durationMin, noteBefore?)`
  (`appointment_repository.dart:103`).
- **Athlete-picker source — design dependency (see Risks #7)**: there is currently **no UI caller
  of `createByTrainer`** in `lib/`, so the trainer→athlete roster provider that feeds the picker
  must be identified/confirmed in `sdd-design` (likely a trainer-links / roster stream provider).
  PR2 does not invent a provider; it consumes the existing roster source.
- **Out of PR2**: recurring sessions (`createRecurringByTrainer` exists at
  `appointment_repository.dart:144`) — explicitly deferred; single-session create only for V1 parity.

### PR3 — "Mis horarios" (availability editor) · Largest slice

Bring the mobile `AvailabilityEditorScreen` capability to web.

- **New UI**: "Mis horarios" entry → embedded availability editor panel(s): recurring **rule
  builder** (day-of-week + start/end + slot duration) and **override editor** (date picker → block
  or extra window). List + add + delete; web dialogs/inline panels, NOT a full-screen push.
- **Providers reused (no change)**: `availabilityRulesStreamProvider(trainerId)`,
  `overridesStreamProvider(OverridesKey{trainerId, fromDate, toDate})`.
- **Repo reused (no change)**: `availabilityRepositoryProvider` →
  `addRule`, `updateRule`, `deleteRule(trainerId, ruleId)`, `addOverride`,
  `deleteOverride(trainerId, overrideId)` (`availability_repository.dart:27–78`).
- **Domain reused (no change)**: `AvailabilityRule` (ISO dayOfWeek 1..7, slotDurationMin ∈ {30,60,90,120}),
  `AvailabilityOverride` (sealed `block` | `extra`, discriminated by `type` — ADR-6).

## 4. Scope OUT (explicit)

- **No domain/model/rules/data changes.** There are none to make — everything is reused.
  `appointment.dart`, `availability_*.dart`, `compute_free_slots.dart`, `agenda_providers.dart`,
  `appointment_repository.dart`, `availability_repository.dart`, `firestore.rules` are read-only here.
- **No literal reuse of mobile widgets.** `DayTimeline`, `showModalBottomSheet`, and safe-area code
  are NOT ported; we build web equivalents with the same functionality.
- **No `AppL10n`.** Web Coach Hub uses hardcoded Spanish + `// i18n`. Any mobile display widget that
  calls `AppL10n` (e.g. an `AppointmentTile`/`_SessionRow`) is rewritten inline rather than imported.
- **No mobile changes.** `trainer_agenda_tab.dart`, `availability_editor_screen.dart`, and
  `athlete_agenda_screen.dart` are untouched (protects SCENARIO-510 — see Risks #5).
- **No router/sidebar changes.** `agendaRoutes` is already spread in `coach_hub_router.dart` and
  `agendaSidebarItems` already registered; only the route's `builder` target changes (PR1).
- **No recurring-session UI** (deferred from PR2). No free-slot suggestion UI in V1 (the trainer
  picks date/time directly via `createByTrainer`, matching the current mobile model).

## 5. Micro-decisions (recommended)

1. **Calendar default = WEEK** (month via toggle). Matches the mobile *trainer* default
   (`TrainerAgendaTab`); the athlete screen uses month, but this is the trainer surface.
2. **"Nueva Sesión" = `AlertDialog`** via `showDialog<bool>`, NOT a bottom sheet. Web/desktop idiom
   and consistent with the Coach Hub section pattern (ADR-CHW pattern point 7).
3. **Day's appointments = vertical card list** (`_AgendaWebDayList`) for V1, NOT an hour grid.
   Simpler, web-friendly, far cheaper to build and test than porting `DayTimeline`. An hour-grid can
   be a later enhancement if requested — list is sufficient for parity of *information*.
4. **Availability editor = embedded panel** (dialogs/inline forms inside the agenda section), NOT a
   separate `/agenda/availability` route, to stay inside the single section and avoid extra wiring.
5. **Single-session create only** in PR2; recurring deferred (keeps PR2 inside budget).

## 6. Risks

1. **Scope size.** Full parity is ~900–1300 lines total — well over the 400-line budget. **Mitigation:
   the 3-PR chain.** Each PR is independently reviewable and PR1/PR2 ship value on their own.
2. **`table_calendar` web behavior.** Package is Flutter-web compatible; mouse vs touch gestures
   differ but week/month toggle works with clicks. Low risk; validate visually during PR1.
3. **Mobile display widgets call `AppL10n`.** Cannot be imported as-is into web Coach Hub. **Mitigation:
   rewrite the appointment row/detail inline with hardcoded Spanish + `// i18n`.**
4. **`DayTimeline` not portable** (safe-area + bottom-sheet interaction). **Mitigation:** decision #3 —
   build a web day list instead of porting the grid.
5. **SCENARIO-510 agenda time-bomb** lives in `test/features/coach/presentation/athlete_agenda_screen_test.dart`
   (mobile athlete screen). **We do NOT touch it** — this change creates only NEW files under
   `coach_hub/presentation/sections/agenda/` and never imports from `athlete_agenda_screen.dart`.
   The only `lib/` edit is the agenda `routes.dart` builder target. Risk: effectively zero, as long
   as no one imports mobile agenda code.
6. **Firestore read access.** `appointments` requires reader to be `trainerId` or `athleteId`; the web
   PF is authenticated as `trainerId`, so `watchForTrainer` works on web. No rule changes. Low risk.
7. **Athlete-picker source unconfirmed (PR2).** No existing UI caller of `createByTrainer` was found
   in `lib/`, so the trainer→athlete roster provider feeding the "Nueva Sesión" picker must be
   resolved in `sdd-design` before PR2 apply. Does NOT block PR1. **Open question for design.**

## 7. Testing / TDD (strict TDD, `flutter test`)

Gate per PR: `flutter analyze` 0 issues + `dart format .` + `flutter test` green. Tests written first.

- **PR1**: widget tests on `AgendaWebScreen` — override `trainerAppointmentsStreamProvider` with a
  fake stream; assert calendar renders, booking dots appear on days with appointments, selected-day
  list shows confirmed appointments, empty state when none, detail dialog opens on tap.
- **PR2**: widget tests for `_NewSessionDialog` — open via button; validate form (athlete required,
  valid date/time/duration); override `appointmentRepositoryProvider` with a fake to assert
  `createByTrainer` is called with normalized args; assert error/loading states.
- **PR3**: widget tests for the availability editor — override `availabilityRules`/`overrides`
  streams and `availabilityRepositoryProvider`; assert add/update/delete rule and add/delete override
  call the repo correctly; assert `block` vs `extra` override branches render and persist.

## 8. Review Workload Forecast (per PR)

| PR | Scope | New files | Est. changed lines | 400-line budget risk | Shippable alone |
|----|-------|-----------|--------------------|--------------------|-----------------|
| PR1 — Ver turnos | calendar + day list + detail dialog (read-only) | 1 screen + private widgets | ~300–400 | Low–Medium | Yes (closes placeholder) |
| PR2 — Nueva Sesión | create dialog → `createByTrainer` | +1 dialog widget | ~250–350 | Medium | Yes (builds on PR1) |
| PR3 — Disponibilidad | rule builder + override editor (CRUD) | +editor widgets | ~400–600 | **High** | Yes (builds on PR1/PR2) |

- **Chained PRs recommended: Yes (PR1 → PR2 → PR3).**
- **Decision needed before apply: No** — chained parity already decided with the user.
- PR3 alone is likely to exceed 400 lines; if it does, split its rule-editor and override-editor into
  two sub-slices rather than requesting a `size:exception`.

## 9. Affected files

**Created (PR1–PR3, all under `lib/features/coach_hub/presentation/sections/agenda/`):**
- `agenda_web_screen.dart` (PR1) + private calendar/day-list/detail widgets
- new-session dialog widget (PR2)
- availability-editor widget(s) (PR3)

**Edited (PR1 only):**
- `lib/features/coach_hub/presentation/sections/agenda/routes.dart` — `/agenda` builder →
  `AgendaWebScreen`; remove `ProximamenteScreen` import.

**Consumed unchanged:** `agenda_providers.dart`, `appointment_repository.dart`,
`availability_repository.dart`, `appointment.dart`, `availability_rule.dart`,
`availability_override.dart`, `compute_free_slots.dart`, `coach_hub_router.dart`,
`sidebar_registry.dart`, `firestore.rules`.
