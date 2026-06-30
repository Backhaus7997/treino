# Design: coach-hub-agenda-web

Status: design complete (hybrid — mirrored to engram `sdd/coach-hub-agenda-web/design`)
Phase: HOW at the architectural level. Reads proposal `sdd/coach-hub-agenda-web/proposal` (obs #117).
Locked: FULL PARITY with mobile `TrainerAgendaTab`, 3 chained PRs (PR1 Ver / PR2 Crear / PR3 Disponibilidad).

---

## 1. Architecture approach

**Pattern**: Web-idiom presentation re-skin over the EXISTING mobile agenda application + domain
layers. Zero new providers, zero new domain, zero Firestore/rule changes. This is a pure
presentation slice inside the `coach_hub` feature, following the established Coach Hub section
contract (ADR-CHW-002/005): each section owns `sections/<name>/routes.dart` exporting
`<name>Routes` + `<name>SidebarItems`, and screens render WITHOUT a Scaffold (the
`CoachHubScaffold` shell provides chrome: sidebar + top bar + `ContentMaxWidth(1240)`).

**Layering** (top → bottom; only the top layer is new):
```
[NEW] coach_hub/presentation/sections/agenda/   ← web widgets (this change)
        AgendaWebScreen, _AgendaWebCalendar, _AgendaWebDayList,
        _AppointmentDetailDialog, _NewSessionDialog, _AvailabilityEditorPanel
            │ watch/read
            ▼
[REUSE] coach/application/agenda_providers.dart  ← providers (UNCHANGED)
        trainerAppointmentsStreamProvider, availabilityRulesStreamProvider,
        overridesStreamProvider, appointmentRepositoryProvider,
        availabilityRepositoryProvider
[REUSE] coach/application/trainer_link_providers.dart ← trainerLinksStreamProvider (UNCHANGED)
[REUSE] profile/application/user_public_profile_providers.dart ← name/avatar (UNCHANGED)
[REUSE] workout/application/session_providers.dart ← currentUidProvider (UNCHANGED)
            │
            ▼
[REUSE] coach/data/{appointment,availability}_repository.dart ← Firestore CRUD (UNCHANGED)
[REUSE] coach/domain/{appointment,availability_rule,availability_override}.dart (UNCHANGED)
[REUSE] coach/presentation/agenda_formatters.dart ← pure formatters, NO AppL10n (UNCHANGED)
```

**Boundary rule (collision-free)**: every NEW file lives under
`lib/features/coach_hub/presentation/sections/agenda/`. The ONLY edit to an existing file is
`sections/agenda/routes.dart` (swap `ProximamenteScreen` → `AgendaWebScreen`), and that edit
happens once in PR1. `feat/chat-web-v1` owns `sections/alumnos/…` — disjoint path → ZERO
collision (proposal risk #5 closed).

### trainerId source — DEFINITIVE
The web screen derives `trainerId` from **`currentUidProvider`** (`workout/application/session_providers.dart:59`),
NOT from a route parameter. Justification: `coach_hub_router.dart` guards every Coach Hub route
with `coachHubRedirect` (`coach_hub_router.dart:80` — `profile.role != UserRole.trainer` →
`/not-allowed`; unauthenticated → `/login`). Inside `/agenda` the current uid is therefore always
a valid trainer. This mirrors how `CoachHubDashboardScreen` works: it watches
`trainerLinksStreamProvider`, which itself reads `currentUidProvider` internally
(`trainer_link_providers.dart:60-65`). Mobile passes `trainerId` as a widget arg because the mobile
tab is nested inside a parent that already has it; on web we read it at the screen root. This keeps
the route builder a `const` `AgendaWebScreen()` with no args.

### Reusable formatters (no rewrite needed)
`AgendaFormatters` (`agenda_formatters.dart`) is pure utility with NO AppL10n dependency:
`formatTime` (HH:mm), `formatDate` (dd/MM/yyyy), `dayOfWeekLabels` (1→Lunes … 7→Domingo, already
Spanish). REUSE it verbatim in all three PRs. The inline-ES rewrite (locked decision) only applies
to copy that the mobile widgets pull from `AppL10n` (titles, button labels, error messages) — NOT
to these formatters.

---

## 2. The AppL10n → inline-ES rewrite (why display widgets are rebuilt, not ported)

The mobile display widgets (`DayTimeline`, `AppointmentTile`-equivalent block, `SessionDetailSheet`,
`AvailabilityEditorScreen`, `NewSessionSheet`) call `AppL10n.of(context).agenda*` for user-facing
copy. The locked web convention is **hardcoded Spanish + `// i18n` marker** (the Coach Hub web
standard, ADR-CHW; matches existing `routes.dart`/`sidebar_registry.dart`). Therefore we do NOT port
the mobile widgets — we build web equivalents that inline the Spanish copy. The mobile copy is the
source of truth for wording. Concrete string map (extracted from the mobile sources read this phase):

| Surface | Mobile source (AppL10n key or inline) | Web inline-ES literal (+ `// i18n`) |
|---|---|---|
| Screen entry — new session CTA | `'NUEVA SESIÓN'` (already inline, trainer_agenda_tab.dart:82) | `'NUEVA SESIÓN'` |
| Availability entry button tooltip | `agendaEditorTitle` | `'Mis horarios'` |
| Day-list empty state | (DayTimeline shows empty grid) | `'No hay sesiones este día.'` |
| Appointment card time | `AgendaFormatters.formatTime` | reuse formatter |
| Appointment card name fallback | `'Alumno'` (day_timeline.dart:327) | `'Alumno'` |
| Detail dialog time range | `'$start – $end · $dur min'` (session_detail_sheet.dart:162) | same composed string |
| Detail "antes de la sesión" | `'ANTES DE LA SESIÓN'` (inline) | `'ANTES DE LA SESIÓN'` |
| Detail "recordatorio (post)" | `'RECORDATORIO (POST)'` (inline) | `'RECORDATORIO (POST)'` |
| Detail save notes | `'GUARDAR NOTAS'` (inline) | `'GUARDAR NOTAS'` |
| Detail save ok / fail | `'Notas guardadas.'` / `'No pudimos guardar. Probá de nuevo.'` | same |
| Cancel reserva CTA | `'CANCELAR RESERVA'` (inline) | `'CANCELAR RESERVA'` |
| Cancel <24h note | `'No se puede cancelar (menos de 24h).'` (inline) | same |
| Cancel confirm dialog | `agendaCancellationConfirmTitle/Body/Cta/Keep` | `'Cancelar reserva'` / `'¿Seguro que querés cancelar esta sesión? El alumno será notificado.'` / `'Cancelar reserva'` / `'No, mantener'` |
| New-session title | `newSessionSheetTitle` | `'Nueva sesión'` |
| New-session alumno label | `newSessionSheetAlumnoLabel` | `'ALUMNO'` |
| New-session no-athletes | `newSessionSheetNoActiveAthletes` | `'No tenés alumnos activos todavía.'` |
| New-session fecha/hora/duración labels | `newSessionSheet{Fecha,Hora,Duracion}Label` | `'FECHA'` / `'HORA'` / `'DURACIÓN'` |
| New-session duration error | `newSessionSheetDurationError` | `'La duración debe estar entre 5 y 480 minutos.'` |
| New-session submit | `newSessionSheetSubmitSingle` | `'REGISTRAR SESIÓN'` |
| New-session past guard | `'No podés registrar una sesión en el pasado.'` (inline) | same |
| New-session ok / fail | `'Sesión registrada.'` / `'No pudimos registrar la sesión. Probá de nuevo.'` | same |
| Editor title | `agendaEditorTitle` | `'Mis horarios'` |
| Editor rules section | `'MIS HORARIOS DE TRABAJO'` (inline) | `'MIS HORARIOS DE TRABAJO'` |
| Editor rules empty | `'Sin horarios configurados. Agregá uno para que tus alumnos puedan reservar.'` | same |
| Editor add-rule CTA | `agendaAddRuleCta` | `'Agregar horario'` |
| Editor overrides section | `'EXCEPCIONES'` (inline) | `'EXCEPCIONES'` |
| Editor overrides empty | `'Sin excepciones.'` (inline) | `'Sin excepciones.'` |
| Editor block-day CTA | `agendaBlockDayCta` | `'Bloquear un día'` |
| Editor rule invalid window | `agendaRuleInvalidWindow` | `'El horario debe terminar después de empezar y entrar al menos un turno.'` |
| Editor save ok / fail | `agendaSaveSuccess` / `agendaSaveError` | `'Guardado.'` / `'No pudimos guardar. Probá de nuevo.'` |
| Editor delete-rule confirm | `agendaRuleDeleteConfirm` | `'¿Eliminar este horario?'` |
| Editor delete-override confirm | `'¿Eliminar esta excepción?'` (inline) | same |
| Editor confirm/cancel buttons | `agendaBookingConfirmCta` / `agendaBookingCancel` | `'Confirmar'` / `'Cancelar'` |

> The verifier should confirm every NEW string carries a trailing `// i18n` comment and that no
> `AppL10n` import appears in any new agenda file.

---

## 3. PR1 — Ver turnos (read-only, shippable alone, closes the placeholder)

### Files
- **EDIT** `sections/agenda/routes.dart`: drop the `proximamente_screen.dart` import; `/agenda`
  builder → `const AgendaWebScreen()`. `agendaSidebarItems` unchanged. (Only existing-file edit in
  the whole change.)
- **NEW** `sections/agenda/agenda_web_screen.dart`: `AgendaWebScreen` (`ConsumerStatefulWidget`, NO
  Scaffold) + private widgets `_AgendaWebCalendar`, `_AgendaWebDayList`, `_AppointmentCard`,
  `_AppointmentDetailDialog`, `_formatTimeRange` helper.

### `AgendaWebScreen` (state + layout)
- `ConsumerStatefulWidget`. State mirrors `_TrainerAgendaTabState`:
  `_focusedDay`, `_selectedDay`, `_calendarFormat = CalendarFormat.week` (locked: week default),
  and a rolling window `_rangeFrom`/`_rangeTo` computed in `initState` (now-1mo → now+1yr, UTC),
  identical to mobile lines 51-58.
- Root layout (NO Scaffold/SafeArea — shell provides them; ADR-CHW-005). Reference the dashboard
  section (`coach_hub_dashboard_screen.dart:109`): `Center > ConstrainedBox(maxWidth: 800) >
  SingleChildScrollView(padding 20/18) > Column(stretch)`. The shell already applies
  `ContentMaxWidth(1240)`; 800 keeps the calendar readable on wide monitors.
- Column children:
  1. Header row: `ElevatedButton.icon` `'NUEVA SESIÓN'` (disabled/no-op in PR1 — wired in PR2; to
     stay shippable, PR1 may render it `onPressed: null` OR omit it and add in PR2. Decision:
     **omit in PR1, add in PR2** so PR1 has no dead UI) + circular `OutlinedButton` `'Mis horarios'`
     (omitted in PR1, added in PR3 — same rationale). → **PR1 renders ONLY calendar + day list +
     detail.** This keeps each PR's surface honest.
  2. `_AgendaWebCalendar` (table_calendar).
  3. `_AgendaWebDayList` for `_selectedDay ?? DateTime.now()`.

### `_AgendaWebCalendar` (`ConsumerWidget`)
Port `_TrainerCalendar` (trainer_agenda_tab.dart:191-341) almost verbatim — it ALREADY uses
`AppPalette`, `TreinoIcon`, `GoogleFonts`, hardcoded ES format labels (`'Mes'`/`'Semana'`), and has
NO AppL10n dependency. Keep:
- `TableCalendar<dynamic>` (table_calendar ^3.2.0), `firstDay`/`lastDay` 2026-01-01 … 2027-12-31.
- `calendarFormat` + `onFormatChanged` (week/month toggle via `availableCalendarFormats`).
- `eventLoader`: dots only on days with ≥1 **confirmed** appointment AND not past (`_isDayPast`),
  computed from `trainerAppointmentsStreamProvider(TrainerAppointmentsKey{trainerId, rangeFrom,
  rangeTo})`. `markerBuilder` → 6px `palette.highlight` dot. (Logic identical to mobile 217-277.)
- All `calendarStyle`/`headerStyle`/`daysOfWeekStyle` blocks verbatim.
Single web-specific check: validate table_calendar mouse/keyboard gestures render on web (proposal
risk #2) — covered by a smoke widget test, not a code change.

### `_AgendaWebDayList` (`ConsumerWidget`) — replaces DayTimeline
Mobile `DayTimeline` is an absolute-positioned hour grid (64px/hr, now-line, tap-to-create,
auto-scroll, overlap columns) — NOT portable and overkill for web V1 (locked decision #3: vertical
card list, not hour grid). New widget:
- Watches `trainerAppointmentsStreamProvider(same key)`.
- Filters confirmed + same y/m/d as `day` (reuse mobile filter logic, day_timeline.dart:108-114).
- Sorts by `startsAt`.
- `.when(loading: spinner, error: retry row, data: …)` — follow the dashboard's
  `_SectionLoading`/`_SectionError` shape (coach_hub_dashboard_screen.dart:377-426) but inline-ES.
- Empty → `'No hay sesiones este día.'` // i18n centered muted text.
- Else → `Column` of `_AppointmentCard`.

### `_AppointmentCard` (`ConsumerWidget`)
Card per appointment (NOT a positioned block). Content from `Appointment` + name resolution:
- Watches `userPublicProfileProvider(appt.athleteId)`; name fallback to `appt.athleteDisplayName`,
  then `'Alumno'` if it looks like a raw uid (reuse the `isRawUid` guard, day_timeline.dart:323-327).
- Row: leading time `AgendaFormatters.formatTime(appt.startsAt)` (accent stripe via
  `palette.highlight`), athlete name, trailing duration `'${appt.durationMin} min'` muted.
- `Container` styling like the dashboard `_StudentTile` (bgCard, radius 14, border) — `const` where
  possible.
- `onTap` → `_showAppointmentDetail(context, ref, appt, trainerId)`.

### `_AppointmentDetailDialog` — replaces SessionDetailSheet (web idiom)
Locked: `showDialog`/`AlertDialog` instead of `showModalBottomSheet`. Reuse the dashboard's
`showDialog<bool>` + `AlertDialog` pattern (coach_hub_dashboard_screen.dart:53-77). Port the
SessionDetailSheet content (session_detail_sheet.dart) into the dialog body, inline-ES:
- Header: time range `'$start – $end · $dur min'` (composed via `AgendaFormatters`).
- `SERIE RECURRENTE` badge if `recurringId != null`.
- Athlete row (initials avatar + name). Tapping it: mobile pushes `/coach/athlete/{id}`; on web the
  equivalent is `/alumnos/{id}` owned by `feat/chat-web-v1` — to avoid a cross-branch route
  dependency, **PR1 renders the athlete name as non-tappable text** (no navigation). Revisit when
  alumnos-web lands. (Documented limitation, not a bug.)
- "ANTES DE LA SESIÓN" + "RECORDATORIO (POST)" `TextField`s bound to controllers; `GUARDAR NOTAS`
  → `appointmentRepositoryProvider.updateNotes(appointmentId, noteBefore, noteAfter)`.
- Cancel section: `CANCELAR RESERVA` (>24h) → `appointmentRepositoryProvider.cancel(...)`; <24h →
  muted note; recurring → `CANCELAR TODA LA SERIE` → `cancelFutureSeries(...)`. Confirm via nested
  `showDialog<bool>` AlertDialog (inline-ES copy from §2 table).
- Because the dialog holds note controllers + save state, model it as a small
  `ConsumerStatefulWidget` `_AppointmentDetailDialog` returned inside `showDialog`.

### Why PR1 is independently shippable
Renders the calendar + day list + detail entirely from `trainerAppointmentsStreamProvider` (read +
the cancel/notes mutations already exist in the repo). Closes the `ProximamenteScreen` placeholder.
No dependency on PR2/PR3. Ships alone.

---

## 4. PR2 — Nueva Sesión (create, builds on PR1)

### Files
- **EDIT** `agenda_web_screen.dart`: add the `'NUEVA SESIÓN'` `ElevatedButton.icon` to the header
  row (the slot left open in PR1); `onPressed` → `_openNewSessionDialog`.
- **NEW** `sections/agenda/new_session_dialog.dart`: `_NewSessionDialog`
  (`ConsumerStatefulWidget`) + private form sub-widgets, OR keep it private inside
  `agenda_web_screen.dart` if total stays small. Decision: **separate file** for review clarity.

### Athlete-picker source — DEFINITIVE ANSWER (the HARD TASK)
PR2's athlete picker reuses **`trainerLinksStreamProvider`** (no-arg
`StreamProvider.autoDispose<List<TrainerLink>>`, `trainer_link_providers.dart:60`), filtered to
`status == TrainerLinkStatus.active`. Display names resolve via
**`userPublicProfileProvider(athleteId)`** (`profile/application/user_public_profile_providers.dart`).

Evidence: the mobile `NewSessionSheet` is the ONLY existing caller of `createByTrainer`, and it
sources its athlete list exactly this way:
- `new_session_sheet.dart:89` → `ref.watch(trainerLinksStreamProvider)`
- `:90-92` → `.where((l) => l.status == TrainerLinkStatus.active)`
- `:925-936` (`_AthleteDropdown`) → `userPublicProfileProvider(link.athleteId)` for each item's label,
  with a `_looksLikeUid` fallback to `'Alumno (xxxxxx)'`.

This is also exactly the provider the web dashboard already uses (`coach_hub_dashboard_screen.dart:250`).
`trainerLinksStreamProvider` reads `currentUidProvider` internally, so it is consistent with the
web `trainerId` source decided in §1. **No new roster provider is created.** Recurring
(`createRecurringByTrainer`, repo:144) is DEFERRED (locked) — PR2 is single-session only.

### `_NewSessionDialog` (AlertDialog)
`showDialog<bool>` returning `true` on success so the caller can show a confirmation SnackBar
(pattern: dashboard `_confirmAction`). Body is a scrollable `Column` (web dialog can be tall →
wrap in `SingleChildScrollView`, `ConstrainedBox(maxWidth: 420)`). Fields (single-mode subset of
mobile — no recurring toggle):
1. **Athlete picker**: `DropdownButtonFormField<String>` fed by active links (see above). Disabled
   submit when empty; show `'No tenés alumnos activos todavía.'` // i18n when the active list is
   empty (mirror new_session_sheet.dart:149-156).
2. **Date**: tappable field → `showDatePicker` (first=today, last=+365d). Reuse mobile `_pickDate`
   (new_session_sheet.dart:322-333).
3. **Time**: tappable field → `showTimePicker`. Reuse mobile `_pickTime`.
4. **Duration**: number `TextField` + preset `ChoiceChip`s. Locked design says "duration from
   allowed set" — mobile uses free-text validated 5..480 with preset chips `{30,45,60,90,120}`. To
   match mobile create-flow PARITY (which is free 5..480, NOT `kAllowedSlotDurations`), keep
   **free-text 5..480 + preset chips**. (`kAllowedSlotDurations {30,60,90,120}` governs availability
   RULES, not trainer-created sessions — `createByTrainer` accepts any `durationMin`. Do not over-
   constrain here.)
5. **Note** (optional `noteBefore`): 2-line `TextField`.

### Submit flow (`_submit`) — reuse mobile `_submitSingle` verbatim (new_session_sheet.dart:347-426)
- Guard athlete selected.
- Compose `startsAt = DateTime.utc(date.y,m,d, time.h,time.min)`; reject if not after `nowWall`
  → `'No podés registrar una sesión en el pasado.'` // i18n.
- `_parsedDuration()` 5..480 → else `'La duración debe estar entre 5 y 480 minutos.'` // i18n.
- `trainerId = ref.read(currentUidProvider)` (null → auth error SnackBar).
- Resolve `athleteDisplayName` from `userPublicProfileProvider(athleteId).future`, fallback to id.
- `await ref.read(appointmentRepositoryProvider).createByTrainer(trainerId, athleteId,
  athleteDisplayName, startsAt, durationMin, noteBefore?)`.
- On success: pop(true), SnackBar `'Sesión registrada.'`. On error: keep dialog, SnackBar
  `'No pudimos registrar la sesión. Probá de nuevo.'`.

### Refresh
No manual refresh needed: `trainerAppointmentsStreamProvider` is a Firestore snapshot stream, so a
new appointment surfaces in the calendar dots + day list automatically (same as mobile). Tests
assert the `createByTrainer` args; live refresh is the stream's responsibility.

### Why PR2 is independently shippable
Adds one button + one dialog on top of PR1. The repo method, providers, and stream already exist.
Ships as the second link in the chain.

---

## 5. PR3 — Mis horarios (availability editor, largest)

### Files
- **EDIT** `agenda_web_screen.dart`: add the circular `'Mis horarios'` `OutlinedButton` to the
  header row; `onPressed` → open the editor. Locked design #4: **embedded panel**, not a separate
  route. Web idiom → open the editor as a large `AlertDialog`/`Dialog` via `showDialog` (consistent
  with PR1/PR2), OR an inline expandable panel. Decision: **`showDialog` with a `Dialog` containing
  a `ConstrainedBox(maxWidth: 560)` scrollable editor** — keeps the agenda screen uncluttered and
  matches the established web dialog idiom. Entry button label `'Mis horarios'` // i18n.
- **NEW** `sections/agenda/availability_editor_panel.dart`.

### Size guard → SUB-SLICE SPLIT (proposal forecast: PR3 ~400-600 lines, HIGH budget risk)
The mobile `AvailabilityEditorScreen` is ~1057 lines (rules list + rule form sheet + override list +
block-override form sheet + 6 shared sub-widgets). The web port, even leaner, will exceed ~400
lines. **Split PR3 into two stacked sub-PRs** (locked preference: split over `size:exception`):

- **PR3a — Reglas (recurring rules)**: `_AvailabilityEditorPanel` shell (opens via dialog) +
  `MIS HORARIOS DE TRABAJO` section + rules list (`_RuleTile`) + `_RuleFormDialog`
  (day-of-week chips, start/end `showTimePicker`, slot-duration chips `{30,60,90,120}`, window
  validation) + delete-rule confirm. Reuses `availabilityRulesStreamProvider(trainerId)`,
  `availabilityRepositoryProvider.{addRule, updateRule, deleteRule}`. ~280-340 lines.
- **PR3b — Excepciones (overrides)**: adds `EXCEPCIONES` section + overrides list (`_OverrideTile`,
  rendering both `block` and `extra` via the sealed `when`) + `_BlockOverrideFormDialog`
  (date picker) + delete-override confirm. Reuses `overridesStreamProvider(OverridesKey)`,
  `availabilityRepositoryProvider.{addOverride, deleteOverride}`. ~180-240 lines.
  (Extra-window CREATE UI is optional in V1 — mobile only exposes block-create + lists both block
  and extra. Match mobile: **render extra overrides, create only block overrides.**)

Both sub-PRs are independently shippable: PR3a delivers usable rule management; PR3b layers
exceptions on top.

### Editor structure (port `_EditorBody`, availability_editor_screen.dart:62-228, inline-ES)
- Loading/error/empty distinction (don't collapse loading into empty): if either stream
  `isLoading` → spinner; if either `hasError` → retry; else render lists. (Verbatim logic
  availability_editor_screen.dart:83-97.)
- Rule form `_RuleFormDialog` (port `_RuleFormSheet`, :382-603): state `_dayOfWeek, _startHour/Min,
  _endHour/Min, _slotDurationMin`; defaults Mon 09:00–11:00 / 60min. On save: validate
  `endTotalMinutes >= startTotalMinutes + slotDurationMin` → else inline-ES window error; then
  `addRule(AvailabilityRule(id: _generateId(), trainerId, …))` or
  `updateRule(existing.copyWith(...))`. Reuse the `_generateId()` 20-char helper (:1052).
- `_DayPicker`, `_TimePicker` (24h `MediaQuery` override), duration `ChoiceChip`s — ported as
  private widgets; all already palette/font-clean. `_TimePicker` uses `showTimePicker` (web-OK).
- Override form `_BlockOverrideFormDialog` (port `_BlockOverrideFormSheet`, :607-756): date picker
  (first=today, last=+365d), save → `addOverride(AvailabilityOverride.block(id, trainerId, date))`.
- `trainerId` from `currentUidProvider` (passed into the panel by `AgendaWebScreen`).

### Why PR3 (a+b) is independently shippable
Pure CRUD over `availabilityRepository`, which already exists and is used by mobile. No dependency
on PR2. The entry button is the only `agenda_web_screen.dart` touch. Ships as the third chain link
(or two stacked links).

---

## 6. Component & data-flow summary

```
AgendaWebScreen (ConsumerStatefulWidget, trainerId = currentUidProvider)
 ├─ _AgendaWebCalendar ── watch trainerAppointmentsStreamProvider ─► dots (confirmed, !past)
 ├─ _AgendaWebDayList ─── watch trainerAppointmentsStreamProvider ─► filter day ─► [_AppointmentCard]
 │       └─ _AppointmentCard ── watch userPublicProfileProvider ─► onTap ─► _AppointmentDetailDialog
 │               └─ updateNotes / cancel / cancelFutureSeries  (PR1)
 ├─ [PR2] header 'NUEVA SESIÓN' ─► _NewSessionDialog
 │       ├─ watch trainerLinksStreamProvider (active) + userPublicProfileProvider  ← athlete picker
 │       └─ createByTrainer(...)  ► stream auto-refreshes calendar + list
 └─ [PR3] header 'Mis horarios' ─► _AvailabilityEditorPanel (Dialog)
         ├─ [PR3a] watch availabilityRulesStreamProvider ─► [_RuleTile] / _RuleFormDialog ─► add/update/deleteRule
         └─ [PR3b] watch overridesStreamProvider ─► [_OverrideTile] / _BlockOverrideFormDialog ─► add/deleteOverride
```

All mutations go through the EXISTING repositories; all reads through EXISTING stream providers;
Firestore security rules unchanged (web PF is `trainerId`; `watchForTrainer` filters on `trainerId`
— proposal risk #6 closed).

---

## 7. ADR-style decisions

- **ADR-AGW-1 — Re-skin, not port.** Build new web widgets under `sections/agenda/`; reuse
  providers+domain+formatters unchanged. *Rejected*: porting mobile widgets (they depend on AppL10n,
  bottom sheets, safe-area, and the 64px hour grid — none web-idiomatic; would also drag AppL10n into
  the web convention). *Rejected*: extracting a shared widget package (premature; the two UIs diverge
  by idiom).
- **ADR-AGW-2 — `trainerId` from `currentUidProvider`, not a route param.** Router already guards
  `role == trainer`. *Rejected*: a `/agenda/:trainerId` route (the web PF only ever manages their own
  agenda; a param invites IDOR-shaped confusion and breaks the `const` builder).
- **ADR-AGW-3 — `showDialog`/`AlertDialog` for detail, create, and editor.** Web idiom; matches the
  dashboard's existing dialog pattern. *Rejected*: `showModalBottomSheet` (mobile-only ergonomics);
  full-screen pushed routes for the editor (locked decision #4 — embedded).
- **ADR-AGW-4 — Vertical card list, not an hour-grid timeline (PR1).** Locked #3. Simpler, web-
  readable, no auto-scroll/now-line/overlap-column complexity. *Rejected*: porting `DayTimeline`
  (absolute layout + gesture-to-create don't translate; large surface for no V1 value).
- **ADR-AGW-5 — Athlete picker = `trainerLinksStreamProvider` (active).** The mobile create flow's
  proven source; no new roster provider. *Rejected*: a bespoke roster provider (duplicates existing
  state, risks divergence); `linksForTrainerProvider` (deprecated, non-stream — :23).
- **ADR-AGW-6 — Create-session duration is free 5..480, not `kAllowedSlotDurations`.** Matches the
  mobile create flow; `createByTrainer` accepts any `durationMin`. *Rejected*: restricting to
  `{30,60,90,120}` (that set governs availability RULES/slot generation, not trainer-registered
  sessions — would diverge from mobile parity).
- **ADR-AGW-7 — Split PR3 into PR3a (rules) + PR3b (overrides).** Forecast HIGH budget risk; locked
  preference is split over `size:exception`. *Rejected*: one PR3 with a `size:exception`.
- **ADR-AGW-8 — Athlete row in the detail dialog is non-tappable in PR1.** The mobile target
  `/coach/athlete/{id}` maps to `/alumnos/{id}` owned by `feat/chat-web-v1`; avoid a cross-branch
  route dependency. *Rejected*: wiring `/alumnos/{id}` now (collision risk + dependency on another
  branch's route). Revisit once alumnos-web merges.
- **ADR-AGW-9 — PR1 omits the create/editor buttons rather than rendering disabled ones.** Keeps
  each PR's surface honest (no dead UI). Buttons arrive with their feature in PR2/PR3.

---

## 8. Test plan (strict TDD — `flutter test`; gate: analyze 0 + dart format + green; tests FIRST)

Shared harness (copy from `coach_hub_dashboard_screen_test.dart`): `_wrap(child, overrides)` →
`ProviderScope(overrides) > MaterialApp(theme: AppTheme.dark(), AppL10n delegates, home:
Scaffold(body: child))`. Override stream providers with `overrideWith((ref) => Stream.value(...))`;
override repos with `Fake`/`Stub` capturing call args (pattern from
`availability_editor_screen_test.dart` `_StubAvailabilityRepository`). Override `currentUidProvider`
with a fixed trainer uid. Register fallback values in `setUpAll`.

**PR1 — `test/features/coach_hub/presentation/sections/agenda/agenda_web_screen_test.dart`**
- Calendar renders (TableCalendar present), week format default.
- Booking dot appears on a day with a confirmed appointment; NOT on a past day; NOT on a cancelled-
  only day. (Override `trainerAppointmentsStreamProvider` with fixtures.)
- Day list: empty state `'No hay sesiones este día.'` when no appts that day.
- Day list: `_AppointmentCard` shows time (`HH:mm`), athlete name (override
  `userPublicProfileProvider`), duration (`N min`); raw-uid name falls back to `'Alumno'`.
- Tap card → `_AppointmentDetailDialog` opens (find time-range text + `'GUARDAR NOTAS'`).
- Loading → spinner; error → retry affordance.

**PR2 — `…/new_session_dialog_test.dart`**
- Tapping `'NUEVA SESIÓN'` opens the dialog.
- Active-links empty → `'No tenés alumnos activos todavía.'` + submit disabled.
- Athlete dropdown lists active links by display name (override `trainerLinksStreamProvider` +
  `userPublicProfileProvider`); paused/terminated links excluded.
- Validation: past date+time → SnackBar `'No podés registrar una sesión en el pasado.'`; duration
  out of 5..480 → duration error; no submit call in either case.
- Happy path: with a Stub `AppointmentRepository`, submit calls `createByTrainer` with the EXACT
  args (trainerId from `currentUidProvider`, selected athleteId, resolved displayName, UTC
  `startsAt`, durationMin, trimmed note→null when empty); dialog pops; success SnackBar.

**PR3a — `…/availability_editor_rules_test.dart`**
- Editor opens from `'Mis horarios'`; shows `MIS HORARIOS DE TRABAJO` + add CTA.
- Empty rules → empty hint copy.
- Existing rules (override `availabilityRulesStreamProvider`) render in tiles with day label +
  `HH:mm – HH:mm · N min`.
- Add-rule form: invalid window (end < start + slot) → window-error SnackBar, no `addRule`.
- Valid save → `addRule` called with a rule carrying the chosen fields + `trainerId`.
- Edit → `updateRule`; delete → confirm dialog → `deleteRule(trainerId, ruleId)`.

**PR3b — `…/availability_editor_overrides_test.dart`**
- `EXCEPCIONES` section + empty hint `'Sin excepciones.'`.
- Override list renders BOTH `block` and `extra` (override `overridesStreamProvider`); block shows
  `'Bloqueado'`-style label, extra shows its time window (sealed `when` both branches exercised).
- Add block override: pick date → `addOverride` called with `AvailabilityOverride.block(...)`.
- Delete override → confirm → `deleteOverride(trainerId, overrideId)`.

---

## 9. Confirmation

Each PR is independently shippable and dependency-ordered PR1 → PR2 → PR3 (PR3 = PR3a → PR3b). All
reuse existing providers/domain/repositories; the ONLY existing-file edit is `sections/agenda/
routes.dart` (PR1) + additive header-button edits to `agenda_web_screen.dart` (PR2, PR3). Zero
collision with `feat/chat-web-v1`. No domain/model/Firestore/rule changes. Smallest correct change
honored: vertical list over hour grid, dialogs over bottom sheets, no new providers.
