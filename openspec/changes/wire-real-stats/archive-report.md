# Archive Report: wire-real-stats (Fase 4 Etapa 6)

| Item | Value |
|---|---|
| Change | wire-real-stats |
| Phase / Etapa | 4 / 6 |
| Owner | Dev C |
| Status | **ARCHIVED** |
| Date archived | 2026-05-21 |
| Delivery strategy | Chained PRs — stacked-to-main |
| Artifact store | `openspec` (with engram mirror) |
| PRs merged | #56 (PR#1 Home) · #57 (PR#2 Own Profile) · #65 (PR#3 Public Profile) · #67 (PR#4 Check-in) |
| Sidecar hotfix | #66 (`fix(routines): filter listAll by visibility=public`) — see Section 6 |
| Main HEAD at archive | `c48f577` |
| REQs delivered | REQ-WRH-001..009 · REQ-WRP-001..010 · REQ-WRX-001..010 (REQ-WRX-004 partial) · REQ-WRC-001..010 · REQ-WRA-001..006 |
| SCENARIOs verified | 44 (298..338 in Dart + 272..274 in `scripts/rules_test/rules.test.js`) |
| Tests baseline → final | 792 → 1012 (+220 net new) |
| Quality gates at close | `flutter analyze` 0 issues · `flutter test` 1012/1012 pass · `dart format` clean on wire-real-stats files (4 pre-existing-drift files addressed in chore PR `chore/dart-format-cleanup`) |

---

## 1. Executive summary

`wire-real-stats` replaced the placeholder data on Home "Esta Semana", own
Profile stats, public Profile counters, and added the basic daily check-in
prompt on Feed — closing Fase 4 Etapa 6 of the roadmap. The work shipped as
**4 chained PRs** against `main`, all under the 400 LOC budget; no
`size:exception` was needed. Strict TDD was enforced for every implementation
task (RED commit precedes GREEN, see `apply-progress.md` TDD Cycle Evidence
tables).

End-to-end the change introduced ~970 production LOC + ~360 test LOC, brought
the test suite from 792 → 1012, validated 44 SCENARIOs (41 Dart widget/unit
+ 3 Firestore rules emulator), and surfaced one unrelated production bug
(`#66` routines listAll) which was remediated mid-flight to unblock the PR#4
smoke. Three deviations are documented below; none block archive. Two
follow-up SDD lines fall out of this cycle: a friend-requests inbox (which
will also tackle the cache-staleness issue surfaced during PR#3 smoke) and a
Fase 6 Cloud Function for bidirectional counter materialization.

---

## 2. Scope delivered (per PR)

### PR#1 — Home "Esta Semana" wire (#56, merged 2026-05-19)

- `WeeklyInsights` Freezed DTO extended with `streak: int` and `monthSessionsCount: int`
- `weeklyInsightsProvider` computes both from `sessions` (inline `_computeStreak`, lifted in PR#2)
- `EstaSemanaCard` refactored to `ConsumerWidget` with `_Skeleton` / `_Loaded` / `_ErrorFallback` subtrees per `AsyncValue.when`
- Header pill "RACHA ACTUAL · SEM N · MMM"; streak number 96 px; day strip horizontal bars; body silhouette PNGs front + back (compressed via pngquant); two period cards (SEMANA + MES)
- Mockup parity validated against `esta-semana.png`
- Lift of streak logic to a shared util deferred to PR#2 (ADR-WRS-08)

### PR#2 — Own Profile stats row (#57, merged 2026-05-20)

- `lib/core/utils/streak_calculator.dart` — pure `computeStreak(List<Session>, {DateTime? now}) → int` (lifted from `insights_providers.dart`)
- `lib/core/utils/k_formatter.dart` — `kFormat(num) → String` ("Xk" ≥ 1000 else integer)
- `lib/features/profile/domain/user_session_stats.dart` — hand-written `@immutable` DTO `{totalSessions, totalVolumeKg, streak}`
- `userSessionStatsProvider` — `FutureProvider.autoDispose<UserSessionStats>` reading `currentUidProvider` + `sessionRepositoryProvider`; null-uid guard
- `ProfileScreen` — 3-stat row above existing PERFIL/sign-out; SESIONES accent, VOLUMEN KG accent + `kFormat`, RACHA highlight magenta

### PR#3 — Public Profile counter denormalization (#65, merged 2026-05-21)

- `UserPublicProfile` +4 nullable counter fields: `workoutsCount`, `racha`, `followersCount`, `followingCount`
- `UserPublicProfileRepository.updateCounters(uid, Map)` — partial counter writes that do NOT clobber other nullables (per design A.2)
- `SessionRepository.finish()` — best-effort dual-write to `userPublicProfiles/{uid}` with `{workoutsCount, racha}` (try/catch + `developer.log`)
- `FriendshipRepository.accept(id, myUid)` — best-effort `followingCount` self-increment for `myUid` (ADR-WRS-12 self-refresh)
- `FriendshipRepository.delete(id, myUid)` — **BREAKING signature change**: requires `myUid` for symmetric self-decrement; all callers updated in the same PR
- `PublicProfileStatsRow` parameterized with nullable counters (null → '0')
- `publicProfileViewProvider` / `PublicProfileView` expose the 4 counters to the UI layer

### PR#4 — Check-in feature + Firestore rules (#67, merged 2026-05-21)

- New feature: `lib/features/check_in/{domain,data,application,presentation}/`
  - `CheckIn` Freezed model with `static String dateKey(DateTime)` (zero-padded YYYY-MM-DD)
  - `CheckInRepository.getTodayForUser` / `createTodayCheckIn(uid, {inGym, gymId?, gymName?})` (idempotent read-then-set on `/users/{uid}/checkIns/{date}`)
  - `checkInRepositoryProvider`, `todayCheckInProvider` (auth-gated `FutureProvider.autoDispose`), `checkInNotifierProvider` (AsyncNotifier with `confirm()` + invalidate)
  - `CheckInDialog` (per ADR-WRS-19, props-down; see Section 5)
  - `CheckInStrings` for UI copy
- `FeedScreen` converted to `ConsumerStatefulWidget` (ADR-WRS-18); `addPostFrameCallback(_maybeShowCheckIn)`; session-scoped `StateProvider<bool>` guard (ADR-WRS-16)
- `firestore.rules`: new block `match /users/{uid}/checkIns/{date} { allow read, write: if request.auth.uid == uid }`
- `scripts/rules_test/rules.test.js` — 3 new SCENARIOs (272/273/274) for owner write / non-owner read blocked / non-owner write blocked
- T64 emulator run on 2026-05-21: 14/14 scenarios PASS (incl. owner/non-owner inverse pairs)
- T68 deploy on 2026-05-21: `firestore.rules` released to `treino-dev` cloud.firestore

---

## 3. ADR summary (PR#1 → PR#4)

19 ADRs ratified across the cycle. See `design.md` for full content. Recap:

| ADR | Topic | PR |
|---|---|---|
| ADR-WRS-01..03 | Streak algorithm (10-day window, calendar month, dedup) | PR#1 |
| ADR-WRS-04..07 | WeeklyInsights DTO shape; not-Freezed; nullable additive fields | PR#1 |
| ADR-WRS-08 | `streak_calculator.dart` lifted to `lib/core/utils/` | PR#2 |
| ADR-WRS-09 | `kFormat` thresholds + locale-free integer fallback | PR#2 |
| ADR-WRS-10 | try/catch + no rethrow on cross-feature writes | PR#3 |
| ADR-WRS-11 | Direct repo-to-repo dependency (no service layer) | PR#3 |
| ADR-WRS-12 | Self-only counter refresh; other member self-heals | PR#3 |
| ADR-WRS-13 | `followerCountResolver` closure injection | PR#3 |
| ADR-WRS-14 | `/users/{uid}/checkIns/{date}` nested path | PR#4 |
| ADR-WRS-15 | Date doc id = natural dedup | PR#4 |
| ADR-WRS-16 | Session-scoped `StateProvider` trigger guard | PR#4 |
| ADR-WRS-17 | NO GPS, NO mood/energy (Q7, Q8 lock) | PR#4 |
| ADR-WRS-18 | FeedScreen as `ConsumerStatefulWidget` (mount-once trigger) | PR#4 |
| **ADR-WRS-19** | **`CheckInDialog` props-down (supersedes D.5 sketch)** | **PR#4 (apply); promoted in archive** |

---

## 4. Deviations from spec / design (3, all documented)

### 4.1 REQ-WRX-004 — partially satisfied (per ADR-WRS-12 self-refresh)

**Spec text** (REQ-WRX-004): when an accept fires, "both members' counters
update." **Implementation**: only the accepting user's `followingCount`
moves (`accept()` self-refresh). `followersCount` is NEVER written by
anyone; the requester's `followingCount` is NOT touched on the
partner-side either.

**Rationale (ADR-WRS-12)**: cross-user writes to `userPublicProfiles` would
require broader Firestore rules. Self-refresh keeps the rule narrow ("any
authed user can write to their OWN public profile only") and avoids the
follow-up rules-audit churn.

**Consequence**: `followersCount` displays a constant 0 on every profile,
and `followingCount` displays only the actions *that user* personally
performed. Mockup expectations are met for the actor; the counterparty's
view is stale until they themselves perform an action.

**Follow-up paths**:
- The next planned SDD `feed-friend-requests-inbox` (engram observation
  `decision/follow-up-friend-requests-inbox-screen-own-sdd-after-wire-real-stats-archive`)
  will surface received requests in-app and is the natural place to
  introduce a partner-side counter update — either by relaxing the rules
  with a narrowly-scoped exception or by triggering a self-refresh on the
  counterparty's next session.
- Fase 6 Cloud Function is the canonical solution for bidirectional
  counter materialization (server-side onWrite trigger on `friendships/`
  that updates both sides atomically).

### 4.2 ADR-WRS-19 — CheckInDialog props-down (supersedes design D.5)

Design D.5 sketch had the dialog reading `userProfileProvider` inline. The
PR#4 implementation deviates to a **container-presentational pattern**:
`CheckInDialog({required gymId, required gymName})` receives both as
constructor props; `FeedScreen._maybeShowCheckIn()` resolves them and
passes down.

**Approved during apply (2026-05-21)** because:
- The container-presentational pattern is explicitly declared in
  `~/.claude/CLAUDE.md` user preferences
- Dialog tests stay free of `userProfileProvider` overrides (no auth
  mocking surface)
- Zero coupling to the `profile` feature from the `check_in` feature
- Q7 lock (profile-based, NO GPS — ADR-WRS-17) is preserved: the lookup
  just moves up one widget tree level

**Acceptable cost**: the dialog is not reactive to mid-session
`userProfileProvider` changes (the props are a snapshot at mount).
Academic — dialogs live ~3 s and `profile.gymId` does not change while a
dialog is open.

**Promoted to formal ADR-WRS-19** in `design.md`; section D.5 updated to
reflect the actual constructor + parent resolver. Done in this archive
commit.

### 4.3 Sidecar hotfix #66 — out-of-scope remediation

While running T68 (deploy `firestore.rules` to `treino-dev`), the
Plantillas screen broke with `permission-denied`. Root cause was a latent
bug introduced by PRs #58 / #64 (`coach-discovery-infra` +
`coach-plans-mobile`): they added a per-doc read rule on `routines/` that
checks `resource.data.visibility`, but `RoutineRepository.listAll()`
issued a bare `_collection.get()` with no `where()`. Firestore rejects
list queries against rules with per-doc conditions unless the query
constrains the same field, so the query was rejected.

Fix shipped as **#66** (`fix(routines): filter listAll by visibility=public
to satisfy per-doc rule`) on a separate branch from main, including:
- `where('visibility', isEqualTo: 'public')` on `listAll()`
- New regression test SCENARIO-450 proving private trainer-assigned plans
  are excluded
- Backfill script `scripts/backfill_routines_source_visibility.js`
  (idempotent, `merge: true`) for any environment whose seeded `routines/`
  docs lack the explicit fields. **Note**: `treino-dev` happened to
  already have the fields populated by some prior manual op, so the
  backfill was not executed against dev. The script is kept as a safety
  net for future environments (prod, fresh seeds, etc.).

This work is NOT counted in the wire-real-stats LOC / scope but is
acknowledged here as part of the cycle narrative. Full root cause and
fix details are also persisted in engram observation
`bug/fixed-plantillas-screen-broken-by-per-doc-routines-rule-after-deploy`.

---

## 5. Files touched

Production:
- `lib/features/insights/{domain,application}/` — PR#1
- `lib/features/home/widgets/esta_semana_card.dart` — PR#1
- `lib/features/insights/presentation/widgets/body_silhouette_placeholder.dart` — PR#1
- `assets/body/` — PR#1 (bodyfront.png, bodyback.png, 17 mask PNGs)
- `lib/core/utils/{streak_calculator,k_formatter}.dart` — PR#2
- `lib/features/profile/domain/user_session_stats.dart` — PR#2
- `lib/features/profile/application/profile_stats_providers.dart` — PR#2
- `lib/features/profile/profile_screen.dart` — PR#2
- `lib/features/profile/domain/user_public_profile.dart` — PR#3
- `lib/features/profile/data/user_public_profile_repository.dart` — PR#3
- `lib/features/workout/data/session_repository.dart` — PR#3
- `lib/features/feed/data/friendship_repository.dart` — PR#3
- `lib/features/feed/presentation/widgets/public_profile_stats_row.dart` — PR#3
- `lib/features/feed/application/public_profile_providers.dart` — PR#3
- `lib/features/feed/domain/public_profile_view.dart` — PR#3
- `lib/features/check_in/{domain,data,application,presentation}/` — PR#4
- `lib/features/feed/feed_screen.dart` — PR#4
- `firestore.rules` — PR#4 (checkIns block)
- `scripts/rules_test/rules.test.js` — PR#4 (SCENARIO-272..274)

Tests (mirror under `test/`): ~12 new test files, ~360 LOC.

SDD artifacts (this folder): `proposal.md`, `explore.md`, `spec.md`,
`design.md`, `tasks.md`, `apply-progress.md`, `verify-report.md`,
`archive-report.md` (this file).

---

## 6. Verification against verify-report

The `verify-report.md` produced 2026-05-21 reports **PASS WITH
DEVIATIONS** (0 CRITICAL, 2 WARNINGS, 4 SUGGESTIONS). Disposition:

| Verify finding | Disposition in archive |
|---|---|
| WARNING-01 — REQ-WRX-004 partial (ADR-WRS-12) | Documented in §4.1 with explicit follow-up paths |
| WARNING-02 — `dart format` drift on 4 unrelated files | Addressed in separate PR `chore/dart-format-cleanup` (one-line chore, not in this archive) |
| SUGGESTION-01 — Add ADR-WRS-18 (props-down) and sync D.5 | **Done in this archive commit** (promoted to ADR-WRS-19 because ADR-WRS-18 was already taken by the FeedScreen ConsumerStatefulWidget decision) |
| SUGGESTION-02 — cache-staleness follow-up | Documented in §7 + already in engram as planned next SDD |
| SUGGESTION-03 — hotfix #66 narrative | Documented in §4.3 |
| SUGGESTION-04 — minor test clock injection (`computeStreak`) | Noted as low-priority polish; not blocking |

---

## 7. Follow-ups

1. **SDD `feed-friend-requests-inbox`** — already planned (engram
   `decision/follow-up-friend-requests-inbox-screen-own-sdd-after-wire-real-stats-archive`).
   Will address (a) UX gap: no in-app inbox for received friend requests;
   (b) FuturProvider cache-staleness in `friendshipByPairProvider` +
   `userPublicProfileProvider` (likely conversion to `StreamProvider` or
   targeted invalidation); (c) probably revisit ADR-WRS-12 self-refresh
   to materialize the counterparty side of counters.

2. **Fase 6 Cloud Function** — canonical solution for bidirectional
   counter writes (server-side `onWrite` trigger on `friendships/` that
   updates both sides atomically). Out of scope until Cloud Functions
   land in Fase 6.

3. **`chore/dart-format-cleanup` PR** — cleanup of 4 pre-existing format
   drifts (`trainer_contact_cta_stub.dart` from PR#61, `routine_repository.dart`
   from #66, plus 2 test files). Open at branch `chore/dart-format-cleanup`,
   pending merge in parallel with this archive.

4. **Lessons-learned promotion** — the "Rule-Query Reconciliation"
   insight (any per-doc Firestore rule needs a query audit + backfill
   plan) deserves a permanent home. Recommended target: a paragraph in
   `~/.claude/skills/sdd-design/SKILL.md` (or `AGENTS.md` in this repo)
   so future `sdd-design` runs surface the requirement automatically.

5. **Local feature branches**: `feat/wire-real-stats-public-profile`,
   `feat/wire-real-stats-pr4`, `fix/profile-setup-trainer-dual-write`,
   `fix/routines-list-query-after-rule-change` — all merged, safe to
   `git branch -d` whenever convenient.

---

## 8. Lessons learned

1. **Container-presentational on dialogs pays off**. ADR-WRS-19 was a tiny
   architectural call but it made every CheckInDialog test trivial. Pattern
   worth adopting for future dialogs (gym selector, post create, etc.).
2. **Cross-feature write try/catch + `developer.log` + no rethrow** is the
   right shape for best-effort denormalization. Validated across two
   repositories (Session, Friendship) and one collection (UserPublicProfile).
   Adopt as a standard pattern.
3. **Rule-Query Reconciliation is a real-world failure mode**. PR#4's rules
   deploy exposed a latent bug from PR#58/#64 (#66 hotfix). Any per-doc
   Firestore rule must trigger an audit of every query against that
   collection + a backfill plan when fields are added. Promote to
   `sdd-design` guidance.
4. **Strict TDD discipline scaled cleanly across 4 chained PRs**. Every
   implementation commit has a paired test commit before it. Apply-progress
   TDD Cycle Evidence tables prove the discipline post-hoc.
5. **Pre-deploy rules emulator run is non-negotiable** (T64). The emulator
   caught zero net-new failures in the new check-in rules but its existence
   forces the discipline of testing rules before they ship.
6. **Hotfix PR pattern is fast and clean**. Two hotfixes in this cycle
   (`#63 trainer dual-write`, `#66 routines visibility`) both shipped as
   their own narrowly-scoped branches, each merged before unblocking the
   downstream SDD smoke. Kept the SDD branch focus tight.
7. **Self-refresh counter design has a discoverable UX cost**. Documenting
   it as ADR-WRS-12 was correct, but real users will notice the gap (PR#3
   smoke surfaced the false alarm). Plan to address explicitly in the
   inbox SDD.
8. **`fake_cloud_firestore` does NOT enforce rules**. Tests passing in
   `fake_cloud_firestore` are necessary but NOT sufficient when rules are
   in play. Always run the emulator suite for rules-touching changes
   (this cycle had T64 baked in for PR#4; carry forward to all SDDs that
   add or modify rules).
9. **Asset compression is worth the chore step**. PR#1's body silhouettes
   went 5.2 MB → 324 KB via `pngquant --quality=65-80 --skip-if-larger
   --strip --force`. Document the command in the asset-onboarding script.
10. **Rebase forward on merge keeps the chain coherent**. All 4 PRs were
    rebased onto main as the previous merged. Force-push-with-lease kept
    the remote consistent. No conflicts beyond trivial ones.

---

## 9. Sign-off

- Strict TDD enforced across all 68 tasks (RED → GREEN evidence in git
  history and in `apply-progress.md`)
- 1012 tests passing on `main @ c48f577`
- 44 SCENARIOs verified (Dart + Firestore emulator)
- 3 deviations documented (none blocking)
- `firestore.rules` deployed to `treino-dev` (T68, 2026-05-21)
- `design.md` synced to actual implementation (ADR-WRS-19 + D.5 update)
- Archive-report persisted to engram topic key
  `sdd/wire-real-stats/archive-report` (observation 76)

**Cycle CLOSED.** Next: merge `chore/dart-format-cleanup`, prune merged
local branches, then `/sdd-new feed-friend-requests-inbox`.
