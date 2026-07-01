# Coach Hub Agenda Web — Tasks
# Change: coach-hub-agenda-web | Artifact: tasks | Store: hybrid
# Generated: 2026-06-30

## Delivery Strategy
- 4 chained PRs: PR1 → PR2 → PR3a → PR3b
- Chained PRs: Yes (PR1 → PR2 → PR3a → PR3b)
- Decision needed before apply: No
- Each PR is independently shippable and gated before merge

---

## Quality Gate (all PRs)
Run before every PR merge:
```
flutter analyze          # must return 0 issues
dart format . --set-exit-if-changed
flutter test             # all tests green
```

---

## PR1 — Ver turnos (read-only calendar + day list)
**Goal**: Replace `ProximamenteScreen` placeholder with the full read-only agenda.
**Satisfies**: REQ-AGW-101, REQ-AGW-102, REQ-AGW-103
**Estimated lines**: ~320 (routes edit ~5 + screen ~180 + calendar widget ~80 + day list ~55)
**Workload risk**: LOW (well under 400-line budget)
**Prerequisite**: none (first in chain)

### TASK PR1-1 — [RED] Write failing widget test skeleton for `AgendaWebScreen`
- **Test file**: `test/features/coach_hub/presentation/sections/agenda/agenda_web_screen_test.dart`
- **Scenarios**: SCENARIO-101-A, SCENARIO-101-B, SCENARIO-101-C, SCENARIO-102-A, SCENARIO-102-B, SCENARIO-103-A, SCENARIO-103-B
- Write `_wrap(child, overrides)` helper (ProviderScope > MaterialApp with AppTheme.dark() + AppL10n delegates + home: Scaffold(body: child))
- Override `trainerAppointmentsStreamProvider` with `Stream.value([])` (empty) and with a fake list of 2 confirmed appointments
- Override `currentUidProvider` with a fixed test UID
- Assert: `find.byType(TableCalendar)` present; week format by default; month toggle button present; empty state copy present; no appointment dots when stream empty
- Assert: day-list cards show time / athlete name / duration on non-empty stream
- Assert: tapping card opens `AlertDialog` with appointment detail; dismiss closes it
- **This test MUST fail** (file does not exist yet)
- Parallel: NO (baseline test; subsequent PR1 tasks depend on it)

### TASK PR1-2 — [RED] Smoke test for `table_calendar` web gestures
- **Test file**: `test/features/coach_hub/presentation/sections/agenda/agenda_web_calendar_smoke_test.dart`
- Scenarios: SCENARIO-101-A, SCENARIO-101-B
- Assert `TableCalendar` renders in a web-targeted widget test using `testWidgets` with `TargetPlatform.linux` (Flutter web proxy)
- Assert week/month format toggle button tappable without throw
- **Must fail before implementation**
- Parallel: YES (can run alongside PR1-1)

### TASK PR1-3 — [GREEN] Edit `routes.dart` — swap placeholder
- **File**: `lib/features/coach_hub/presentation/sections/agenda/routes.dart`
- Replace `const ProximamenteScreen(label: 'Agenda')` with `const AgendaWebScreen()`
- Add import for `agenda_web_screen.dart`
- Remove `// TODO(W2+)` comment
- REQ satisfied: C-10 (PR1 shippable, closes placeholder)
- Parallel: NO (must follow PR1-1 test definition)

### TASK PR1-4 — [GREEN] Create `agenda_web_screen.dart` — `AgendaWebScreen` shell
- **File**: `lib/features/coach_hub/presentation/sections/agenda/agenda_web_screen.dart`
- `ConsumerStatefulWidget` — NO `Scaffold` (C-2)
- State fields: `_focusedDay`, `_selectedDay`, `_calendarFormat = CalendarFormat.week`, `_rangeFrom` (now − 1 month UTC), `_rangeTo` (now + 1 year UTC)
- Derive `trainerId` from `currentUidProvider` (read via `ref.watch`)
- Layout: `Center > ConstrainedBox(maxWidth: 800) > SingleChildScrollView > Column`
- Children: `_AgendaWebCalendar` + `_AgendaWebDayList` (stubs that return `const SizedBox()` initially)
- PR1 omits "Nueva Sesión" button and "Mis horarios" button (ADR-AGW-9 — no dead UI)
- All hardcoded strings carry `// i18n`
- REQ: REQ-AGW-101, C-2, C-3, C-5, C-6
- Parallel: NO (depends on PR1-3)

### TASK PR1-5 — [GREEN] Create `_AgendaWebCalendar` widget (inline in screen file or extracted)
- Port `_TrainerCalendar` from `trainer_agenda_tab.dart:191-341`
- `TableCalendar` (package `table_calendar ^3.2.0`): `calendarFormat = _calendarFormat`, `focusedDay`, `firstDay = _rangeFrom`, `lastDay = _rangeTo`
- Week/month toggle: `HeaderStyle` with custom `rightChevron` area; toggle button label `'Mes'` / `'Semana'` `// i18n`
- `eventLoader`: filter `trainerAppointmentsStreamProvider(TrainerAppointmentsKey{trainerId, rangeFrom, rangeTo})` — include only `status == confirmed && !isPast` (mirror mobile dot logic)
- `markerBuilder`: 6 px filled dot using `AppPalette.of(context).primary` (no hex — C-3)
- `onDaySelected`: update `_selectedDay` + `_focusedDay` in parent state via callback
- REQ: REQ-AGW-101 (SCENARIO-101-A, -B, -C)
- Parallel: NO (depends on PR1-4)

### TASK PR1-6 — [GREEN] Create `_AgendaWebDayList` widget
- Watches `trainerAppointmentsStreamProvider`; filters `status == confirmed` AND same y/m/d as `_selectedDay`; sorts by `startsAt`
- `.when`: loading → `CircularProgressIndicator`; error → retry button; empty → `'No hay sesiones este día.'` `// i18n`; data → `ListView` of `_AppointmentCard`
- REQ: REQ-AGW-102 (SCENARIO-102-A, -B)
- Parallel: NO (depends on PR1-4)

### TASK PR1-7 — [GREEN] Create `_AppointmentCard` widget
- Displays: `AgendaFormatters.formatTime(startsAt)` + athlete name (via `userPublicProfileProvider(athleteId)`; fallback `'Alumno (${athleteId.substring(0,6)})'` when `isRawUid`) + `'${durationMin} min'` `// i18n`
- `onTap` → opens `_AppointmentDetailDialog` via `showDialog`
- Uses `AppPalette.of(context)` for colors; `TreinoIcon` for any icons (C-3, C-4)
- REQ: REQ-AGW-102, SCENARIO-102-A
- Parallel: NO (depends on PR1-6)

### TASK PR1-8 — [GREEN] Create `_AppointmentDetailDialog` — `AlertDialog` detail view
- `showDialog<void>` / `ConsumerStatefulWidget` inside `AlertDialog` (ADR-AGW-3, C-7)
- Displays: time range (`AgendaFormatters.formatTime(startsAt)` → `formatTime(endsAt)`), `SERIE RECURRENTE` badge if recurring, athlete name — **NON-TAPPABLE** (ADR-AGW-8 — avoid `/alumnos/{id}` cross-branch dep)
- `ANTES DE LA SESIÓN` + `RECORDATORIO (POST)` `TextEditingController`s → `updateNotes`
- `CANCELAR RESERVA`: >24 h → call cancel repo; <24 h → inline note `// i18n`
- `CANCELAR TODA LA SERIE` → `cancelFutureSeries` → nested confirm `AlertDialog`
- Dismiss action closes dialog
- All strings hardcoded ES + `// i18n`; NO `AppL10n` import
- REQ: REQ-AGW-103 (SCENARIO-103-A, -B)
- Parallel: NO (depends on PR1-7)

### TASK PR1-9 — [REFACTOR] Make PR1 tests green + quality gate
- Run `flutter analyze` → fix all issues to 0
- Run `dart format .`
- Run `flutter test test/features/coach_hub/presentation/sections/agenda/agenda_web_screen_test.dart`
- Run `flutter test test/features/coach_hub/presentation/sections/agenda/agenda_web_calendar_smoke_test.dart`
- All assertions from PR1-1 and PR1-2 must pass
- Parallel: NO (final gate before PR1 merge)

---

## PR2 — Nueva Sesión (create appointment)
**Goal**: Add session-creation dialog with athlete picker and `createByTrainer` call.
**Satisfies**: REQ-AGW-201, REQ-AGW-202
**Estimated lines**: ~240 (screen edit ~15 + dialog ~225)
**Workload risk**: LOW
**Prerequisite**: PR1 merged

### TASK PR2-1 — [RED] Write failing widget tests for `_NewSessionDialog`
- **Test file**: `test/features/coach_hub/presentation/sections/agenda/new_session_dialog_test.dart`
- **Scenarios**: SCENARIO-201-A, -B, -C, SCENARIO-202-A, -B
- `_StubAppointmentRepository` capturing `createByTrainer` args
- Override `trainerLinksStreamProvider` with 2 active + 1 paused link
- Override `userPublicProfileProvider(id)` per active athlete
- Override `currentUidProvider` fixed UID
- Override `appointmentRepositoryProvider` with stub
- Assert dialog opens via "Nueva Sesión" button tap
- Assert empty athlete list → submit disabled + `'No tenés alumnos activos todavía.'` `// i18n`
- Assert dropdown lists only active links by display name (excludes paused)
- Assert submit blocked when athlete / date / time missing → inline validation errors shown
- Assert past datetime → submit blocked + error `'No podés registrar una sesión en el pasado.'` `// i18n`
- Assert invalid duration (< 5 or > 480) → submit blocked
- Assert happy path: stub `createByTrainer` called with exact `(trainerId, athleteId, athleteDisplayName, startsAt UTC, durationMin)` + dialog closes + success snackbar `'Sesión registrada.'` `// i18n`
- Assert repo failure → dialog stays open + error inline
- **Must fail** before implementation
- Parallel: NO

### TASK PR2-2 — [GREEN] Edit `agenda_web_screen.dart` — add "Nueva Sesión" header button
- Add `ElevatedButton.icon` with `TreinoIcon.add` (or equivalent) and label `'NUEVA SESIÓN'` `// i18n`
- `onPressed` → `_openNewSessionDialog(context, ref)` which calls `showDialog<bool>(...)`
- Refresh is automatic via Firestore stream — no manual invalidation needed
- REQ: REQ-AGW-201 (SCENARIO-201-A)
- Parallel: NO (depends on PR2-1 test definition)

### TASK PR2-3 — [GREEN] Create `new_session_dialog.dart` — `_NewSessionDialog`
- **File**: `lib/features/coach_hub/presentation/sections/agenda/new_session_dialog.dart`
- `ConsumerStatefulWidget` inside `showDialog<bool>`; returns `true` on success
- Layout: `SingleChildScrollView > ConstrainedBox(maxWidth: 420) > Column`
- Fields:
  - **Athlete picker**: `DropdownButtonFormField` sourced from `trainerLinksStreamProvider` filtered to `TrainerLinkStatus.active`; names via `userPublicProfileProvider(athleteId)` with `'Alumno (xxxxxx)'` fallback; empty active list → disabled submit + inline message
  - **Date**: `showDatePicker` (first = today, last = today + 365 d)
  - **Time**: `showTimePicker`
  - **Duration**: free-text `TextFormField` (5..480 min) + preset chips {30, 45, 60, 90, 120} (ADR-AGW-6)
  - **Note**: optional `TextFormField`
- `_submit` logic (mirrors `new_session_sheet.dart:347-426`):
  - Past guard
  - `_parsedDuration` validation
  - `trainerId` from `currentUidProvider`
  - `athleteDisplayName` via `userPublicProfileProvider.future` with id fallback
  - Call `appointmentRepositoryProvider.createByTrainer(trainerId, athleteId, athleteDisplayName, startsAt UTC, durationMin, noteBefore?)`
  - Success → `Navigator.of(context).pop(true)` + `ScaffoldMessenger` snackbar `'Sesión registrada.'` `// i18n`
  - Failure → keep dialog open + inline error `'No pudimos registrar...'` `// i18n`
- NO recurring creation (DEFERRED per spec out-of-scope)
- All strings hardcoded ES + `// i18n`; NO `AppL10n` import
- REQ: REQ-AGW-201, REQ-AGW-202 (all scenarios)
- Parallel: NO (depends on PR2-2)

### TASK PR2-4 — [REFACTOR] Make PR2 tests green + quality gate
- Run full gate: `flutter analyze` (0 issues) + `dart format .` + `flutter test` (all green including PR1 suite)
- Parallel: NO

---

## PR3a — Reglas de disponibilidad (recurring rules CRUD)
**Goal**: Rules list + add/update/delete editor in a dialog panel.
**Satisfies**: REQ-AGW-301
**Estimated lines**: ~310 (screen edit ~10 + editor shell ~80 + rule tile ~40 + rule form dialog ~180)
**Workload risk**: MEDIUM — monitor; if `_RuleFormDialog` alone exceeds 180 lines, extract into its own file before commit
**Prerequisite**: PR2 merged

### TASK PR3a-1 — [RED] Write failing widget tests for availability rules editor
- **Test file**: `test/features/coach_hub/presentation/sections/agenda/availability_editor_rules_test.dart`
- **Scenarios**: SCENARIO-301-A, -B, -C, -D
- `_StubAvailabilityRepository` (mirrors `availability_editor_screen_test.dart` stub pattern) capturing `addRule`, `updateRule`, `deleteRule` args
- Override `availabilityRulesStreamProvider(trainerId)` with `Stream.value([])` and with 1 existing rule
- Override `currentUidProvider` fixed UID
- Assert: "Mis horarios" button opens the editor dialog
- Assert: empty state shows prompt to add first rule (SCENARIO-301-A)
- Assert: rule tile shows `dayOfWeek` label + `HH:mm–HH:mm` + `N min`
- Assert: opening add form → filling day/window/slot → confirm → `addRule` called with correct fields + `trainerId` (SCENARIO-301-B)
- Assert: invalid window (endTotal < startTotal + slotDuration) → `addRule` NOT called + error shown
- Assert: edit existing → confirm → `updateRule(trainerId, updatedRule)` called (SCENARIO-301-C)
- Assert: delete → confirm dialog → `deleteRule(trainerId, ruleId)` called → rule removed (SCENARIO-301-D)
- Assert loading spinner shown (distinct from empty — do NOT collapse loading into empty per design)
- **Must fail** before implementation
- Parallel: NO

### TASK PR3a-2 — [GREEN] Edit `agenda_web_screen.dart` — add "Mis horarios" header button
- Add `OutlinedButton` with label `'Mis horarios'` `// i18n` → `showDialog` opening `AvailabilityEditorPanel`
- Pass `trainerId` (from `currentUidProvider`) into panel
- REQ: REQ-AGW-301
- Parallel: NO (depends on PR3a-1)

### TASK PR3a-3 — [GREEN] Create `availability_editor_panel.dart` — editor shell + rules section
- **File**: `lib/features/coach_hub/presentation/sections/agenda/availability_editor_panel.dart`
- Dialog layout: `Dialog > ConstrainedBox(maxWidth: 560) > SingleChildScrollView > Column`
- Section header `'MIS HORARIOS DE TRABAJO'` `// i18n`
- Rules list: watches `availabilityRulesStreamProvider(trainerId)`; `.when` loading/error/empty/data
  - **Loading**: `CircularProgressIndicator` — do NOT treat as empty
  - **Empty**: `'Todavía no tenés horarios configurados.'` `// i18n` + add button
  - **Data**: `ListView` of `_RuleTile`
- `_RuleTile`: displays day label (`AgendaFormatters.dayOfWeekLabels[dayOfWeek]`), `HH:mm–HH:mm`, `N min`; edit icon → opens `_RuleFormDialog`; delete icon → confirm `AlertDialog` → `availabilityRepositoryProvider.deleteRule(trainerId, ruleId)`
- FAB / add button → opens `_RuleFormDialog(mode: add)`
- REQ: REQ-AGW-301 (SCENARIO-301-A, -D)
- Parallel: NO (depends on PR3a-2)

### TASK PR3a-4 — [GREEN] Create `_RuleFormDialog` (within panel file or extracted)
- Port `_RuleFormSheet` from `availability_editor_screen.dart:382-603`
- Fields: `_dayOfWeek` (1–7; `_DayPicker`), `_startHour`/`_startMin`, `_endHour`/`_endMin`, `_slotDurationMin`
- Defaults: Monday, 09:00–11:00, 60 min
- Duration options (chips): {30, 60, 90, 120}
- Validation: `endTotal >= startTotal + slotDurationMin`; else inline error `'La ventana debe ser mayor al slot.'` `// i18n`
- Add mode: calls `availabilityRepositoryProvider.addRule(trainerId, AvailabilityRule(id: _generateId(20chars), trainerId, ...))`
- Edit mode: calls `availabilityRepositoryProvider.updateRule(trainerId, existing.copyWith(...))`
- Web idiom: `AlertDialog` (NOT `showModalBottomSheet`)
- REQ: REQ-AGW-301 (SCENARIO-301-B, -C)
- **If this file alone exceeds 180 lines, extract into `rule_form_dialog.dart`**
- Parallel: NO (depends on PR3a-3)

### TASK PR3a-5 — [REFACTOR] Make PR3a tests green + quality gate
- Full gate: `flutter analyze` (0) + `dart format .` + `flutter test` (all green)
- Parallel: NO

---

## PR3b — Excepciones de disponibilidad (overrides add/delete)
**Goal**: Override list with block (day-off) and extra window add/delete.
**Satisfies**: REQ-AGW-302
**Estimated lines**: ~210 (panel edit ~30 + override tile ~40 + block form dialog ~80 + extra form dialog ~60)
**Workload risk**: LOW
**Prerequisite**: PR3a merged

### TASK PR3b-1 — [RED] Write failing widget tests for availability overrides
- **Test file**: `test/features/coach_hub/presentation/sections/agenda/availability_editor_overrides_test.dart`
- **Scenarios**: SCENARIO-302-A, -B, -C
- Override `overridesStreamProvider(OverridesKey{trainerId})` with `Stream.value([])` and with 1 block + 1 extra override
- Override `availabilityRepositoryProvider` stub capturing `addOverride`, `deleteOverride`
- Assert: `'EXCEPCIONES'` section header visible in editor dialog
- Assert: empty state shown when no overrides (distinct message from rules empty state)
- Assert: list renders both `block` and `extra` override tiles (both `when` branches covered)
- Assert: "Bloquear día" flow — date picker → confirm → `addOverride(trainerId, override{type: block, date})` called (SCENARIO-302-A)
- Assert: "Ventana extra" flow — date + start + end time → confirm → `addOverride(trainerId, override{type: extra, ...})` called (SCENARIO-302-B)
- Assert: delete → confirm → `deleteOverride(trainerId, overrideId)` called → override removed (SCENARIO-302-C)
- **Must fail** before implementation
- Parallel: NO

### TASK PR3b-2 — [GREEN] Add overrides section to `availability_editor_panel.dart`
- New section header `'EXCEPCIONES'` `// i18n` below rules section
- Watches `overridesStreamProvider(OverridesKey{trainerId})`; `.when` loading/error/empty/data
- **Empty**: `'Sin excepciones configuradas.'` `// i18n`
- **Data**: `ListView` of `_OverrideTile` — handles both `block` and `extra` sealed types
  - `block` tile: date label + `'Día bloqueado'` `// i18n` + delete icon
  - `extra` tile: date + time range + `'Ventana extra'` `// i18n` + delete icon
- Delete icon → confirm `AlertDialog` → `availabilityRepositoryProvider.deleteOverride(trainerId, overrideId)`
- Add buttons: `'+ Bloquear día'` `// i18n` → `_BlockOverrideFormDialog`; `'+ Ventana extra'` `// i18n` → `_ExtraOverrideFormDialog`
- REQ: REQ-AGW-302 (SCENARIO-302-C)
- Parallel: NO (depends on PR3b-1)

### TASK PR3b-3 — [GREEN] Create `_BlockOverrideFormDialog`
- `AlertDialog` with `showDatePicker` (first = today, last = today + 365 d)
- Confirm → `availabilityRepositoryProvider.addOverride(trainerId, AvailabilityOverride.block(id: _generateId(20chars), trainerId, date))`
- REQ: REQ-AGW-302 (SCENARIO-302-A)
- Parallel: YES with PR3b-4 (independent forms)

### TASK PR3b-4 — [GREEN] Create `_ExtraOverrideFormDialog`
- `AlertDialog` with date picker + `showTimePicker` for start + `showTimePicker` for end
- Validate end > start; inline error if not
- Confirm → `availabilityRepositoryProvider.addOverride(trainerId, AvailabilityOverride.extra(id: _generateId(20chars), trainerId, date, startHour, startMin, endHour, endMin))`
- REQ: REQ-AGW-302 (SCENARIO-302-B)
- Parallel: YES with PR3b-3

### TASK PR3b-5 — [REFACTOR] Make PR3b tests green + final quality gate
- Full gate: `flutter analyze` (0) + `dart format .` + `flutter test` (ALL suites green: agenda_web_screen_test, agenda_web_calendar_smoke_test, new_session_dialog_test, availability_editor_rules_test, availability_editor_overrides_test)
- Parallel: NO

---

## New Files Summary (all under `lib/features/coach_hub/presentation/sections/agenda/`)

| File | Created in | Purpose |
|------|-----------|---------|
| `agenda_web_screen.dart` | PR1 | `AgendaWebScreen` shell + `_AgendaWebCalendar` + `_AgendaWebDayList` + `_AppointmentCard` + `_AppointmentDetailDialog` |
| `new_session_dialog.dart` | PR2 | `_NewSessionDialog` |
| `availability_editor_panel.dart` | PR3a + PR3b | `AvailabilityEditorPanel` shell + `_RuleTile` + `_RuleFormDialog` + `_OverrideTile` + `_BlockOverrideFormDialog` + `_ExtraOverrideFormDialog` |

## Edited Files

| File | PR | Change |
|------|-----|--------|
| `lib/features/coach_hub/presentation/sections/agenda/routes.dart` | PR1 | Swap `ProximamenteScreen` → `AgendaWebScreen` |
| `lib/features/coach_hub/presentation/sections/agenda/agenda_web_screen.dart` | PR2 | Add "Nueva Sesión" button |
| `lib/features/coach_hub/presentation/sections/agenda/agenda_web_screen.dart` | PR3a | Add "Mis horarios" button |

## Test Files Summary

| Test file | PR | Scenarios covered |
|-----------|-----|------------------|
| `test/.../agenda_web_screen_test.dart` | PR1 | 101-A/B/C, 102-A/B, 103-A/B |
| `test/.../agenda_web_calendar_smoke_test.dart` | PR1 | 101-A/B (web gesture smoke) |
| `test/.../new_session_dialog_test.dart` | PR2 | 201-A/B/C, 202-A/B |
| `test/.../availability_editor_rules_test.dart` | PR3a | 301-A/B/C/D |
| `test/.../availability_editor_overrides_test.dart` | PR3b | 302-A/B/C |

---

## Review Workload Forecast

| PR | Est. lines | Budget risk | Chained PRs recommended |
|----|-----------|-------------|------------------------|
| PR1 | ~320 | LOW | — |
| PR2 | ~240 | LOW | — |
| PR3a | ~310 | MEDIUM (watch `_RuleFormDialog`; extract if > 180 ln) | — |
| PR3b | ~210 | LOW | — |

Chained PRs: Yes (PR1 → PR2 → PR3a → PR3b)
400-line budget risk: Low for all PRs (PR3a borderline; mitigation: extract rule form dialog)
Decision needed before apply: No
