# Spec: coach-hub-web-foundation

**Change**: coach-hub-web-foundation
**Owner**: Track A (Shell & navigation)
**Date**: 2026-06-11
**Phase**: Fase W1 — Web foundation + detailed sidebar shell
**Artifact store**: openspec (file + Engram `sdd/coach-hub-web-foundation/spec`)
**Proposal ref**: `openspec/changes/coach-hub-web-foundation/proposal.md`
**Scenario range**: SCENARIO-748..SCENARIO-771

---

## Overview

This change introduces the web navigation shell for Coach Hub: a `ShellRoute`-backed `CoachHubScaffold` (sidebar + top bar + content area), a data-driven 19-item sidebar grouped into 6 sections, a persisted collapse state, responsive guards, and the migration of `CoachHubDashboardScreen` inside the shell with its `Scaffold` stripped. It also adds the `borderHover` palette token and ~12 `TreinoIcon` aliases required by the sidebar. After W1, every future web section plugs in via its own `sections/<section>/routes.dart` without touching `coach_hub_router.dart`.

---

## Requirements

---

### REQ-CHW-SHELL-001 — CoachHubScaffold Layout

`CoachHubScaffold` MUST render a three-region layout: sidebar (left), top bar (top-right), content area (remaining space). The content area MUST wrap its `child` in `ContentMaxWidth(1240)`. The outer container MUST use `AppPalette.of(context).bg` as background color.

**Related SCENARIOs**: SCENARIO-748, SCENARIO-749

---

### REQ-CHW-SHELL-002 — Dark Mode Only

`CoachHubScaffold` and all shell widgets MUST render exclusively in dark mode. No light-theme code branch MUST be introduced. All colors MUST use `AppPalette.of(context)` tokens. No hex literals are permitted.

**Related SCENARIOs**: SCENARIO-749

---

### REQ-CHW-SIDEBAR-001 — 19-Item Grouped Sidebar

`sidebar_registry.dart` MUST define exactly 19 `SidebarItem` entries organized into 6 labeled groups plus a bottom section:

| Group | Items |
|---|---|
| RESUMEN | Dashboard, Actividad, Agenda |
| ALUMNOS | Alumnos, Invitaciones, Cuestionario |
| PLAN | Rutinas, Planner semanal, Biblioteca, Templates |
| WELLNESS | Nutrición, Recetas, Suplementos, Hábitos |
| NEGOCIO | Pagos, Planes comerciales, Reportes |
| COMUNICACIÓN | Chat |
| Bottom | Ajustes |

Group labels and item names MUST be in es-AR Rioplatense. All sidebar strings MUST be tagged `// i18n: Fase W1`.

**Related SCENARIOs**: SCENARIO-750, SCENARIO-751

---

### REQ-CHW-SIDEBAR-002 — Navigation Behavior

The Dashboard sidebar item MUST navigate to its real screen. All other 18 items MUST navigate to the shared `ProximamenteScreen`, which renders the section label as a header plus the text `"Próximamente."` and carries a `// TODO(W2+): wire real screen` marker. (`/upload-plan` stays reachable as a legacy route inside the shell but is NOT a sidebar item.)

**Related SCENARIOs**: SCENARIO-752, SCENARIO-753

---

### REQ-CHW-SIDEBAR-003 — Collapse / Expand

The sidebar MUST support two visual states: expanded (264 px) showing icons, group headers, and item labels; collapsed (72 px) showing icons only (group headers hidden). State toggle MUST be triggered by the top bar's sidebar toggle button. The collapsed-state width MUST be exactly 72 px and the expanded-state width MUST be exactly 264 px.

**Related SCENARIOs**: SCENARIO-754, SCENARIO-755

---

### REQ-CHW-SIDEBAR-004 — Collapse State Persisted

The sidebar collapsed/expanded state MUST be persisted to `localStorage` via `SharedPreferences` key `coach_hub.sidebar.collapsed`. On browser reload, the sidebar MUST restore the previously saved state. Default state (first visit, no key present) MUST be expanded.

**Related SCENARIOs**: SCENARIO-755, SCENARIO-756

---

### REQ-CHW-ROUTER-001 — ShellRoute Wraps Signed-in Routes

`coach_hub_router.dart` MUST wrap all signed-in routes inside a single `ShellRoute` whose `pageBuilder` renders `CoachHubScaffold`. The `ShellRoute.routes` list MUST be assembled by aggregating each section's `sections/<section>/routes.dart` exports.

**Related SCENARIOs**: SCENARIO-748, SCENARIO-757

---

### REQ-CHW-ROUTER-002 — Public Routes Outside Shell (Load-Bearing Invariant)

`/login` and `/not-allowed` MUST be declared as top-level `GoRoute`s, siblings of the `ShellRoute`, and MUST NOT appear as children inside `ShellRoute.routes`. A widget-pumped test MUST assert that pumping `/login` and `/not-allowed` does NOT find a `CoachHubScaffold` key in the widget tree.

**Related SCENARIOs**: SCENARIO-758, SCENARIO-759

---

### REQ-CHW-ROUTER-003 — Per-Section routes.dart Convention

Each section MUST own a `sections/<section>/routes.dart` file exporting its route list. Adding or modifying a section's routes MUST require no changes to `coach_hub_router.dart` beyond the one-time inclusion of the section's export in the aggregator list.

**Related SCENARIOs**: SCENARIO-757

---

### REQ-CHW-TOPBAR-001 — Top Bar Contents

The top bar MUST contain, left to right: sidebar toggle `IconButton`, breadcrumb widget (center), notifications bell `IconButton` (static, no badge), user menu widget (right). The top bar background MUST use `AppPalette.of(context).bg`.

**Related SCENARIOs**: SCENARIO-760

---

### REQ-CHW-TOPBAR-002 — Breadcrumb Derivation

The breadcrumb MUST read the current `GoRouterState.uri` and render the trail by matching path segments against `sidebarRegistry` item routes. The active item's label MUST appear as the last breadcrumb segment.

**Related SCENARIOs**: SCENARIO-761

---

### REQ-CHW-RESPONSIVE-001 — Compact Breakpoint Force-Collapse

At viewport widths between 768 px (inclusive) and 1280 px (exclusive), `CoachHubScaffold` MUST force the sidebar into the collapsed (72 px) state and MUST disable manual expand. At or above 1280 px the sidebar MAY be expanded or collapsed per user preference. (Below 768 px the `MobileBanner` replaces the shell entirely — see REQ-CHW-RESPONSIVE-002.)

**Related SCENARIOs**: SCENARIO-762

---

### REQ-CHW-RESPONSIVE-002 — Mobile Banner

At viewport widths below 768 px, `CoachHubScaffold` MUST replace the entire layout with a full-screen banner reading `"Coach Hub no está optimizado para móvil — usá la app"`. The sidebar and top bar MUST NOT render at this width.

**Related SCENARIOs**: SCENARIO-763

---

### REQ-CHW-DASHBOARD-001 — Dashboard Inside Shell, Single Scaffold

After W1.4, `CoachHubDashboardScreen` MUST be located at `lib/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_screen.dart`. It MUST NOT contain its own `Scaffold`. A widget test MUST assert exactly one `Scaffold` ancestor exists when the dashboard is pumped inside the shell.

**Related SCENARIOs**: SCENARIO-764, SCENARIO-765

---

### REQ-CHW-DASHBOARD-002 — Dashboard Content Unchanged

The dashboard content (pending requests list, filter chips, active alumnos list, paused/terminated sections, upload-plan CTA) MUST be functionally identical after the move. The brand header row (previously lines 119–165) MUST be removed. The `ConstrainedBox(maxWidth: 800)` MAY remain unchanged for W1.

**Related SCENARIOs**: SCENARIO-765

---

### REQ-CHW-UPLOADPLAN-001 — /upload-plan Route Preserved

`/upload-plan` and `/upload-plan/preview` routes MUST remain functional inside the shell after W1.2. Navigating to `/upload-plan` MUST render `CoachHubUploadPlanScreen` inside the shell (sidebar and top bar visible).

**Related SCENARIOs**: SCENARIO-766

---

### REQ-CHW-PALETTE-001 — borderHover Token Added

`AppPalette` (all palette implementations) MUST include a `borderHover` color field. Its default value in `MintMagenta` MUST be `border` at a higher alpha. This addition MUST be purely additive — `copyWith` exhaustivity tests MUST remain green.

**Related SCENARIOs**: SCENARIO-767

---

### REQ-CHW-ICONS-001 — TreinoIcon Aliases for Sidebar

`TreinoIcon` MUST expose at least 12 new `const IconData` aliases covering the sidebar items that lack icons today (including but not limited to: Solicitudes, Invitaciones, Cuestionario, Rutinas, Templates, Planner semanal, Biblioteca, Nutrición, Recetas, Suplementos, Hábitos, Planes comerciales, Reportes, Ajustes). Each alias MUST map to a specific Phosphor variant. No sidebar widget MUST reference `PhosphorIcons.X` directly.

**Related SCENARIOs**: SCENARIO-768

---

### REQ-CHW-QA-001 — Existing Tests Stay Green

All 234+ existing tests MUST remain green after each etapa merges. No existing test file MUST be deleted or made to fail by W1 changes.

**Related SCENARIOs**: SCENARIO-769

---

### REQ-CHW-QA-002 — New Tests Required

W1 MUST add: (a) redirect scenarios for at least 4 new shell-wrapped routes in `coach_hub_router_redirect_test.dart`, (b) shell invariant test in `coach_hub_router_shell_test.dart` asserting public routes are outside the shell, (c) widget test for `CoachHubScaffold`, (d) unit test for `sidebarCollapsedProvider` persistence.

**Related SCENARIOs**: SCENARIO-758, SCENARIO-759, SCENARIO-769, SCENARIO-770

---

### REQ-CHW-QA-003 — Build and Serve

`flutter build web -t lib/main_coach_hub.dart` MUST complete with 0 errors. `flutter analyze` MUST report 0 issues. `dart format .` MUST produce no diffs. The `coach-hub-dev` Firebase Hosting target MUST serve the shell successfully (manual smoke test per quality gate).

**Related SCENARIOs**: SCENARIO-771

---

## Scenarios

---

### SCENARIO-748: Shell renders sidebar + top bar + content area
- **Given** a trainer is authenticated and navigates to `/dashboard`
- **When** the route is resolved and the widget tree is pumped at 1440×900
- **Then** a `CoachHubScaffold` is present in the tree
- **And** a sidebar widget, top bar widget, and content area are all found as descendants
- **Test target**: `test/features/coach_hub/presentation/shell/coach_hub_scaffold_test.dart`
- **REQ**: REQ-CHW-SHELL-001, REQ-CHW-ROUTER-001

---

### SCENARIO-749: Shell uses dark palette tokens only
- **Given** `CoachHubScaffold` is pumped with a `ProviderScope`
- **When** the background color is read from the scaffold's decoration
- **Then** the color equals `AppPalette.of(context).bg` (no hardcoded hex)
- **And** no `ThemeData.light()` branch exists in any shell widget
- **Test target**: `test/features/coach_hub/presentation/shell/coach_hub_scaffold_test.dart`
- **REQ**: REQ-CHW-SHELL-001, REQ-CHW-SHELL-002

---

### SCENARIO-750: Sidebar shows all 19 items in 6 labeled groups
- **Given** `CoachHubScaffold` is pumped in expanded state
- **When** the sidebar is rendered
- **Then** exactly 6 group header labels are found (RESUMEN, ALUMNOS, PLAN, WELLNESS, NEGOCIO, COMUNICACIÓN)
- **And** exactly 19 item labels are found matching the locked list
- **And** Ajustes appears in the bottom section
- **Test target**: `test/features/coach_hub/presentation/shell/coach_hub_sidebar_test.dart`
- **REQ**: REQ-CHW-SIDEBAR-001

---

### SCENARIO-751: Sidebar item labels are in es-AR
- **Given** `sidebarRegistry` is read at runtime
- **When** all item labels and group names are collected
- **Then** no item or group uses English labels (e.g., "Settings" instead of "Ajustes")
- **Test target**: `test/features/coach_hub/presentation/shell/sidebar_registry_test.dart`
- **REQ**: REQ-CHW-SIDEBAR-001

---

### SCENARIO-752: Dashboard sidebar item navigates to real screen
- **Given** `CoachHubScaffold` is pumped with a real router
- **When** the user taps the "Dashboard" sidebar item
- **Then** the content area renders `CoachHubDashboardScreen` (not a placeholder)
- **Test target**: `test/features/coach_hub/presentation/shell/coach_hub_sidebar_test.dart`
- **REQ**: REQ-CHW-SIDEBAR-002

---

### SCENARIO-753: Unimplemented sidebar item shows Próximamente placeholder
- **Given** `CoachHubScaffold` is pumped with a real router
- **When** the user taps "Nutrición" (not yet shipped)
- **Then** the content area renders a widget containing the text `"Próximamente — Nutrición"`
- **And** no navigation error or exception is thrown
- **Test target**: `test/features/coach_hub/presentation/shell/coach_hub_sidebar_test.dart`
- **REQ**: REQ-CHW-SIDEBAR-002

---

### SCENARIO-754: Sidebar collapse changes width
- **Given** `CoachHubScaffold` is pumped in expanded state (264 px)
- **When** the sidebar toggle button is tapped
- **Then** the sidebar animates to 72 px
- **And** group header labels are no longer visible
- **And** item icons remain visible
- **Test target**: `test/features/coach_hub/presentation/shell/coach_hub_sidebar_test.dart`
- **REQ**: REQ-CHW-SIDEBAR-003

---

### SCENARIO-755: Sidebar collapse state persists across reload
- **Given** the user has collapsed the sidebar (state `true` written to `coach_hub.sidebar.collapsed`)
- **When** the page is reloaded (new `ProviderContainer` initialized with real `SharedPreferences`)
- **Then** `sidebarCollapsedProvider` returns `true`
- **And** the sidebar renders at 72 px without user interaction
- **Test target**: `test/features/coach_hub/application/sidebar_collapsed_provider_test.dart`
- **REQ**: REQ-CHW-SIDEBAR-003, REQ-CHW-SIDEBAR-004

---

### SCENARIO-756: Default sidebar state is expanded (first visit)
- **Given** `SharedPreferences` contains no `coach_hub.sidebar.collapsed` key
- **When** `sidebarCollapsedProvider` is read
- **Then** it returns `false` (expanded)
- **Test target**: `test/features/coach_hub/application/sidebar_collapsed_provider_test.dart`
- **REQ**: REQ-CHW-SIDEBAR-004

---

### SCENARIO-757: Adding a section routes.dart registers route without touching router
- **Given** `coach_hub_router.dart` aggregates `webRoutes` from section `routes.dart` files
- **When** a new `sections/alumnos/routes.dart` exporting `/alumnos` is added to the aggregator list
- **Then** navigating to `/alumnos` resolves to the route defined in that file
- **And** `coach_hub_router.dart` requires only a one-line addition to the aggregator list
- **Test target**: structural / code-review enforced via `test/app/coach_hub_router_redirect_test.dart` new scenarios
- **REQ**: REQ-CHW-ROUTER-001, REQ-CHW-ROUTER-003

---

### SCENARIO-758: /login does not render shell scaffold
- **Given** an unauthenticated user navigates to `/login`
- **When** the widget tree is pumped
- **Then** no `CoachHubScaffold` key is found in the widget tree
- **And** no sidebar widget is found
- **Test target**: `test/app/coach_hub_router_shell_test.dart`
- **REQ**: REQ-CHW-ROUTER-002

---

### SCENARIO-759: /not-allowed does not render shell scaffold
- **Given** an athlete user lands on `/not-allowed`
- **When** the widget tree is pumped
- **Then** no `CoachHubScaffold` key is found in the widget tree
- **Test target**: `test/app/coach_hub_router_shell_test.dart`
- **REQ**: REQ-CHW-ROUTER-002

---

### SCENARIO-760: Top bar contains required elements
- **Given** `CoachHubScaffold` is pumped at 1440×900
- **When** the top bar region is inspected
- **Then** a sidebar toggle `IconButton` is found on the left
- **And** a breadcrumb widget is found in the center
- **And** a notifications bell `IconButton` is found on the right (no badge)
- **And** a user menu widget is found on the right
- **Test target**: `test/features/coach_hub/presentation/shell/coach_hub_top_bar_test.dart`
- **REQ**: REQ-CHW-TOPBAR-001

---

### SCENARIO-761: Breadcrumb reflects current route label
- **Given** the shell is rendered with router location `/dashboard`
- **When** the breadcrumb widget is inspected
- **Then** it displays "Dashboard" as the final segment
- **Test target**: `test/features/coach_hub/presentation/shell/coach_hub_breadcrumb_test.dart`
- **REQ**: REQ-CHW-TOPBAR-002

---

### SCENARIO-762: Viewport 768–1279 px forces sidebar collapsed
- **Given** `CoachHubScaffold` is pumped at viewport width 1100 px
- **When** the layout is resolved
- **Then** the sidebar is in collapsed state (72 px)
- **And** the sidebar toggle button does not expand the sidebar
- **Test target**: `test/features/coach_hub/presentation/shell/coach_hub_scaffold_test.dart`
- **REQ**: REQ-CHW-RESPONSIVE-001

---

### SCENARIO-763: Viewport below 768 px shows mobile banner
- **Given** `CoachHubScaffold` is pumped at viewport width 600 px
- **When** the layout is resolved
- **Then** a widget containing `"Coach Hub no está optimizado para móvil — usá la app"` is found
- **And** no sidebar widget is found
- **And** no top bar widget is found
- **Test target**: `test/features/coach_hub/presentation/shell/coach_hub_scaffold_test.dart`
- **REQ**: REQ-CHW-RESPONSIVE-002

---

### SCENARIO-764: Dashboard screen has exactly one Scaffold ancestor
- **Given** the shell is rendered and the user is on `/dashboard`
- **When** the widget tree is pumped
- **Then** exactly one `Scaffold` widget is found in the subtree rooted at `CoachHubScaffold`
- **And** no nested `Scaffold` exists inside `CoachHubDashboardScreen`
- **Test target**: `test/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_in_shell_test.dart`
- **REQ**: REQ-CHW-DASHBOARD-001

---

### SCENARIO-765: Dashboard content unchanged after move
- **Given** the shell is rendered with a mocked `trainerLinksStreamProvider`
- **When** the user is on `/dashboard`
- **Then** the content area contains pending requests list, filter chips, active alumnos list, and upload-plan CTA
- **And** no brand header row is present
- **Test target**: `test/features/coach_hub/presentation/sections/dashboard/coach_hub_dashboard_in_shell_test.dart`
- **REQ**: REQ-CHW-DASHBOARD-001, REQ-CHW-DASHBOARD-002

---

### SCENARIO-766: /upload-plan renders inside shell
- **Given** an authenticated trainer navigates to `/upload-plan`
- **When** the widget tree is pumped
- **Then** `CoachHubScaffold` is present in the tree
- **And** `CoachHubUploadPlanScreen` is found as a descendant of the content area
- **Test target**: `test/app/coach_hub_router_redirect_test.dart` (structural)
- **REQ**: REQ-CHW-UPLOADPLAN-001

---

### SCENARIO-767: borderHover token resolves on hover
- **Given** `AppPalette.of(context)` is called in a test environment
- **When** `palette.borderHover` is accessed
- **Then** it returns a non-null `Color` value
- **And** the `MintMagenta` `copyWith` call with no arguments compiles without exhaustivity errors
- **Test target**: `test/app/theme/app_palette_test.dart`
- **REQ**: REQ-CHW-PALETTE-001

---

### SCENARIO-768: TreinoIcon alias resolves to its Phosphor variant
- **Given** `TreinoIcon.ajustes` (or any newly added alias) is referenced in widget code
- **When** the widget is compiled and rendered
- **Then** the alias resolves to its mapped `PhosphorIconData` without a build error
- **And** no direct `PhosphorIcons.X` reference exists in any shell or sidebar widget file
- **Test target**: `flutter analyze` + code-review enforced
- **REQ**: REQ-CHW-ICONS-001

---

### SCENARIO-769: All 234+ existing tests remain green
- **Given** W1 changes are fully applied (all 4 etapas merged)
- **When** the full test suite is run
- **Then** all previously passing tests still pass (≥234 tests green)
- **And** no test file is deleted
- **Test target**: CI full suite
- **REQ**: REQ-CHW-QA-001

---

### SCENARIO-770: New shell invariant test exists and passes
- **Given** `test/app/coach_hub_router_shell_test.dart` is present
- **When** the test suite runs
- **Then** all scenarios in that file pass
- **And** the file covers at minimum: `/login` outside shell, `/not-allowed` outside shell
- **Test target**: `test/app/coach_hub_router_shell_test.dart`
- **REQ**: REQ-CHW-QA-002

---

### SCENARIO-771: coach-hub-dev builds and serves shell
- **Given** `flutter build web -t lib/main_coach_hub.dart` completes
- **When** the `coach-hub-dev` Hosting target is served
- **Then** the shell renders at `https://coach-hub-dev.web.app/dashboard` (or emulator equivalent)
- **And** the sidebar, top bar, and dashboard content area are all visible
- **And** `flutter analyze` reports 0 issues
- **Test target**: manual smoke test (quality gate)
- **REQ**: REQ-CHW-QA-003

---

## Coverage Matrix — Coach Hub Web Foundation (Fase W1)

| REQ | Category | SCENARIOs |
|-----|----------|-----------|
| REQ-CHW-SHELL-001 | Scaffold layout | SCENARIO-748, SCENARIO-749 |
| REQ-CHW-SHELL-002 | Dark mode only | SCENARIO-749 |
| REQ-CHW-SIDEBAR-001 | 19-item grouped sidebar | SCENARIO-750, SCENARIO-751 |
| REQ-CHW-SIDEBAR-002 | Navigation behavior | SCENARIO-752, SCENARIO-753 |
| REQ-CHW-SIDEBAR-003 | Collapse/expand | SCENARIO-754, SCENARIO-755 |
| REQ-CHW-SIDEBAR-004 | Persist collapse state | SCENARIO-755, SCENARIO-756 |
| REQ-CHW-ROUTER-001 | ShellRoute wraps signed-in | SCENARIO-748, SCENARIO-757 |
| REQ-CHW-ROUTER-002 | Public routes outside shell | SCENARIO-758, SCENARIO-759 |
| REQ-CHW-ROUTER-003 | Per-section routes.dart | SCENARIO-757 |
| REQ-CHW-TOPBAR-001 | Top bar contents | SCENARIO-760 |
| REQ-CHW-TOPBAR-002 | Breadcrumb derivation | SCENARIO-761 |
| REQ-CHW-RESPONSIVE-001 | Compact force-collapse | SCENARIO-762 |
| REQ-CHW-RESPONSIVE-002 | Mobile banner | SCENARIO-763 |
| REQ-CHW-DASHBOARD-001 | Single Scaffold after move | SCENARIO-764, SCENARIO-765 |
| REQ-CHW-DASHBOARD-002 | Dashboard content unchanged | SCENARIO-765 |
| REQ-CHW-UPLOADPLAN-001 | /upload-plan preserved | SCENARIO-766 |
| REQ-CHW-PALETTE-001 | borderHover token | SCENARIO-767 |
| REQ-CHW-ICONS-001 | TreinoIcon aliases | SCENARIO-768 |
| REQ-CHW-QA-001 | Existing tests green | SCENARIO-769 |
| REQ-CHW-QA-002 | New tests required | SCENARIO-758, SCENARIO-759, SCENARIO-769, SCENARIO-770 |
| REQ-CHW-QA-003 | Build and serve | SCENARIO-771 |

---

## Coverage Matrix — Coach Hub Agenda Web (PR #213, #217, #220, #221)

| REQ | Category | SCENARIOs | Status |
|-----|----------|-----------|--------|
| REQ-AGW-101 | Calendar week/month toggle | SCENARIO-AGW-101-A, SCENARIO-AGW-101-B, SCENARIO-AGW-101-C | Shipped in PR #213 |
| REQ-AGW-102 | Day list shows appointments | SCENARIO-AGW-102-A, SCENARIO-AGW-102-B | Shipped in PR #213 |
| REQ-AGW-103 | Appointment detail dialog | SCENARIO-AGW-103-A, SCENARIO-AGW-103-B | Shipped in PR #213 |
| REQ-AGW-201 | Nueva Sesión dialog | SCENARIO-AGW-201-A, SCENARIO-AGW-201-B, SCENARIO-AGW-201-C | Shipped in PR #217 |
| REQ-AGW-202 | Session creation via repository | SCENARIO-AGW-202-A, SCENARIO-AGW-202-B | Shipped in PR #217 |
| REQ-AGW-301 | Recurring rules CRUD | SCENARIO-AGW-301-A, SCENARIO-AGW-301-B, SCENARIO-AGW-301-C, SCENARIO-AGW-301-D | Shipped in PR #220 |
| REQ-AGW-302 | Override editor (block/extra) | SCENARIO-AGW-302-A, SCENARIO-AGW-302-B, SCENARIO-AGW-302-C | Shipped in PR #221 |

---

## Change: coach-hub-agenda-web (Agenda Web Implementation)

**Merged from**: `openspec/changes/coach-hub-agenda-web/spec.md`
**Date merged**: 2026-07-01
**Status**: Fully implemented (PR #213, #217, #220, #221)

This change introduces full-parity web agenda for the Coach Hub, replacing the ProximamenteScreen placeholder. Delivered as four chained PRs: PR1 (Ver turnos) → PR2 (Nueva Sesión) → PR3a (Reglas) → PR3b (Excepciones). All new files live under `coach_hub/presentation/sections/agenda/`. No backend, domain, or mobile changes.

---

### REQ-AGW-101 — Calendar renders with week default and month toggle

The system MUST display a `table_calendar` widget defaulting to week view.
The system MUST provide a toggle to switch to month view.
The system MUST render booking dots on days that have at least one appointment.
`// i18n` comments MUST accompany every hardcoded Spanish string.

**Related SCENARIOs**: SCENARIO-AGW-101-A, SCENARIO-AGW-101-B, SCENARIO-AGW-101-C

---

### REQ-AGW-102 — Day selection shows appointment list

The system MUST show the appointments for the selected day as a vertical card list (`_AgendaWebDayList`).
Each card MUST display: start time, athlete name, and duration.
The system MUST show an empty-state widget when the selected day has no appointments.

**Related SCENARIOs**: SCENARIO-AGW-102-A, SCENARIO-AGW-102-B

---

### REQ-AGW-103 — Appointment detail dialog

The system MUST open an `AlertDialog` with appointment details when a card is tapped.
The dialog MUST NOT use `showModalBottomSheet`.

**Related SCENARIOs**: SCENARIO-AGW-103-A, SCENARIO-AGW-103-B

---

### REQ-AGW-201 — Nueva Sesión dialog

The system MUST show a "Nueva Sesión" button on `AgendaWebScreen`.
Tapping it MUST open `_NewSessionDialog` via `showDialog<bool>`.
The dialog MUST contain: athlete picker, date field, time field, duration selector.
Duration options MUST be drawn from the allowed set: {30, 60, 90, 120} minutes.

**Related SCENARIOs**: SCENARIO-AGW-201-A, SCENARIO-AGW-201-B, SCENARIO-AGW-201-C

---

### REQ-AGW-202 — Session creation calls repository and updates calendar

The system MUST call `appointmentRepository.createByTrainer` on valid submission.
On success the dialog MUST close and the new appointment MUST appear in the calendar/day list.
Recurring session creation is DEFERRED (out of scope for PR2).

**Related SCENARIOs**: SCENARIO-AGW-202-A, SCENARIO-AGW-202-B

---

### REQ-AGW-301 — Recurring rule list and CRUD

The system MUST display a list of the trainer's recurring availability rules.
Each rule MUST show: day of week, start time, end time, slot duration.
The system MUST allow adding, updating, and deleting rules inline (no route push).
`slotDurationMin` MUST be one of {30, 60, 90, 120}.
`dayOfWeek` MUST follow ISO 8601 (1 = Monday … 7 = Sunday).
The system MUST show an empty-state widget when no rules exist.

**Related SCENARIOs**: SCENARIO-AGW-301-A, SCENARIO-AGW-301-B, SCENARIO-AGW-301-C, SCENARIO-AGW-301-D

---

### REQ-AGW-302 — Override editor — block and extra windows

The system MUST allow adding and deleting availability overrides.
An override MUST be either `block` (day-off) or `extra` (one-off extra window).
Deleting an override MUST call `availabilityRepository.deleteOverride(trainerId, overrideId)`.

**Related SCENARIOs**: SCENARIO-AGW-302-A, SCENARIO-AGW-302-B, SCENARIO-AGW-302-C

---

### Cross-cutting constraints (coach-hub-agenda-web)

| # | Constraint |
|---|-----------|
| C-AGW-1 | All files MUST be under `coach_hub/presentation/sections/agenda/` |
| C-AGW-2 | NO `Scaffold` — `CoachHubScaffold` provides the shell (ADR-CHW-005) |
| C-AGW-3 | Use `AppPalette.of(context)` — MUST NOT hardcode hex colors |
| C-AGW-4 | Use `TreinoIcon.X` — MUST NOT use Phosphor or other icon packs |
| C-AGW-5 | Widgets MUST be `ConsumerStatefulWidget`; page-local state `autoDispose+family` |
| C-AGW-6 | Strings hardcoded Spanish + `// i18n`; MUST NOT call `AppL10n` |
| C-AGW-7 | Dialogs MUST use `showDialog` / `AlertDialog`; MUST NOT use `showModalBottomSheet` |
| C-AGW-8 | MUST NOT modify mobile files; SCENARIO-510 time-bomb is untouched |
| C-AGW-9 | `dart analyze` must return 0 errors; `dart format` applied; all tests green before merge |
| C-AGW-10 | Each PR MUST be independently shippable (PR1 closes placeholder; PR2/PR3a/PR3b build on it) |

---

### Out of Scope (coach-hub-agenda-web)

- Recurring session creation UI (deferred post-PR2)
- Free-slot suggestion UI
- Any AppL10n / i18n infrastructure
- Any mobile file changes
- Any Firestore rule changes
- Any backend / domain / repository changes

---

## Out of Scope (Explicit)

- **Badge wiring** — `badgeProvider` infrastructure is NOT added in W1. Solicitudes badge deferred to W2; Chat badge to W5; Pagos badge to W4; Agenda badge to W4.
- **Actividad data source** — the `Actividad` sidebar item exists and routes to a placeholder; the data model (Firestore collection vs CF aggregation) is a dedicated Fase W2 proposal.
- **Production domain** — `coach-hub-prod` Hosting target and domain choice deferred until user confirms domain (e.g., `coach.treino.app`).
- **Perfil Público location** — deferred to Fase W6 (Ajustes tab is the working assumption; confirmed in W6 proposal).
- **Real navigation for non-shipped sections** — all 19 non-Dashboard, non-ImportarExcel items route to `_PlaceholderScreen` until their respective fases land.
- **Dashboard content redesign** — W4.1 per mockup. The existing layout and `ConstrainedBox(maxWidth: 800)` are left untouched.
- **Notification drawer** — bell renders as static `IconButton`; drawer is Fase W3 at earliest.
- **Mobile code** — `lib/app/router.dart` and all mobile screens are untouched.

---

## Hard Constraints

1. `pubspec.yaml` MUST NOT be modified. `shared_preferences ^2.3.0` and `web ^1.1.0` are already present.
2. `firestore.rules`, `storage.rules`, `firestore.indexes.json` MUST NOT be modified.
3. All colors in client Dart MUST use `AppPalette.of(context)`. No hex literals.
4. All icons MUST use `TreinoIcon.X`. No direct `PhosphorIcons.X` references.
5. All user-facing UI strings in es-AR Rioplatense with `// i18n: Fase W1` markers.
6. Dark mode only — no light theme code.
7. Each PR diff MUST be ≤ 400 LOC (W1.1 ~400, W1.2 ~250, W1.3 ~300, W1.4 ~150).
8. Conventional commits only. NO `Co-Authored-By`. NO AI attribution.

---

## Artifact References

- File: `openspec/changes/coach-hub-web-foundation/spec.md`
- Engram: `sdd/coach-hub-web-foundation/spec`
- Proposal: `openspec/changes/coach-hub-web-foundation/proposal.md` + Engram `sdd/coach-hub-web-foundation/proposal` (#48)
- Exploration: `openspec/changes/coach-hub-web-foundation/exploration.md` + Engram `sdd/coach-hub-web-foundation/explore` (#45)

---

## Coverage Matrix — Coach Hub Pagos Web (PR #224, #226, #231)

| REQ | Category | Status |
|-----|----------|--------|
| REQ-PAGW-ROUTE-001 | `/pagos` route wired | Shipped in PR #224 |
| REQ-PAGW-SHELL-001 | Section contract (no Scaffold/SafeArea) | Shipped in PR #226 |
| REQ-PAGW-SHELL-002 | Section header + Registrar pago button | Shipped in PR #226 |
| REQ-PAGW-KPI-001 | KPI row (Ingreso/Pendiente/Vencido) | Shipped in PR #226 |
| REQ-PAGW-TAB-001 | 4 tabs with mutually exclusive grouping | Shipped in PR #226 |
| REQ-PAGW-TAB-002 | Tab badge shows payment count | Shipped in PR #226 |
| REQ-PAGW-TABLE-001 | Payments table (6 columns) | Shipped in PR #231 |
| REQ-PAGW-ACTION-001 | "Marcar pagado" persists and updates | Shipped in PR #231 |
| REQ-PAGW-ACTION-002 | "Recordar" sends in-app chat reminder | Shipped in PR #231 |
| REQ-PAGW-REGISTRAR-001 | "Registrar pago" dialog + repository | Shipped in PR #231 |
| REQ-PAGW-EMPTY-001 | Empty state per tab | Shipped in PR #231 |
| REQ-PAGW-ROLE-001 | Non-trainer role gate (invariant) | Shipped in PR #224 |
| REQ-PAGW-EXTRACT-001 | Widget extraction (PR1, behavior-preserving) | Shipped in PR #224 |

---

## Change: coach-hub-pagos-web (Pagos Web Implementation)

**Merged from**: `openspec/changes/coach-hub-pagos-web/spec.md`
**Date merged**: 2026-07-01
**Status**: Fully implemented (PR #224, #226, #231)

This change introduces the `/pagos` section screen for trainer-wide payment tracking, replacing the ProximamenteScreen placeholder. Delivered as three chained PRs: PR1 (Widget extraction) → PR2a (Screen shell + data) → PR2b (Rich table + row actions). All new files live under `coach_hub/presentation/sections/pagos/`. No backend, domain, or mobile changes.

---

### REQ-PAGW-ROUTE-001 — `/pagos` route renders `PagosWebScreen`, not `ProximamenteScreen`

`sections/pagos/routes.dart` MUST register `PagosWebScreen` as the widget for the `/pagos` route. `ProximamenteScreen` MUST NOT appear in the pagos route definition after this change.

**Related Scenarios**: 
- GIVEN the router is built WHEN the `/pagos` route is resolved THEN the widget tree contains `PagosWebScreen` and no `ProximamenteScreen`.
- GIVEN a trainer navigates via the sidebar Pagos item WHEN the route resolves THEN `PagosWebScreen` is rendered (no placeholder).

---

### REQ-PAGW-SHELL-001 — `PagosWebScreen` honors the section contract (no Scaffold, no SafeArea)

`PagosWebScreen` MUST be a `ConsumerStatefulWidget`. It MUST NOT introduce `Scaffold`, `SafeArea`, or `AppBackground` anywhere in its subtree. The shell provides those layers (ADR-CHW-005). It MUST use `AppPalette.of(context)` for all colors. No HEX literal color constants in any new file under `sections/pagos/`.

---

### REQ-PAGW-SHELL-002 — Section header and "Registrar pago" action

`PagosWebScreen` MUST render a section header with text `"PAGOS"` and a primary action button labeled `"+ Registrar pago"`. Tapping `"+ Registrar pago"` MUST open the `RegistrarPagoDialog` via `showDialog`/`AlertDialog`. No bottom sheets.

---

### REQ-PAGW-KPI-001 — KPI row shows Ingreso del mes, Pendiente cobrar, Vencido

The screen MUST render a KPI row containing exactly three tiles: **"Ingreso del mes"** (sum of `amountArs` for `status==paid` payments in the current calendar month), **"Pendiente cobrar"** (sum of `amountArs` for Por vencer payments from `pagosPorCobrarProvider`), and **"Vencido"** (sum of `amountArs` for Vencidos payments). Values MUST be formatted as `$X.XXX` (es-AR, no decimals). All derivations are client-side; no new Firestore query or Cloud Function.

---

### REQ-PAGW-TAB-001 — 4 tabs with mutually exclusive grouping

The screen MUST render exactly 4 tabs: **Vencidos**, **Por vencer**, **Pagados**, **Todos**. A `Payment` MUST belong to exactly one of the first three groups — no overlap between Vencidos and Por vencer.

| Tab | Filter rule |
|-----|-------------|
| Vencidos | `status == pending` AND `createdAt < currentPeriodStart` |
| Por vencer | `pagosPorCobrarProvider` current-period pending (status == pending AND createdAt >= currentPeriodStart) |
| Pagados | `status == paid` |
| Todos | all payments |

---

### REQ-PAGW-TAB-002 — Tab badge shows payment count

Each tab label MUST display the count of payments belonging to that group as a badge or parenthetical (e.g. `"Vencidos · 3"`). Count updates reactively as the provider stream changes.

---

### REQ-PAGW-TABLE-001 — Payments table columns

Each active tab MUST render a `PagosTable` widget with exactly 6 columns: **Alumno** (athlete display name), **Concepto/Plan** (payment `concept`), **Monto** (`amountArs` formatted es-AR), **Vencimiento** (formatted date), **Estado** (chip: `"Pagado"` / `"Pendiente"` / `"Vencido"`), **Acciones** (row action buttons).

---

### REQ-PAGW-ACTION-001 — "Marcar pagado" persists via repository and updates UI reactively

Each row with `status == pending` MUST show a `"Marcar pagado"` action button. Tapping it MUST open an `AlertDialog` for confirmation. On confirm, it MUST call `paymentRepository.markManyPaid` for that payment. On success, the payment's `status` becomes `paid` and the row moves from Por vencer/Vencidos to Pagados reactively via the provider stream. `showDialog`/`AlertDialog` only — no bottom sheets.

---

### REQ-PAGW-ACTION-002 — "Recordar" sends a payment reminder via the in-app chat

Each payment row MUST show a `"Recordar"` action button. Tapping it MUST open a confirmation dialog pre-filled with an editable reminder message; on confirm it MUST send that message to the athlete through the existing in-app chat (`chatForOtherUidProvider` resolves/creates the trainer↔athlete `Chat`, then `ChatRepository.sendMessage`). The message MUST include: the payment `amountArs` (formatted es-AR), the payment `concept`, and the trainer's `paymentAlias` (from `UserProfile`) when present. The `notifyOnChatMessage` Cloud Function delivers the push to the athlete. No athlete phone number is required or stored. (Supersedes the earlier WhatsApp `wa.me` approach — the in-app chat needs no phone and keeps the trainer inside the app.)

---

### REQ-PAGW-REGISTRAR-001 — "Registrar pago" dialog adds a payment via repository

`RegistrarPagoDialog` (extracted from `alumno_detail_screen.dart`) MUST collect `amount` (int, ARS) and `concept` (String). On confirm, it MUST call `paymentRepository.add(...)` with the provided values and the current trainer ID. The new payment appears in the appropriate tab reactively via `trainerPaymentsProvider`. On cancel, no write occurs.

---

### REQ-PAGW-EMPTY-001 — Empty state per tab

When a tab has zero payments, a non-crashing, informative empty-state widget MUST be displayed. The empty-state text MUST be tab-specific (e.g., `"No hay pagos vencidos"`, `"No hay pagos pendientes"`, `"No hay pagos registrados"`, `"No hay pagos"` for Todos).

---

### REQ-PAGW-ROLE-001 — Non-trainer roles do not access `/pagos`

The `/pagos` route MUST remain gated to the `trainer` role. Athletes navigating to `/pagos` MUST receive the same not-allowed treatment as the existing role gate (no change to existing gate logic — this requirement documents the invariant).

---

### REQ-PAGW-EXTRACT-001 — Widget extraction from `alumno_detail_screen.dart` is behavior-preserving (PR1)

The widgets and helpers extracted from `alumno_detail_screen.dart` (`RegistrarPagoDialog`, `EstadoCuentaCard`, `PagosTable`, `_marcarPagado`, `_registrarPago`, `_fmtArs`, `nextDueDate`, `fmtDayMonth`) to `sections/pagos/widgets/` MUST NOT change the behavior of `alumno_detail_screen.dart`. After extraction, `alumno_detail_screen.dart` MUST re-import them; all existing tests and `flutter analyze` MUST pass unchanged.

---

### Cross-cutting constraints (coach-hub-pagos-web)

| # | Constraint |
|---|-----------|
| C-PAGW-1 | All files MUST be under `coach_hub/presentation/sections/pagos/` |
| C-PAGW-2 | NO `Scaffold` — `CoachHubScaffold` provides the shell (ADR-CHW-005) |
| C-PAGW-3 | Use `AppPalette.of(context)` — MUST NOT hardcode hex colors |
| C-PAGW-4 | Use `TreinoIcon.X` — MUST NOT use Phosphor or other icon packs |
| C-PAGW-5 | Widgets MUST be `ConsumerStatefulWidget`; page-local state `autoDispose+family` |
| C-PAGW-6 | Strings hardcoded Spanish + `// i18n`; MUST NOT call `AppL10n` |
| C-PAGW-7 | Dialogs MUST use `showDialog` / `AlertDialog`; MUST NOT use `showModalBottomSheet` |
| C-PAGW-8 | MUST NOT modify mobile files; payment-handling on mobile remains unchanged |
| C-PAGW-9 | `dart analyze` must return 0 errors; `dart format` applied; all tests green before merge |
| C-PAGW-10 | Each PR MUST be independently shippable (PR1 extraction; PR2a screen+data; PR2b table+actions) |

---

### Out of Scope (coach-hub-pagos-web)

- Mercado Pago or any payment gateway integration
- Storing athlete phone number
- Auto-detecting uncharged recurring periods (requires Cloud Function — V2)
- Month selector for payment history (V2)
- CSV export (V2)
- `Proyectado mes` KPI (V2, non-trivial client-side derivation)
- Real `dueDate` field (uses `createdAt` as proxy; full recurring billing deferred)
