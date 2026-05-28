# Spec: profile (Main Feature Spec)

**Feature**: profile
**Source**: Consolidated from profile-screen-rewrite (Fase 3 Etapa 7)
**Last Updated**: 2026-05-28
**Owner**: Backhaus

---

## Overview

The `profile` feature provides a complete user profile surface with account management, personal data editing, gym selection, and assigned routine tracking. All entry points are integrated into `ProfileScreen`, which displays a composable header, avatar card, CUENTA section (4 tiles), and action tiles (sign-out, delete account stub).

---

## REQ Matrix (Non-Removed from profile-screen-rewrite)

| ID | Strength | Description |
|---|---|---|
| REQ-PROFILE-001 | MUST | `ProfileHeader` renders "TU CUENTA" label + "PERFIL" title in Barlow Condensed. No settings icon. |
| REQ-PROFILE-003 | MUST | `ProfileAvatarCard` renders avatar + displayName + derived @handle + optional gym chip. Card is read-only. |
| REQ-PROFILE-004 | MUST | `@handle` derived on render: `displayName.toLowerCase().replaceAll(' ', '.')` — NOT persisted. |
| REQ-PROFILE-005 | MUST | Gym chip visible when `UserProfile.gymId` non-null; hidden when null. |
| REQ-PROFILE-007 | MUST | `ProfileCuentaSection` renders 4 tiles in order: Solicitudes / Datos personales / Gimnasio / Mis rutinas. |
| REQ-PROFILE-008 | MUST | Solicitudes tile shows count from `pendingRequestsCountProvider(myUid)`; navigates to `/profile/friend-requests`. |
| REQ-PROFILE-009 | MUST | Datos personales tile navigates to `/profile/edit-personal`. |
| REQ-PROFILE-010 | MUST | Gimnasio tile navigates to `/profile/gym`. |
| REQ-PROFILE-011 | MUST | Mis rutinas tile navigates to `/profile/routines`. |
| REQ-PROFILE-013 | MUST | Router registers 3 new sub-routes: `/profile/edit-personal`, `/profile/gym`, `/profile/routines`. Existing `/profile/friend-requests` unbroken. |
| REQ-PROFILE-015 | MUST | `/profile/edit-personal` form pre-populated with current UserProfile values. |
| REQ-PROFILE-016 | MUST | Saving form calls `UserRepository.update(uid, partial)`; pops on success. |
| REQ-PROFILE-017 | MUST | Form validators match existing app patterns. |
| REQ-PROFILE-018 | MUST | Avatar upload reuses Fase 1 Etapa 6 helper; no new infrastructure. |
| REQ-PROFILE-019 | MUST | `/profile/gym` allows search + select + update via `UserRepository.update`. |
| REQ-PROFILE-020 | MUST | `/profile/routines` lists trainer-assigned only: `source == 'trainer-assigned' AND assignedTo == myUid`. |
| REQ-PROFILE-021 | MUST | `/profile/routines` renders empty state when no assigned plans. |
| REQ-PROFILE-026 | MUST | `ProfileScreen` body renders "Cerrar sesión" + "Eliminar cuenta" tiles below CUENTA section. |
| REQ-PROFILE-027 | MUST | "Cerrar sesión" tile calls `authNotifierProvider.notifier.signOut()`. |
| REQ-PROFILE-028 | MUST | "Eliminar cuenta" tile opens stub sheet; CANCELAR closes without action. |
| REQ-PROFILE-CX-001 | MUST | Colors via `AppPalette.of(context)` only — no hex literals. |
| REQ-PROFILE-CX-002 | MUST | Icons via `TreinoIcon.X` only — no `PhosphorIcons.X` direct usage. |
| REQ-PROFILE-CX-003 | MUST | Spacing values from scale: 8 / 12 / 14 / 18 / 20. |
| REQ-PROFILE-CX-004 | MUST | Strict TDD enforced; all strings marked `// i18n: Fase 6 Etapa 3`. |

---

## Section A — ProfileScreen Composition

### ProfileHeader (REQ-PROFILE-001)

Renders a "TU CUENTA" eyebrow label in secondary style and a "PERFIL" title in Barlow Condensed. No back arrow, no settings icon.

### ProfileAvatarCard (REQ-PROFILE-003, REQ-PROFILE-004, REQ-PROFILE-005)

Displays the user's avatar, displayName, derived @handle (pure function, not persisted), and an optional gym chip. Card is read-only — edit access lives in the Datos personales tile.

#### @Handle Derivation Algorithm

- Input: `displayName` (string or null)
- Fallback: `"sin_handle"` if null/empty/whitespace
- Algorithm: trim → lowercase → collapse whitespace to dots → preserve Unicode (accents) → strip non-letter/digit/dot/underscore
- Output: `@{derived_string}`
- Examples: "Ana Núñez" → "@ana.núñez", "O'Brien" → "@obrien", null → "@sin_handle"

### ProfileCuentaSection (REQ-PROFILE-007 through REQ-PROFILE-011)

Renders a "CUENTA" section header followed by exactly 4 tiles in fixed order:
1. Solicitudes (count from `pendingRequestsCountProvider`) → `/profile/friend-requests`
2. Datos personales → `/profile/edit-personal`
3. Gimnasio → `/profile/gym`
4. Mis rutinas (count from `assignedRoutinesCountProvider`) → `/profile/routines`

---

## Section B — Edit Personal Screen (REQ-PROFILE-015 through REQ-PROFILE-018)

### Form Fields

- displayName (text)
- gender (segmented: HOMBRE / MUJER / OTRO)
- bodyWeightKg (numeric)
- heightCm (numeric)
- experienceLevel (segmented: PRINCIPIANTE / INTERMEDIO / AVANZADO)
- avatar (image picker)

### Save Flow

1. Validate all fields
2. Collect only changed fields into partial map
3. Call `UserRepository.update(uid, partial)`
4. On success, `context.pop()`
5. On error, show SnackBar

### Avatar Upload

Reuses `avatarUploadServiceProvider` from `lib/features/profile_setup/application/profile_setup_providers.dart`. No new Firebase Storage rules or packages.

---

## Section C — Gym Selection Screen (REQ-PROFILE-019)

Allows search + selection from existing gym catalog. Confirming saves via `UserRepository.update({gymId: selectedId})`. Reuses `filteredGymsProvider`, `gymSearchQueryProvider`, and `GymCard` from profile_setup feature.

---

## Section D — Trainer-Assigned Routines Screen (REQ-PROFILE-020, REQ-PROFILE-021)

Filters routines via `RoutineRepository.listAssignedTo(myUid)` where `source == 'trainer-assigned' AND assignedTo == myUid`. Renders `RoutineCard` for each. Shows empty state when list is empty.

---

## Section E — Action Tiles (REQ-PROFILE-026 through REQ-PROFILE-028)

### Cerrar Sesión Tile

Calls `authNotifierProvider.notifier.signOut()` on tap.

### Eliminar Cuenta Tile

Opens `EliminarCuentaStubSheet` with copy "Esta función estará disponible en una versión futura." and CANCELAR button only (no destructive button). Real account deletion deferred to future SDD.

---

## Cross-Cutting Requirements (REQ-PROFILE-CX-001 through REQ-PROFILE-CX-004)

### Colors (REQ-PROFILE-CX-001)
All colors via `AppPalette.of(context)` — no hex literals.

### Icons (REQ-PROFILE-CX-002)
All icons via `TreinoIcon.X` — no `PhosphorIcons.X` direct usage.

### Spacing (REQ-PROFILE-CX-003)
All spacing from scale: 8 / 12 / 14 / 18 / 20 logical pixels.

### Testing & i18n (REQ-PROFILE-CX-004)
- Strict TDD enforced: tests RED before implementation GREEN
- All user-facing strings marked `// i18n: Fase 6 Etapa 3` for Fase 6 i18n sweep

---

## Out of Scope (Explicit)

- PREFERENCIAS section (notifications, theme, language) — Fase 6
- Real account deletion implementation — stub copy only
- `@handle` as persisted field — derived only
- Self-created or favorite routines in Mis rutinas — trainer-assigned only
- Header notification bell — Solicitudes tile is sole entry point
- Changes to coach/coach_hub features — separate development track
- New Firestore collections or rules changes

---

## Architecture Notes

### Providers

| Provider | Type | Purpose |
|---|---|---|
| `userProfileProvider` | StreamProvider | Avatar card + form populate + gym screen |
| `pendingRequestsCountProvider` | Provider.select | Solicitudes tile count |
| `assignedRoutinesCountProvider` | FutureProvider.autoDispose.family | Mis rutinas tile count |
| `assignedRoutinesProvider` | FutureProvider.autoDispose.family | Routines screen list |
| `avatarUploadServiceProvider` | (reused) | Avatar upload handler |
| `userRepositoryProvider` | (reused) | All save operations |

### Routes

All sub-routes register as siblings inside existing `/profile` GoRoute:
- `/profile/edit-personal` (ConsumerStatefulWidget)
- `/profile/gym` (ConsumerStatefulWidget)
- `/profile/routines` (ConsumerWidget)

ShellRoute preserves bottom bar visibility.

### Widgets

- `ProfileHeader` — header composition
- `ProfileAvatarCard` — read-only card with derived @handle
- `ProfileCuentaSection` — 4-tile layout
- `ProfileSectionTile` — shared tile component (7 consumers)
- `ProfileEditPersonalScreen` — form + avatar upload
- `ProfileGymScreen` — gym search + select
- `ProfileRoutinesScreen` — assigned routines list
- `EliminarCuentaStubSheet` — bottom sheet with stub copy

---

## Hard Constraints

1. ZERO firestore.rules / firestore.indexes.json / storage.rules changes
2. ZERO new freezed models
3. ZERO new packages
4. All colors via AppPalette — no hex literals
5. All icons via TreinoIcon — no PhosphorIcons.X direct usage
6. Spacing from scale only (8 / 12 / 14 / 18 / 20)
7. Strict TDD — RED before GREEN per task pair
8. All new strings marked `// i18n: Fase 6 Etapa 3`

---

## History

| Date | Event |
|---|---|
| 2026-05-27 | Initial spec created in profile-screen-rewrite SDD; scope includes 5-tile CUENTA (Solicitudes, Datos personales, Gimnasio, Mis rutinas, Historial) + Settings screen |
| 2026-05-27 | Historial tile excluded from scope; Settings screen planned for PR#4 |
| 2026-05-28 | PR#4 PIVOT: Settings screen scrapped; sign-out + eliminar-cuenta tiles moved to ProfileScreen body. REQs 002, 006, 012, 022–025 marked REMOVED; REQs 026–028 added for body tiles. |
| 2026-05-28 | Main profile spec created by merging non-removed delta REQs into openspec/specs/profile/spec.md. |
