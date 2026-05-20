# Proposal: wire-real-stats (Fase 4 Etapa 6)

## TL;DR

Replace all placeholder/stub stats in **Home "Esta Semana"**, **own Profile**, and **Public Profile** with real Session-derived data, and ship a **basic location-only daily check-in** triggered from Feed. Delivered as **4 chained PRs** on `feat/wire-real-stats`, each under 400 LOC, all owned by **Dev C** (continuity from exploration).

---

## Intent

### Problem

Home, Profile (own), and Public Profile show hardcoded zeros or empty placeholders despite having real Session data available. The product looks unfinished and breaks the trust signal that "your training is being tracked". Etapa 6 of Fase 4 in the roadmap closes this gap and introduces the **basic check-in** prompt (location confirmation only).

### Why now

- Etapa 5 (`insights-history`) shipped `weeklyInsightsProvider` with `daysTrained`, `sessionsCount`, `setsByGroup`. This is the foundation. Without wiring it everywhere, the work is invisible to the user.
- `user-public-profiles` (PR #40) established the denormalization pattern (`displayName`, `avatarUrl` mirrored to `userPublicProfiles`). The same pattern unblocks public stats now.
- Without check-in we can't ship the daily engagement loop that Fase 5 (notifications) will hook into.

### Success criteria

- Home `EstaSemanaCard` shows real `streak`, `daysTrained` strip, `SEMANA`/`MES` counts.
- Own Profile shows real `SESIONES` (all-time), `VOLUMEN KG` (all-time, formatted `92k`), `RACHA`.
- Public Profile shows real `WORKOUTS`, `RACHA`, `SEGUIDORES`, `SIGUIENDO` for any user.
- Check-in dialog appears once per day on Feed mount when no check-in exists, persists to `users/{uid}/checkIns/{date}`.
- 0 `flutter analyze` issues, all new tests green, rules tests cover check-in owner-only R/W.

---

## Scope

### In scope

- Extend `WeeklyInsights` DTO with `streak` + `monthSessionsCount`.
- New `userSessionStatsProvider` for own profile.
- Extend `UserPublicProfile` model with `workoutsCount`, `racha`, `followersCount`, `followingCount` (all nullable).
- Cross-feature write: `SessionRepository.finish()` updates `userPublicProfiles/{uid}` counters (try/catch, non-blocking).
- Cross-feature write: `FriendshipRepository` accept/delete updates `userPublicProfiles/{uid}` counters (try/catch, non-blocking).
- New `lib/features/check_in/` feature module (domain + data + application + presentation).
- `FeedScreen` mounts check-in dialog once per session per day when `todayCheckInProvider == null`.
- `firestore.rules` adds `/users/{uid}/checkIns/{date}` owner-only block.
- `scripts/rules_test/rules.test.js` adds 3 check-in scenarios.
- `kFormatter` helper (`>= 1000 → "Xk"`) reusable across own/public profile.

### Out of scope (explicit)

- Full ProfileScreen rebuild (avatar editing, settings menu, Datos personales, Gimnasio, Mis rutinas, Historial, Notificaciones). **Only the 3-stat row is added** to the existing `PERFIL` placeholder.
- Muscle map SVG asset with colored body regions — `BodySilhouettePlaceholder` stays.
- GPS proximity detection for check-in. Use `userProfile.gymId` as default; if null, dialog still records check-in without gym pre-fill.
- Mood / energy / soreness sliders in check-in.
- Push notification for check-in reminder.
- Cloud Functions aggregation (deferred to Fase 6).
- Activity tab + Routines tab content in public profile.
- Ranking, Retos, Missions, Bets, Gamification.
- Coach/Trainer features.

---

## Locked Decisions (10 questions answered)

### Pre-locked by user (read before this phase)

| # | Question | Decision | Rationale |
|---|---|---|---|
| Q1 | ProfileScreen scope | **Option A — Stats row only** | Roadmap scope is "stats reales only". Full rebuild is a separate etapa. |
| Q4 | Public profile stats architecture | **Option A — Denormalized in `userPublicProfiles`** | Consistent with `displayName`/`avatarUrl` denormalization in PR #40. No Cloud Functions needed. |

### Locked in this phase

| # | Question | Decision | Rationale |
|---|---|---|---|
| Q2 | Streak includes today? | **Yes if trained today, else count from yesterday backwards** | Matches mockup copy "No rompas la racha — entrenaste hoy." |
| Q3 | Month boundary | **Calendar month (`DateTime.now().toLocal().month`)** | Simpler, matches user mental model. NOT rolling 30 days. |
| Q5 | Follower/following counts | **Denormalized in `userPublicProfiles`** | Same pattern as Q4. `FriendshipRepository` writes on accept/delete (try/catch). |
| Q6 | Check-in trigger | **On `FeedScreen` mount, once per session per day, only if no check-in today** | Dismissible (NO option also records dismissal to prevent re-trigger). |
| Q7 | Check-in gymId source | **Auto-read from `userProfile.gymId`. NO GPS.** | If null → record check-in without gym pre-fill. |
| Q8 | Check-in mood/energy | **OUT OF SCOPE** | Roadmap "básico" = location confirmation only. Mood for Fase 4.5 or Fase 6. |
| Q9 | VOLUMEN KG `92k` formatting | **IN SCOPE — `kFormatter` helper** | `>= 1000 → "${(v/1000).toStringAsFixed(0)}k"`. Reusable. |
| Q10 | Check-in rules test location | **Add to existing `scripts/rules_test/rules.test.js`** | Consistent with prior etapas. No new file. |

---

## Approach

### High-level

Extend existing infrastructure rather than build new abstractions. Reuse `weeklyInsightsProvider` and `MuscleGroupDisplay` from Etapa 5. Apply the **denormalization pattern** from `user-public-profiles` to public stats (workouts/racha/followers/following). Wrap all cross-feature writes in `try/catch` so they degrade gracefully (counter stale, but no UX block).

### Why this approach

- **Denormalization over Cloud Functions**: Cloud Functions are explicitly deferred to Fase 6. Client-side denormalized writes work today, are cheap to read, and are the pattern the team already validated.
- **Reuse over rebuild**: `weeklyInsightsProvider` already reads finished sessions and computes day-aggregated data. Adding `streak` + `monthSessionsCount` is a 2-field DTO extension, not a new provider.
- **Stats row only on Profile**: Honors the roadmap scope. Avoids 800+ LOC profile rebuild that would balloon the etapa.
- **Check-in as new feature module**: Clean isolation under `lib/features/check_in/`. No coupling with existing features beyond the FeedScreen mount trigger.

### Rejected alternatives

- **Single PR (~800 LOC)**: Requires `size:exception`, reviewer overload, hard to rollback per sub-feature. Rejected.
- **Two PRs (stats bundle + check-in)**: PR#1 still ~600 LOC. Rejected.
- **Three PRs (Home / Profile / Check-in)**: PR#2 (own + public profile combined) would be ~450 LOC and cross 3 feature boundaries. Rejected.
- **Query-based counts for public profile**: 2 extra Firestore reads per public profile view, plus violates `users/{uid}/sessions` owner-only rule. Rejected.

---

## PR Chain Plan

All 4 PRs target `main` (stacked branches, NOT feature-branch-chain). Each merges before the next opens, to keep the diff small for review.

```
PR#1 (Home)  →  PR#2 (Own Profile)  →  PR#3 (Public Profile)  →  PR#4 (Check-in)
```

### PR#1 — `feat/wire-real-stats-home`

| Aspect | Detail |
|---|---|
| **Targets** | `main` |
| **Delivers** | Home "Esta Semana" card wired to real data |
| **Files modified** | `lib/features/insights/domain/weekly_insights.dart` (+streak, +monthSessionsCount), `lib/features/insights/application/insights_providers.dart` (compute fields), `lib/features/home/widgets/esta_semana_card.dart` (→ ConsumerWidget), `lib/features/insights/presentation/insights_screen.dart` (display streak) |
| **Files created** | None |
| **LOC estimate** | ~150 prod + ~80 test |
| **Tests** | Unit tests for streak algorithm (today trained, today not trained, gap, empty, timezone), unit test for monthSessionsCount, widget test for EstaSemanaCard rendering states |
| **Review forecast** | ~30 min — single feature boundary (insights + home consumer) |
| **Rollback** | Revert single commit; `weeklyInsightsProvider` extension is backwards-compatible (new fields default to safe values) |
| **Owner** | Dev C |

### PR#2 — `feat/wire-real-stats-own-profile`

| Aspect | Detail |
|---|---|
| **Targets** | `main` (after PR#1 merges) |
| **Delivers** | Own Profile stats row (3 stats) on top of existing `PERFIL` placeholder |
| **Files modified** | `lib/features/profile/profile_screen.dart` (add stats row above existing Center/sign-out) |
| **Files created** | `lib/features/profile/application/profile_stats_providers.dart` (`userSessionStatsProvider`), `lib/shared/format/k_formatter.dart` (or under `lib/core/format/`), tests for provider + formatter |
| **LOC estimate** | ~200 prod + ~60 test |
| **Tests** | Unit tests for `userSessionStatsProvider` (sessions total, volume total, streak), unit tests for `kFormatter` (boundaries: 999, 1000, 1500, 92000), widget test ProfileScreen renders stats row + retains sign-out button |
| **Review forecast** | ~30 min — isolated to profile feature + 1 helper |
| **Rollback** | Revert commit; ProfileScreen returns to placeholder; no data migration |
| **Owner** | Dev C |

### PR#3 — `feat/wire-real-stats-public-profile`

| Aspect | Detail |
|---|---|
| **Targets** | `main` (after PR#2 merges) |
| **Delivers** | Public Profile 4-stat row wired with real data via denormalized counters + cross-feature writes from Session/Friendship |
| **Files modified** | `lib/features/profile/domain/user_public_profile.dart` (+workoutsCount, +racha, +followersCount, +followingCount — all nullable, Freezed regen), `lib/features/workout/data/session_repository.dart` (`finish()` writes counters try/catch), `lib/features/feed/data/friendship_repository.dart` (accept/delete writes counters try/catch), `lib/features/feed/presentation/widgets/public_profile_stats_row.dart` (parameterize), `lib/features/feed/domain/public_profile_view.dart` (+4 fields), `lib/features/feed/application/public_profile_providers.dart` (pass-through) |
| **Files created** | Tests for cross-feature write paths |
| **LOC estimate** | ~300 prod + ~80 test |
| **Tests** | Unit test SessionRepository.finish writes counters (success + failure non-blocking), unit test FriendshipRepository accept/delete updates counters, unit test PublicProfileView exposes all 4 stats, widget test PublicProfileStatsRow renders parameterized values |
| **Review forecast** | ~60 min — touches 3 features (workout, profile, feed). HIGH coordination |
| **Rollback** | Revert commit; new nullable fields are safe to drop. **NO backfill needed** — counters lazily populate as users finish sessions or accept friendships. Stale counters until next event. |
| **Owner** | Dev C |
| **Risk note** | Cross-feature write coupling. Must wrap in try/catch. Must NOT block session.finish() or friendship.accept() on write failure. |

### PR#4 — `feat/wire-real-stats-checkin`

| Aspect | Detail |
|---|---|
| **Targets** | `main` (after PR#3 merges) |
| **Delivers** | New `check_in` feature module + FeedScreen trigger + Firestore rules + rules tests |
| **Files modified** | `lib/features/feed/feed_screen.dart` (dialog trigger on mount), `firestore.rules` (+checkIns block), `scripts/rules_test/rules.test.js` (+3 scenarios) |
| **Files created** | `lib/features/check_in/domain/check_in.dart` (Freezed model), `lib/features/check_in/data/check_in_repository.dart` (`createTodayIfAbsent`, `getTodayForUser`), `lib/features/check_in/application/check_in_providers.dart` (`todayCheckInProvider`, `checkInNotifier`), `lib/features/check_in/presentation/check_in_dialog.dart` |
| **LOC estimate** | ~200 prod + ~100 test + ~60 rules test |
| **Tests** | Unit tests CheckInRepository (createTodayIfAbsent dedup, getTodayForUser), provider tests, widget test for CheckInDialog (NO/SÍ buttons, dismissible), rules test 3 scenarios (owner R/W, non-owner read blocked, non-owner write blocked) |
| **Review forecast** | ~45 min — new feature module, isolated except for FeedScreen trigger |
| **Rollback** | Revert commit; `firestore.rules` revert; existing check-in docs become inert (no reader). No data loss risk for other features. |
| **Owner** | Dev C |

### Summary table

| PR | Prod LOC | Test LOC | Total | Within 400 budget? |
|---|---|---|---|---|
| PR#1 Home | ~150 | ~80 | ~230 | Yes |
| PR#2 Own Profile | ~200 | ~60 | ~260 | Yes |
| PR#3 Public Profile | ~300 | ~80 | ~380 | Yes (tight) |
| PR#4 Check-in | ~200 | ~160 | ~360 | Yes |

---

## Cross-Dev Coordination Plan

Etapa 6 owner: **Dev C** (continuity from exploration). Cross-boundary touches require explicit greenlight from feature owners before the PR opens.

| PR | Files crossing feature boundary | Owner to greenlight | Coordination action |
|---|---|---|---|
| PR#1 | `insights/` (Dev C owns Etapa 5) | Self | No external coordination — same dev |
| PR#2 | `profile_screen.dart` (originally Dev A) | Dev A | Notify in #treino-dev: "Adding stats row above existing Center/sign-out. No structural change to placeholder. PR link incoming." |
| PR#3 | `session_repository.dart` (Dev B), `friendship_repository.dart` (Dev C, feed), `user_public_profile.dart` (Dev A, profile) | Dev A + Dev B | **HIGH coordination**. Open draft PR early. Tag Dev A (Freezed regen on UserPublicProfile) and Dev B (SessionRepository.finish cross-feature write). Document the try/catch contract explicitly. |
| PR#4 | `feed_screen.dart` (Dev C, feed), `firestore.rules` (shared infra) | Self + rules reviewer | Self-owned for FeedScreen. Rules change needs a second pair of eyes (Dev A or Dev B). |

### Handoff message template (PR#3)

```
Hi Dev A & Dev B — opening PR#3 of wire-real-stats chain.

Touches:
- profile/domain/user_public_profile.dart: +4 nullable fields (workoutsCount, racha, followersCount, followingCount). Freezed regen included.
- workout/data/session_repository.dart: finish() now writes workoutsCount + racha to userPublicProfiles. Wrapped in try/catch — does NOT block session finish on failure.
- feed/data/friendship_repository.dart: accept/delete update follower/following counters. Same try/catch contract.

Pattern follows user-public-profiles PR #40 (displayName/avatarUrl denormalization). Rules: existing /userPublicProfiles/{uid} write rule already allows owner. No rules change.

Counters are nullable and degrade gracefully. No backfill needed — lazy population on next event.

PR link: <url>
```

---

## Lessons Learned Maintained

Continuing standards established in `user-public-profiles`:

1. **Rules Audit section** in PR#4 design.md (covers `/users/{uid}/checkIns/{date}`).
2. **Field-level Privacy Classification table** in PR#4 design.md (5 check-in fields, all Private/owner-only).
3. **Sidecar fixes documented** if discovered during smoke testing of any PR.
4. **Try/catch contract for cross-feature writes** carried from `user-public-profiles` displayName mirror to PR#3 counters.

---

## Top Risks (carried forward to design)

1. **Cross-feature write failure silence**: PR#3 writes from Session/Friendship into `userPublicProfiles`. If write fails silently (offline, permissions, network), counters stay stale forever for that event. Mitigation: log to console + telemetry hook (when telemetry lands in Fase 5); add backfill script to scripts/ for future repair.
2. **Streak timezone edge cases**: DST + travel across timezones can over/under-count days. Mitigation: explicit test coverage with fixed-timezone scenarios; document `toLocal()` contract in provider.
3. **Check-in dialog UX annoyance**: If trigger logic regresses (e.g., resets per tab switch), users see dialog repeatedly. Mitigation: gate by `todayCheckInProvider` AND a session-scoped flag (`_checkInDialogShownThisSession`).

---

## Hard Constraints (enforced in design + apply)

1. Strict TDD: tests first, RED→GREEN per work unit.
2. Rules Audit mandatory in PR#4 design.
3. Field-level Privacy Classification mandatory for check-in fields.
4. All colors via `AppPalette.of(context)`. NO hex literals.
5. All icons via `TreinoIcon.X`. NO `PhosphorIcons.X` direct.
6. Spacing: 8 / 12 / 14 / 18 / 20 px only.
7. NO Cloud Functions introduced.
8. NO modificar archivos out-of-scope per design Section sub-feature.

---

## Ready for Spec + Design

Spec and design can run in **parallel** after this proposal lands. Spec captures behavior + acceptance criteria per PR. Design captures: schema, providers, dialog UX flow, cross-feature write contract, Rules Audit (PR#4), Field Privacy Classification (PR#4).
