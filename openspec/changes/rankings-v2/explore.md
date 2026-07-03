# Exploration — rankings-v2

Scope: UX/gating/placement fixes on top of the solid rankings v1 base (opt-in, denormalization, families, queries). Three targets: (1) opt-in gating, (2) leaderboard shows no data, (3) relocate rankings out of `/profile`.

Infra constraint (unchanged): org blocks public Cloud Functions. Everything stays client-side — metrics denormalized onto `userPublicProfiles/{uid}` at session finish, leaderboards = gym-scoped indexed Firestore queries.

---

## Target 1 — Opt-in gating (bug confirmed)

Navigation to `/profile/rankings` is **unconditional** — nothing gates it on `rankingOptIn`:

- `lib/app/router.dart:531-535` — the GoRoute has no redirect/guard.
- `lib/features/profile/profile_screen.dart:232` — `_RankingsTile.onTap` pushes `/profile/rankings` regardless of opt-in.
- `lib/features/gym_rankings/presentation/rankings_screen.dart:70-86` — `RankingsScreen.build` branches only on `gymId` (loading/error/no-gym/data); never reads `rankingOptIn`.

Irony: `_RankingsTile` (profile_screen.dart:220-222) **already watches** `userPublicProfileProvider(myUid)` to derive `optIn` — but only for the `Switch` value, not to gate the tap.

Provider exposing opt-in: `userPublicProfileProvider` (`lib/features/profile/application/user_public_profile_providers.dart:22-32`), a `StreamProvider.family.autoDispose<UserPublicProfile?, String>` keyed by uid, auth-gated.

Fix shape: inside `RankingsScreen.build` (or a thin wrapper), watch `userPublicProfileProvider(myUid)`. When `rankingOptIn == false`, render an "enable rankings" invitation state (icon + copy + CTA calling `enableRankingOptIn`) instead of `_RankingsBody`. Fall through to gym-check + leaderboards only when opted-in. Reuses the existing controller — no new abstraction.

---

## Target 2 — No-data diagnosis

Query is **correct** — verified against the deployed index byte-for-byte.

`UserPublicProfileRepository.leaderboard()` (`lib/features/profile/data/user_public_profile_repository.dart:129-144`):
```dart
_col.where('gymId', isEqualTo: gymId)
    .where('rankingOptIn', isEqualTo: true)
    .orderBy(metricField, descending: true)
    .limit(limit)
    .get();
```
- Filters `gymId ==` + `rankingOptIn == true`, `orderBy` desc. No `uid != me` filter — does NOT exclude the current user.
- `gymId` never null here (screen gates on it before mounting `_RankingsBody`, plus defensive guard at line 134).
- Field names match `firestore.indexes.json:205-249` exactly. All 5 composite indexes deployed on treino-dev.

### Discriminating symptom table

| Root cause | Firestore behavior | UI rendered |
|---|---|---|
| Composite index still BUILDING | Future throws `FAILED_PRECONDITION` | `_ErrorBlock` — "No pudimos cargar el ranking. Intentá de nuevo." |
| Doc missing/null on the sorted field | Query succeeds, doc silently excluded | `_EmptyLeaderboard` — "Todavía nadie de tu gym se sumó a este ranking." |
| Gym genuinely has 0 opted-in | Query succeeds, empty | Same `_EmptyLeaderboard` |

### Ranked root causes (most likely first)

1. **[MOST LIKELY] `racha` field absent on the reporter's own doc.** `RankingOptInController.enableRankingOptIn` (`lib/features/profile/application/ranking_optin_controller.dart:50-80`) backfills `lifetimeVolumeKg` + `bestSquatKg`/`bestBenchKg`/`bestDeadliftKg` via `updateCounters`, then `setRankingOptIn(uid, true)`. It **never writes `racha`** (comment says racha is "already denormalized by `finish()`"). But `racha` is `int? racha` with **no `@Default`** (`user_public_profile.dart:43`), whereas `lifetimeVolumeKg` has `@Default(0)`. Firestore **drops a doc from an `orderBy(field)` composite query if that field is absent**. So if the reporter never finished a session under the racha-writing branch after opting in, his Rachas leaderboard renders empty while Volumen/Lifts may show his row. Discriminating symptom: **which dimension is empty** — only Rachas ⇒ confirms; all 5 ⇒ weakens.
2. **Index still BUILDING on treino-dev.** Symptom: error copy ("No pudimos cargar...") not empty-state copy.
3. **Backfill failed / never triggered** (opted-in before code deployed, or metric write raced). Symptom: `lifetimeVolumeKg`/best lifts are `0`/null despite logged sessions.

### Runtime verification needed (code alone can't resolve)
1. Firebase console → 5 indexes' build STATE (Enabled vs Building).
2. Firebase console → open `userPublicProfiles/{his-uid}`: is `racha` present/non-null? are the other 4 fields present? is `rankingOptIn === true` (boolean)?
3. If `racha` absent → confirm he has ≥1 `finished` + fully-completed session dated after the racha-denormalization code deployed.

---

## Target 3 — Navigation relocation

Current Entrenar tab: `WorkoutScreen` (`lib/features/workout/workout_screen.dart`) — single ShellRoute root, role-branched (`_AthleteWorkout` vs `TrainerWorkoutView`). Athlete body = one flat scrollable `ListView` of sections (MiPlan, TrainerTemplates, MisRutinas, Plantillas, Historial). No internal tabs/PageView. go_router `ShellRoute` for bottom-bar sub-routes + top-level routes for immersive flows.

Precedents: in-tab `TabBar` driven by `?tab=` query param (`TrainerCoachView`); push to dedicated top-level route (`HistorialSection` "Ver todo" → `/workout/historial`, outside the shell).

### Options
1. **Shell sub-route `/workout/rankings` + entry card in the Entrenar list** (mirrors `/profile/rankings` mechanics, relocated). Card renders opt-in CTA or leaderboard entry based on `rankingOptIn`. Pros: minimal risk, proven mechanics, bottom bar stays. Cons: still bottom-of-list discoverability. Effort: Low. **[RECOMMENDED]**
2. **TabBar/segmented control at top of `WorkoutScreen`** ("Mi plan" vs "Rankings"), `?tab=rankings` deep-link. Pros: true first-class second screen. Cons: restructures a high-traffic single-purpose screen, TabController index math collides with role/no-gym branches. Effort: Medium.
3. **Dedicated top-level immersive route `/workout/rankings` (outside shell) + header action on `WorkoutScreen`.** Pros: full-bleed screen, zero risk to `_AthleteWorkout` body. Cons: `WorkoutScreen` has no header/app-bar today — must add one. Effort: Low-Medium.

Recommendation: Option 1 first (lowest risk, composes with the Target-1 gate). Option 3 if product wants genuine second-screen status. Option 2 only if Entrenar becomes multi-section beyond rankings.

### Open decision for propose
Where does the opt-in `Switch` live once the screen moves? Today it's in `ProfileScreen._RankingsTile`. Options: move with the screen / stay in profile / duplicate (single source of truth via the same controller).

---

## Readiness
- Targets 1 + 2 (cause #1: racha backfill gap) — ready for propose, small/low-risk/high-confidence.
- Target 3 — carries the toggle-ownership product decision; propose as its own section.

Engram: `sdd/rankings-v2/explore` (id 363).
