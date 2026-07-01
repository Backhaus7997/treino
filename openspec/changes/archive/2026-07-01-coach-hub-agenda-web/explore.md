# Exploration: coach-hub-agenda-web

## Current State

### Domain model (file:line refs)

**AvailabilityRule** (`lib/features/coach/domain/availability_rule.dart:16`)
- Recurring weekly slot published by a trainer
- Fields: `id`, `trainerId`, `dayOfWeek` (ISO 1=Mon..7=Sun), `startHour`, `startMinute`, `endHour`, `endMinute`, `slotDurationMin` (30|60|90|120)
- Stored at Firestore `coach_availability_rules/{id}`

**AvailabilityOverride** (`lib/features/coach/domain/availability_override.dart:16`)
- Sealed union: `block` (blocks an entire date) | `extra` (adds a one-off window)
- Fields: `id`, `trainerId`, `date` (Timestamp), + time fields for `extra` variant
- Stored at `coach_availability_overrides/{id}`
- ADR-6: discriminated by `type` field on wire

**Appointment** (`lib/features/coach/domain/appointment.dart:37`)
- Full booking record. Fields: `id`, `trainerId`, `athleteId`, `athleteDisplayName`, `startsAt` (UTC, minute-precision per ADR-7), `durationMin`, `status` (confirmed|cancelled), `cancelledAt`, `cancelledBy`, `cancellationLog[]`, `noteBefore`, `noteAfter`, `recurringId`
- IMPORTANT: there are TWO creation flows:
  - `Appointment.create()` (deterministic ID `{trainerId}_{startsAtMs}`) — used when athlete self-books a free slot (legacy; 28-day horizon guard)
  - `createByTrainer()` (auto-ID, `lib/features/coach/data/appointment_repository.dart:103`) — current model (2026-06-03); trainer schedules directly, overlapping sessions allowed
  - `createRecurringByTrainer()` — batch-creates recurring sessions with shared `recurringId`
- Stored at `appointments/{id}`

**computeFreeSlots** (`lib/features/coach/domain/compute_free_slots.dart:21`)
- Pure function: rules + overrides + existing appointments → `List<DateTime>` free slots for a given date
- Algorithm: block override early-return → week-rule slots → extra override slots → subtract confirmed appointments

**AgendaProviders** (`lib/features/coach/application/agenda_providers.dart`)
- `availabilityRulesStreamProvider(trainerId)` — stream of rules
- `overridesStreamProvider(OverridesKey)` — stream of overrides in date range
- `appointmentsForAthleteStreamProvider(athleteId)` — athlete's confirmed appts
- `trainerAppointmentsStreamProvider(TrainerAppointmentsKey)` — trainer's confirmed appts in date range
- `freeSlotsProvider(FreeSlotsKey)` — derived: computes free slots from the above

### Mobile — what exists today

**TrainerAgendaTab** (`lib/features/coach/presentation/trainer_agenda_tab.dart:30`)
- Lives inside `TrainerCoachView` (mobile shell, tab index 2)
- Trainer sees: monthly/week calendar (dots on booked days) + `DayTimeline` below
- Actions: "NUEVA SESIÓN" button → `NewSessionSheet`; clock icon → `AvailabilityEditorScreen` (`/coach/availability-editor`)
- Uses `table_calendar ^3.2.0` and a custom `DayTimeline` widget

**DayTimeline** (`lib/features/coach/presentation/widgets/day_timeline.dart`)
- Teams-style hour grid, ScrollController, auto-scroll to current hour
- Renders confirmed appointments as positioned blocks with athlete name
- Mobile-specific: sized for narrow viewports (64px per hour), uses `MediaQuery.paddingOf` for safe area

**AvailabilityEditorScreen** (`lib/features/coach/presentation/availability_editor_screen.dart:28`)
- Mobile-only full-screen route via `push('/coach/availability-editor')`
- CRUD for rules + overrides (add/delete recurring rules, block/extra overrides)
- This is WHERE the PF sets their availability today — ONLY on mobile

**AthleteAgendaScreen** (`lib/features/coach/presentation/athlete_agenda_screen.dart:27`)
- Athlete read-only view: TableCalendar (month format) + upcoming list + day bottom-sheet
- Uses `appointmentsForAthleteStreamProvider`
- SCENARIO-510 test: tapping a day → `_DaySessionsSheet` (read-only, no book/cancel controls)

### Web Coach Hub — the placeholder

`lib/features/coach_hub/presentation/sections/agenda/routes.dart:13`
- `agendaRoutes` = single `GoRoute('/agenda')` → `ProximamenteScreen(label: 'Agenda')`
- Already wired in `coach_hub_router.dart` ShellRoute (`lib/app/coach_hub_router.dart:103`)
- Already registered in `sidebar_registry.dart` (`lib/features/coach_hub/presentation/shell/sidebar_registry.dart:39`) in `SidebarGroup.resumen`

**Coach Hub section pattern** (from `dashboard/routes.dart` + `coach_hub_scaffold.dart`):
1. Each section owns its `routes.dart` exporting `<section>Routes` + `<section>SidebarItems`
2. Screen has NO Scaffold/SafeArea — `CoachHubScaffold` provides shell (ADR-CHW-005)
3. Content in `Center > ConstrainedBox(maxWidth: ~800)` or direct `Padding(horizontal: 20, vertical: 18)`
4. Hardcoded Spanish strings + `// i18n: Fase W1` comments — NO `AppL10n`
5. `AppPalette.of(context)` for colors; `TreinoIcon.X` for icons
6. `autoDispose` + `family` providers for page-local state
7. No `showModalBottomSheet` on web (desktop idiom); dialogs via `showDialog<bool>` (AlertDialog)

### Firestore rules summary

`firestore.rules`:
- `coach_availability_rules`: read = any authenticated; write = only owning trainer
- `coach_availability_overrides`: read = any authenticated; write = only owning trainer
- `appointments`: read = only parties involved (athleteId or trainerId); write = trainer creates/updates own sessions via `createByTrainer`

### Coordination check — feat/chat-web-v1

The other dev touches `lib/features/coach_hub/presentation/sections/alumnos/alumno_detail_screen.dart`.
The agenda section creates/modifies ONLY:
- `lib/features/coach_hub/presentation/sections/agenda/` (routes.dart + new screen)
- Zero overlap with `alumno_detail_screen.dart`

**Result: FULLY INDEPENDENT. Zero collision risk.**

---

## Affected Areas

- `lib/features/coach_hub/presentation/sections/agenda/routes.dart` — replace ProximamenteScreen with real screen; add sub-routes if needed
- `lib/features/coach_hub/presentation/sections/agenda/` — new screen file(s) to create
- `lib/features/coach/application/agenda_providers.dart` — consumed as-is; no changes needed
- `lib/features/coach/data/appointment_repository.dart` — consumed as-is; no changes needed
- `lib/features/coach/domain/appointment.dart` — consumed as-is
- `lib/app/coach_hub_router.dart` — no change needed (agendaRoutes already spread here)
- `lib/features/coach_hub/presentation/shell/sidebar_registry.dart` — no change needed (agendaSidebarItems already registered)

---

## Reuse Assessment

**table_calendar** — already in pubspec (`^3.2.0`). Web-compatible (Flutter web). `_TrainerCalendar` widget in `trainer_agenda_tab.dart` is a clean ConsumerWidget with no mobile-only dependencies. It CAN be extracted into a shared widget or copied and adapted for web with minimal changes.

**DayTimeline** — NOT directly reusable on web. It uses `MediaQuery.paddingOf(context).bottom` for safe-area (mobile idiom), fixed `_kHourHeight = 64px` (fine for both), and `showModalBottomSheet` for new-session sheet. For web, tapping an empty slot should use `showDialog` or an inline panel, not a bottom sheet. The rendering logic (hour grid + positioned blocks) IS portable; only the interaction layer needs web adaptation.

**AppointmentTile** / `_SessionRow` — pure display widgets, no mobile-specific APIs. Directly reusable.

**AgendaFormatters** (`lib/features/coach/presentation/agenda_formatters.dart`) — date/time formatting utils, no platform dependency. Reusable as-is.

---

## Design Options

### Option A — Read-only weekly view ("Ver mis turnos")

**Scope**: Display only. The trainer sees a weekly calendar with confirmed appointments. No booking, no availability editing.

**What it builds**:
- `AgendaWebScreen` (ConsumerStatefulWidget, no Scaffold)
- Weekly/month toggle using existing `table_calendar` CalendarFormat
- Selected-day appointment list inline (no bottom sheet; web idiom)
- Empty state when no appointments

**Providers needed**: `trainerAppointmentsStreamProvider(TrainerAppointmentsKey)` — already exists

**Pros**:
- Smallest V1 surface: 1 new file, ~250–350 lines
- Zero domain/data changes
- Zero collision with other PRs
- Tests are straightforward (widget tests on the screen, mock the stream provider)
- Highest chance of shipping quickly

**Cons**:
- PF still has to go to mobile to edit availability and create sessions
- Arguably a "window" with low action value on web

**Effort**: Low (~1–2 days including tests)

---

### Option B — Read-only + "Nueva Sesión" creation

**Scope**: View appointments + create a new session for a specific athlete via a dialog (no availability editing).

**What it builds**:
- Everything in Option A
- "Nueva sesión" button → `showDialog` (AlertDialog form): pick athlete from `trainerLinksStreamProvider`, date/time, duration
- Writes via `appointmentRepositoryProvider.createByTrainer(...)`

**Providers needed**: adds `trainerLinksStreamProvider`, `appointmentRepositoryProvider`

**Pros**:
- Meaningful action: PF can schedule sessions from web
- All backend pieces already exist (`createByTrainer`, `watchForTrainer`)
- No Firestore schema changes

**Cons**:
- Dialog form (athlete picker + date + time + duration) adds ~2–3 widgets of complexity
- Needs error handling (form validation, write errors)
- Bigger test surface: widget tests + provider override for write path

**Effort**: Medium (~3–4 days including tests)

---

### Option C — Full trainer agenda: view + session creation + availability editor

**Scope**: Parity with the mobile `TrainerAgendaTab` + `AvailabilityEditorScreen`.

**What it builds**:
- Everything in Option B
- Availability editor embedded as a tab or side panel: add/delete recurring weekly rules, block/extra date overrides
- All AvailabilityRepository CRUD

**Pros**:
- Full web feature parity
- PF no longer needs mobile for availability management

**Cons**:
- Availability editor is a complex multi-form surface (rule builder, date picker for overrides)
- High chance of scope creep beyond a reasonable V1 PR
- The mobile editor already works; adding it to web has lower ROI for V1
- Would push the PR well above the 400-line budget guideline

**Effort**: High (~7–10 days including tests)

---

## Approaches comparison

| Approach | Scope | Lines estimate | Effort | Blocks other work? | V1 value |
|----------|-------|---------------|--------|-------------------|----------|
| A — Read-only view | View appts | 250–350 | Low | No | Medium — visibility |
| B — View + Nueva Sesión | View + create | 450–600 | Medium | No | High — action from web |
| C — Full parity | View + create + availability editor | 900–1300 | High | No | Very high — but V2 scope |

---

## Recommendation

**Ship Option A as the V1 PR, followed by Option B as V2.**

Reasoning:
1. The PF already manages availability on mobile (`AvailabilityEditorScreen`) — no urgency to replicate it on web for V1.
2. Option A closes the "Próximamente" gap and gives the PF read access to their week on any browser. That alone has real value for a trainer reviewing their schedule on desktop.
3. Option B (creating sessions) is the highest-ROI next step, and it is a self-contained additive change that can be its own PR chained on top of A.
4. Option C should only happen once A + B are stable and the team explicitly wants availability management on web.

If the decision is made that V1 must include session creation (Option B), it is feasible as a single PR but the 400-line budget will likely be exceeded — the orchestrator should flag this for a `size:exception` or chain A→B as separate PRs.

---

## Open Questions for Proposal

1. **V1 scope**: Is read-only (Option A) sufficient, or must V1 include session creation (Option B)? This is the primary fork.
2. **Date range**: Should the web calendar default to the current week or current month? (Mobile trainer defaults to week, athlete defaults to month.)
3. **"Nueva Sesión" entry point**: If included in V1, should it use the same form as mobile's `NewSessionSheet` adapted into an `AlertDialog`, or a dedicated web panel?
4. **Availability editor**: Explicitly out of scope for V1? Or is there stakeholder pressure to add it now?
5. **SCENARIO-510 risk**: The test file (`test/features/coach/presentation/athlete_agenda_screen_test.dart`) tests the athlete's mobile screen, not the trainer's web screen. As long as this PR only creates new files under `coach_hub/presentation/sections/agenda/` and does NOT touch `athlete_agenda_screen.dart` or `trainer_agenda_tab.dart`, SCENARIO-510 is completely safe.

---

## Risks

1. **DayTimeline web adaptation**: The `DayTimeline` widget is not directly portable — it uses bottom safe-area padding and bottom-sheet interaction. A web equivalent needs a different scroll/interaction model. Recommend building a simpler `_AgendaWebDayList` (vertical list of appointment cards) instead of trying to port the hour-grid view for V1.

2. **SCENARIO-510 time-bomb**: The test is scoped to `AthleteAgendaScreen` (athlete, mobile). This change creates ONLY new files under `coach_hub/presentation/sections/agenda/`. Zero risk of touching SCENARIO-510 unless someone incorrectly imports from `athlete_agenda_screen.dart`. The test remains isolated.

3. **400-line PR budget**: Option A is safe (~300 lines). Option B will likely exceed the budget (~550 lines) and should be a chained PR or require `size:exception`.

4. **table_calendar web rendering**: The package is Flutter web compatible but touch/scroll gestures differ. Week/month format toggle should work fine on desktop with mouse clicks. No known blockers.

5. **Firestore rules — trainer read access**: `appointments` collection rule requires the reader to be `athleteId` OR `trainerId`. The web PF is authenticated as `trainerId`, so `watchForTrainer` queries work correctly on web. No rule changes needed.

6. **No AppL10n**: Web Coach Hub uses hardcoded Spanish (`// i18n` comments). This must NOT use `AppL10n.of(context)` — any imported widgets from mobile that use `AppL10n` (like `AppointmentTile`) must be copied/adapted or the l10n call removed.

---

## Ready for Proposal

Yes. The domain is fully mapped, the web section pattern is clear, and the V1 scope decision (Option A vs B) is the only open fork. Once that is answered, `sdd-propose` can proceed with high confidence.
