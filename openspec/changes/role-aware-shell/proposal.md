# Proposal — role-aware-shell

**Change name**: `role-aware-shell`
**Phase / Etapa**: Fase 5 · Etapa 5 (next slot — role-aware shell stabilization, after Etapa 4 `coach-plans-mobile`)
**Status**: ready for spec + design
**Date**: 2026-05-21

## Intent

After Etapa 4 (`coach-plans-mobile`), the trainer role exists in the data layer and in the Coach tab — but the rest of the app shell is still 100% athlete-shaped. Concretely:

- Trainer's INICIO tab shows the athlete home (streak card, "empezar entrenamiento", weekly stats).
- Trainer's ENTRENAR tab shows MiPlanSection / PlantillasSection / HistorialSection — irrelevant content; tapping EMPEZAR creates a workout session under the trainer's UID.
- Trainer's PERFIL tab shows athlete-only stats (SESIONES, VOLUMEN KG, RACHA) which are always zero for a trainer.
- Top-level routes `/workout/session/*`, `/workout/historial/*` are not role-guarded — a trainer can deep-link into athlete-only flows.
- The single trainer-only route reachable from the shell (`/workout/routine-editor/:athleteId`, used by Etapa 4 to assign plans) has no guard either.

The user-facing impact: a trainer signing into the mobile app today gets an experience that looks broken (zeroed stats, irrelevant tabs, the ability to start fake workouts). This is the last load-bearing UI gap before Etapa 5 (chat) starts piling more trainer-only surfaces on top.

**Success looks like**:
- A trainer opens the app and lands on a shell that shows 4 tabs (INICIO, FEED, COACH, PERFIL), each tab renders trainer-appropriate content, and they physically cannot reach athlete-only flows even by deep-link.
- An athlete sees exactly the same 5-tab shell they have today — zero regression.
- The pattern is consistent with the existing `CoachScreen` dispatch (`switch(role)` → AthleteX / TrainerX views), so future role-aware screens follow the same template.

## Scope

### IN scope (this change ships)

1. **Role-aware shell + bottom bar**
   - `_ShellScaffold` (in `lib/app/router.dart`) becomes a `ConsumerWidget` that reads `userProfileProvider.select((async) => async.valueOrNull?.role)`.
   - `TreinoBottomBar` accepts a tab list as a parameter (or derives it from role internally — design phase decides). It is no longer hardcoded to 5 tabs.
   - Trainer tab list: `['/inicio', '/feed', '/coach', '/profile']` (4 tabs — INICIO, FEED, COACH, PERFIL; ENTRENAR dropped).
   - Athlete tab list unchanged: `['/workout', '/feed', '/home', '/coach', '/profile']` (5 tabs).
   - Loading/null role → render the same neutral empty surface used by `_CoachLoadingView` (no spinner; cf. ADR-3 in CoachScreen). This avoids the "athlete tabs briefly visible to trainer" flicker.
   - Tab-index arithmetic in `_currentIndex` / `onTap` is computed from the active tab list (NOT from a hardcoded 5-element `_kTabs`).
   - **Note**: trainer INICIO routes to `/home` (same path) — keeps the route shared between roles; the screen dispatches per role. This avoids a parallel `/trainer-home` route.

2. **Trainer Home (`TrainerHomeView`)** — full screen, not a placeholder
   - `HomeScreen` becomes a role-dispatcher: `switch(role) { athlete → AthleteHomeView, trainer → TrainerHomeView, null → loading surface }`. Existing home content moves into `AthleteHomeView` unchanged.
   - `TrainerHomeView` content (v1):
     - **Header** — reuse `HomeHeader` (already accepts `UserProfile?` and shows the user's `displayName` if present; works for both roles).
     - **"Tus alumnos activos"** — card showing the active count derived from `trainerLinksStreamProvider` (already exists; filtered by `status == active`). Tap → `context.go('/coach')` (lands on the TrainerCoachView ALUMNOS tab via the existing `DefaultTabController` default).
     - **"Solicitudes pendientes"** — card showing the pending count from the same provider (filter `status == pending`). Hidden when count is zero. Tap → `context.go('/coach')` (lands on DASHBOARD tab — same surface where the pending list lives today).
   - Providers consumed: `userProfileProvider` (header), `trainerLinksStreamProvider` (both cards).
   - Loading/error: same patterns as `TrainerCoachView._DashboardTab` — spinner inside each card, friendly fallback text on error.
   - **No new data plumbing in this change** — every piece of content is backed by a provider that already exists. (A "Sesiones de hoy" widget would require new agenda data — defer to Etapa 6 Agenda.)

3. **Trainer Profile (`TrainerProfileView`)**
   - `ProfileScreen` becomes a role-dispatcher: `switch(role) { athlete → AthleteProfileView, trainer → TrainerProfileView, null → loading surface }`. Existing content (athlete stats row, PERFIL heading, sign-out button) moves into `AthleteProfileView` unchanged.
   - `TrainerProfileView` content (v1, **read-only**):
     - Hide `_OwnProfileStatsRow` (sessions/volume/streak are meaningless for a trainer).
     - Show a trainer-appropriate read-only block:
       - `trainerSpecialty` (e.g. "Hipertrofia, fuerza")
       - `trainerBio` (multi-line text)
       - `trainerMonthlyRate` (formatted as currency / "$ X / mes")
     - When any of these fields is null/empty: show a muted hint like "Tu PF te dejó configurar esto desde el Coach Hub" (these fields are not user-editable in the app today; they're written by Admin SDK or — eventually — by the Coach Hub web app in Etapa 7).
     - Keep PERFIL heading + sign-out button intact.
   - Providers consumed: `userProfileProvider` (single source).

4. **Route guards in `authRedirect`**
   - After the profile-completeness gate and before the "public-route → /home" redirect (the exact slot documented at lines 78–84 of `router.dart`):
     - If `role == trainer` and the location matches the **athlete-only path patterns**, redirect to `/coach`.
     - Athlete-only path patterns (BLOCKED for trainer):
       - `/workout` (the tab root itself — trainer has no ENTRENAR tab)
       - `/workout/routine/*` (athlete viewing a routine)
       - `/workout/exercise/*` (athlete viewing an exercise — verified: only `routine_detail_screen.dart` pushes this route, which is athlete flow)
       - `/workout/session/*` (session player — athlete-only mutation)
       - `/workout/historial/*` (athlete session history)
     - **Whitelist** (ALLOWED for trainer even though it lives under `/workout/`):
       - `/workout/routine-editor/*` (the plan editor used by trainer in Etapa 4 `coach-plans-mobile`)
   - **Redirect target**: `/coach` (the trainer's primary tab — semantically correct; same destination used today by the Coach view when a trainer interacts with the link UI). `/home` would also work but `/coach` is the trainer's mental "home base" until Etapa 8.
   - The guard uses the same `read(userProfileProvider)` pattern already present for the profile-completeness check, with the same `profileAsync.isLoading → return null` guard (so navigation isn't redirected mid-load and there's no flicker).
   - The reverse direction (athlete blocked from `/workout/routine-editor/*` or `/coach/athlete/*`) is **out of scope** here — the athlete UI doesn't expose entry points to those routes, and the additional defense-in-depth can land in a follow-up. Documented as a known gap.

### OUT of scope (deferred)

| Item | Reason | Suggested follow-up |
|---|---|---|
| Editable trainer fields (bio / specialty / monthly rate from the mobile app) | The trainer can't update these from the app yet. Adding edit UI here triples the surface of this change and blocks shipping. Today these are written by Admin SDK; soon by the Coach Hub web app (Fase 5 · Etapa 7). | Etapa 5 · stabilization-2 (mobile editor) OR Etapa 7 (Coach Hub) |
| Redesigning the Coach tab | Already done in Etapas 1–4. `AthleteCoachView` and `TrainerCoachView` work; no touch. | — |
| New trainer-only data (sesiones de hoy, broadcasts, leaderboards, advanced analytics) | Requires new collections / providers. Out of scope for a stabilization etapa. | Etapa 6 (Agenda) for sesiones de hoy; future etapas for the rest. |
| `sharedWithTrainer: bool` on `TrainerLink` | Cross-etapa tech debt flagged in the `coach-plans-mobile` archive. Required before Etapa 6 (Coach Hub) for the PF to see athletes' sessions. | Re-flagged here as a known cross-etapa dependency; not addressed in this change. |
| Refactoring `UserProfile` or role mechanics | Roles are immutable, schema is fine, role provider works. No reason to touch. | — |
| Athlete-side guards (block athlete from `/workout/routine-editor/*` and `/coach/athlete/*`) | UI doesn't expose entry points. Adding now bloats this change. | Defense-in-depth follow-up. |
| Widget tests for role dispatch parity | Existing `CoachScreen` dispatch isn't tested either — establish a convention in a dedicated tests-pass etapa. | Testing-pass etapa (post-Fase 5 close). |
| Reverse-role flicker on profile load | We mitigate by rendering an empty surface for `null` role, mirroring `_CoachLoadingView`. A real "skeleton shell" with placeholder tab silhouettes is design-bait — out of scope. | — |

## Approach summary

**Approach D (Hybrid) from explore** — refined with the 4 question answers:

```
┌─────────────────────────────────────────────────────────────────┐
│  authRedirect (router.dart)                                     │
│                                                                  │
│   profile loading? → return null   (no redirect, hold position) │
│   role == trainer ∧ location in athlete-only set                │
│                  ∧ location NOT in trainer-whitelist            │
│                  → redirect '/coach'                            │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  _ShellScaffold  (ConsumerWidget)                               │
│   reads role via userProfileProvider.select(role)               │
│   tabs = role == trainer ? _kTrainerTabs : _kAthleteTabs        │
│   bottomBar = TreinoBottomBar(tabs: tabs, current: i)           │
└─────────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│  HomeScreen / ProfileScreen                                     │
│   switch (role) {                                                │
│     athlete → AthleteXView   (existing content, lifted as-is)   │
│     trainer → TrainerXView   (new — small, read-only, reusing   │
│                               existing providers)               │
│     null    → empty surface  (no spinner — ADR-3 pattern)       │
│   }                                                              │
└─────────────────────────────────────────────────────────────────┘
```

**Why this approach**:
- Mirrors the proven `CoachScreen` template — the team already knows it and it has shipped in production.
- Defense-in-depth: even if a future refactor breaks the UI-level role check, the route guard still blocks deep-links.
- Minimum data plumbing. No new providers, no new repositories, no new Firestore queries. Reuses `userProfileProvider` and `trainerLinksStreamProvider`.
- Athlete code paths are unchanged — the athlete branch in every dispatcher receives the existing widget tree verbatim.

### Per-touchpoint summary (filled by design)

| Touchpoint | Reads | Renders for athlete | Renders for trainer |
|---|---|---|---|
| `_ShellScaffold` (router.dart) | `userProfileProvider.select(role)` | Bottom bar with 5 athlete tabs | Bottom bar with 4 trainer tabs |
| `TreinoBottomBar` | tab list (param) | 5-tab pill animation | 4-tab pill animation |
| `HomeScreen` | `userProfileProvider.select(role)` | `AthleteHomeView` = existing content (header + EmpezarEntrenamientoCard + EstaSemanaCard + resume-session listener) | `TrainerHomeView` (header + "Tus alumnos activos" + "Solicitudes pendientes") |
| `ProfileScreen` | `userProfileProvider.select(role)` | `AthleteProfileView` = existing (stats row + PERFIL heading + sign-out) | `TrainerProfileView` (no stats; trainer fields read-only + PERFIL heading + sign-out) |
| `authRedirect` | `userProfileProvider` (already read for profile-completeness gate) | unchanged | redirect to `/coach` if location matches athlete-only patterns |

## Risks

Carried from explore + propose-level additions. Top three first.

1. **Tab-index ↔ tab-list synchronization** (carried from explore). `_currentIndex` and `onTap` in `_ShellScaffold` are computed against `_kTabs`. With two tab lists (4 vs 5) and two index sets, off-by-one bugs are likely. Mitigation: design must pick **named-route lookup** (`tabs.indexWhere((path) => location.startsWith(path))`) instead of any positional arithmetic. The `TreinoBottomBar` pill highlight already uses `_items.length` for the `tabWidth` calculation, so it adapts naturally to 4 tabs — but `currentIndex` MUST be valid for the active list (i.e., `0 <= currentIndex < tabs.length`).

2. **Profile loading flicker / "athlete tabs visible to trainer briefly"** (carried from explore). On cold start, `userProfileProvider` is in `loading` state until the Firestore snapshot resolves. If `_ShellScaffold` renders before then, we have to pick a default. We propose: render the empty surface (no bottom bar, no body content) for `role == null`, matching `_CoachLoadingView`'s ADR-3 rationale. **Risk**: on slow connections, the trainer sees a blank screen for a few seconds. Mitigation: rely on the splash screen to keep the profile pre-loaded; design phase confirms whether `authRedirect`'s profile-completeness gate already covers this (it sets `return null` while loading, which means GoRouter holds at the previous location — typically `/splash` — so the shell never renders with a null role except in edge cases).

3. **Route guard ↔ profile-load race** (propose-level). The guard reads `userProfileProvider`. If a trainer cold-starts directly at `/workout` (e.g., via push notification or saved last-location), the guard fires before the profile loads, returns `null`, GoRouter holds, then the profile resolves and the guard re-fires and redirects. **The existing profile-completeness check has exactly this shape** (lines 85–92 of router.dart) — we follow the same `profileAsync.isLoading → return null` pattern, so behavior is consistent. Risk is low but documented.

4. **`activeSessionForUidProvider` on trainer's home** (carried from explore). If a trainer has a stale active-session record (legacy data created before the role guard existed), the listener in `HomeScreen` would surface `ResumeSessionModal`. Mitigation: moving the listener into `AthleteHomeView` (where it belongs) eliminates this for trainers automatically — the dispatcher means the listener doesn't even register for the trainer branch.

5. **TrainerHomeView empty-state UX** (propose-level). A trainer who has just signed up has zero active links and zero pending requests. The view should not feel broken in that state. Mitigation: design phase defines the empty state — likely a single "card" with copy like "Aún no tenés alumnos. Compartí tu perfil para que te encuentren." and no CTAs (discovery from the trainer side is not in scope).

6. **Whitelist breakage on future workout sub-routes** (propose-level). If Fase 5 · Etapa 8 (Coach Hub Excel import) or a later etapa adds a new trainer-only subroute under `/workout/`, the guard list must be updated. Mitigation: design phase encodes the trainer-allowed pattern set as a single named constant near the guard, with a comment pointing future authors at it.

## Acceptance criteria (verify will use)

The change is complete when every checkbox passes manually + automated tests.

- [ ] **Bottom bar — athlete**: Athlete user sees 5 tabs (ENTRENAR, FEED, INICIO, COACH, PERFIL). Tab pill animation works. No visual regression vs. pre-change.
- [ ] **Bottom bar — trainer**: Trainer user sees 4 tabs (INICIO, FEED, COACH, PERFIL). Pill animation adapts to 4 tabs (no visual glitch).
- [ ] **Tab index**: Tapping any tab navigates to its route and the pill highlights the correct cell for both roles.
- [ ] **HomeScreen — athlete**: Athlete sees the existing home content (header + EmpezarEntrenamientoCard + EstaSemanaCard + resume-session modal listener) — zero regression.
- [ ] **HomeScreen — trainer**: Trainer sees `TrainerHomeView` with header + alumnos-activos card + pending-requests card. Counts match the live `trainerLinksStreamProvider` state. Pending card is hidden when count is zero. Empty-state copy renders when no active links.
- [ ] **HomeScreen — trainer no resume modal**: With a legacy stale active-session record, the `ResumeSessionModal` does NOT surface on the trainer's home.
- [ ] **ProfileScreen — athlete**: Athlete sees the existing stats row (SESIONES / VOLUMEN KG / RACHA) + PERFIL heading + sign-out — zero regression.
- [ ] **ProfileScreen — trainer**: Trainer sees `TrainerProfileView` — NO athlete stats row, trainer fields (specialty, bio, monthly rate) shown read-only, hint when fields are null, PERFIL heading + sign-out present.
- [ ] **Guard — trainer redirect**: Trainer attempting `context.go('/workout')`, `/workout/routine/X`, `/workout/exercise/X`, `/workout/session/X/Y`, `/workout/historial/X` is redirected to `/coach`.
- [ ] **Guard — trainer whitelist**: Trainer accessing `/workout/routine-editor/<athleteId>` is NOT redirected (the Etapa 4 plan editor still works).
- [ ] **Guard — athlete unaffected**: Athlete navigating to any route they could reach before still works — zero regression.
- [ ] **Guard — loading state**: Cold-start on a guarded URL does not flash content (`profileAsync.isLoading → return null` pattern works as it does today for profile-completeness).
- [ ] **Tests pass**: `flutter analyze` zero issues. `flutter test` green. Existing `authRedirect` unit tests still pass; new tests added for the role-guard branches (strict-TDD says these test cases come first).
- [ ] **No new providers, no new repositories, no new Firestore queries** (sanity check vs. scope creep).

## Branch target / PR strategy

**Estimated LOC** (rough): 350–500 changed lines across ~8 files.

- `lib/app/router.dart`: ~+40 LOC (guard branch + `_ShellScaffold` to ConsumerWidget + two `_kTabs` lists).
- `lib/core/widgets/treino_bottom_bar.dart`: ~±50 LOC (parameterize tab list; minor refactor of `_items` from `static const` to a passed-in list).
- `lib/features/home/home_screen.dart`: ~±20 LOC (extract existing content into `AthleteHomeView`, add dispatcher).
- `lib/features/home/widgets/trainer_home_view.dart`: **NEW** ~150 LOC (header + 2 cards + empty state).
- `lib/features/home/widgets/athlete_home_view.dart`: **NEW or rename** ~80 LOC (just lifts the existing HomeScreen body).
- `lib/features/profile/profile_screen.dart`: ~±20 LOC (extract into `AthleteProfileView`, add dispatcher).
- `lib/features/profile/widgets/trainer_profile_view.dart`: **NEW** ~100 LOC (trainer fields display).
- `lib/features/profile/widgets/athlete_profile_view.dart`: **NEW or rename** ~80 LOC (lifts existing).
- Tests (strict-TDD): `test/app/router_test.dart` — ~+80 LOC for guard cases. Trainer home / profile widget tests are optional (CoachScreen precedent has none); if added, ~+100 LOC.

**Recommended strategy**: **single PR** (`feat/role-aware-shell`).

Rationale:
- Estimated diff sits below the 400-line "high risk" threshold for the bulk of production code; tests push it slightly over but tests don't count against review fatigue the same way.
- All touchpoints are tightly coupled — splitting them would require feature flags or partial-state intermediate commits (e.g., bottom bar updated but Home dispatcher not yet), which actually makes review harder.
- The change is mostly mechanical refactor (extract widgets into role-dispatched views) + one new guard branch + one new content view. Each piece is auditable in isolation within the PR diff.

If the apply phase reveals scope expansion (e.g., trainer-fields editor sneaks in, or tests blow up the line count to 700+), **fall back to chained PRs** in this order:
1. `feat/role-aware-shell-1-guard-and-bar` (router + bottom bar + tests) — small, ships a working shell with trainer = 4 tabs but trainer home/profile still show athlete content.
2. `feat/role-aware-shell-2-trainer-home-profile` (HomeScreen + ProfileScreen dispatchers + TrainerHomeView + TrainerProfileView) — builds on PR 1.

This is `ask-on-risk` delivery: if `sdd-tasks` estimates > 400 LOC or flags chain risk, the orchestrator will surface the decision before apply.

## Open follow-ups for design + tasks

Design must answer:

1. **Where does `AthleteHomeView` / `TrainerHomeView` live?** Same file as `HomeScreen` (inline, like CoachScreen) or separate files under `lib/features/home/widgets/`? Recommendation: separate files (the views are substantial — CoachScreen's two views are also in separate files `athlete_coach_view.dart` and `trainer_coach_view.dart`).
2. **Bottom bar — internal ConsumerWidget vs. tab-list param?** Cleaner option: make `TreinoBottomBar` a `ConsumerWidget` that reads `userProfileProvider` and builds its own tab list. Cons: ties the widget to Riverpod, harder to unit-test in isolation, hides the role coupling. The other option (tab list as param) keeps the widget pure and pushes the role-read into `_ShellScaffold`. Recommendation: **param** — keeps the widget pure and the role read in one place.
3. **Tab path constants location?** `_kAthleteTabs` and `_kTrainerTabs` as private constants in `router.dart`, OR exposed from `treino_bottom_bar.dart`, OR a new `lib/app/tabs.dart`. Recommendation: keep in `router.dart` (single source of truth for the shell — index <-> route mapping lives next to the ShellRoute).
4. **Whitelist regex vs. explicit prefix list?** The trainer's blocked-paths set is small (5 patterns) and the whitelist is 1 entry (`/workout/routine-editor/`). Use simple `location.startsWith(...)` checks, no regex. Design phase confirms.
5. **TrainerProfileView card layout?** Tasks should not invent visual design — design references `docs/design-decisions.md` and `docs/design-system.md` for the right tokens. The current `_OwnProfileStatsRow` uses a `Row` of `_StatTile`s; the trainer version is a `Column` of label/value rows. Confirm in design.
6. **Should `TrainerProfileView` show the avatar?** Probably yes (eventually) but the existing `ProfileScreen` doesn't show it either today — out of scope for v1 unless trivial. Design picks.
7. **Test strategy for `TreinoBottomBar` with 4 tabs?** If the bottom bar becomes parameterized, an existing widget test for 5 tabs should be parameterized; add a second test for 4 tabs. Strict-TDD: write the failing test first.

Tasks phase will need to know:

- Test runner: `flutter test`.
- Test convention: strict-TDD active. Each task creates the failing test, then the implementation, then green.
- Style: `flutter analyze` 0 issues + `dart format .` before commit.
- Naming: `AthleteHomeView`, `TrainerHomeView`, `AthleteProfileView`, `TrainerProfileView` — mirrors `AthleteCoachView` / `TrainerCoachView`.

## Cross-etapa dependencies / known gaps

- **`sharedWithTrainer: bool` on `TrainerLink`**: re-flagged from `coach-plans-mobile` archive. Required before Etapa 6 (Coach Hub) for the PF to see athletes' sessions. NOT addressed in this change.
- **Athlete-side guards** (block athlete from `/workout/routine-editor/*` and `/coach/athlete/*`): defense-in-depth gap; UI doesn't expose entry points so impact is low.
- **Trainer editable fields**: requires either an in-app form (out of scope) or the Coach Hub web app (Etapa 7). Today these fields are written by Admin SDK only.

## Ready for spec + design

**Yes.** Codebase is well-understood. The four open product questions from explore are resolved:

| # | Question | Decision |
|---|---|---|
| Q1 | Trainer Home v1 content | Full screen (header + 2 cards reusing `trainerLinksStreamProvider`). No new data plumbing. |
| Q2 | 4 vs 5 tabs for trainer | 4 tabs (drop ENTRENAR). Athlete keeps 5. |
| Q3 | Route guard target for trainer on `/workout/*` | Redirect to `/coach` — trainer's primary tab. Whitelist `/workout/routine-editor/*`. |
| Q4 | Profile trainer fields v1 | Read-only display of specialty + bio + monthly rate. Hide athlete stats. Editing deferred to Coach Hub. |

Design + spec can run in parallel from here.
