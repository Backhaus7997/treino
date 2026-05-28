# Proposal: profile-screen-rewrite (Fase 3 Etapa 7)

## TL;DR

Rewrite `ProfileScreen` from a Fase 1 stub into a coherent, mockup-paritied surface with header, avatar card, CUENTA section (5 tiles), edit/settings sub-screens. Ships as **4 chained PRs (~1350 LOC total)** against `main`, no `size:exception` needed. Closes the UX debt accumulated across Fases 1/3/4 where stats and friend-requests were grafted onto a placeholder screen any beta tester opens in the first 5 minutes.

---

## Intent

### Problem

`lib/features/profile/profile_screen.dart` today is a **Fase 1 Etapa 7 stub** with two add-ons grafted on top:

- Stats row (SESIONES / VOLUMEN KG / RACHA) — Fase 4 Etapa 6 PR#2 (`wire-real-stats`)
- Solicitudes de amistad tile — Fase 3 Etapa 6 (`feed-friend-requests-inbox`)

The placeholder body — `"PERFIL / Tu cuenta y ajustes / Cerrar sesión"` — is still there, sitting next to real features. The mockup the user maintains describes a **full profile experience** (header, avatar card, 5-tile CUENTA section, edit screens, settings) that was never scoped as its own etapa. This SDD fills that gap.

### Why now

- The screen is visited within the first 5 minutes of any new install — it is the worst possible surface to ship in a half-built state.
- Fase 5 (Excel import + nutrition) is de-facto closed (PR #92 merged); the implementation pipeline is free for Fase 3 closure.
- Re-opening Fase 3 mirrors the precedent set by Etapa 6 (`feed-friend-requests-inbox`) which also reopened Fase 3 mid-Fase-4 to close a UX gap.
- Cero conflict-risk against `main`: the other dev's track lives under `lib/features/coach/` and `lib/features/coach_hub/`; this SDD does not touch either.

### Success criteria

- ProfileScreen body matches the locked mockup: header ("TU CUENTA" label + "PERFIL" Barlow Condensed title + gear icon) → stats row (unchanged) → avatar card (avatar + nombre + @handle + gym chip + edit pencil) → "CUENTA" section with 5 tiles in locked order (Solicitudes / Datos personales / Gimnasio / Mis rutinas / Historial).
- All 4 sub-routes exist and are reachable: `/profile/edit-personal`, `/profile/gym`, `/profile/routines`, `/profile/settings`.
- "Cerrar sesión" lives **only** inside `/profile/settings` after PR#4 — the body-footer button is gone.
- "Eliminar cuenta" tile in Settings opens a bottom sheet with copy "Próximamente en Fase 6" (UI stub only).
- 4 PRs merge in order, each under the 400-LOC review budget, each independently green on `flutter analyze` + `dart format .` + `flutter test`.

---

## Scope

### In scope — locked decisions (2026-05-27)

| # | Decision | Locked answer |
|---|---|---|
| 1 | Phase home | **Fase 3 Etapa 7**. Re-opens Fase 3, same convention as Etapa 6 (`feed-friend-requests-inbox`). |
| 2 | Delivery strategy | **4 chained PRs against `main`**, ~1350 LOC total. Cero conflict-risk (Fase 5 closed; other dev's track is disjoint under `lib/features/coach*`). |
| 3 | `@handle` field | **Derived on-the-fly** from `displayName.toLowerCase().replaceAll(' ', '.')`. NO new field on `UserProfile`. NO migration. |
| 4 | Join date ("Desde sept 2025") | **Dropped**. Not in avatar card scope. |
| 5 | Notificaciones toggle / PREFERENCIAS section | **NOT in this SDD**. Push notifications + i18n + theme are Fase 6. |
| 6 | "Mis rutinas" semantics | **Only trainer-assigned plans** (`source == 'trainer-assigned'`, `assignedTo == myUid`). Reuses existing `RoutineRepository.listAssignedTo`. Plantillas seedeadas / saved-favorites NOT included. |
| 7 | Solicitudes tile location | **Moved INTO CUENTA section** as 5th tile. Final order: Solicitudes / Datos personales / Gimnasio / Mis rutinas / Historial. |
| 8 | Settings minimal MVP | **2 tiles only**: "Cerrar sesión" (moved from ProfileScreen footer) + "Eliminar cuenta" (UI stub, copy "Próximamente en Fase 6"). NO idioma, NO theme, NO privacy. |
| 9 | Avatar edit | Pencil icon on avatar card opens the **same** `/profile/edit-personal` screen as the "Datos personales" tile. No separate avatar-only flow. |

### Out of scope (explicit)

- PREFERENCIAS section (deferred to Fase 6 — Notificaciones FCM + i18n + theme).
- Account deletion **implementation** (stub copy only — real implementation needs server-side cascade, Fase 6 polish).
- Self-created routines or saved-favorite plantillas in "Mis rutinas".
- `@handle` as a persisted Firestore field — derived on-the-fly only.
- Join date display ("Desde sept 2025").
- Header icon for friend requests (notification-bell pattern) — the tile inside CUENTA is the only entry point.
- Push notifications wiring of any kind.
- Localization of new strings — es-AR baseline only, hardcoded. Localización es Fase 6 Etapa 3.
- Changes to `lib/features/coach/` or `lib/features/coach_hub/` — other dev's track, scope disjunto.
- New Firestore collections or rules changes — uses existing `users/{uid}` owner-only rule.
- New freezed models — `UserProfile` already covers every field we need.

---

## Capabilities

### New Capabilities

- None. This SDD is UI-layer rewrite over existing data/domain capabilities.

### Modified Capabilities

- `profile-management`: ProfileScreen body is rewritten into a header + avatar card + 5-tile CUENTA section; 4 sub-routes added (`/profile/edit-personal`, `/profile/gym`, `/profile/routines`, `/profile/settings`); "Cerrar sesión" relocates from body footer to Settings.

---

## Chained PRs strategy

4 PRs strictly chained on `main`, each independently mergeable. Each rebases on top of the previous after merge.

| PR | Branch | Est. LOC | Scope |
|---|---|---|---|
| PR#1 | `feat/profile-screen-rewrite-pr1-scaffold` | ~400 | Read-only screen scaffold + stub sub-routes |
| PR#2 | `feat/profile-screen-rewrite-pr2-edit-personal` | ~400 | `/profile/edit-personal` form + avatar upload reuse |
| PR#3 | `feat/profile-screen-rewrite-pr3-gym-routines` | ~350 | `/profile/gym` selection + `/profile/routines` list |
| PR#4 | `feat/profile-screen-rewrite-pr4-settings` | ~200 | `/profile/settings` real + sign-out move + footer cleanup |

---

## Touch list per PR

### PR#1 — Read-only screen scaffold (~400 LOC)

**New files**:
- `lib/features/profile/presentation/widgets/profile_header.dart` — "TU CUENTA" label + "PERFIL" Barlow Condensed title + gear icon → `/profile/settings`.
- `lib/features/profile/presentation/widgets/profile_avatar_card.dart` — avatar + nombre + @handle (derived) + gym chip + pencil icon → `/profile/edit-personal`.
- `lib/features/profile/presentation/widgets/profile_cuenta_section.dart` — "CUENTA" section header + 5 tiles (Solicitudes embedded + Datos personales stub + Gimnasio stub + Mis rutinas stub + Historial → existing `/workout/historial`).
- `lib/features/profile/presentation/widgets/profile_section_tile.dart` — shared tile widget (icon + title + subtitle + chevron + onTap).
- `lib/features/profile/presentation/profile_settings_screen.dart` — stub body: placeholder "Coming in PR#4".
- Stub screens for `/profile/edit-personal`, `/profile/gym`, `/profile/routines` (placeholder bodies).
- Widget tests for each new widget + integration test asserting all 4 stub routes are reachable from ProfileScreen.

**Modified files**:
- `lib/features/profile/profile_screen.dart` — replace placeholder body with `_ProfileHeader` + existing `_OwnProfileStatsRow` + `_ProfileCuentaSection`. **KEEP** the existing "Cerrar sesión" TextButton during PR#1-PR#3 (intentional duplication — better than breaking sign-out mid-chain; removed in PR#4).
- `lib/app/router.dart` — register 4 new sub-routes of `/profile`. Audit existing `/profile/friend-requests` registration to avoid collision.
- Existing `ProfileFriendRequestsTile` usage — either inline its logic into the new section or embed the widget as the 5th tile. Existing test coverage from `feed-friend-requests-inbox` must remain green.

### PR#2 — Datos personales edit + avatar edit (~400 LOC)

**New files**:
- `lib/features/profile/presentation/profile_edit_personal_screen.dart` — single-screen form (displayName, gender, bodyWeightKg, heightCm, experienceLevel, avatar) + save button.
- Widget tests for the screen — happy path, validation error path, avatar upload happy path.

**Modified files**:
- `lib/features/profile/profile_screen.dart` — unstub the pencil icon and "Datos personales" tile destinations (route already wired in PR#1).
- Reuse existing: validators from `email_password_validator.dart`, `UserRepository.update(uid, partial)`, `firebase_storage` avatar upload helper from Fase 1 Etapa 6 ProfileSetup.

### PR#3 — Gimnasio change + Mis rutinas list (~350 LOC)

**New files**:
- `lib/features/profile/presentation/profile_gym_screen.dart` — search + select from gym catalog, save → return.
- `lib/features/profile/presentation/profile_routines_screen.dart` — list filtered to `assignedTo: myUid` via existing `RoutineRepository.listAssignedTo` + reuse existing `RoutineCard`.
- Widget tests for both screens.

**Modified files**:
- `lib/features/profile/profile_screen.dart` — unstub the "Gimnasio" and "Mis rutinas" tile destinations.

### PR#4 — Settings real + sign-out move + cleanup (~200 LOC)

**New / replaced files**:
- `lib/features/profile/presentation/profile_settings_screen.dart` — **real implementation, replacing PR#1 stub**. 2 tiles:
  - "Cerrar sesión" → `authNotifierProvider.notifier.signOut()`.
  - "Eliminar cuenta" → destructive bottom sheet, copy "Esta función estará disponible en una versión futura" + CANCELAR button only (no confirm action).
- Widget tests for Settings: both tiles render, "Cerrar sesión" fires signOut, "Eliminar cuenta" opens sheet, CANCELAR closes without action.

**Modified files**:
- `lib/features/profile/profile_screen.dart` — **REMOVE** the existing "Cerrar sesión" TextButton from the body footer. After PR#4 it lives only in Settings.
- Cleanup any orphaned imports / placeholder constants.

---

## Architecture sketch

### Composition tree (post PR#4)

```
ProfileScreen (ConsumerWidget)
  ├─ _ProfileHeader            ("TU CUENTA" label + "PERFIL" + gear → /profile/settings)
  ├─ _OwnProfileStatsRow       (unchanged from wire-real-stats)
  ├─ _ProfileAvatarCard        (avatar + nombre + @handle derived + gym chip + pencil → /profile/edit-personal)
  └─ _ProfileCuentaSection     (header "CUENTA" + 5 tiles)
        ├─ Solicitudes de amistad (N)  → /profile/friend-requests   (existing logic)
        ├─ Datos personales            → /profile/edit-personal
        ├─ Gimnasio                    → /profile/gym
        ├─ Mis rutinas                 → /profile/routines
        └─ Historial                   → /workout/historial          (existing route)
```

### Routing

- ShellRoute keeps the bottom bar visible on all sub-routes of `/profile`.
- Existing `/profile/friend-requests` route (Fase 3 Etapa 6) stays untouched; PR#1 audits the structure to avoid collision when registering the 4 new sub-routes.

### State / data layer (zero new code)

- All new screens are `ConsumerWidget` — no Stateful needed.
- **No new freezed models** — `UserProfile` already has every field the avatar card and edit form need.
- **No new Firestore collections** — uses existing `users/{uid}` (owner-only rule) and existing `routines` query path.
- **No `firestore.rules` changes** — design phase to confirm with a quick audit.
- @handle is **derived on render**: `displayName.toLowerCase().replaceAll(' ', '.')`. Not persisted. Not a freezed field.
- "Mis rutinas" reuses `RoutineRepository.listAssignedTo` already battle-tested in Coach Hub.

---

## Risks

| # | Risk | Likelihood | Mitigation |
|---|---|---|---|
| 1 | Routing collision: `/profile/friend-requests` (Fase 3 Etapa 6) already registered; new sub-routes might conflict. | Medium | PR#1 audits `router.dart` structure first; design phase produces a route topology diagram. |
| 2 | Duplicated "Cerrar sesión" across PR#1-PR#3 (footer + Settings stub will both exist mid-chain). | Low | **Intentional** — better than breaking the user's only sign-out path mid-chain. PR#4 cleanup removes the footer button. |
| 3 | Stub destinations in PR#1 (tappable tiles → "Coming soon" screens). | Low | Acceptable for chained PRs. PR#1 MUST NOT merge to `main` and stop — the chain is a series, not a single release point. Track via `chain:incomplete` label until PR#4 merges. |
| 4 | Avatar upload UX regression. | Low | Reuse the existing image picker + Firebase Storage helper from Fase 1 Etapa 6 ProfileSetup. NO new infrastructure. |
| 5 | "Solicitudes de amistad" tile relocation breaks existing tests. | Low | PR#1 either inlines the logic or embeds the existing `ProfileFriendRequestsTile` widget unchanged. Run the `feed-friend-requests-inbox` test suite after the move. |
| 6 | "Mis rutinas" filter semantics misread by a future reader (e.g., assumes self-created or favorites). | Low | Spec MUST encode the exact filter: `source == 'trainer-assigned' AND assignedTo == myUid`. Comment in the screen file. |
| 7 | "Eliminar cuenta" stub copy interpreted as live feature. | Low | Bottom sheet copy is explicit: "Esta función estará disponible en una versión futura" + CANCELAR only (no destructive button). |
| 8 | i18n debt: new strings hardcoded es-AR, breaking the Fase 6 localización track. | Low | Out of scope explicitly. Strings go through a `// i18n: Fase 6` comment marker so the Fase 6 sweep finds them. |

---

## Rollback plan

Each PR is independently revertible via `git revert <merge-commit>` on `main`. Because the chain duplicates "Cerrar sesión" through PR#1-PR#3 and only removes it in PR#4, reverting PR#4 alone restores the footer button and Settings stub coexists — UX degraded but functional. Reverting PR#3 unstubs `/profile/gym` and `/profile/routines` back to placeholder bodies. Reverting PR#2 unstubs `/profile/edit-personal`. Reverting PR#1 restores the original Fase 1 placeholder body. No data migration to roll back.

---

## Dependencies

- Existing: `UserRepository.update`, `RoutineRepository.listAssignedTo`, `authNotifierProvider`, `friendshipRepository`, gym catalog read path, Firebase Storage avatar helper (Fase 1 Etapa 6), `AppPalette`, `TreinoIcon`, `RoutineCard`.
- No new packages. No `build_runner` regen (no new freezed).

---

## Estimated size

| PR | Prod LOC | Test LOC | Total LOC |
|---|---|---|---|
| PR#1 | ~280 | ~120 | ~400 |
| PR#2 | ~270 | ~130 | ~400 |
| PR#3 | ~240 | ~110 | ~350 |
| PR#4 | ~130 | ~70 | ~200 |
| **Total** | **~920** | **~430** | **~1350** |

All under the 400-LOC review budget individually. **No `size:exception` needed for any PR.**

---

## Delivery strategy

| Aspect | Choice |
|---|---|
| Strategy | **`chained-pr`** against `main`, 4 PRs strictly sequenced |
| Base branch | `main` |
| `size:exception` | **Not needed** on any PR |
| TDD | Strict TDD active — RED → GREEN per work unit, tests first |

### Quality gate (must pass per PR before claiming done)

- `flutter analyze` — 0 issues
- `dart format .` — clean
- `flutter test` — all green (new + existing)

### Commits

Conventional commits. NO Co-Authored-By. NO AI attribution. Suggested first commit per PR: `feat(profile): scaffold rewrite (header + avatar card + cuenta section)` etc.

---

## Reviewer focus

- **PR#1**: scaffold sanity — header / avatar card / 5-tile CUENTA section visually match mockup. All 4 stub routes reachable. Existing friend-requests behavior unchanged. Footer "Cerrar sesión" still present (intentional).
- **PR#2**: form correctness, reuse of existing validators, `UserRepository.update` writes correct partial, avatar upload reuses Fase 1 helper.
- **PR#3**: gym selection persists, routines list filter is **exactly** `source == 'trainer-assigned' AND assignedTo == myUid`.
- **PR#4**: clean removal of duplicated sign-out button, Settings tile pattern matches CUENTA section, "Eliminar cuenta" sheet has no destructive button.

### Smoke validation per PR

- **PR#1**: open Profile → see new header, avatar card, 5 tiles. Tap each tile → land on stub screen with placeholder text. Sign out from existing footer button still works.
- **PR#2**: tap "Datos personales" → form opens populated with current data → edit displayName → save → return → avatar card shows new name. Repeat for avatar upload.
- **PR#3**: tap "Gimnasio" → search/select → save → return → chip + tile subtitle reflect new gym. Tap "Mis rutinas" → list of trainer-assigned plans renders.
- **PR#4**: tap gear icon → Settings with 2 tiles → tap "Cerrar sesión" → logged out. Footer "Cerrar sesión" is **GONE**. Tap "Eliminar cuenta" → sheet with copy + CANCELAR only.

---

## Ready for Spec + Design

Spec and design can run in **parallel** after this proposal lands.

- **Spec** captures: per-screen behavior, per-PR acceptance criteria, edit-form validation contract, "Mis rutinas" filter contract, Settings stub copy contract, navigation contract for 4 new sub-routes, intentional sign-out duplication window (PR#1-PR#3).
- **Design** captures: route topology (existing `/profile/friend-requests` + 4 new sub-routes, ShellRoute layout), widget composition tree, @handle derivation rule, avatar upload reuse path, copy table (es-AR baseline strings), explicit rules audit confirming no `firestore.rules` changes, "Mis rutinas" exact query shape.
