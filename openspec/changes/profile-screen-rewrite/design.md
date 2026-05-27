# Design: profile-screen-rewrite (Fase 3 Etapa 7)

## 1. TL;DR

We rewrite `ProfileScreen` from a Fase 1 placeholder into a four-section composition (header + stats row + avatar card + CUENTA section) backed entirely by `ConsumerWidget`s and the **existing** `userProfileProvider` / `pendingRequestCountProvider` / `userSessionStatsProvider`. The only new application-layer artifact is `assignedRoutinesCountProvider`, a `FutureProvider.autoDispose.family<int, String>` derived from the existing `RoutineRepository.listAssignedTo`. No new freezed models, no new repositories, no new collections. The `@handle` is a pure derivation (`displayName.toLowerCase().replaceAll(' ', '.')`) extracted to `lib/core/utils/handle_derivation.dart` so the same rule is tested once and reused by the avatar card and (eventually) Public Profile. The four new sub-routes register **inside the existing `/profile` GoRoute** as additional `routes:` entries alongside the existing `friend-requests` child — zero collision risk. We deliberately keep the legacy `Cerrar sesión` `TextButton` in the ProfileScreen body through PR#1-PR#3 (intentional duplication) and remove it in PR#4 the same commit that the real Settings screen ships, so sign-out is never broken mid-chain. **Rules audit conclusion: zero `firestore.rules` and zero `firestore.indexes.json` changes — every op already authorized.** The full es-AR copy table lives in §8 as the source-of-truth for Fase 6 Etapa 3 localización.

---

## 2. Architecture overview

### Provider topology (post PR#4)

```
authStateChangesProvider                          (existing — feature: auth)
  └─ userProfileProvider                          (existing — StreamProvider<UserProfile?>)
       └─ ProfileAvatarCard reads displayName, avatarUrl, gymId
       └─ ProfileEditPersonalScreen reads ALL fields to populate form
       └─ ProfileGymScreen reads current gymId for selected highlight

  └─ currentUidProvider / authState.uid           (existing)
       └─ pendingRequestCountProvider(myUid)      (existing) → Solicitudes tile count
       └─ userSessionStatsProvider                (existing) → stats row (UNCHANGED)
       └─ assignedRoutinesCountProvider(myUid)    NEW — FutureProvider.autoDispose.family<int, String>
            └─ Mis rutinas tile subtitle ("N activas")

routineRepositoryProvider                         (existing)
  └─ assignedRoutinesCountProvider derives from listAssignedTo(uid).length

userRepositoryProvider                            (existing)
  └─ ProfileEditPersonalScreen save → UserRepository.update(uid, partial)
  └─ ProfileGymScreen save        → UserRepository.update(uid, {'gymId': ...})

avatarUploadServiceProvider                       (existing — feature: profile_setup)
  └─ ProfileEditPersonalScreen avatar upload reuse
```

**No new repositories, no new domain types, no new freezed models.** `UserProfile` already has every field the avatar card and edit form need.

### Why `FutureProvider.autoDispose` (not Stream) for assignedRoutinesCountProvider

`RoutineRepository.listAssignedTo` is a `Future<List<Routine>>` (one-shot `.get()`, not `.snapshots()`) — see `lib/features/workout/data/routine_repository.dart:45`. Promoting to a streaming variant is out of scope for this SDD (touches the workout feature and Coach Hub). The CUENTA tile subtitle "N activas" tolerates a one-frame stale value: it refreshes on each `/profile` mount because of `autoDispose`. A future SDD that introduces a live count (push-notification badge etc.) can replace this provider without touching consumers.

### Widget tree — ProfileScreen (post PR#4)

```
ProfileScreen (ConsumerWidget)
  └─ Column
       ├─ ProfileHeader              ("TU CUENTA" eyebrow + "PERFIL" title + gear icon → /profile/settings)
       ├─ _OwnProfileStatsRow        (existing, unchanged from wire-real-stats)
       ├─ ProfileAvatarCard          (avatar + displayName + @handle derived + gym chip + pencil → /profile/edit-personal)
       └─ ProfileCuentaSection       (header "CUENTA" + 4 ProfileSectionTile — Historial excluded per scope decision 2026-05-27)
             ├─ ProfileSectionTile.solicitudes  → /profile/friend-requests   (existing route, count from pendingRequestCountProvider)
             ├─ ProfileSectionTile.datos        → /profile/edit-personal
             ├─ ProfileSectionTile.gym          → /profile/gym
             └─ ProfileSectionTile.routines     → /profile/routines           (subtitle "N activas" from assignedRoutinesCountProvider)
```

### Widget tree — ProfileEditPersonalScreen

```
ProfileEditPersonalScreen (ConsumerStatefulWidget — needs TextEditingControllers)
  └─ Column
       ├─ _EditPersonalHeader        (caretLeft back + "EDITAR PERFIL" title)
       └─ Expanded(SingleChildScrollView)
             └─ Form(key: _formKey)
                  ├─ _AvatarEditor          (tap → image_picker → upload via AvatarUploadService → preview)
                  ├─ _DisplayNameField      (validator: non-empty, max 50)
                  ├─ _GenderSelector        (segmented control: male/female/other)
                  ├─ _BodyWeightKgField     (validator: numeric, 30-300)
                  ├─ _HeightCmField         (validator: numeric, 120-230)
                  ├─ _ExperienceLevelSelector (segmented control: beginner/intermediate/advanced)
                  └─ Row(_DiscardPill, _SavePill)
```

### Widget tree — ProfileGymScreen

```
ProfileGymScreen (ConsumerStatefulWidget — local search query state)
  └─ Column
       ├─ _GymScreenHeader            (back + "GIMNASIO" title)
       ├─ _GymSearchField             (reuses gymSearchQueryProvider from profile_setup)
       └─ Expanded(ListView)
             └─ for gym in filteredGymsProvider: GymCard (existing widget, reuse)
             └─ GymCard("OTRO GYM / SIN GYM", gymId: null)
       └─ _SaveBar(_SavePill)         (disabled when selection == current)
```

### Widget tree — ProfileRoutinesScreen

```
ProfileRoutinesScreen (ConsumerWidget)
  └─ Column
       ├─ _RoutinesScreenHeader      (back + "MIS RUTINAS" title)
       └─ Expanded(
            ref.watch(assignedRoutinesProvider(myUid)).when(
              loading → CircularProgressIndicator
              error   → "No pudimos cargar tus rutinas..."
              data([]) → "Tu PF todavía no te asignó ninguna rutina."
              data(list) → ListView.separated(RoutineCard(routine: r) for r in list)
            )
          )
```

Note: `assignedRoutinesProvider` (LIST) and `assignedRoutinesCountProvider` (COUNT) are siblings. The count provider derives `.length` from the list provider so they share a single Firestore round-trip per `/profile` mount.

### Widget tree — ProfileSettingsScreen (PR#4)

```
ProfileSettingsScreen (ConsumerWidget)
  └─ Column
       ├─ _SettingsHeader            (back + "AJUSTES" title)
       └─ Expanded(ListView)
             ├─ ProfileSectionTile.cerrarSesion   → ref.read(authNotifierProvider.notifier).signOut()
             └─ ProfileSectionTile.eliminarCuenta → showModalBottomSheet(EliminarCuentaStubSheet)
```

---

## 3. Route topology (resolves risk #1)

### Current state of `lib/app/router.dart` (lines 308-318)

The `/profile` GoRoute lives inside the `ShellRoute`. It already has a `routes:` child for `friend-requests` (added by Fase 3 Etapa 6). The new sub-routes drop in as additional siblings — no collision.

### Proposed registration (after PR#1)

```dart
GoRoute(
  path: '/profile',
  pageBuilder: (_, __) => _noAnim(const ProfileScreen()),
  routes: [
    // Existing — Fase 3 Etapa 6
    GoRoute(
      path: 'friend-requests',
      pageBuilder: (_, __) => _noAnim(const FriendRequestsInboxScreen()),
    ),
    // NEW — Fase 3 Etapa 7 (this SDD)
    GoRoute(
      path: 'edit-personal',
      pageBuilder: (_, __) => _noAnim(const ProfileEditPersonalScreen()),
    ),
    GoRoute(
      path: 'gym',
      pageBuilder: (_, __) => _noAnim(const ProfileGymScreen()),
    ),
    GoRoute(
      path: 'routines',
      pageBuilder: (_, __) => _noAnim(const ProfileRoutinesScreen()),
    ),
    GoRoute(
      path: 'settings',
      pageBuilder: (_, __) => _noAnim(const ProfileSettingsScreen()),
    ),
  ],
),
```

### Final route table

| Path | Screen | Phase | Notes |
|---|---|---|---|
| `/profile` | `ProfileScreen` | existing, rewrite body | inside ShellRoute → bottom bar visible |
| `/profile/friend-requests` | `FriendRequestsInboxScreen` | existing (Fase 3 Etapa 6) | unchanged |
| `/profile/edit-personal` | `ProfileEditPersonalScreen` | NEW PR#1 stub → PR#2 real | bottom bar visible (inside ShellRoute) |
| `/profile/gym` | `ProfileGymScreen` | NEW PR#1 stub → PR#3 real | bottom bar visible |
| `/profile/routines` | `ProfileRoutinesScreen` | NEW PR#1 stub → PR#3 real | bottom bar visible |
| `/profile/settings` | `ProfileSettingsScreen` | NEW PR#1 stub → PR#4 real | bottom bar visible |

### Historial tile — EXCLUDED FROM SCOPE (2026-05-27)

The proposal originally claimed "Historial → /workout/historial (existing route)" which was factually wrong (only the detail route `/workout/historial/:sessionId` exists; there is no listing route). The design briefly proposed sending the tile to `/workout` (Workout tab) as honest sub-optimal UX.

**Final resolution (user decision 2026-05-27)**: Drop the Historial tile from CUENTA section entirely. Rationale: shipping a tile that drops the user on the wrong screen and forces them to scroll is worse than not shipping the tile at all. Athletes who want their history continue to find it via the Workout tab's HistorialSection (existing behavior, no regression).

A future SDD may introduce a dedicated `/workout/historial-list` (or `/profile/historial`) screen + Historial tile in CUENTA. Both deliverables go together to avoid this same sub-optimal-UX trap.

### Navigation primitives

All in-shell sub-routes use `context.push` (not `go`) for forward navigation, so `pop` returns to ProfileScreen with the bottom bar intact. (Historial cross-tab exception removed — tile no longer exists.)

---

## 4. Widget specs per new component

### 4.1 PR#1 components

#### `ProfileHeader`

**Path**: `lib/features/profile/presentation/widgets/profile_header.dart`
**Type**: `ConsumerWidget` (needs context.push)
**Constructor**: `const ProfileHeader({super.key})`

**Render**:
- `Padding(EdgeInsets.fromLTRB(20, 18, 20, 14))`
- `Row(crossAxisAlignment: center, children: [Expanded(Column), gearButton])`
  - Column (start-aligned):
    - `Text("TU CUENTA", GoogleFonts.barlowCondensed(fontWeight: w700, fontSize: 12, letterSpacing: 1.4, color: palette.textMuted))`
    - `SizedBox(height: 4)`
    - `Text("PERFIL", GoogleFonts.barlowCondensed(fontWeight: w700, fontSize: 28, letterSpacing: 1.2, color: palette.textPrimary))`
  - `GestureDetector(onTap: () => context.push('/profile/settings'), child: Icon(PhosphorIconsRegular.gearSix, size: 24, color: palette.textPrimary))`

**Icon gap**: `TreinoIcon` does NOT currently expose a gear icon (see `lib/core/widgets/treino_icon.dart` — no `gear` constant). **PR#1 MUST add `static const IconData settings = PhosphorIconsRegular.gearSix;` to `TreinoIcon`** and reference `TreinoIcon.settings` (NEVER `PhosphorIconsRegular.gearSix` directly — project rule). See Risk #7 in §10.

**Tap target**: 48×48 hit area on the gear (use `Padding(EdgeInsets.all(12))` around the 24px icon).

**Test surface**: renders both texts, gear tap pushes `/profile/settings`.

---

#### `ProfileAvatarCard`

**Path**: `lib/features/profile/presentation/widgets/profile_avatar_card.dart`
**Type**: `ConsumerWidget`
**Constructor**: `const ProfileAvatarCard({super.key})`

**Subscriptions**:
- `ref.watch(userProfileProvider)` → `AsyncValue<UserProfile?>`

**Render** (data state):
- `Padding(EdgeInsets.symmetric(horizontal: 20, vertical: 14))`
- `Container(padding: EdgeInsets.all(14), decoration: bgCard + radius 18 + 0.12-alpha border)`
- `Row(children: [avatar(64), SizedBox(14), Expanded(Column), pencilButton])`
  - Avatar: `PostAvatar(authorDisplayName: displayName ?? "", authorAvatarUrl: avatarUrl, size: 64)` (reuses existing helper from `feed/presentation/widgets/post_avatar.dart`)
  - Column (start-aligned):
    - `Text(displayName ?? "Sin nombre", barlowCondensed w700 fontSize 20 color textPrimary)`
    - `SizedBox(height: 2)`
    - `Text("@${deriveHandle(displayName)}", barlow w400 fontSize 13 color textMuted)`
    - `SizedBox(height: 6)`
    - if `gymId != null`: `_GymChip(gymId: gymId!)` — small pill `padding(horizontal: 10, vertical: 4)`, `palette.bgCard` slightly elevated tint, label = `gymNameFromId(gymId)` (existing helper from `feed/domain/gym_name.dart`)
  - Pencil: `GestureDetector(onTap: () => context.push('/profile/edit-personal'), child: Icon(TreinoIcon.edit, size: 20, color: palette.textMuted))`

**Loading/error**: render skeleton — gray avatar circle + two empty text bars — never a CircularProgressIndicator (this card is the visual anchor of the screen; flicker is worse than skeleton).

**Defensive null**: if `displayName == null` (signup mid-flight race), render "Sin nombre" + skip @handle line. The router's `/profile-setup` redirect normally prevents this, but defensive rendering avoids a frame of broken state.

**Test surface**: renders avatar+name+@handle+gym chip from a seeded UserProfile, pencil tap pushes `/profile/edit-personal`.

---

#### `ProfileSectionTile` (shared, reused across CUENTA section AND Settings screen)

**Path**: `lib/features/profile/presentation/widgets/profile_section_tile.dart`
**Type**: `StatelessWidget` (no provider subscription — count is passed in)
**Constructor**:
```dart
const ProfileSectionTile({
  super.key,
  required this.icon,
  required this.title,
  this.subtitle,
  this.trailing,                // optional override for non-chevron trailing
  this.destructive = false,     // tints icon + title in palette.danger
  required this.onTap,
});

final IconData icon;
final String title;
final String? subtitle;
final Widget? trailing;
final bool destructive;
final VoidCallback onTap;
```

**Render**:
- `Padding(EdgeInsets.symmetric(horizontal: 20, vertical: 6))`
- `GestureDetector(onTap, behavior: opaque, child: Container(padding(horizontal: 14, vertical: 12), bgCard, radius 14, 0.12-alpha border, Row))`
  - `Icon(icon, size: 20, color: destructive ? palette.danger : palette.accent)`
  - `SizedBox(width: 14)`
  - `Expanded(Column(crossAxisStart, mainAxisSize.min, children: [titleText, if subtitle: SizedBox(2) + subtitleText]))`
    - title: `barlowCondensed w700 fontSize 16 color destructive ? palette.danger : palette.textPrimary`
    - subtitle: `barlow w400 fontSize 12 color palette.textMuted`
  - trailing ?? `Icon(TreinoIcon.chevronRight, size: 16, color: palette.textMuted)`

**Test surface**: renders title only, renders title+subtitle, renders trailing override, tap fires onTap, destructive variant tints correctly.

---

#### `ProfileCuentaSection`

**Path**: `lib/features/profile/presentation/widgets/profile_cuenta_section.dart`
**Type**: `ConsumerWidget`
**Constructor**: `const ProfileCuentaSection({super.key})`

**Subscriptions**:
- `ref.watch(authStateChangesProvider).valueOrNull?.uid` → `myUid`
- `ref.watch(userProfileProvider)` → for gym subtitle
- `ref.watch(pendingRequestCountProvider(myUid ?? ''))` → for Solicitudes count
- `ref.watch(assignedRoutinesCountProvider(myUid ?? ''))` → `AsyncValue<int>` for Mis rutinas count

**Render**:
- `Padding(EdgeInsets.fromLTRB(20, 18, 20, 8))`
- `Text("CUENTA", barlowCondensed w700 fontSize 12 letterSpacing 1.4 color palette.textMuted)`
- `SizedBox(height: 6)`
- 4 `ProfileSectionTile` in locked order (Historial removed per scope decision 2026-05-27):
  1. Solicitudes: icon `TreinoIcon.users`, title `"Solicitudes de amistad"`, subtitle `"$count nuevas"` (or `null` when count == 0), onTap `context.push('/profile/friend-requests')`
  2. Datos personales: icon `TreinoIcon.edit`, title `"Datos personales"`, subtitle `"Editá tu info"`, onTap `context.push('/profile/edit-personal')`
  3. Gimnasio: icon `TreinoIcon.gym`, title `"Gimnasio"`, subtitle `userProfile.gymId == null ? "Sin gym" : gymNameFromId(userProfile.gymId!)`, onTap `context.push('/profile/gym')`
  4. Mis rutinas: icon `TreinoIcon.dumbbell`, title `"Mis rutinas"`, subtitle `routinesCount.maybeWhen(data: (n) => "$n activas", orElse: () => "")`, onTap `context.push('/profile/routines')`

**Test surface**: all 4 tiles render in correct order, subtitles reflect provider state, taps navigate to correct routes.

---

#### Stub screens (PR#1)

For each of `ProfileEditPersonalScreen`, `ProfileGymScreen`, `ProfileRoutinesScreen`, `ProfileSettingsScreen` ship a temporary placeholder body during PR#1:

```dart
class ProfileEditPersonalScreen extends StatelessWidget {
  const ProfileEditPersonalScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Column(
      children: [
        // Minimal header so back navigation works mid-chain.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
          child: GestureDetector(
            onTap: () => context.pop(),
            child: Row(children: [
              Icon(TreinoIcon.back, size: 20, color: palette.textPrimary),
              const SizedBox(width: 14),
              Text("EDITAR PERFIL", style: ...),
            ]),
          ),
        ),
        Expanded(child: Center(child: Text("Próximamente en PR#2", style: ...))),
      ],
    );
  }
}
```

Same skeleton (different title + PR label) for `/profile/gym` (PR#3), `/profile/routines` (PR#3), `/profile/settings` (PR#4).

The duplicated `Cerrar sesión` `TextButton` stays in `ProfileScreen` body during PR#1-PR#3 (intentional, per ADR-PSR-008).

---

### 4.2 PR#2 components

#### `ProfileEditPersonalScreen`

**Path**: `lib/features/profile/presentation/profile_edit_personal_screen.dart`
**Type**: `ConsumerStatefulWidget` (needs TextEditingControllers + form state)
**Constructor**: `const ProfileEditPersonalScreen({super.key})`

**Subscriptions**:
- Initial form values: `ref.read(userProfileProvider).valueOrNull` in `initState` (one-shot, not watched — otherwise form fields fight live updates)
- Save handler: `ref.read(userRepositoryProvider)` + `ref.read(avatarUploadServiceProvider)`
- Save state: local `ValueNotifier<_SaveState>` (idle / uploading / saving / error) for UI feedback

**Render**: see widget tree in §2. Form fields:

| Field | Widget | Validator |
|---|---|---|
| Avatar | `_AvatarEditor` (tap → `image_picker` → upload via `avatarUploadServiceProvider.upload(path)`) | none |
| Display name | `TextFormField` | non-empty, max 50 chars |
| Gender | `_GenderSelector` (3 segments: HOMBRE / MUJER / OTRO) | none (nullable allowed) |
| Body weight kg | `TextFormField` keyboardType numeric | 30-300, numeric |
| Height cm | `TextFormField` keyboardType numeric | 120-230, numeric |
| Experience | `_ExperienceLevelSelector` (3 segments: PRINCIPIANTE / INTERMEDIO / AVANZADO) | none (nullable allowed) |

**Save flow**:
1. `_formKey.currentState!.validate()` — if false, abort.
2. If avatar changed (local path set): upload via `avatarUploadServiceProvider.upload(localPath)` → get `avatarUrl`. Wrap in try/catch — on failure show SnackBar `"No pudimos subir tu foto. Probá de nuevo."` and abort save.
3. Build partial: `{'displayName': name, 'gender': gender?.name, 'bodyWeightKg': weight, 'heightCm': height, 'experienceLevel': level?.name, if avatarUrl changed: 'avatarUrl': avatarUrl}`.
4. `await ref.read(userRepositoryProvider).update(uid, partial)` — already does the dual-write to `userPublicProfiles` for `displayName`/`avatarUrl`/`gymId` (per `user_repository.dart:234-268`).
5. On success: `context.pop()` — `userProfileProvider` is a StreamProvider, so the avatar card on ProfileScreen rebuilds with new data on the next frame. **No `ref.invalidate` needed.**

**Discard flow**: if form is dirty (`_formKey.currentState!.value != initialValues`), show confirmation dialog `"¿Descartar los cambios?"`. Otherwise just `context.pop()`.

**Reused**:
- `avatarUploadServiceProvider` from `lib/features/profile_setup/application/profile_setup_providers.dart`
- `image_picker` (already used by ProfileSetup step 1)
- `userRepositoryProvider.update` — already handles the dual-write
- Validators: roll inline (no existing reusable validators for name/weight/height — `email_password_validator.dart` is auth-specific despite the proposal's reference)

**Test surface**: form renders populated from seeded UserProfile, validation rejects empty name + out-of-range weight/height, save fires `UserRepository.update` with correct partial, avatar upload happy path stores URL in partial, avatar upload error shows SnackBar.

---

### 4.3 PR#3 components

#### `ProfileGymScreen`

**Path**: `lib/features/profile/presentation/profile_gym_screen.dart`
**Type**: `ConsumerStatefulWidget` (local pending selection state)
**Constructor**: `const ProfileGymScreen({super.key})`

**Subscriptions**:
- `ref.watch(userProfileProvider).valueOrNull?.gymId` → currentGymId (highlight)
- `ref.watch(filteredGymsProvider)` → search-filtered list (REUSES `lib/features/profile_setup/application/profile_setup_providers.dart` provider — no duplication)
- `ref.read(userRepositoryProvider)` for save

**Local state**: `String? _pendingGymId` (null until user selects; initialized to currentGymId on first build).

**Save**: `await ref.read(userRepositoryProvider).update(uid, {'gymId': _pendingGymId})` → pop. `userProfileProvider` stream re-emits → avatar card chip + CUENTA tile subtitle refresh automatically.

**Reused**:
- `filteredGymsProvider` / `gymSearchQueryProvider` — verbatim from profile_setup
- `GymCard` widget from `lib/features/profile_setup/presentation/widgets/gym_card.dart`

**Test surface**: list renders, search filters, tap selects, save fires `UserRepository.update({'gymId': ...})`, save disabled when no change.

---

#### `ProfileRoutinesScreen`

**Path**: `lib/features/profile/presentation/profile_routines_screen.dart`
**Type**: `ConsumerWidget`
**Constructor**: `const ProfileRoutinesScreen({super.key})`

**Subscriptions**:
- `ref.watch(authStateChangesProvider).valueOrNull?.uid` → `myUid`
- `ref.watch(assignedRoutinesProvider(myUid ?? ''))` → `AsyncValue<List<Routine>>`

**Render**: `AsyncValue.when`:
- `loading` → `Center(CircularProgressIndicator(palette.accent))`
- `error` → `Center(Text("No pudimos cargar tus rutinas. Intentá de nuevo.", textMuted))`
- `data([])` → `Center(Text("Tu PF todavía no te asignó ninguna rutina.", textMuted))`
- `data(list)` → `ListView.separated(padding horizontal 20 vertical 14, itemCount, separator SizedBox(height: 12), builder → RoutineCard(routine: list[i]))`

**Tap on RoutineCard**: `context.push('/workout/routine/${routine.id}')` (existing route — bottom bar visible, detail screen).

**Reused**: `RoutineCard` from `lib/features/workout/presentation/widgets/routine_card.dart`.

**Test surface**: loading/error/empty/data states render correctly, tile tap pushes routine detail.

---

#### NEW providers (PR#3)

**Path**: `lib/features/profile/application/assigned_routines_providers.dart`

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/workout_providers.dart' show routineRepositoryProvider;
import '../../workout/domain/routine.dart';

/// Live list of trainer-assigned routines for [uid].
///
/// Backed by [RoutineRepository.listAssignedTo] (one-shot Future — the
/// underlying query is `.get()`, not `.snapshots()`). Re-fetched each time
/// `/profile/routines` is opened because of `autoDispose`.
///
/// REQ-PSR-MIS-RUTINAS-001 — Mis rutinas filter is exactly
/// `source == 'trainer-assigned' AND assignedTo == myUid`, which is
/// the exact shape of [RoutineRepository.listAssignedTo].
final assignedRoutinesProvider =
    FutureProvider.autoDispose.family<List<Routine>, String>((ref, uid) {
  if (uid.isEmpty) return Future.value(const []);
  return ref.watch(routineRepositoryProvider).listAssignedTo(uid);
});

/// Synchronous count derived from [assignedRoutinesProvider]. Returns 0
/// during loading/error so the CUENTA tile subtitle "N activas" renders
/// without flicker. Mirrors the [pendingRequestCountProvider] pattern from
/// feed-friend-requests-inbox (ADR-FRI-007).
final assignedRoutinesCountProvider =
    Provider.autoDispose.family<int, String>((ref, uid) {
  return ref.watch(assignedRoutinesProvider(uid)).maybeWhen(
        data: (list) => list.length,
        orElse: () => 0,
      );
});
```

---

### 4.4 PR#4 components

#### `ProfileSettingsScreen` (real implementation, replaces PR#1 stub)

**Path**: `lib/features/profile/presentation/profile_settings_screen.dart`
**Type**: `ConsumerWidget`
**Constructor**: `const ProfileSettingsScreen({super.key})`

**Render**:
- `Column(children: [_SettingsHeader, Expanded(ListView)])`
- Header: back button + "AJUSTES" title (same pattern as other sub-screen headers)
- ListView:
  - `SizedBox(height: 18)`
  - `ProfileSectionTile(icon: TreinoIcon.signOut, title: "Cerrar sesión", onTap: () => ref.read(authNotifierProvider.notifier).signOut())`
  - `ProfileSectionTile(icon: TreinoIcon.trash, title: "Eliminar cuenta", destructive: true, onTap: () => _showEliminarCuentaSheet(context))`

**Reused**: `ProfileSectionTile` (same widget as CUENTA section).

**Test surface**: both tiles render, "Cerrar sesión" calls `authNotifierProvider.notifier.signOut`, "Eliminar cuenta" opens sheet.

---

#### `EliminarCuentaStubSheet`

**Path**: `lib/features/profile/presentation/widgets/eliminar_cuenta_stub_sheet.dart`
**Type**: `StatelessWidget`
**Constructor**: `const EliminarCuentaStubSheet({super.key})`

**Render**:
- `Padding(EdgeInsets.fromLTRB(20, 14, 20, 20))`
- `Column(mainAxisSize.min, children: [dragHandle, SizedBox(18), title, SizedBox(8), body, SizedBox(20), cancelPill])`
  - Drag handle: `Container(width: 40, height: 4, color: palette.border)` centered
  - Title: `Text("Eliminar cuenta", barlowCondensed w700 fontSize 18 color palette.danger)`
  - Body: `Text("Esta función estará disponible en una versión futura.", barlow fontSize 14 color palette.textMuted, textAlign center)`
  - Cancel pill: full-width, outlined, `palette.border` border, label `"CANCELAR"` (barlowCondensed w700 13 letterSpacing 1.0), onPressed `Navigator.pop(context)`

**No destructive button** (per proposal locked decision #8). This is a copy-only stub.

**Invocation pattern** (from ProfileSettingsScreen):
```dart
await showModalBottomSheet<void>(
  context: context,
  backgroundColor: palette.bgCard,
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
  ),
  builder: (_) => const EliminarCuentaStubSheet(),
);
```

**Test surface**: renders title + body + CANCELAR pill, tap CANCELAR pops sheet, NO destructive button exists.

---

#### Cleanup (PR#4)

- `lib/features/profile/profile_screen.dart` — remove the `Expanded(Center(Column(... TextButton(signOut) ...)))` block that was kept through PR#1-#3. The body becomes a clean `Column([ProfileHeader, _OwnProfileStatsRow, ProfileAvatarCard, ProfileCuentaSection])`.
- Drop the `auth_strings.dart` import (`AuthStrings.profileSignOut`) from `profile_screen.dart`. The string "Cerrar sesión" lives in the Settings tile now, hardcoded (per ADR-PSR-007 i18n strategy).

---

## 5. Solicitudes tile relocation strategy (resolves risk #3)

**Decision: refactor (option b)** — inline the count subscription into the new `ProfileCuentaSection.ProfileSectionTile.solicitudes` and **delete** `ProfileFriendRequestsTile` + its dedicated widget test.

**Rationale**:
- The legacy `ProfileFriendRequestsTile` was a one-off styling that does not fit the CUENTA section visual rhythm (different padding, no subtitle support, different icon size — see `lib/features/profile/presentation/widgets/profile_friend_requests_tile.dart:31-36`). Reusing it AS-IS would break visual uniformity across the 5 tiles.
- The "count derivation" logic is one line: `ref.watch(pendingRequestCountProvider(myUid ?? ''))`. There is no real code to preserve; inlining loses nothing.
- The behavior contract (always visible, count = 0 during loading, navigates to `/profile/friend-requests`) is preserved verbatim by the new tile.

**Migration plan** (executed in PR#1):
- Delete `lib/features/profile/presentation/widgets/profile_friend_requests_tile.dart`.
- Delete `test/features/profile/presentation/widgets/profile_friend_requests_tile_test.dart`.
- Migrate the assertions into a new test file `test/features/profile/presentation/widgets/profile_cuenta_section_test.dart` that covers all 5 tiles. The behavioral coverage (renders count, navigates to `/profile/friend-requests`, count 0 fallback) is preserved — just under a different test owner.
- Remove the `ProfileFriendRequestsTile` import from `lib/features/profile/profile_screen.dart`.

**Verification gate**: after PR#1, `flutter test` MUST still pass the assertions migrated from the old file (now in the new `profile_cuenta_section_test.dart`). If any scenario from the old test file isn't covered by the new one, PR#1 fails its quality gate.

This decision is locked as **ADR-PSR-003**.

---

## 6. @handle derivation pattern

### API

**Path**: `lib/core/utils/handle_derivation.dart`

```dart
/// Derives a public `@handle` from a [displayName].
///
/// Algorithm:
///   1. Returns `"sin_handle"` if [displayName] is null/empty/whitespace-only.
///   2. Trims surrounding whitespace.
///   3. Lowercases.
///   4. Collapses internal whitespace runs to a single dot.
///   5. Preserves accents and Unicode letters (Rioplatense names — "Núñez",
///      "Iñaki" — render with their natural diacritics in the @handle).
///   6. Strips characters that are NOT Unicode letter, digit, dot, or
///      underscore (e.g. apostrophes, hyphens, emojis). They are dropped,
///      NOT replaced — so "O'Brien" → "@obrien", not "@o.brien".
///   7. Collapses consecutive dots to a single dot, then trims leading/
///      trailing dots.
///
/// The result is NOT persisted anywhere — it is a presentation-layer
/// derivation called on each render of [ProfileAvatarCard]. If the user
/// edits their display name, the next stream emit from [userProfileProvider]
/// triggers a re-derivation on the next build.
///
/// REQ-PSR-HANDLE-001.
String deriveHandle(String? displayName) { ... }
```

### Expected outputs

| Input | Output | Notes |
|---|---|---|
| `"Ana Núñez"` | `"@ana.núñez"` | accents preserved |
| `"María José Pérez"` | `"@maría.josé.pérez"` | multi-word collapse to dots |
| `"  Juan  Pablo  "` | `"@juan.pablo"` | trim + whitespace collapse |
| `"O'Brien"` | `"@obrien"` | apostrophe stripped (not replaced with dot) |
| `"Anna-Maria"` | `"@annamaria"` | hyphen stripped |
| `null` | `"@sin_handle"` | null fallback |
| `""` | `"@sin_handle"` | empty fallback |
| `"   "` | `"@sin_handle"` | whitespace-only fallback |
| `"Pibe 💪"` | `"@pibe"` | emoji stripped |
| `"123 Ana"` | `"@123.ana"` | digits allowed (Unicode digit class) |
| `"...Ana..."` | `"@ana"` | leading/trailing dots trimmed |

### Notes on rendering

`ProfileAvatarCard` prepends the literal `@` in the Text widget, NOT inside `deriveHandle`, so the function is a pure body that downstream consumers can wrap differently (e.g. PublicProfileScreen might one day prepend a different prefix). The fallback `"sin_handle"` is intentionally without the `@` for the same reason — the caller composes the prefix.

### Test surface

`test/core/utils/handle_derivation_test.dart` — one test per row of the table above, plus an `equals` golden of the full mapping. No widget tests needed for the pure function.

This decision is locked as **ADR-PSR-001**.

---

## 7. Rules Audit (resolves risk #4)

Audited against the **current** `firestore.rules` (read at design time). Every op this SDD performs is already covered.

| Op | Caller | Required rule | Status |
|---|---|---|---|
| READ `users/{uid}` | `userProfileProvider` → `UserRepository.watch(uid)` (`.snapshots()`) | owner-only read on `users/{uid}` — `request.auth.uid == uid` | EXISTS — used by ProfileScreen since Fase 1 Etapa 7 |
| UPDATE `users/{uid}` (displayName, gender, weight, height, experienceLevel, avatarUrl, bornAt) | `UserRepository.update(uid, partial)` from ProfileEditPersonalScreen save | owner-only update on `users/{uid}` with immutable field guards (`uid`, `role`, `email`, `createdAt`) | EXISTS — proven in production by ProfileSetup since Fase 1 Etapa 6 |
| UPDATE `users/{uid}` (gymId only) | `UserRepository.update(uid, {'gymId': ...})` from ProfileGymScreen save | same owner-only update on `users/{uid}` | EXISTS — same rule, same path |
| DUAL-WRITE `userPublicProfiles/{uid}` (displayName, avatarUrl, gymId, displayNameLowercase) | `UserRepository.update` `WriteBatch` (lines 248-256 of user_repository.dart) | owner-only update on `userPublicProfiles/{uid}` with required uid+displayNameLowercase derivation enforced | EXISTS — proven in production since wire-real-stats PR#3 |
| UPLOAD avatar to Storage `avatars/{uid}.jpg` | `AvatarUploadService.upload(localPath)` from ProfileEditPersonalScreen | owner-only Storage write on `avatars/{uid}.*` (storage.rules, Etapa 6) | EXISTS — used by ProfileSetup step 1 in production |
| READ `routines` where `assignedTo == myUid && source == 'trainer-assigned'` ORDER BY `createdAt DESC` LIMIT 20 | `RoutineRepository.listAssignedTo(myUid)` from ProfileRoutinesScreen + assignedRoutinesCountProvider | per-doc visibility rule on `routines` (`resource.data.visibility == 'private' && resource.data.assignedTo == request.auth.uid`) + composite index `routines(assignedTo, source, createdAt DESC)` | EXISTS — declared in `firestore.indexes.json` and proven in production by coach-plans-mobile + Coach Hub assigned-plans grid |
| READ `pendingRequestsStreamProvider` for Solicitudes tile count | unchanged from feed-friend-requests-inbox | unchanged | EXISTS |
| ~~READ `userSessionStatsProvider` for Historial tile subtitle~~ | **REMOVED 2026-05-27** — Historial tile excluded from scope | — | n/a |
| SIGN OUT | `authNotifierProvider.notifier.signOut()` from Settings tile | n/a (auth, not Firestore) | EXISTS |

### Verdict

**Zero `firestore.rules` changes. Zero `firestore.indexes.json` changes. Zero `storage.rules` changes.**

This audit explicitly checks every op against the current rules, avoiding the trap of the `wire-real-stats` #66 hotfix where a missing rule for `routines.create` surfaced only at runtime. The proposal's assumption that this SDD is rules-clean is **confirmed**.

---

## 8. Copy table — es-AR baseline (resolves risk #5)

All strings are Rioplatense Spanish, hardcoded in the widget source with the marker comment `// i18n: Fase 6 Etapa 3` adjacent to each string literal so the localización sweep can grep `'i18n: Fase 6'` to find every entry.

This table is the **source-of-truth** for the ARB file content when Fase 6 Etapa 3 lands.

### ProfileScreen / ProfileHeader

| Context | String | Style notes |
|---|---|---|
| Header eyebrow | `"TU CUENTA"` | UPPERCASE Barlow Condensed w700 12pt letterSpacing 1.4 textMuted |
| Header title | `"PERFIL"` | UPPERCASE Barlow Condensed w700 28pt letterSpacing 1.2 textPrimary |
| Gear icon tooltip / a11y label | `"Abrir ajustes"` | Semantics label |

### ProfileAvatarCard

| Context | String | Style notes |
|---|---|---|
| Display name fallback (null) | `"Sin nombre"` | sentence case, barlowCondensed w700 20pt textPrimary |
| @handle prefix | `"@"` | literal — see §6 for the derivation that follows |
| @handle null fallback | `"@sin_handle"` | see §6 fallback table |
| Gym chip "no gym" fallback | (omit chip — render nothing) | per §4.1 spec |
| Pencil tooltip / a11y label | `"Editar perfil"` | Semantics label |

### ProfileCuentaSection — header

| Context | String | Style notes |
|---|---|---|
| Section header | `"CUENTA"` | UPPERCASE Barlow Condensed w700 12pt letterSpacing 1.4 textMuted |

### ProfileCuentaSection — 5 tiles (in order)

| # | Title | Subtitle | Subtitle dynamic? |
|---|---|---|---|
| 1 | `"Solicitudes de amistad"` | `"$count nuevas"` when count > 0; null when count == 0 | yes, from `pendingRequestCountProvider` |
| 2 | `"Datos personales"` | `"Editá tu info"` | no, voseo |
| 3 | `"Gimnasio"` | `gymNameFromId(gymId)` if set; `"Sin gym"` otherwise | yes, from `userProfileProvider` |
| 4 | `"Mis rutinas"` | `"$n activas"` (always shown, "0 activas" is valid) | yes, from `assignedRoutinesCountProvider` |
| ~~5~~ | ~~`"Historial"`~~ | — | **REMOVED 2026-05-27** — Historial tile excluded from scope |

### ProfileEditPersonalScreen

| Context | String | Style notes |
|---|---|---|
| Screen title | `"EDITAR PERFIL"` | UPPERCASE Barlow Condensed w700 |
| Avatar editor caption | `"Tocá para cambiar tu foto"` | barlow 12pt textMuted, voseo |
| Display name label | `"NOMBRE"` | UPPERCASE label barlowCondensed w700 12pt textMuted |
| Display name hint | `"Tu nombre"` | barlow 14pt textMuted |
| Display name validation: empty | `"Ingresá un nombre"` | barlow 12pt danger, voseo |
| Display name validation: too long | `"Máximo 50 caracteres"` | barlow 12pt danger |
| Gender label | `"GÉNERO"` | UPPERCASE label |
| Gender option male | `"HOMBRE"` | UPPERCASE Barlow Condensed |
| Gender option female | `"MUJER"` | UPPERCASE Barlow Condensed |
| Gender option other | `"OTRO"` | UPPERCASE Barlow Condensed |
| Body weight label | `"PESO (KG)"` | UPPERCASE label |
| Body weight validation: out of range | `"Ingresá un peso entre 30 y 300 kg"` | barlow 12pt danger, voseo |
| Body weight validation: non-numeric | `"Ingresá un número válido"` | barlow 12pt danger, voseo |
| Height label | `"ALTURA (CM)"` | UPPERCASE label |
| Height validation: out of range | `"Ingresá una altura entre 120 y 230 cm"` | barlow 12pt danger, voseo |
| Height validation: non-numeric | `"Ingresá un número válido"` | barlow 12pt danger, voseo |
| Experience label | `"EXPERIENCIA"` | UPPERCASE label |
| Experience option beginner | `"PRINCIPIANTE"` | UPPERCASE Barlow Condensed |
| Experience option intermediate | `"INTERMEDIO"` | UPPERCASE Barlow Condensed |
| Experience option advanced | `"AVANZADO"` | UPPERCASE Barlow Condensed |
| Save button | `"GUARDAR"` | UPPERCASE pill, mint-filled, barlowCondensed w700 13pt letterSpacing 1.0 |
| Discard button | `"DESCARTAR"` | UPPERCASE pill, outlined-muted, same geometry |
| Discard confirmation title | `"¿Descartar los cambios?"` | sentence case, voseo |
| Discard confirmation body | `"Lo que editaste se va a perder."` | sentence case, voseo |
| Discard confirmation cancel | `"VOLVER"` | UPPERCASE pill outlined |
| Discard confirmation confirm | `"DESCARTAR"` | UPPERCASE pill, danger-filled |
| Avatar upload error SnackBar | `"No pudimos subir tu foto. Probá de nuevo."` | sentence case, voseo |
| Save error SnackBar | `"No pudimos guardar los cambios. Probá de nuevo."` | sentence case, voseo |

### ProfileGymScreen

| Context | String | Style notes |
|---|---|---|
| Screen title | `"GIMNASIO"` | UPPERCASE |
| Search hint | `"Buscar gym"` | sentence case, barlow 14pt textMuted (reuses profile_setup wording verbatim) |
| Otro / sin gym card name | `"OTRO GYM / SIN GYM"` | UPPERCASE (reuses profile_setup card verbatim) |
| Otro / sin gym card address | `"No registramos tu gimnasio"` | (reuses profile_setup wording verbatim) |
| Save button | `"GUARDAR"` | UPPERCASE pill mint-filled |
| Save error SnackBar | `"No pudimos guardar el gimnasio. Probá de nuevo."` | voseo |

### ProfileRoutinesScreen

| Context | String | Style notes |
|---|---|---|
| Screen title | `"MIS RUTINAS"` | UPPERCASE |
| Empty state | `"Tu PF todavía no te asignó ninguna rutina."` | sentence case, barlow 14pt textMuted, voseo |
| Error state | `"No pudimos cargar tus rutinas. Intentá de nuevo."` | sentence case, voseo |

### ProfileSettingsScreen

| Context | String | Style notes |
|---|---|---|
| Screen title | `"AJUSTES"` | UPPERCASE Barlow Condensed |
| Sign-out tile title | `"Cerrar sesión"` | sentence case, barlowCondensed w700 16pt textPrimary |
| Eliminar cuenta tile title | `"Eliminar cuenta"` | sentence case, destructive (danger color) |
| Eliminar cuenta sheet title | `"Eliminar cuenta"` | sentence case, barlowCondensed w700 18pt danger |
| Eliminar cuenta sheet body | `"Esta función estará disponible en una versión futura."` | sentence case, barlow 14pt textMuted |
| Eliminar cuenta sheet cancel | `"CANCELAR"` | UPPERCASE pill outlined-muted, barlowCondensed w700 13pt letterSpacing 1.0 |

### Deviations from proposal copy

- Proposal said Eliminar cuenta sheet copy is `"Próximamente en Fase 6"`. We pick `"Esta función estará disponible en una versión futura."` because it is non-leaky (does not reference internal phase labels visible to end users) and matches the tone of comparable destructive-action placeholders in iOS apps. The proposal's reviewer-facing label `"Próximamente en Fase 6"` was metadata, not final UI copy.
- Proposal said Mis rutinas subtitle is `"(N activas)"` with parentheses; we drop the parens to match the visual rhythm of the other subtitles (none use parens — see Gimnasio `"Smart Fit Palermo"`).

---

## 9. ADR table

| ID | Decision | Rationale | Rejected alternatives |
|---|---|---|---|
| **ADR-PSR-001** | `@handle` is derived on-the-fly via a pure function in `lib/core/utils/handle_derivation.dart`, NOT persisted on `UserProfile` | Persisting `@handle` introduces a migration burden for every existing user, a uniqueness constraint we are not ready to enforce, and a rename UX (`@handle` history) we have no design for. Derivation gives us the user-recognition benefit (display name → predictable handle) without any of these costs. Locked decision #3. | (a) Add `handle` field to `UserProfile` + backfill migration: 4× more work, requires uniqueness enforcement at the rules layer, and locks us into a specific algorithm. Rejected. (b) Generate `@handle` on signup, store it, allow rename: full feature, out of Fase 3 Etapa 7 scope. Deferred to a possible future SDD. |
| **ADR-PSR-002** | "Mis rutinas" filter scope is exactly `source == 'trainer-assigned' AND assignedTo == myUid` (one-shot Future, NOT stream) | Matches the user's mental model: "Mis rutinas" = "lo que mi PF me asignó". Saved-favorite plantillas have their own UX surface (the Plantillas section in `/workout`); mixing them in "Mis rutinas" would confuse the boundary. Locked decision #6. Reuses `RoutineRepository.listAssignedTo` (proven in production by Coach Hub). Future SDD can promote to a streaming variant if a "new routine assigned" notification appears. | (a) Include self-created routines: out of scope, breaks the "Mis rutinas = lo que mi PF me asignó" semantics. (b) Include saved-favorite plantillas: duplicates Plantillas section's purpose. (c) Stream the list from day one: requires touching `RoutineRepository` (out of scope), and the screen is opened transiently — Future is sufficient. |
| **ADR-PSR-003** | Refactor (not reuse): delete `ProfileFriendRequestsTile`, inline the count subscription into the CUENTA section's `ProfileSectionTile.solicitudes`, migrate the test assertions into `profile_cuenta_section_test.dart` | Visual uniformity across the 5 CUENTA tiles is a non-negotiable mockup parity requirement; the legacy tile uses different padding/icon-size and lacks subtitle support. The "count derivation" is one line — there is no real code to preserve. Test coverage is migrated, not lost. See §5 for the migration plan. | (a) Reuse `ProfileFriendRequestsTile` as-is inside the CUENTA section: visual inconsistency with the other 4 tiles, requires retrofitting subtitle support → more LOC than the refactor. Rejected. (b) Keep both tiles (legacy outside CUENTA + new inside CUENTA): two paths to the same screen, contradicts locked decision #7. Rejected. |
| **ADR-PSR-004** | Chain integrity protocol: each PR is independently mergeable AND independently revertible. The 4 PRs are a strict sequence — PR#N+1 rebases on PR#N's merge commit. The chain MUST progress (cannot stop at PR#2 mid-quarter) | Without this rule, stub destinations in PR#1 ("Próximamente en PR#2") would ship to production as a permanent UX defect. The rule says: opening the PR#1 chain commits the team to merging all 4 within the same sprint. Tracked via `chain:incomplete` label until PR#4 lands. | (a) Single 1350-LOC PR: violates the 400-LOC review budget, would require a `size:exception` we explicitly rejected (proposal §"Delivery strategy"). Rejected. (b) Land PR#1 only and defer PR#2-#4 to a separate quarter: ships stub destinations indefinitely. Rejected as a worse UX defect than the original placeholder. |
| **ADR-PSR-005** | Avatar pencil and "Datos personales" CUENTA tile BOTH navigate to `/profile/edit-personal` — single shared edit surface | The mockup's edit-personal screen already exposes the avatar editor as its first field. A separate avatar-only flow would duplicate UI for zero gain, and a second route adds maintenance burden. Locked decision #9. | (a) Separate `/profile/edit-avatar` route with just the image picker: 2× screens to maintain, breaks DRY, no UX win. Rejected. (b) Inline avatar picker as a bottom sheet from ProfileScreen body: feels lightweight but the mockup shows a full edit-personal surface — the user expects to land there. Rejected. |
| **ADR-PSR-006** | "Eliminar cuenta" is a copy-only UI stub (`EliminarCuentaStubSheet`) — no destructive button, no callable code path | Real account deletion needs a privileged Cloud Function for cascade cleanup (sessions, friendships, posts, routines, public profile, trainer link, etc.) — out of Fase 3 Etapa 7 scope. Locked decision #8. The stub gives users discoverability ("the option exists") without the cliff. | (a) Hide the tile entirely until Fase 6: hurts discoverability — users will assume the app cannot delete their data, which is a regulatory red flag (DNDA / GDPR). Rejected. (b) Wire it to `UserRepository.delete`: that method explicitly throws `UnsupportedError` (lines 278-282 of user_repository.dart) for exactly this reason. Cannot ship. (c) Add a destructive "Eliminar" button that no-ops: trains the user to expect destruction; first-tap-no-effect is a worse trust signal than "coming soon". Rejected. |
| **ADR-PSR-007** | All new es-AR strings are hardcoded inline with `// i18n: Fase 6 Etapa 3` marker comments. Full copy lives in §8 of this design as the source-of-truth for the ARB sweep | Setting up ARB for this SDD alone would require importing `flutter_localizations`, configuring `MaterialApp.locale`, and creating the codegen pipeline — a Fase 6 Etapa 3 deliverable, not a Fase 3 line item. The marker comment makes the Fase 6 sweep mechanical: `rg "i18n: Fase 6"` finds every string. The design.md table becomes the authoritative spec for the ARB file content. | (a) Spin up partial ARB infra for just these strings: forces a half-implemented localization pipeline that Fase 6 has to undo and redo. Rejected. (b) Defer the strings to Fase 6 (ship with placeholders / Lorem Ipsum): blocks shipping the screen rewrite. Rejected. |
| **ADR-PSR-008** | The legacy "Cerrar sesión" `TextButton` stays in `ProfileScreen` body through PR#1, PR#2, PR#3. PR#4 removes it the same commit that the real Settings tile ships | The user's only sign-out path cannot disappear mid-chain. The duplication window is 3 PRs (worst case ≈ 2 weeks of stacked review). Removing the legacy button in PR#1 and shipping a stub Settings screen would mean any beta tester who needs to log out during the chain transition is locked out until PR#4 merges. Intentional, scoped, removed-by-PR#4. | (a) Remove the legacy button in PR#1, leave the Settings stub as the only sign-out: breaks sign-out for the 2-week chain window. Rejected. (b) Move sign-out to Settings in PR#1 with a real Settings screen: that is PR#4's scope — would conflate the chain. Rejected. (c) Leave the legacy button forever: contradicts locked decision #8 (Settings minimal MVP includes Cerrar sesión as its primary tile). Rejected. |
| **ADR-PSR-009** | Route topology: the 4 new sub-routes register inside the existing `/profile` GoRoute as additional `routes:` siblings of the existing `friend-requests` child. All inside ShellRoute → bottom bar visible | The `/profile` GoRoute already declared the `routes:` pattern in Fase 3 Etapa 6 — we extend the existing list rather than redefining the parent. Zero collision risk with `/profile/friend-requests`. ShellRoute placement matches every other in-shell sub-route (`/feed/profile/:uid`, `/coach/athlete/:athleteId`) and matches the proposal's "stay within the profile context" UX intent. See §3 for the final code snippet. | (a) Register the 4 routes as top-level (outside ShellRoute): hides the bottom bar — overkill for non-immersive edit surfaces. Rejected. (b) Create a nested ShellRoute for `/profile/*`: over-engineering — no shared chrome justifies it. Rejected. |
| **ADR-PSR-010** | **REVISED 2026-05-27** — Historial tile EXCLUDED from CUENTA section entirely. CUENTA renders 4 tiles (Solicitudes / Datos personales / Gimnasio / Mis rutinas) instead of 5 | Initial design proposed sending the Historial tile to `/workout` (Workout tab) because no dedicated historial listing route exists. User decided (2026-05-27) that shipping a tile that drops the user on the wrong screen and forces scroll is worse than not shipping the tile. Athletes continue to access history via Workout tab → HistorialSection (existing flow, no regression). Future SDD owns both the dedicated `/workout/historial-list` route AND the Historial tile in CUENTA — both deliverables go together to avoid the same sub-optimal-UX trap. | (a) `/workout` cross-tab navigation: shipped a tile that lands on the wrong content. Rejected. (b) Build dedicated route now: out of scope (workout feature, not profile). Rejected. (c) `/profile/historial` mirror: duplicates section logic, breaks DRY. Rejected. |
| **ADR-PSR-011** | Reuse `filteredGymsProvider`, `gymSearchQueryProvider`, and `GymCard` from `lib/features/profile_setup/*` verbatim in `ProfileGymScreen` — no extraction to a shared module | A shared `gym_catalog` feature is premature abstraction with two consumers. The profile_setup providers are stable (no churn since Fase 1 Etapa 6), and cross-feature imports are acceptable per the project's import-discipline rules (profile may import profile_setup). When a third consumer appears (e.g. Coach Hub gym filter), extract to `core/gym_catalog/`. | (a) Extract to `lib/core/gym_catalog/` now: premature abstraction with no proven third consumer. Rejected. (b) Duplicate the hardcoded gym list inside profile: 2× copies to keep in sync, regression-prone. Rejected. |
| **ADR-PSR-012** | `ProfileSectionTile` is a shared widget used by BOTH `ProfileCuentaSection` (5 tiles) AND `ProfileSettingsScreen` (2 tiles) — 7 consumers from day one | Two surfaces × shared visual contract = real DRY. Settings tile geometry is identical to CUENTA tile geometry per the mockup — same padding, same icon size, same chevron. Inlining each surface separately would duplicate ~40 LOC. The `destructive: true` flag handles the only variant (Eliminar cuenta). | (a) Two separate tile widgets (one for CUENTA, one for Settings): 2× LOC, drift risk over time. Rejected. (b) Inline Container styling at every callsite: 7× duplication, breaks visual uniformity if styling evolves. Rejected. |
| **ADR-PSR-013** | `assignedRoutinesProvider` is `FutureProvider.autoDispose.family<List<Routine>, String>` backed by `RoutineRepository.listAssignedTo`. The count provider derives `.length` from the list provider — single Firestore round-trip per `/profile` mount | The underlying repo method is a one-shot `.get()`, not `.snapshots()`. Promoting to stream is out of scope (touches workout feature). `autoDispose` means each `/profile` mount triggers a fresh fetch — tolerable staleness for a subtitle. Sibling providers (list + count) share the same Future so the count tile and the routines screen do not double-fetch. | (a) Add a streaming variant `watchAssignedTo`: out of scope. (b) Cache without `autoDispose`: leaks across sessions, never refreshes. (c) Two separate Futures (count + list): doubles Firestore reads when the user opens the screen after seeing the count on /profile. Rejected. |
| **ADR-PSR-014** | Edit form save uses `userProfileProvider`'s stream re-emission to refresh the avatar card — NO `ref.invalidate` in the save handler | `userProfileProvider` is already a `StreamProvider` backed by `UserRepository.watch(uid)` (`.snapshots()`). Firestore commits to `users/{uid}` trigger a new snapshot, which Riverpod propagates, which rebuilds the avatar card on the next frame. Manual invalidation is unnecessary and would risk double-fire races. This is the same pattern locked by ADR-FRI-001 (feed-friend-requests-inbox) — `.snapshots()` + stream is enough. | (a) Manual `ref.invalidate(userProfileProvider)` in save handler: redundant, risks race with the stream emit. Rejected. (b) Switch `userProfileProvider` to `FutureProvider` + manual invalidation: regression from current Stream behavior. Rejected. |

---

## 10. Risks → tasks must address

These are the items the `sdd-apply` phase MUST explicitly handle. Risk-numbering picks up where the proposal left off — no overlap with proposal risks.

1. **Existing `ProfileFriendRequestsTile` test compatibility** (proposal risk #5 → resolved by ADR-PSR-003). Apply must DELETE the legacy widget + its test file, and CREATE `profile_cuenta_section_test.dart` covering all behavioral assertions from the old file (renders count, navigates to `/profile/friend-requests`, count=0 fallback, count>0 rendering). PR#1 quality gate fails if any old assertion is unmigrated.

2. **`userProfileProvider` reactivity in edit form save → avatar card refresh**. Apply must add a widget test for ProfileEditPersonalScreen that: (a) seeds `userProfileProvider` with initial UserProfile, (b) triggers save with edited displayName, (c) pumps a frame, (d) verifies the parent ProfileAvatarCard rebuilds with the new name — proving the stream re-emission works end-to-end without `ref.invalidate`.

3. **`RoutineRepository.listAssignedTo` signature audit** (DONE in this design — see §4.3). The method exists at `lib/features/workout/data/routine_repository.dart:45` with signature `Future<List<Routine>> listAssignedTo(String athleteId)`. Apply must NOT modify this method; `assignedRoutinesProvider` consumes it as-is.

4. **Gym catalog reuse cross-feature import** (resolved by ADR-PSR-011). Apply must import `filteredGymsProvider` / `gymSearchQueryProvider` / `GymCard` from `lib/features/profile_setup/*` directly. The import discipline rule (`profile` may import `profile_setup` for shared catalog widgets) is enforced by the existing `dart analyze` config; apply must verify zero new analyzer warnings.

5. **Avatar upload helper reuse** (resolved by §4.2 + ADR-PSR-005). `AvatarUploadService` already exists at `lib/features/profile_setup/data/avatar_upload_service.dart:12`. `avatarUploadServiceProvider` already exists at `lib/features/profile_setup/application/profile_setup_providers.dart:43`. Apply must consume both verbatim — no new upload service.

6. **Sign-out flow during chain transition** (resolved by ADR-PSR-008). Apply must keep the legacy `TextButton(signOut)` in `lib/features/profile/profile_screen.dart` body during PR#1, PR#2, PR#3 — verbatim from current code (lines 42-49). PR#4 removes it in the same diff that ships the real `ProfileSettingsScreen` with the new sign-out tile. The smoke validation for each PR explicitly verifies sign-out works (per proposal §"Smoke validation").

7. **`TreinoIcon.settings` gap** (NEW risk — discovered during this design). `TreinoIcon` (lib/core/widgets/treino_icon.dart) does NOT expose a gear/settings icon. PR#1 MUST add `static const IconData settings = PhosphorIconsRegular.gearSix;` to `TreinoIcon` BEFORE `ProfileHeader` references it. Project rule: NEVER use `PhosphorIcons.X` directly (see CLAUDE.md Quick reference). Apply must include this 1-line addition in PR#1 as part of the header scaffold.

8. ~~**Historial tile destination correctness**~~ — **RESOLVED 2026-05-27 by scope reduction.** Historial tile is excluded from CUENTA section entirely per revised ADR-PSR-010. No destination to wire; no cross-tab navigation to verify. Future SDD that introduces the dedicated historial route also introduces the tile.

9. **PR#1 stub screens must include a working back button**. Each stub screen (edit-personal, gym, routines, settings) renders a minimal header with a back button (TreinoIcon.back + context.pop) so the chain-transition UX is not a dead-end. The placeholder body says `"Próximamente en PR#N"` where N is the real-implementation PR (per §4.1).

10. **i18n marker comment placement** (resolved by ADR-PSR-007). Apply must add `// i18n: Fase 6 Etapa 3` comments adjacent to EVERY string literal listed in §8. The Fase 6 sweep relies on `rg "i18n: Fase 6"` to find them. Apply quality gate: `rg "i18n: Fase 6" lib/features/profile/` returns ≥ 1 hit per new file containing user-facing copy.

---

## 11. Test surface summary

Per `sdd-init/treino`, this project has **Strict TDD active**. Each new widget/provider listed in §4 has a corresponding `*_test.dart` per the structure:

```
test/
  core/utils/
    handle_derivation_test.dart                      [PR#1] — pure function, 11 scenarios from §6 table
  features/profile/
    application/
      assigned_routines_providers_test.dart          [PR#3] — list provider + count provider derivation
    presentation/
      profile_screen_test.dart                       [PR#1, updated PR#4]
      profile_edit_personal_screen_test.dart         [PR#2]
      profile_gym_screen_test.dart                   [PR#3]
      profile_routines_screen_test.dart              [PR#3]
      profile_settings_screen_test.dart              [PR#4]
      widgets/
        profile_header_test.dart                     [PR#1]
        profile_avatar_card_test.dart                [PR#1]
        profile_section_tile_test.dart               [PR#1]
        profile_cuenta_section_test.dart             [PR#1] — replaces deleted profile_friend_requests_tile_test.dart
        eliminar_cuenta_stub_sheet_test.dart         [PR#4]
```

The exact RED/GREEN sequencing per work unit is defined by `sdd-tasks` (next phase). Strict TDD means: write the failing test BEFORE the widget/provider that makes it pass, one work unit at a time, commit per work unit.

---

## 12. Out of scope confirmations (carried from proposal)

To prevent scope creep during apply:

- NO push notifications (Fase 6).
- NO i18n / ARB infrastructure (Fase 6 Etapa 3 — copy table in §8 is the spec).
- NO theme switcher (Fase 6).
- NO PREFERENCIAS section.
- NO real account deletion implementation — Eliminar cuenta is copy-only stub (ADR-PSR-006).
- NO `@handle` persistence — derivation-only (ADR-PSR-001).
- NO join date display.
- NO header notification bell — Solicitudes lives inside CUENTA only (locked decision #7).
- NO changes to `lib/features/coach/` or `lib/features/coach_hub/`.
- NO new Firestore collections.
- NO `firestore.rules`, `firestore.indexes.json`, or `storage.rules` changes (verified by §7).
- NO new freezed models.
- NO new packages.
