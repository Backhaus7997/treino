# Exploration: role-aware-shell

**Change**: `role-aware-shell`
**Fase / Etapa**: Fase 5 · Etapa 5
**Project**: treino
**Artifact store**: hybrid (engram + openspec)
**Engram key**: `sdd/role-aware-shell/explore` (id #104)

---

## Problem Statement

Trainer and athlete share an identical UI shell. Only the Coach tab is role-aware. Concrete problems:

1. Trainer can execute a workout session via EMPEZAR button, creating session records.
2. Trainer's Home shows athlete dashboard (streak, weekly stats, `EmpezarEntrenamientoCard`).
3. Trainer's Workout tab shows `MiPlanSection` + `PlantillasSection` + `HistorialSection` — none relevant.
4. Trainer's Profile shows athlete session stats (SESIONES, VOLUMEN KG, RACHA).
5. Routes `/workout/session/*`, `/workout/historial/*` are not role-guarded — trainer can deep-link.
6. `/workout/routine-editor/:athleteId` and `/coach/athlete/:athleteId` have no guard either (trainer-only but unguarded).

## Current State

**Shell architecture** (`lib/app/router.dart`):

- `_ShellScaffold` — plain `StatelessWidget`, NOT a `ConsumerWidget`. Does NOT read role. Takes `location: String` and `child: Widget`. Renders `TreinoBottomBar` with `_kTabs = ['/workout', '/feed', '/home', '/coach', '/profile']`.
- `TreinoBottomBar` — pure presentational widget with hardcoded `_items` list (5 tabs: ENTRENAR, FEED, INICIO, COACH, PERFIL). Tabs are static const — no role awareness.
- `ShellRoute` in `GoRouter` — single `ShellRoute` wrapping all 5 tab routes.
- `authRedirect` — comment at line 78–84 explicitly documents: "Role-awareness (Etapa 7, Option A)… the outer 5-tab shell is shared between athlete and trainer. Differentiation lives in CoachScreen. When Fase 5 introduces /trainer/... routes, the branch goes EXACTLY here." This is the designated injection point.

**Role provider** (`lib/features/profile/application/user_providers.dart`):

- `userProfileProvider` — `StreamProvider<UserProfile?>` driven by `authStateChangesProvider`. Single source of truth for role.
- Pattern in widgets: `ref.watch(userProfileProvider.select((async) => async.valueOrNull?.role))` (used by `CoachScreen`).

**Existing role-aware screen**: `CoachScreen` — switches on `UserRole` to render `AthleteCoachView` or `TrainerCoachView`. Proven template.

**Mutation points a trainer must not reach**:

1. `EmpezarEntrenamientoCard` (HomeScreen) — navigates to `/workout`, then `_StartSessionCTABar` → `/workout/session/...`.
2. `SessionPlayerScreen` — writes Firestore session docs under the caller's UID.
3. `activeSessionForUidProvider` listener in HomeScreen — `ResumeSessionModal` could show for trainer.
4. `_OwnProfileStatsRow` in ProfileScreen — reads `userSessionStatsProvider` (athlete aggregates).

**Trainer-specific `UserProfile` fields**: `trainerBio`, `trainerSpecialty`, `trainerLatitude/Longitude/Geohash`, `trainerMonthlyRate` — none surfaced in ProfileScreen.

## Affected Areas

| File | Reason |
|------|--------|
| `lib/app/router.dart` | `_ShellScaffold` → ConsumerWidget; `_kTabs` role-split; `authRedirect` add role guard |
| `lib/core/widgets/treino_bottom_bar.dart` | `_items` hardcoded — must accept dynamic tab list or become ConsumerWidget |
| `lib/features/home/home_screen.dart` | Add role dispatch (Athlete/Trainer Home views) |
| `lib/features/home/widgets/empezar_entrenamiento_card.dart` | Athlete-only, hide for trainer |
| `lib/features/home/widgets/esta_semana_card.dart` | Athlete-only (workout insights), hide for trainer |
| `lib/features/workout/workout_screen.dart` | Athlete-only — no trainer dispatch (tab eliminated) |
| `lib/features/workout/presentation/routine_detail_screen.dart` | `_StartSessionCTABar` EMPEZAR — must not render for trainer |
| `lib/features/profile/profile_screen.dart` | Role dispatch (hide athlete stats, show trainer fields) |
| Routes `/workout/session/*`, `/workout/historial/*` | No role guard |
| Route `/workout/routine-editor/:athleteId` | Trainer-only, no guard |
| Route `/coach/athlete/:athleteId` | Trainer-only, no guard |

## Approaches Considered

| | Approach | Pros | Cons | Effort |
|---|---|---|---|---|
| A | Route guards in `authRedirect` only | Centralized; prevents deep-link abuse | Doesn't fix Home/Profile content | Medium |
| B | Split ShellRoute trees per role | Maximum separation; trainer can't reach `/workout` at all | GoRouter doesn't support dynamic routes natively; high complexity | High |
| C | Single shell, role-aware screens (CoachScreen pattern) | Follows proven pattern; minimal structural change | No route-level defense; deep-link abuse possible | Low–Medium |
| **D** | **Hybrid: role-aware shell + route guards (RECOMMENDED)** | **Defense-in-depth; proven pattern extended; solves both tab count and content** | Bottom bar index arithmetic must stay in sync with active tab list | Medium |

## Recommendation

**Approach D (Hybrid)**:

- `_ShellScaffold` becomes `ConsumerWidget`, reads role.
- `TreinoBottomBar` accepts a dynamic tab list (or becomes ConsumerWidget).
- Trainer = 4 tabs (INICIO, FEED, COACH, PERFIL — no ENTRENAR). Athlete = 5 tabs.
- `HomeScreen` dispatches `switch(role)` → `AthleteHomeView` / `TrainerHomeView`.
- `ProfileScreen` dispatches `switch(role)` → `AthleteProfileView` / `TrainerProfileView`.
- `authRedirect` adds a role guard at the designated line 78–84 injection point: block trainer from `/workout`, `/workout/session/*`, `/workout/historial/*`, `/workout/routine/*`; ALLOW `/workout/routine-editor/*` (trainer's plan-editor flow from Etapa 4).

## Open Questions for `sdd-propose`

1. **Tab count for trainer**: 4 (drop ENTRENAR) or 5 (keep with disabled state)?
2. **Trainer Home v1 content**: placeholder or full screen with alumnos/requests/agenda?
3. **Route guard target**: redirect trainer to `/coach` (semantic) or `/inicio` (the new trainer home)?
4. **Profile trainer fields v1**: just hide athlete stats, or also surface editable `trainerBio`/`trainerSpecialty`/`trainerMonthlyRate`?

## Out of Scope

- Redesigning the Coach tab (already done via `TrainerCoachView` / `AthleteCoachView`).
- New trainer features (leaderboards, broadcast messages, advanced analytics).
- Refactoring `UserProfile` or role mechanics.
- `sharedWithTrainer: bool` on `TrainerLink` (Etapa 6 pre-req).
- Coach Hub web app.

## Risks

- `_ShellScaffold` → ConsumerWidget introduces a brief loading window where role is null — must render neutral state (skeleton or empty surface), not flash athlete tabs.
- `_kTabs` index shift (4 vs 5 tabs) breaks `_currentIndex` if positional logic isn't replaced with named-route lookup.
- `/workout/routine-editor/:athleteId` is trainer-only but lives under `/workout` ShellRoute subtree — the trainer guard must explicitly whitelist this path.
- `activeSessionForUidProvider` in HomeScreen: a trainer with legacy session data would see `ResumeSessionModal` unless the dispatch to `TrainerHomeView` removes the listener entirely (separate widget, not a guard inside the same screen).

## Ready for Proposal

Yes — codebase is well-understood, the role provider pattern is clean and proven, the designated `authRedirect` injection point is documented by the team, and `CoachScreen` provides a clear template. Open product decisions (trainer home content, 4 vs 5 tabs) are the remaining items for propose.
