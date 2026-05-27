# Spec: profile-screen-rewrite (Fase 3 Etapa 7)

**Change**: profile-screen-rewrite
**Phase/Etapa**: Fase 3 / Etapa 7
**Owner**: Backhaus
**PRs**: 4 chained PRs against `main` — `feat/profile-screen-rewrite-pr{1..4}`
**SCENARIO range**: 494–528
**REQ count**: 22 (+ 4 cross-cutting)

---

## REQ Matrix

| ID | PR# | Strength | Description |
|---|---|---|---|
| REQ-PSR-001 | PR#1 | MUST | `ProfileHeader` renders "TU CUENTA" label + "PERFIL" Barlow Condensed title + gear icon |
| REQ-PSR-002 | PR#1 | MUST | Gear icon in `ProfileHeader` navigates to `/profile/settings` |
| REQ-PSR-003 | PR#1 | MUST | `ProfileAvatarCard` renders avatar + `displayName` + derived `@handle` + gym chip (when gymId is set). **Pencil icon REMOVED per design decision 2026-05-27** — card is read-only, edit access lives in the "Datos personales" tile of CUENTA |
| REQ-PSR-004 | PR#1 | MUST | `@handle` is derived on render: `displayName.toLowerCase().replaceAll(' ', '.')` — NOT a persisted field |
| REQ-PSR-005 | PR#1 | MUST | Gym chip is visible when `UserProfile.gymId` is non-null; MUST NOT render when `gymId` is null |
| ~~REQ-PSR-006~~ | — | — | **REMOVED 2026-05-27** — Pencil icon dropped from `ProfileAvatarCard`; edit access is single-entry via the "Datos personales" tile of CUENTA. Placeholder ID kept for numbering continuity |
| REQ-PSR-007 | PR#1 | MUST | `ProfileCuentaSection` renders 4 tiles in exact order: Solicitudes / Datos personales / Gimnasio / Mis rutinas. Historial tile is **explicitly excluded** from this SDD scope per user decision 2026-05-27 (no dedicated historial route exists yet; access remains via Workout tab → HistorialSection scroll) |
| REQ-PSR-008 | PR#1 | MUST | Solicitudes tile displays count from `pendingRequestsCountProvider(myUid)` and navigates to `/profile/friend-requests` |
| REQ-PSR-009 | PR#1 | MUST | Datos personales tile navigates to `/profile/edit-personal` (stub body in PR#1, real screen from PR#2 onward) |
| REQ-PSR-010 | PR#1 | MUST | Gimnasio tile navigates to `/profile/gym` (stub in PR#1, real in PR#3) |
| REQ-PSR-011 | PR#1 | MUST | Mis rutinas tile navigates to `/profile/routines` (stub in PR#1, real in PR#3) |
| ~~REQ-PSR-012~~ | — | — | **REMOVED 2026-05-27** — Historial tile explicitly excluded per scope reduction; placeholder ID kept to preserve numbering continuity downstream |
| REQ-PSR-013 | PR#1 | MUST | Router registers 4 new sub-routes: `/profile/settings`, `/profile/edit-personal`, `/profile/gym`, `/profile/routines`; existing `/profile/friend-requests` MUST NOT be broken |
| REQ-PSR-014 | PR#1 | MUST | "Cerrar sesión" TextButton remains in `ProfileScreen` body footer through PR#1–PR#3 (intentional duplication) |
| REQ-PSR-015 | PR#2 | MUST | `/profile/edit-personal` screen renders a form pre-populated with current `UserProfile` values: displayName, gender, bodyWeightKg, heightCm, experienceLevel, avatar |
| REQ-PSR-016 | PR#2 | MUST | Saving the form calls `UserRepository.update(uid, partial)` with only the changed fields; successful save returns to the previous screen |
| REQ-PSR-017 | PR#2 | MUST | Form fields apply the same validators used elsewhere in the app (displayName non-empty, bodyWeightKg and heightCm numeric ranges) |
| REQ-PSR-018 | PR#2 | MUST | Avatar upload reuses the existing image picker + Firebase Storage helper from Fase 1 Etapa 6 ProfileSetup; no new upload infrastructure |
| REQ-PSR-019 | PR#3 | MUST | `/profile/gym` screen allows search + selection from the gym catalog; confirming updates `UserProfile.gymId` via `UserRepository.update` |
| REQ-PSR-020 | PR#3 | MUST | `/profile/routines` screen lists only trainer-assigned plans: `source == 'trainer-assigned' AND assignedTo == myUid`; reuses `RoutineRepository.listAssignedTo` |
| REQ-PSR-021 | PR#3 | MUST | `/profile/routines` screen renders an empty state when no assigned plans exist |
| REQ-PSR-022 | PR#4 | MUST | `/profile/settings` real screen renders exactly 2 tiles: "Cerrar sesión" and "Eliminar cuenta" |
| REQ-PSR-023 | PR#4 | MUST | Tapping "Cerrar sesión" in Settings calls `authNotifierProvider.notifier.signOut()` |
| REQ-PSR-024 | PR#4 | MUST | Tapping "Eliminar cuenta" opens a bottom sheet with copy "Esta función estará disponible en una versión futura" + CANCELAR button only; CANCELAR closes the sheet without any destructive action |
| REQ-PSR-025 | PR#4 | MUST | `ProfileScreen` body footer "Cerrar sesión" TextButton is REMOVED after PR#4 merges |
| REQ-PSR-CX-001 | All | MUST | Colors via `AppPalette.of(context)` only — no hex literals |
| REQ-PSR-CX-002 | All | MUST | Icons via `TreinoIcon.X` only — no `PhosphorIcons.X` direct usage |
| REQ-PSR-CX-003 | All | MUST | Spacing values from scale: 8 / 12 / 14 / 18 / 20 |
| REQ-PSR-CX-004 | All | MUST | Strict TDD — tests written RED before implementation (GREEN) for every work unit; new strings marked `// i18n: Fase 6` |

---

## Section A — PR#1 Read-Only Scaffold: REQ-PSR-001–014

### Requirement: ProfileHeader Composition (REQ-PSR-001, REQ-PSR-002)

`ProfileHeader` MUST render a "TU CUENTA" label (small caps / secondary style) and a "PERFIL" title in Barlow Condensed. It MUST render a gear icon that, when tapped, navigates to `/profile/settings`. No back-navigation arrow on this top-level screen.

#### SCENARIO-494: ProfileHeader renders all three elements

- GIVEN an authenticated user is on `ProfileScreen`
- WHEN the screen builds
- THEN the text "TU CUENTA" is visible
- AND the text "PERFIL" is visible in Barlow Condensed style
- AND a gear icon is present in the header

#### SCENARIO-495: Tapping the gear icon navigates to /profile/settings

- GIVEN `ProfileScreen` is rendered
- WHEN the user taps the gear icon in `ProfileHeader`
- THEN the router navigates to `/profile/settings`

---

### Requirement: ProfileAvatarCard Composition (REQ-PSR-003, REQ-PSR-004, REQ-PSR-005, ~~REQ-PSR-006~~)

`ProfileAvatarCard` MUST display the user's avatar image, their `displayName`, a derived `@handle`, and an optional gym chip. **The card is READ-ONLY** — no pencil icon, no edit affordance. Edit access lives exclusively in the "Datos personales" tile of CUENTA section per design decision 2026-05-27. The `@handle` MUST be derived at render time via `displayName.toLowerCase().replaceAll(' ', '.')` — it MUST NOT be read from Firestore or any persisted field.

#### SCENARIO-496: ProfileAvatarCard renders avatar, displayName, and derived @handle

- GIVEN a `UserProfile` with `displayName: "Maria Gomez"`
- WHEN `ProfileAvatarCard` builds
- THEN "Maria Gomez" is visible
- AND "@maria.gomez" is visible as the handle
- AND the user's avatar image is rendered

#### SCENARIO-497: @handle derivation for display name with spaces and lowercase

- GIVEN a `UserProfile` with `displayName: "Ana Núñez"`
- WHEN `ProfileAvatarCard` builds
- THEN the rendered handle is "@ana.núñez"

#### SCENARIO-498: Gym chip is visible when UserProfile.gymId is non-null

- GIVEN a `UserProfile` with `gymId: "gym-abc"`
- WHEN `ProfileAvatarCard` builds
- THEN a gym chip is rendered

#### SCENARIO-499: Gym chip is absent when UserProfile.gymId is null

- GIVEN a `UserProfile` with `gymId: null`
- WHEN `ProfileAvatarCard` builds
- THEN no gym chip is rendered

#### ~~SCENARIO-500~~: REMOVED 2026-05-27 — Pencil icon dropped from ProfileAvatarCard (placeholder kept for numbering continuity)

- GIVEN `ProfileAvatarCard` is rendered
- WHEN the user taps the pencil icon
- THEN the router navigates to `/profile/edit-personal`

---

### Requirement: ProfileCuentaSection Tile Order (REQ-PSR-007 through REQ-PSR-012)

`ProfileCuentaSection` MUST render a "CUENTA" section header followed by exactly 4 tiles in this fixed order: Solicitudes, Datos personales, Gimnasio, Mis rutinas. Each tile MUST include an icon (`TreinoIcon.X`), a title, a subtitle, a chevron, and an `onTap` callback. No tile may be conditionally hidden. **Historial tile excluded** per scope decision 2026-05-27 — access remains via Workout tab → HistorialSection.

#### SCENARIO-501: CUENTA section renders exactly 5 tiles in correct order

- GIVEN an authenticated user is on `ProfileScreen`
- WHEN `ProfileCuentaSection` builds
- THEN exactly 4 tiles are rendered in the order: Solicitudes, Datos personales, Gimnasio, Mis rutinas (Historial intentionally absent per scope decision 2026-05-27)

#### SCENARIO-502: Solicitudes tile shows count from pendingRequestsCountProvider

- GIVEN `pendingRequestsCountProvider(myUid)` returns `4`
- WHEN `ProfileCuentaSection` builds
- THEN the Solicitudes tile label reflects the count `4`

#### SCENARIO-503: Tapping Datos personales tile navigates to /profile/edit-personal

- GIVEN `ProfileCuentaSection` is rendered
- WHEN the user taps the Datos personales tile
- THEN the router navigates to `/profile/edit-personal`

#### SCENARIO-504: Tapping Gimnasio tile navigates to /profile/gym

- GIVEN `ProfileCuentaSection` is rendered
- WHEN the user taps the Gimnasio tile
- THEN the router navigates to `/profile/gym`

#### SCENARIO-505: Tapping Mis rutinas tile navigates to /profile/routines

- GIVEN `ProfileCuentaSection` is rendered
- WHEN the user taps the Mis rutinas tile
- THEN the router navigates to `/profile/routines`

#### ~~SCENARIO-506~~: REMOVED 2026-05-27 — Historial tile excluded from scope (placeholder kept for SCENARIO numbering continuity)

---

### Requirement: Router Sub-Route Registration (REQ-PSR-013)

The router MUST register `/profile/settings`, `/profile/edit-personal`, `/profile/gym`, and `/profile/routines` as sub-routes of `/profile`. The existing `/profile/friend-requests` route MUST remain registered and functional. Sub-routes that have stub bodies in PR#1 MUST navigate to placeholder screens — they MUST NOT throw routing errors.

#### SCENARIO-507: All 4 new sub-routes are registered and reachable from ProfileScreen

- GIVEN an authenticated user
- WHEN the router processes pushes to `/profile/settings`, `/profile/edit-personal`, `/profile/gym`, `/profile/routines`
- THEN each resolves to its destination screen without a routing error

#### SCENARIO-508: Existing /profile/friend-requests route is unaffected by PR#1

- GIVEN the router from Fase 3 Etapa 6
- WHEN PR#1 changes are applied to `router.dart`
- THEN `/profile/friend-requests` still navigates to `FriendRequestsInboxScreen`

---

### Requirement: Cerrar Sesión Footer Present in PR#1–PR#3 (REQ-PSR-014)

The existing "Cerrar sesión" TextButton in `ProfileScreen` body footer MUST remain present through PR#1, PR#2, and PR#3. This is intentional — it preserves the user's only confirmed sign-out path until Settings is real (PR#4).

#### SCENARIO-509: Cerrar sesión button is present in ProfileScreen body in PR#1

- GIVEN PR#1 changes are applied
- WHEN `ProfileScreen` builds
- THEN the "Cerrar sesión" TextButton is present in the body footer
- AND it can still trigger sign-out

---

## Section B — PR#2 Datos Personales + Avatar Edit: REQ-PSR-015–018

### Requirement: Edit Personal Screen Form (REQ-PSR-015, REQ-PSR-016, REQ-PSR-017)

`ProfileEditPersonalScreen` MUST render a form pre-populated with the current `UserProfile` values for displayName, gender, bodyWeightKg, heightCm, and experienceLevel. A save action MUST call `UserRepository.update(uid, partial)` with only the changed fields. On success, the screen MUST pop back to the caller. Field validators MUST match those used in the existing registration/setup flows.

#### SCENARIO-510: Edit form is pre-populated with current UserProfile values

- GIVEN a `UserProfile` with `displayName: "Carlos"`, `heightCm: 175`, `bodyWeightKg: 80`
- WHEN `ProfileEditPersonalScreen` opens
- THEN the displayName field shows "Carlos"
- AND the heightCm field shows "175"
- AND the bodyWeightKg field shows "80"

#### SCENARIO-511: Saving valid form calls UserRepository.update with partial data

- GIVEN the user edits `displayName` to "Carlos R." and leaves other fields unchanged
- WHEN the user taps the save button and the form is valid
- THEN `UserRepository.update(uid, {displayName: "Carlos R."})` is called
- AND the screen pops back on success

#### SCENARIO-512: Form shows validation error for empty displayName

- GIVEN `ProfileEditPersonalScreen` is open
- WHEN the user clears the displayName field and taps save
- THEN a validation error is displayed
- AND `UserRepository.update` is NOT called

#### SCENARIO-513: Form shows validation error for out-of-range bodyWeightKg

- GIVEN `ProfileEditPersonalScreen` is open
- WHEN the user enters `bodyWeightKg: 0` (invalid) and taps save
- THEN a validation error is displayed
- AND `UserRepository.update` is NOT called

---

### Requirement: Avatar Upload Reuse (REQ-PSR-018)

The avatar field in `ProfileEditPersonalScreen` MUST reuse the existing image picker + Firebase Storage upload helper from Fase 1 Etapa 6 ProfileSetup. No new upload infrastructure, Firebase Storage rules changes, or new packages are permitted.

#### SCENARIO-514: Avatar picker opens existing picker UI

- GIVEN `ProfileEditPersonalScreen` is rendered
- WHEN the user taps the avatar change control
- THEN the existing image picker UI opens (same as ProfileSetup flow)

#### SCENARIO-515: Selected image uploads via existing Firebase Storage helper and URL is saved

- GIVEN the user selects a new image from the picker
- WHEN upload completes
- THEN the avatar URL in `UserProfile` is updated via `UserRepository.update`
- AND the new avatar is reflected in `ProfileAvatarCard` on the next build

---

## Section C — PR#3 Gimnasio + Mis Rutinas: REQ-PSR-019–021

### Requirement: Gym Selection Screen (REQ-PSR-019)

`ProfileGymScreen` MUST allow the user to search and select a gym from the existing gym catalog. Confirming a selection MUST call `UserRepository.update(uid, {gymId: selectedId})`. After successful save, the screen MUST return to `ProfileScreen` and the gym chip in `ProfileAvatarCard` MUST reflect the new value on the next build.

#### SCENARIO-516: Gym screen loads and renders the gym catalog list

- GIVEN `ProfileGymScreen` opens
- WHEN the gym catalog data is available
- THEN a searchable list of gyms is rendered

#### SCENARIO-517: Selecting a gym and confirming persists the gymId

- GIVEN the user selects gym "CrossFit Norte" from the list
- WHEN the user confirms the selection
- THEN `UserRepository.update(uid, {gymId: "crossfit-norte-id"})` is called
- AND the screen returns to the previous route

#### SCENARIO-518: Gym chip in ProfileAvatarCard updates after gym change

- GIVEN the user changed their gym in `ProfileGymScreen`
- WHEN `ProfileScreen` rebuilds
- THEN the gym chip displays the newly selected gym name

---

### Requirement: Trainer-Assigned Routines List (REQ-PSR-020, REQ-PSR-021)

`ProfileRoutinesScreen` MUST list routines where `source == 'trainer-assigned' AND assignedTo == myUid` using `RoutineRepository.listAssignedTo`. Self-created or saved-favorite routines MUST NOT appear. It MUST render an empty state widget when no assigned plans exist. It MUST reuse the existing `RoutineCard` widget.

#### SCENARIO-519: Routines screen shows only trainer-assigned plans for the current user

- GIVEN routines exist: R1 (`source: 'trainer-assigned'`, `assignedTo: myUid`), R2 (`source: 'self-created'`, `assignedTo: myUid`), R3 (`source: 'trainer-assigned'`, `assignedTo: otherUid`)
- WHEN `ProfileRoutinesScreen` builds
- THEN only R1 is rendered
- AND R2 and R3 are NOT rendered

#### SCENARIO-520: Routines screen renders RoutineCard for each result

- GIVEN `RoutineRepository.listAssignedTo(myUid)` returns `[R1, R2]`
- WHEN `ProfileRoutinesScreen` builds
- THEN exactly 2 `RoutineCard` widgets are rendered

#### SCENARIO-521: Routines screen renders empty state when no plans are assigned

- GIVEN `RoutineRepository.listAssignedTo(myUid)` returns `[]`
- WHEN `ProfileRoutinesScreen` builds
- THEN an empty state widget is visible
- AND no `RoutineCard` widgets are rendered

---

## Section D — PR#4 Settings + Cleanup: REQ-PSR-022–025

### Requirement: Settings Screen Real Implementation (REQ-PSR-022, REQ-PSR-023, REQ-PSR-024)

`ProfileSettingsScreen` real implementation MUST render exactly 2 tiles: "Cerrar sesión" and "Eliminar cuenta". No other tiles (idioma, theme, privacy) MUST appear. Tapping "Cerrar sesión" MUST call `authNotifierProvider.notifier.signOut()`. Tapping "Eliminar cuenta" MUST open a modal bottom sheet with the copy "Esta función estará disponible en una versión futura" and a CANCELAR button only — no destructive confirm action.

#### SCENARIO-522: Settings screen renders exactly 2 tiles

- GIVEN an authenticated user opens `/profile/settings`
- WHEN `ProfileSettingsScreen` builds (PR#4 real implementation)
- THEN exactly 2 tiles are visible: "Cerrar sesión" and "Eliminar cuenta"
- AND no other settings tiles are present

#### SCENARIO-523: Tapping Cerrar sesión calls signOut

- GIVEN `ProfileSettingsScreen` is rendered
- WHEN the user taps the "Cerrar sesión" tile
- THEN `authNotifierProvider.notifier.signOut()` is called

#### SCENARIO-524: Tapping Eliminar cuenta opens bottom sheet with stub copy

- GIVEN `ProfileSettingsScreen` is rendered
- WHEN the user taps the "Eliminar cuenta" tile
- THEN a modal bottom sheet opens
- AND the copy "Esta función estará disponible en una versión futura" is visible
- AND a "CANCELAR" button is present
- AND NO destructive confirm button is present

#### SCENARIO-525: CANCELAR in Eliminar cuenta sheet closes without action

- GIVEN the "Eliminar cuenta" bottom sheet is open
- WHEN the user taps "CANCELAR"
- THEN the sheet closes
- AND no destructive operation is performed
- AND the user remains authenticated

---

### Requirement: Footer Sign-Out Button Removal (REQ-PSR-025)

After PR#4 merges, the "Cerrar sesión" TextButton in `ProfileScreen` body footer MUST be absent. The only sign-out entry point MUST be the "Cerrar sesión" tile inside `/profile/settings`.

#### SCENARIO-526: Cerrar sesión button is absent from ProfileScreen body after PR#4

- GIVEN PR#4 changes are applied to `ProfileScreen`
- WHEN `ProfileScreen` builds
- THEN no "Cerrar sesión" TextButton exists in the body footer
- AND sign-out remains reachable via the gear icon → `/profile/settings`

---

## Section E — Cross-Cutting

### Requirement: Style and TDD Discipline (REQ-PSR-CX-001 through REQ-PSR-CX-004)

All files touched across PR#1–PR#4 MUST use `AppPalette.of(context)` for colors, `TreinoIcon.X` for icons, spacing values from the project scale (8 / 12 / 14 / 18 / 20 logical pixels), and hardcoded es-AR strings marked `// i18n: Fase 6`. Every work unit MUST have tests written RED before the implementation goes GREEN.

#### SCENARIO-527: No hex color literals in any new or modified file

- GIVEN any file created or modified in PR#1–PR#4
- WHEN `flutter analyze` and a manual review are run
- THEN no hex literals (`0xFF…`, `Color(0x…)`) appear in the new code
- AND all color references use `AppPalette.of(context)`

#### SCENARIO-528: All new icon usages reference TreinoIcon, not PhosphorIcons directly

- GIVEN any file created or modified in PR#1–PR#4
- WHEN the file is reviewed
- THEN no `PhosphorIcons.X` references appear in widget build methods
- AND all icon usages go through `TreinoIcon.X`

---

## REQ → SCENARIO Traceability

| REQ | SCENARIOs |
|---|---|
| REQ-PSR-001 | 494 |
| REQ-PSR-002 | 495 |
| REQ-PSR-003 | 496 |
| REQ-PSR-004 | 496, 497 |
| REQ-PSR-005 | 498, 499 |
| ~~REQ-PSR-006~~ | ~~500~~ (both REMOVED 2026-05-27) |
| REQ-PSR-007 | 501 |
| REQ-PSR-008 | 502 |
| REQ-PSR-009 | 503 |
| REQ-PSR-010 | 504 |
| REQ-PSR-011 | 505 |
| REQ-PSR-012 | 506 |
| REQ-PSR-013 | 507, 508 |
| REQ-PSR-014 | 509 |
| REQ-PSR-015 | 510 |
| REQ-PSR-016 | 511 |
| REQ-PSR-017 | 512, 513 |
| REQ-PSR-018 | 514, 515 |
| REQ-PSR-019 | 516, 517, 518 |
| REQ-PSR-020 | 519, 520 |
| REQ-PSR-021 | 521 |
| REQ-PSR-022 | 522 |
| REQ-PSR-023 | 523 |
| REQ-PSR-024 | 524 |
| REQ-PSR-025 | 525, 526 |
| REQ-PSR-CX-001 | 527 |
| REQ-PSR-CX-002 | 528 |
| REQ-PSR-CX-003 | 527 |
| REQ-PSR-CX-004 | (enforced by TDD process — no dedicated scenario) |

---

## Non-Functional Requirements

- **Performance**: `pendingRequestsCountProvider` MUST use `.select()` so the Solicitudes tile rebuilds only when the integer count changes, not on every list reference change. At typical inbox sizes (0–20), this is sufficient.
- **Accessibility**: All tile `onTap` targets MUST be at least 44×44 logical pixels. Form fields in `ProfileEditPersonalScreen` MUST support keyboard navigation (tab order). "CANCELAR" in the bottom sheet MUST be reachable without gesture (accessible via semantics).
- **Correctness**: `@handle` derivation MUST be applied consistently across `ProfileAvatarCard` and any screen that also displays the handle — no separate derivation paths.
- **No new infrastructure**: No new Firestore collections, no `firestore.rules` changes, no new freezed models, no new packages across all 4 PRs.

---

## Excluded Behaviors (out of scope)

The following are explicitly NOT covered by this spec and MUST NOT be implemented in this change:

- PREFERENCIAS section (push notifications, theme, i18n toggles) — deferred to Fase 6.
- Account deletion implementation — stub copy only; real server-side cascade is Fase 6 polish.
- `@handle` as a persisted Firestore field — derived on-the-fly only; no migration.
- Join date display ("Desde sept 2025") — dropped from avatar card scope.
- Self-created or saved-favorite plantillas in "Mis rutinas" — trainer-assigned plans only.
- Header icon for friend requests (notification-bell pattern) — tile inside CUENTA is the sole entry point.
- Localization of any new string — es-AR baseline hardcoded, marked `// i18n: Fase 6`.
- Changes to `lib/features/coach/` or `lib/features/coach_hub/` — other dev's track.
- New Firestore collections or `firestore.rules` changes.
- `StreamProvider` conversion of `friendshipByPairProvider` or `userPublicProfileProvider` — separate SDD.
- Any changes to `TreinoBottomBar` or the bottom navigation bar.
