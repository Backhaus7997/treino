# Exploration: Fase 4 Etapa 6 — Wire data atrasada (wire-real-stats)

## Goal

Replace all placeholder/stub data in Home "Esta Semana", own Profile, and Public Profile with real Session-derived stats, and add a basic check-in daily prompt (check-in.png).

---

## Mockup Analysis

### esta-semana.png (Home card)
- Top-left: pill "RACHA ACTUAL" (accent outline)
- Top-right: "SEM 17 · MAR" (week+month label)
- Large number: "12 DÍAS" (streak count, large Barlow font)
- Subtext: "No rompas la racha — entrenaste hoy." (motivational copy)
- Day strip: L M M J V S D — dots, some filled (accent) = trained, some empty = not trained
- Two mini-cards bottom row:
  - SEMANA: "4 entrenos"
  - MES: "16 entrenos"
- Right side: muscle silhouette (front+back) with highlighted groups — green = trained this week
- No "Tocá para ver tus insights" label — this card IS the destination with real data

### check-in.png
- Modal/dialog overlay on top of Feed screen (blurred background showing Feed)
- Center icon: location pin (accent color)
- Header: "¿ESTÁS EN EL GYM HOY?"
- Subtext: "Smart Fit · Palermo. Detectamos que estás cerca..."
- Two buttons: "NO" (dark, outline) | "SÍ, ENTRE" (accent fill)
- NOT a full-screen route — it is a dialog/bottom-sheet overlay
- Triggered from Feed context (location-aware prompt) — NOT from bottom bar tab

### profile.png (own profile)
- 3-stat row: "143 SESIONES" | "92k VOLUMEN KG" | "12 RACHA"
- SESIONES and VOLUMEN KG in accent (green); RACHA in highlight/magenta
- No "WORKOUTS" label — own profile uses "SESIONES" not "WORKOUTS"
- ProfileScreen is currently a minimal Center() placeholder — needs full rebuild

### feed-publico.png (public profile)
- 4-stat row: "89 WORKOUTS" | "23 RACHA" | "412 SEGUIDORES" | "284 SIGUIENDO"
- RACHA is accent color, others textPrimary
- PublicProfileStatsRow currently hardcodes all '0' values

---

## Current State Mapping

### Home "Esta Semana" (EstaSemanaCard)
- File: `lib/features/home/widgets/esta_semana_card.dart`
- Current state: StatelessWidget with no provider. Renders `BodySilhouettePlaceholder` with label "Tocá para ver tus insights". GestureDetector taps to `/home/insights`.
- Placeholders: everything — streak, day dots, muscle map, SEMANA/MES counts are ALL absent.
- The card needs to become a ConsumerWidget (or ConsumerStatelessWidget) to read `weeklyInsightsProvider`.

### Profile (own) — ProfileScreen
- File: `lib/features/profile/profile_screen.dart`
- Current state: A Center() with "PERFIL" text + "Tu cuenta y ajustes" + sign-out button. Completely unimplemented per mockup.
- No stats rows, no avatar, no settings menu items (Datos personales, Gimnasio, Mis rutinas, Historial, Notificaciones).
- This is NOT just a stats wire — it's a full screen build. However, Etapa 6 scope from roadmap is ONLY workouts + racha reales. The profile.png shows a much richer screen.
- Decision needed: scope full profile build here vs. only add stats sub-widget?

### Public Profile stats (PublicProfileStatsRow)
- File: `lib/features/feed/presentation/widgets/public_profile_stats_row.dart`
- Current state: StatelessWidget, all values hardcoded '0'. No params.
- Labels: WORKOUTS | RACHA | SEGUIDORES | SIGUIENDO
- WORKOUTS (count of finished sessions) and RACHA need Session data.
- SEGUIDORES / SIGUIENDO come from friendships collection — already exists via FriendshipRepository but count not exposed by `publicProfileViewProvider`.
- The widget needs to become parameterized: accept `workoutsCount`, `racha`, `seguidores`, `siguiendo`.

### Check-in
- No existing feature directory, no screen, no model, no route.
- check-in.png is a dialog/overlay — NOT a full screen route.
- Triggered from Feed (location-aware prompt).
- Entry point unclear — could be: (a) dialog shown on Feed mount, (b) button in Home, (c) notification deep-link.
- From mockup: appears on Feed over blurred background → most natural as a dialog called from FeedScreen.

---

## Reusable Infra from Etapa 5

### weeklyInsightsProvider — REUSE DIRECTLY for Home card
- Already computes: `daysTrained` (List<bool> 7), `sessionsCount` (week), `setsByGroup` (MuscleGroupDisplay map)
- Missing for Home card: `streak` (consecutive days) and `monthSessionsCount`
- Approach: extend `WeeklyInsights` DTO with `streak` + `monthSessionsCount` fields, compute in `weeklyInsightsProvider`
- Alternative: create separate `homeStatsProvider` — avoids polluting Insights DTO but duplicates repo reads

### MuscleGroupDisplay + toDisplayGroup() — REUSE DIRECTLY
- Already maps granular `muscleGroup` strings → 6 display groups
- Home card muscle map (when real SVG asset arrives) will use same mapping
- For now, `setsByGroup` from `weeklyInsights` is exactly what the Home card highlights need

### SessionRepository.listByUid — REUSE for streak and month count
- Already fetches all sessions descending by `startedAt`
- No date-range overload exists — streak + month count require client-side filtering
- Option: add `listByUidInRange(uid, from, to)` to repo for month query; but full list + client filter is simpler and avoids over-engineering (session count per user typically < 1000 in early product)

---

## Streak Calculation Algorithm

Decision points:
1. **What counts as "trained"**: only `SessionStatus.finished` (not active/abandoned). Consistent with Etapa 5.
2. **Granularity**: a day is "trained" if at least one finished session has `startedAt.toLocal()` date on that calendar day.
3. **Algorithm**: Iterate backwards from "today" (local date). For each day going back, check if any session exists on that day. Stop at first gap. The result is the number of consecutive days before the first gap.
4. **Edge case — today**: If the user trained today, streak includes today. If not, the streak is still alive (today's session not yet done). Two sub-options:
   - **Option A** (mockup-aligned): streak = consecutive days ending yesterday OR today if trained today. "No rompas la racha — entrenaste hoy." copy implies today counts.
   - **Option B**: streak = consecutive days of training completed, not including today. Conservative.
   - **Recommendation**: Option A — check if trained today; if yes, count from today back. If no, count from yesterday back. This matches the copy in the mockup.
5. **Timezone**: use `DateTime.now().toLocal()` — consistent with Etapa 5.
6. **Maximum lookback**: cap at 365 days to avoid O(n) loop on large datasets. In practice sessions list from `listByUid` is the natural limit.

Pseudocode:
```
Set trainedDates = sessions.where(finished).map(s => toLocalDate(s.startedAt)).toSet()
today = toLocalDate(now)
streak = 0
cursor = today
while trainedDates.contains(cursor):
  streak++
  cursor = cursor.subtract(1 day)
// If today not trained, check starting from yesterday:
if streak == 0:
  cursor = today.subtract(1 day)
  while trainedDates.contains(cursor):
    streak++
    cursor = cursor.subtract(1 day)
```

---

## Volume/Sessions Count per Period

### SEMANA (Home card)
- Already in `weeklyInsights.sessionsCount` — REUSE directly.

### MES (Home card)
- Definition: calendar month of `DateTime.now().toLocal()` (not rolling 30 days).
- Computation: `allSessions.where(s => finished && s.startedAt.toLocal().month == now.month && s.startedAt.toLocal().year == now.year).length`
- Add `monthSessionsCount` to WeeklyInsights DTO, compute in `weeklyInsightsProvider`.

### Profile SESIONES total
- All-time count of finished sessions: `allSessions.where(finished).length`
- New provider needed: `profileStatsProvider` (own profile) — or read from `weeklyInsightsProvider` result but it only fetches week/all and doesn't compute total.
- Better: create `userSessionStatsProvider` that returns `{totalSessions, totalVolumeKg, streak}` for the own profile.

### Profile VOLUMEN KG total
- Sum of `totalVolumeKg` across all finished sessions — already stored in Session model.
- The "92k" in mockup suggests formatting: if >= 1000, display as "Xk".

### Public Profile WORKOUTS
- Same as profile total sessions count, but for another user.
- **Security concern**: `users/{uid}/sessions` is owner-only readable. We CANNOT read another user's sessions.
- Options:
  - **A) Denormalized counter in userPublicProfiles**: `workoutsCount`, `streak`. Updated when a session is finished (via client-side write to userPublicProfiles). Readable by anyone.
  - **B) Cloud Function**: triggered on session finish, updates counters. Not yet in scope (Fase 4 explicitly defers Cloud Functions to Fase 6).
  - **C) Skip public workout/racha for now**: show '--' or '0' with a comment noting this needs Cloud Functions.
  - **Recommendation**: Option A (denormalized counters). Update `userPublicProfiles/{uid}` when `SessionRepository.finish()` is called. The `UserPublicProfile` model and repo already support adding fields. Rules already allow owner-write. This is consistent with the established pattern (displayName denormalized to userPublicProfiles).

### Public Profile SEGUIDORES / SIGUIENDO
- Already in `friendships` collection but no count provider exists.
- Need: count of friendships where uid is in members AND status=accepted.
- Options:
  - **A) Query-count client-side**: `friendships` where `members` array-contains uid AND status=accepted. Count both directions.
  - **B) Denormalized counters in userPublicProfiles**: `followersCount`, `followingCount`.
  - Recommendation: denormalized (B) — consistent with approach for workouts. Avoids extra queries. Update on friendship create/update.
  - BUT: friendship updates happen in FriendshipRepository which is in feed feature. Cross-feature write needed.
  - Alternative short-term: query-based counts since friendship counts are low.

---

## Check-in Data Model

### Schema proposal
- **Collection path**: `users/{uid}/checkIns/{date}` where `{date}` = ISO date string `YYYY-MM-DD` local. One doc per day (upsert pattern — if user checks in twice the second write overwrites).
- **Fields**:
  - `uid: String` — owner
  - `date: String` — `YYYY-MM-DD` local date (also the doc ID for dedup)
  - `checkedInAt: Timestamp` — actual timestamp of check-in
  - `gymId: String?` — gym where checked in (from user's profile.gymId at time of check-in)
  - `gymName: String?` — gym display name at time of check-in (denormalized for display)
  - All other potential fields (mood, energy, soreness, notes) are **OUT OF SCOPE** for this etapa per roadmap ("básico").
- **Frequency**: once per day (doc ID = date = natural dedup)
- **Privacy**: ALL fields private — health/location data, owner-only R/W.

### Firestore rules addition
```
match /users/{uid}/checkIns/{date} {
  allow read, write: if request.auth != null && request.auth.uid == uid;
}
```
Nested under `/users/{uid}` so consistent with sessions pattern.

### Rules test addition (rules.test.js)
- SCENARIO for owner-only R/W on checkIns
- SCENARIO for non-owner read blocked
- SCENARIO for non-owner write blocked

### Field-level Privacy Classification
| Field | Classification | Exposure |
|---|---|---|
| uid | Private | Owner only |
| date | Private | Owner only |
| checkedInAt | Private | Owner only |
| gymId | Private | Owner only |
| gymName | Private | Owner only |

None of these fields go to `userPublicProfiles`. No backfill needed.

---

## Sub-Feature Scope

### Sub-feature A: Home "Esta Semana" wire

**Files to modify**:
- `lib/features/home/widgets/esta_semana_card.dart` — convert to ConsumerWidget, wire weeklyInsightsProvider
- `lib/features/insights/domain/weekly_insights.dart` — add `streak` + `monthSessionsCount` fields
- `lib/features/insights/application/insights_providers.dart` — compute streak + monthSessionsCount
- `lib/features/insights/presentation/insights_screen.dart` — if streak is exposed there too (likely add streak display)

**Files to create**:
- None (reuses existing infrastructure)

**Estimated LOC**: ~150 prod + ~80 test (provider unit test for streak algorithm is critical)

### Sub-feature B: Profile stats wire

**B1 — Own Profile (ProfileScreen)**:
- `lib/features/profile/profile_screen.dart` — full rebuild per mockup
- New: `lib/features/profile/application/profile_stats_providers.dart` — `userSessionStatsProvider`
- Estimated: ~200 prod + ~60 test

**B2 — Public Profile (PublicProfileStatsRow)**:
- `lib/features/feed/presentation/widgets/public_profile_stats_row.dart` — parameterize
- `lib/features/profile/domain/user_public_profile.dart` — add `workoutsCount`, `racha` fields (nullable)
- `lib/features/profile/data/user_public_profile_repository.dart` — no change (merge-writes already work)
- `lib/features/profile/data/user_repository.dart` — propagate counters on profile setup? No — counters updated by workout flow
- `lib/features/workout/data/session_repository.dart` — update `finish()` to also write to userPublicProfiles (cross-feature write concern)
- OR: new service/use-case layer
- `lib/features/feed/application/public_profile_providers.dart` — expose workoutsCount + racha in PublicProfileView
- `lib/features/feed/domain/public_profile_view.dart` — add workoutsCount, racha, followersCount, followingCount
- Estimated: ~250 prod + ~80 test

### Sub-feature C: Check-in

**Files to create**:
- `lib/features/check_in/domain/check_in.dart` — Freezed model
- `lib/features/check_in/data/check_in_repository.dart` — create/get today's check-in
- `lib/features/check_in/application/check_in_providers.dart` — `todayCheckInProvider`, `checkInNotifier`
- `lib/features/check_in/presentation/check_in_dialog.dart` — dialog widget matching mockup

**Files to modify**:
- `lib/features/feed/feed_screen.dart` — trigger check-in dialog on first mount if no check-in today
- `firestore.rules` — add checkIns sub-collection rule
- `scripts/rules_test/rules.test.js` — add 3 new scenarios

**Estimated LOC**: ~200 prod + ~100 test + ~60 rules test

---

## Approaches

| # | Approach | Scope | Estimated LOC | PR budget | Pros | Cons | Complexity |
|---|---|---|---|---|---|---|---|
| A | Single PR — all 3 sub-features | Home + Profile + Check-in | ~800+ | Needs size:exception | One squash, simpler coordination | Reviewer cognitive overload, hard to rollback single sub-feature | High |
| B | Three chained PRs | PR#1 Home wire, PR#2 Profile stats, PR#3 Check-in | ~150 / ~450 / ~360 | PR#1 ok, PR#2 borderline, PR#3 ok | Clean rollback per sub-feature, reviewable | 3 PRs to land, sequencing overhead, PR#2 crosses feature boundaries | Medium |
| C | Two PRs: stats bundle + check-in | PR#1: Home + Profile stats; PR#2: Check-in | ~600 / ~360 | PR#1 needs size:exception | Check-in isolated (new feature) | PR#1 still large | Medium-High |
| D | Four PRs: home / own-profile / public-profile / check-in | PR#1: Home (~150), PR#2: own profile (~200), PR#3: public profile (~300), PR#4: check-in (~360) | 150/200/300/360 | All within budget | All reviewable, surgical rollback | 4 PRs, slow to land | Low per PR |

**Recommendation**: Approach D (4 PRs chained on feature branch). Each is under 400 lines, surgically rollbackable, and maps cleanly to distinct concerns. PR#3 (public profile) is the most complex due to cross-feature writes — isolating it reduces blast radius.

---

## Cross-Dev Coordination

| File | Feature | Dev owner | Risk |
|---|---|---|---|
| `lib/features/profile/profile_screen.dart` | profile | Dev A (historically) | CONFIRM ownership before modifying |
| `lib/features/profile/domain/user_public_profile.dart` | profile | Dev A | Adding fields = freezed regen needed |
| `lib/features/feed/presentation/widgets/public_profile_stats_row.dart` | feed | Dev C (Etapa 4 owner) | Parameterizing breaks existing tests |
| `lib/features/feed/application/public_profile_providers.dart` | feed | Dev C | Need to add stats fields to PublicProfileView |
| `lib/features/workout/data/session_repository.dart` | workout | Dev B (Etapa 2/3) | Adding userPublicProfiles write to finish() is cross-domain write |
| `lib/features/insights/domain/weekly_insights.dart` | insights | Dev C (Etapa 5) | Extends DTO — freezed regen + test updates |
| `lib/features/insights/application/insights_providers.dart` | insights | Dev C | Adding streak/month computation |
| `firestore.rules` | infra | Shared | Rules change needs review + rules test |

Etapa 6 is assigned to **Dev B** per roadmap. Dev B owns workout player/summary but must coordinate with Dev A (profile) and Dev C (feed/insights) for cross-feature modifications.

---

## Failure Modes / Risks

1. **Cross-feature write for public stats**: Writing `workoutsCount`/`racha` to `userPublicProfiles` from `SessionRepository.finish()` introduces a cross-feature dependency (workout → profile). If this write fails silently, public stats never update. Mitigation: wrap in `try/catch`, log error, don't block session finish.

2. **Streak edge cases**: Timezone shifts (user crosses timezone boundary during training trip) can cause double-count or miss-count days. DST transitions add ±1h ambiguity. The `toLocal()` approach handles most cases but requires explicit test coverage with known-timezone scenarios.

3. **ProfileScreen scope creep**: The profile.png mockup shows a full rich screen (avatar, settings menu, gymId display, etc.). Etapa 6 scope is ONLY stats wire. Without explicit scope agreement, the implementer may build the full screen, ballooning scope beyond 400 LOC easily.

4. **Check-in trigger UX**: The mockup shows a dialog over the Feed. If triggered every time Feed mounts (including tab-switches), it becomes annoying. Logic should check `todayCheckInProvider` first and show dialog only if no check-in exists for today. This requires an extra provider call on FeedScreen mount.

5. **userPublicProfile fields addition**: Adding `workoutsCount` and `racha` to `UserPublicProfile` requires freezed regeneration, which touches `.freezed.dart` and `.g.dart` generated files. These changes must be coordinated across the team to avoid merge conflicts.

6. **follower/following counts**: If implemented via query-based approach, two Firestore queries per public profile view (one for followers, one for following). At scale this adds latency. Denormalized approach avoids this but requires FriendshipRepository (feed feature) to update userPublicProfiles (profile feature) — same cross-feature coupling problem.

---

## Open Questions for sdd-propose

1. **ProfileScreen scope**: Is Etapa 6 meant to add ONLY the stats row to the existing placeholder, or build the full profile.png screen? The mockup shows a rich screen but the placeholder is currently minimal.
2. **Streak definition — today**: Does "racha" include today if the user hasn't trained yet? Or does it count only if today is complete?
3. **Month boundary**: SEMANA stats use Mon-Sun calendar week. MES stats use calendar month (Jan/Feb/…) or rolling 30 days?
4. **Public profile stats — architecture decision**: Denormalized counters in `userPublicProfiles` (preferred but introduces cross-feature write) vs. query-based (simpler but 2 extra queries per view) vs. defer to Cloud Functions?
5. **Follower/following counts**: Same decision as above — denormalized or query-based?
6. **Check-in trigger**: On Feed mount? On Home mount? Via a "+" FAB? What is the trigger rule (only once per day, only if no check-in today)?
7. **Check-in gymId**: Should the check-in auto-read the user's `profile.gymId` (already in UserProfile) or require GPS proximity detection? The mockup mentions "Smart Fit · Palermo. Detectamos que estás cerca" — GPS is out of scope for MVP. Use profile.gymId as the default gym.
8. **Check-in mood/energy fields**: Roadmap says "básico" — does that mean ONLY the gym check-in (binary yes/no) or also mood/energy sliders? Mockup only shows location confirmation with NO/SÍ — no mood fields visible.
9. **profile.png VOLUMEN KG**: The "92k" format suggests large number formatting. Is this an Etapa 6 requirement or deferred?
10. **Check-in rules test**: Should the new checkIns scenarios be added to the existing `rules.test.js` file or a new file?

---

## Out of Scope

- Muscle map SVG asset with colored body regions (BodySilhouettePlaceholder remains for now)
- Coach/Trainer features
- Push notification for check-in reminder
- GPS proximity detection for gym (mockup mentions it, but it's not basic)
- Mood/energy/soreness sliders in check-in
- Ranking, Retos, Missions, Bets, Gamification
- Cloud Functions aggregation (deferred to Fase 6)
- Full ProfileScreen rich build (avatar editing, settings menu items) — only stats row
- Activity tab in public profile (currently placeholder copy "Aún no hay actividad reciente.")
- Routines tab content in public profile

---

## Ready for Proposal
Yes — codebase is well-understood, infra exists, key decisions are identified. The main decision gate before proposal is: public profile stats architecture (denormalized vs query-based) and ProfileScreen scope (stats-only vs full build).
