# Design: wire-real-stats (Fase 4 Etapa 6)

## TL;DR

Four chained PRs on `feat/wire-real-stats`. PR#1 extends `WeeklyInsights` with `streak`+`monthSessionsCount` and turns `EstaSemanaCard` into a `ConsumerWidget`. PR#2 wires own-profile stats via a new `userSessionStatsProvider` and `kFormat` helper. PR#3 denormalizes 4 nullable counter fields onto `userPublicProfiles` and wires cross-feature writes from `SessionRepository.finish` and `FriendshipRepository.accept/delete` (try/catch, no rethrow). PR#4 introduces the `check_in` feature module, a `/users/{uid}/checkIns/{date}` collection with owner-only rules, and a session-scoped trigger on `FeedScreen`. Total: 4 PRs, ~20 production files, ~9 test files, 18 ADRs, 1 Firestore rules GAP (closed by PR#4).

---

## Section A — Home Wire Design (PR#1)

### A.1 File map

| File | Op | Reason |
|---|---|---|
| `lib/features/insights/domain/weekly_insights.dart` | MODIFY | Add 2 fields + copyWith + ==/hashCode + ctor |
| `lib/features/insights/application/insights_providers.dart` | MODIFY | Compute streak + monthSessionsCount, return new DTO |
| `lib/features/home/widgets/esta_semana_card.dart` | MODIFY | StatelessWidget → ConsumerWidget; AsyncValue routing; render real values |
| `lib/features/insights/presentation/insights_screen.dart` | TOUCH (optional) | Display streak if mockup requires |
| `test/features/insights/application/insights_providers_streak_test.dart` | CREATE | Streak algorithm unit tests (8 scenarios) |
| `test/features/insights/application/insights_providers_month_test.dart` | CREATE | monthSessionsCount calendar-boundary tests (4 scenarios) |
| `test/features/home/widgets/esta_semana_card_test.dart` | CREATE | Widget test: loading / data / error routing |

Out of PR#1: no new providers, no router changes, no rules changes.

### A.2 WeeklyInsights DTO extension

Current DTO is a hand-written `@immutable` class (not Freezed). Maintain that style — adding Freezed now would force a generator regen and conflict with parallel work on `user_public_profile.dart`. Two pure-additive fields:

```dart
@immutable
class WeeklyInsights {
  const WeeklyInsights({
    required this.weekStart,
    required this.weekEnd,
    required this.daysTrained,
    required this.sessionsCount,
    required this.plannedSessionsCount,
    required this.monthSessionsCount, // NEW
    required this.streak,             // NEW
    required this.setsByGroup,
    required this.targetByGroup,
  });
  // ...
  final int monthSessionsCount;
  final int streak;
  // copyWith + == + hashCode extended (add monthSessionsCount, streak to Object.hash)
}
```

`plannedSessionsCount` stays (existing Etapa 5 contract). Field order in ctor preserves backward source compatibility for named args — new fields go after the existing block, no positional reorder.

### A.3 Streak algorithm

Placement: top-level pure function in `insights_providers.dart` (private `_computeStreak`). Pure function = unit-testable without Firestore.

```dart
int _computeStreak(
  Iterable<Session> finishedSessions, {
  required DateTime now,
}) {
  final today = DateTime(now.year, now.month, now.day);
  final trainedDates = <DateTime>{};
  for (final s in finishedSessions) {
    if (s.status != SessionStatus.finished) continue;
    final d = s.startedAt.toLocal();
    trainedDates.add(DateTime(d.year, d.month, d.day));
  }

  // Q2 locked: include today if trained, else count from yesterday backwards.
  var streak = 0;
  var cursor = today;
  while (trainedDates.contains(cursor)) {
    streak++;
    cursor = cursor.subtract(const Duration(days: 1));
  }
  if (streak == 0) {
    cursor = today.subtract(const Duration(days: 1));
    while (trainedDates.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
  }
  return streak;
}
```

Contract:
- Input is the `allSessions` list already fetched by `weeklyInsightsProvider` (no extra Firestore call).
- `now` is injected — production calls pass `DateTime.now().toLocal()`, tests pass deterministic values.
- All comparisons happen on `DateTime(y,m,d)` floored to midnight local. DST does not affect equality at the date-level.
- O(n) over finishedSessions to build the set; O(streak) on the while loop. Safe up to thousands of sessions.

### A.4 monthSessionsCount

```dart
int _computeMonthSessionsCount(
  Iterable<Session> sessions, {
  required DateTime now,
}) {
  final local = now.toLocal();
  return sessions.where((s) {
    if (s.status != SessionStatus.finished) return false;
    final d = s.startedAt.toLocal();
    return d.year == local.year && d.month == local.month;
  }).length;
}
```

Q3 locked: calendar month boundary via `toLocal()`. NOT a rolling 30-day window.

### A.5 EstaSemanaCard structure

```
EstaSemanaCard extends ConsumerWidget
  build(context, ref)
    final palette = AppPalette.of(context)
    final asyncInsights = ref.watch(weeklyInsightsProvider)
    return asyncInsights.when(
      data:    (insights) => _Loaded(insights ?? empty)
      loading: ()           => _Skeleton()
      error:   (_, __)      => _ErrorFallback()
    )
```

Three internal widgets (private):
- `_Loaded({required WeeklyInsights insights})` — renders the full card per mockup
- `_Skeleton()` — same outer Container but with shimmer / placeholder children
- `_ErrorFallback()` — fallback to current "Tocá para ver tus insights" copy so users still reach Insights

`_Loaded` structure (top → bottom):

```
Container (bg, border, radius 20, padding 18)
  Column
    Row spaceBetween
      _RachaPill(streak)              // "RACHA ACTUAL" pill (accent outline)
      _WeekMonthLabel(weekStart)      // "SEM 17 · MAR"
    SizedBox 14
    _StreakBig(streak)                // "12 DÍAS" Barlow Condensed huge
    _StreakSubtext(streak)            // motivational copy
    SizedBox 14
    Row
      Expanded(_DayStrip(daysTrained))    // L M M J V S D dots
      SizedBox 14
      Expanded(BodySilhouettePlaceholder) // existing — kept until SVG arrives
    SizedBox 14
    Row spaceEvenly
      _MiniStat('SEMANA', '${sessionsCount} entrenos')
      _MiniStat('MES',    '${monthSessionsCount} entrenos')
```

Tap-to-insights: keep the outer `GestureDetector(onTap: () => context.push('/home/insights'))` wrapping the whole card.

### A.6 AsyncValue state routing

| State | Render | Tap behavior |
|---|---|---|
| `loading` | Skeleton (same outer chrome, shimmering inner) | No-op (avoid pushing while data not ready) |
| `error` | Fallback copy "Tocá para ver tus insights" (current placeholder) | Push `/home/insights` |
| `data: null` (no auth) | Hidden / Skeleton | No-op |
| `data: WeeklyInsights` | `_Loaded` | Push `/home/insights` |

Reasoning: skeleton during loading prevents layout shift; error keeps the entry point alive so the user can still navigate.

### A.7 Tests

- `insights_providers_streak_test.dart` — pure function tests, no Firestore:
  - SC-STREAK-1: empty sessions → streak 0
  - SC-STREAK-2: trained today only → streak 1
  - SC-STREAK-3: trained yesterday only (not today) → streak 1 (Q2 locked behavior)
  - SC-STREAK-4: trained 5 consecutive days ending today → streak 5
  - SC-STREAK-5: trained 5 consecutive days ending yesterday → streak 5
  - SC-STREAK-6: gap of 1 day in the middle → only the most-recent run counts
  - SC-STREAK-7: 2 sessions same calendar day → counts as 1 (dedup by date)
  - SC-STREAK-8: active session (not finished) does NOT count
- `insights_providers_month_test.dart`:
  - SC-MONTH-1: sessions across two months → only current month counted
  - SC-MONTH-2: session at month boundary 23:59 local on last day of previous month → NOT counted
  - SC-MONTH-3: session at 00:00 local on first day of current month → counted
  - SC-MONTH-4: active sessions excluded
- `esta_semana_card_test.dart`:
  - Loading state renders skeleton, no tap navigation
  - Data state renders streak + sessionsCount + monthSessionsCount labels
  - Error state renders fallback copy, tap navigates to /home/insights

### A.8 ADRs (PR#1)

| ADR | Decision | Rationale | Rejected |
|---|---|---|---|
| ADR-WRS-01 | Extend WeeklyInsights DTO instead of creating a new `homeStatsProvider` | Single source of truth for the week aggregate; same `listByUid` call serves both Home and Insights → no duplicate Firestore reads | Separate `homeStatsProvider` (avoids polluting Insights DTO) — rejected: 2× repo reads, drift risk between Home and Insights numbers |
| ADR-WRS-02 | Streak today inclusion: include today if trained, else count from yesterday backwards (Q2 lock) | Matches mockup copy "No rompas la racha — entrenaste hoy"; user feedback loop is more rewarding when today counts immediately on finish | Conservative "yesterday only" — rejected: causes 1-day perceived drop on the day the user finishes a streak day |
| ADR-WRS-03 | Calendar month for MES, not rolling 30 days (Q3 lock) | Matches user mental model ("este mes"); rolling 30 makes the counter wobble at month start | Rolling 30 — rejected: harder to reason about and demote sense of fresh-month-fresh-start |
| ADR-WRS-04 | Keep hand-written `@immutable` instead of converting WeeklyInsights to Freezed | Avoids generator regen during a PR that will be reviewed in parallel with PR#3 (which DOES regen Freezed for `UserPublicProfile`); reduces merge-conflict surface on `.freezed.dart` files | Convert to Freezed — rejected: orthogonal cleanup, can ship later as standalone refactor |

---

## Section B — Own Profile Stats Design (PR#2)

### B.1 File map

| File | Op | Reason |
|---|---|---|
| `lib/features/profile/profile_screen.dart` | MODIFY | Add stats row above existing PERFIL + sign-out scaffold |
| `lib/features/profile/application/profile_stats_providers.dart` | CREATE | Hosts `userSessionStatsProvider` |
| `lib/features/profile/domain/user_session_stats.dart` | CREATE | Immutable DTO `{totalSessions, totalVolumeKg, streak}` |
| `lib/core/utils/number_format.dart` | CREATE | `kFormat(num)` helper |
| `test/features/profile/application/profile_stats_providers_test.dart` | CREATE | Provider tests with fake repository |
| `test/core/utils/number_format_test.dart` | CREATE | kFormat boundary tests |
| `test/features/profile/profile_screen_test.dart` | CREATE | Widget test: stats row + sign-out coexist |

### B.2 userSessionStatsProvider signature

```dart
// profile_stats_providers.dart
final userSessionStatsProvider =
    FutureProvider.autoDispose<UserSessionStats?>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;

  final repo = ref.read(sessionRepositoryProvider);
  final all = await repo.listByUid(uid);

  final finished =
      all.where((s) => s.status == SessionStatus.finished).toList(growable: false);

  final totalSessions = finished.length;
  final totalVolumeKg = finished.fold<double>(0, (sum, s) => sum + s.totalVolumeKg);
  final streak = computeStreak(finished, now: DateTime.now().toLocal());

  return UserSessionStats(
    totalSessions: totalSessions,
    totalVolumeKg: totalVolumeKg,
    streak: streak,
  );
});
```

Where `computeStreak` is the same pure function extracted from PR#1 (exposed as `@visibleForTesting` or moved to a shared `lib/features/insights/application/streak_calculator.dart`). To keep PR#1 self-contained, PR#2 lifts `_computeStreak` from `insights_providers.dart` into `streak_calculator.dart` and re-uses it from BOTH providers. This refactor is part of PR#2 to avoid bloating PR#1.

Sequencing note: PR#2 must rebase on PR#1's branch. The lift is mechanical — no behavior change.

### B.3 kFormat implementation

```dart
// lib/core/utils/number_format.dart

/// Formats numeric values >= 1000 as "Xk" (no decimals). Below 1000 returns
/// the integer string. Used for profile stats (e.g. "92k VOLUMEN KG").
///
/// Examples:
///   kFormat(0)     → "0"
///   kFormat(999)   → "999"
///   kFormat(1000)  → "1k"
///   kFormat(1500)  → "2k"   (rounded to nearest by toStringAsFixed(0))
///   kFormat(92000) → "92k"
String kFormat(num value) {
  if (value < 0) return value.toInt().toString(); // defensive: no negative formatting
  if (value >= 1000) {
    return '${(value / 1000).toStringAsFixed(0)}k';
  }
  return value.toInt().toString();
}
```

Note on `toStringAsFixed(0)` rounding: 1500 → "2k", 1499 → "1k". This is acceptable for the volume stat (granularity at 1k is fine for the 92k UX). Documented in tests.

### B.4 ProfileScreen layout

Per Q1 (lock): stats row ONLY, on top of existing scaffold. Sign-out preserved.

```
ProfileScreen extends ConsumerWidget
  build(context, ref)
    final palette = AppPalette.of(context)
    final asyncStats = ref.watch(userSessionStatsProvider)

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 20),
          _OwnProfileStatsRow(asyncStats: asyncStats),   // NEW
          SizedBox(height: 20),
          Expanded(child: _ExistingScaffold()),          // PERFIL + sign-out, unchanged
        ],
      ),
    )

_OwnProfileStatsRow(AsyncValue<UserSessionStats?> asyncStats)
  → when:
     loading → 3-tile skeleton (same heights, shimmering values)
     error   → Row of 3 tiles with '--' values, accent + textPrimary colors preserved
     data    → Row spaceBetween:
                _StatTile('SESIONES',   '${stats.totalSessions}',     accent=true)
                _StatTile('VOLUMEN KG', kFormat(stats.totalVolumeKg), accent=true)
                _StatTile('RACHA',      '${stats.streak}',            highlight=true)  // magenta
```

Color routing matches mockup: SESIONES + VOLUMEN KG in `palette.accent` (green/mint), RACHA in `palette.highlight` (magenta). Reuse existing `_StatTile` style from `PublicProfileStatsRow` if compatible — but since that widget is in `feed/`, copy the styling logic into a private `_StatTile` in `profile_screen.dart` to avoid cross-feature widget import.

### B.5 AsyncValue routing

| State | Tiles | Sign-out |
|---|---|---|
| loading | Shimmer placeholders | Visible (unaffected) |
| error | "--" placeholders, palette colors preserved | Visible |
| data (no auth) | Stats row hidden | Visible (defensive; route is auth-gated) |
| data | Real values via kFormat | Visible |

Sign-out is in the existing scaffold and is ALWAYS rendered regardless of stats state. Q1 lock guarantee.

### B.6 Tests

- `number_format_test.dart`:
  - kFormat(0) → "0"
  - kFormat(999) → "999"
  - kFormat(1000) → "1k"
  - kFormat(1499) → "1k"
  - kFormat(1500) → "2k"
  - kFormat(92000) → "92k"
  - kFormat(999_999) → "1000k" (documented edge — large but no M format in scope)
  - kFormat(-5) → "-5" (defensive)
- `profile_stats_providers_test.dart` (uses fake SessionRepository injected via ProviderContainer override):
  - SC-STATS-1: empty sessions → totalSessions=0, totalVolumeKg=0, streak=0
  - SC-STATS-2: 3 finished + 1 active → totalSessions=3, totalVolume sums only finished, streak counts only finished
  - SC-STATS-3: when uid is null → provider returns null
- `profile_screen_test.dart`:
  - Renders sign-out button regardless of stats state
  - data state shows real numbers
  - loading state shows skeletons
  - error state shows "--" placeholders, sign-out still tappable

### B.7 ADRs (PR#2)

| ADR | Decision | Rationale | Rejected |
|---|---|---|---|
| ADR-WRS-05 | Stats row prepended to existing scaffold, NOT full ProfileScreen rebuild | Q1 lock; scope hygiene; rebuilding profile is its own etapa | Full rebuild per profile.png — rejected: blows 400 LOC budget, conflicts with future Coach profile work |
| ADR-WRS-06 | `kFormat` lives in `lib/core/utils/number_format.dart` | Cross-cutting utility (will be reused by public profile in PR#3 and likely insights/feed later); avoids feature-local duplication | Co-locate in `profile/presentation/` — rejected: 2 callers already known (PR#2 + PR#3 public stats) |
| ADR-WRS-07 | New `UserSessionStats` DTO instead of returning a record `(int, double, int)` | Named fields prevent positional bugs; ergonomic for widget consumption (`stats.totalVolumeKg`); easy to extend | Tuple/record — rejected: weaker type safety; one more refactor when a 4th field appears |
| ADR-WRS-08 | Lift `_computeStreak` into shared `streak_calculator.dart` in PR#2 (not PR#1) | Keeps PR#1 minimal and focused on the Home wire; PR#2 is the second consumer, so it owns the extraction | Duplicate the function in PR#2 — rejected: drift risk; tests would need to be duplicated too |

---

## Section C — Public Profile Cross-Feature Writes Design (PR#3)

### C.1 File map

| File | Op | Reason |
|---|---|---|
| `lib/features/profile/domain/user_public_profile.dart` | MODIFY | Add 4 nullable counter fields; Freezed regen |
| `lib/features/profile/domain/user_public_profile.freezed.dart` | REGEN | Freezed generator |
| `lib/features/profile/domain/user_public_profile.g.dart` | REGEN | json_serializable generator |
| `lib/features/profile/data/user_public_profile_repository.dart` | NO CHANGE | `set()` already merge-writes; nullable fields no-op when null |
| `lib/features/workout/data/session_repository.dart` | MODIFY | `finish()` triggers public counter refresh via injected `UserPublicProfileRepository`; new ctor param + try/catch wrapper |
| `lib/features/workout/application/session_providers.dart` | MODIFY | `sessionRepositoryProvider` wires the new dependency |
| `lib/features/feed/data/friendship_repository.dart` | MODIFY | `accept()` + `delete()` trigger cross-feature counter writes |
| `lib/features/feed/application/public_profile_providers.dart` | MODIFY | `_friendshipRepositoryProvider` wires new dependency; `publicProfileViewProvider` pass-through of 4 counters |
| `lib/features/feed/domain/public_profile_view.dart` | MODIFY | Add 4 nullable counter fields |
| `lib/features/feed/presentation/widgets/public_profile_stats_row.dart` | MODIFY | Parameterized 4 values; null-coalesce to "0"; reuse `kFormat` |
| `lib/features/feed/presentation/public_profile_screen.dart` | TOUCH | Pass real counters from `PublicProfileView` to the widget |
| `test/features/workout/data/session_repository_test.dart` | MODIFY | New tests: cross-feature write happens; write failure does NOT throw |
| `test/features/feed/data/friendship_repository_test.dart` | MODIFY | New tests: accept/delete refresh both members' counters; failure swallowed |
| `test/features/feed/presentation/widgets/public_profile_stats_row_test.dart` | MODIFY | Parameterized rendering + null fallback |

### C.2 UserPublicProfile Freezed additions

```dart
@freezed
class UserPublicProfile with _$UserPublicProfile {
  const factory UserPublicProfile({
    required String uid,
    String? displayName,
    String? displayNameLowercase,
    String? avatarUrl,
    String? gymId,
    int? workoutsCount,     // NEW — public-soft
    int? racha,             // NEW — public-soft
    int? followersCount,    // NEW — public-soft
    int? followingCount,    // NEW — public-soft
  }) = _UserPublicProfile;

  factory UserPublicProfile.fromJson(Map<String, Object?> json) =>
      _$UserPublicProfileFromJson(json);
}
```

All 4 fields nullable to preserve backwards compatibility (pre-backfill users have null → UI shows "0"). NO backfill script needed; counters populate lazily on the next session finish / friendship event (per proposal rollback note).

### C.3 Cross-feature write strategy

The architectural challenge: `SessionRepository` and `FriendshipRepository` need to MUTATE `userPublicProfiles/{uid}` from inside their own feature modules. Three options were considered:

| Option | Pros | Cons | Verdict |
|---|---|---|---|
| (A) Direct dependency: repos take `UserPublicProfileRepository` in ctor | Simple, no new abstractions; one Firestore write per event; testable via DI override | Introduces feature-to-feature coupling (workout → profile, feed → profile) | CHOSEN |
| (B) Domain event bus: repos emit `SessionFinished` / `FriendshipChanged`, a listener in `profile/` writes counters | Decouples features; aligns with event-sourcing direction | New infra (event bus + listener lifecycle); test surface grows; latency between event and write | Rejected — over-engineered for 2 call sites |
| (C) Cloud Function trigger on Firestore writes | Server-authoritative; client cannot drift | Phase 6 work; cost; cold-start latency; out of scope per proposal | Rejected — explicit out-of-scope |

**Chosen pattern**: thin direct dependency. Each mutating repository accepts an optional `UserPublicProfileRepository` in its constructor (default-constructible for tests that don't care about counter writes). The write is wrapped in `try/catch` and never rethrows — the cross-feature write is best-effort.

**Why no service layer**: a `WorkoutStatsService` orchestrating SessionRepository + UserPublicProfileRepository would be ceremony for a single call site. Inverted: when a third call site appears (e.g., a backfill script), THAT is the moment to extract a service. Today, the repository owns its post-write side effect.

#### C.3.1 SessionRepository.finish() — wired

```dart
class SessionRepository {
  SessionRepository({
    required FirebaseFirestore firestore,
    UserPublicProfileRepository? userPublicProfileRepo,   // NEW, optional
  })  : _firestore = firestore,
        _userPublicProfileRepo = userPublicProfileRepo;

  final FirebaseFirestore _firestore;
  final UserPublicProfileRepository? _userPublicProfileRepo;

  Future<void> finish({
    required String uid,
    required String sessionId,
    required DateTime finishedAt,
    required double totalVolumeKg,
    required int durationMin,
    bool wasFullyCompleted = false,
  }) async {
    // 1. EXISTING: update the session doc.
    await _sessions(uid).doc(sessionId).update({
      'status': SessionStatusX(SessionStatus.finished).toJson(),
      'finishedAt': Timestamp.fromDate(finishedAt.toUtc()),
      'totalVolumeKg': totalVolumeKg,
      'durationMin': durationMin,
      'wasFullyCompleted': wasFullyCompleted,
    });

    // 2. NEW: refresh public counters. Best-effort — never blocks session finish.
    final pub = _userPublicProfileRepo;
    if (pub == null) return;
    try {
      final all = await listByUid(uid);
      final finished = all.where((s) => s.status == SessionStatus.finished);
      final stats = (
        workouts: finished.length,
        racha: computeStreak(finished, now: DateTime.now().toLocal()),
      );
      await pub.set(UserPublicProfile(
        uid: uid,
        workoutsCount: stats.workouts,
        racha: stats.racha,
      ));
    } catch (e, st) {
      developer.log(
        'wire-real-stats: failed to refresh public counters for $uid',
        error: e,
        stackTrace: st,
        name: 'SessionRepository.finish',
      );
      // Intentionally no rethrow — public stats are best-effort.
    }
  }
}
```

`_userPublicProfileRepo` is optional so existing tests that construct `SessionRepository(firestore: fake)` still work. Production wiring uses the new constructor param.

#### C.3.2 FriendshipRepository.accept() and delete() — wired

```dart
class FriendshipRepository {
  FriendshipRepository({
    required FirebaseFirestore firestore,
    UserPublicProfileRepository? userPublicProfileRepo,   // NEW, optional
  })  : _firestore = firestore,
        _userPublicProfileRepo = userPublicProfileRepo;
  // ...

  Future<void> accept(String friendshipId, String myUid) async {
    // ... existing logic (read, validate, update status='accepted') ...
    await _friendships.doc(friendshipId).update({
      'status': FriendshipStatus.accepted.toJson(),
    });
    // After the doc transitions to 'accepted', both members' followers/following
    // counts changed. Refresh both.
    final members = (data['members'] as List).cast<String>();
    await _refreshCountersFor(members);
  }

  Future<void> delete(String friendshipId) async {
    // Read BEFORE delete to capture members (delete returns void).
    final snap = await _friendships.doc(friendshipId).get();
    final members = snap.exists
        ? (snap.data()!['members'] as List).cast<String>()
        : const <String>[];

    await _friendships.doc(friendshipId).delete();

    if (members.isNotEmpty) {
      await _refreshCountersFor(members);
    }
  }

  Future<void> _refreshCountersFor(List<String> uids) async {
    final pub = _userPublicProfileRepo;
    if (pub == null) return;
    for (final uid in uids) {
      try {
        final friends = await acceptedFriendsOf(uid);
        final followers = friends.length;       // accepted = symmetric → same count
        final following = friends.length;
        await pub.set(UserPublicProfile(
          uid: uid,
          followersCount: followers,
          followingCount: following,
        ));
      } catch (e, st) {
        developer.log(
          'wire-real-stats: failed to refresh follower counts for $uid',
          error: e, stackTrace: st,
          name: 'FriendshipRepository._refreshCountersFor',
        );
        // Best-effort.
      }
    }
  }
}
```

Open detail — `followersCount` vs `followingCount`: in the current data model, `friendships` is symmetric (accepted both ways simultaneously), so for a given user, followers == following == count of accepted edges. We still write BOTH fields so the UI surface is forward-compatible if an asymmetric follow model ever ships.

**Symmetric write side-effect**: `_refreshCountersFor` writes to `userPublicProfiles/{otherMember}`. This is a write by uid A to userPublicProfiles/B. Rule audit (§E.1) confirms this is BLOCKED today — only the owner can write. See Audit Gap A1.

Wait — that's a real gap. Re-reading the rules:

```
match /userPublicProfiles/{uid} {
  allow update: if request.auth != null
                && request.auth.uid == uid
                && request.resource.data.uid == resource.data.uid;
}
```

uid A CANNOT write to userPublicProfiles/B. The cross-write would fail. Caller (uid A) accepts friendship → tries to update B's counters → DENIED.

**Mitigation**: each member updates THEIR OWN public counters when THEY perform a friendship op. Specifically:
- `accept(friendshipId, myUid)` — only the accepter (myUid) writes their own counters. The requester's counters drift until the requester next performs ANY friendship op (e.g., requests another friend) OR until next session finish triggers a counter refresh that includes followers/following.

But session finish only writes workoutsCount+racha, not followersCount. We have two clean choices:

| Option | Mechanics | Verdict |
|---|---|---|
| (i) Loosen the rule: allow members of the same friendship to refresh each other's `followersCount`/`followingCount` only | Rules carve-out; introduces a narrow trust boundary | Rejected — increases rule complexity, requires PR#3 rules change (was scoped to PR#4 only) |
| (ii) Self-only refresh: each user writes ONLY their own counters when they perform an op | Simple; no rule change; eventual consistency: the OTHER member's count is one event behind until they act | CHOSEN |
| (iii) Cloud Function | Server-authoritative; correct | Out of scope |

**Decision**: Self-only refresh. After `accept(friendshipId, myUid)`, only `myUid`'s counters are refreshed. After `delete(friendshipId)`, ONLY the caller's counters are refreshed (need to thread `myUid` into `delete()` too — see signature change below).

Updated FriendshipRepository design:

```dart
Future<void> accept(String friendshipId, String myUid) async {
  // ... existing logic ...
  await _refreshCountersForSelf(myUid);
}

Future<void> delete(String friendshipId, String myUid) async {  // SIG CHANGE
  await _friendships.doc(friendshipId).delete();
  await _refreshCountersForSelf(myUid);
}

Future<void> _refreshCountersForSelf(String uid) async {
  final pub = _userPublicProfileRepo;
  if (pub == null) return;
  try {
    final friends = await acceptedFriendsOf(uid);
    final n = friends.length;
    await pub.set(UserPublicProfile(
      uid: uid,
      followersCount: n,
      followingCount: n,
    ));
  } catch (e, st) {
    developer.log(/* ... */);
  }
}
```

`delete()` signature change is BREAKING for callers. Audit of callers (search `friendshipRepository.delete` / `.delete(`) is mandatory in PR#3 implementation. Expected callers: friendship list screens (accept-pending or unfriend buttons). Each caller already has `myUid` in scope (it's their own UI).

The "eventual one-event-behind" drift for the OTHER member is acceptable: as soon as they open Feed → trigger ANY friendship-related action OR finish a session → their userPublicProfile is touched (session finish refreshes workouts+racha; we extend it to ALSO refresh followers/following in the finish() call). That closes the drift window cheaply.

Refined: `SessionRepository.finish()` now refreshes ALL 4 counters in one merge write (workouts, racha, followers, following). The follower counts come from `acceptedFriendsOf(uid)`.

```dart
// inside finish() try block
final all = await listByUid(uid);
final finished = all.where((s) => s.status == SessionStatus.finished);

// Inject the friendship repo too? Or reach via DI? Better: pass a
// "computeFollowerCount" closure to SessionRepository at construction time
// to avoid coupling SessionRepository to FriendshipRepository directly.
final followers = await _followerCountResolver?.call(uid) ?? null;

await pub.set(UserPublicProfile(
  uid: uid,
  workoutsCount: finished.length,
  racha: computeStreak(finished, now: DateTime.now().toLocal()),
  followersCount: followers,
  followingCount: followers,
));
```

Final shape — `SessionRepository` accepts:
- `UserPublicProfileRepository? userPublicProfileRepo`
- `Future<int> Function(String uid)? followerCountResolver` — closure that wraps `FriendshipRepository.acceptedFriendsOf(uid).length`. Optional; null → skip follower fields (still merge-writes the rest).

This pattern keeps SessionRepository from importing the feed feature.

### C.4 PublicProfileView DTO additions

```dart
@freezed
class PublicProfileView with _$PublicProfileView {
  const factory PublicProfileView({
    required String authorDisplayName,
    required String? authorAvatarUrl,
    required String? authorGymId,
    required Friendship? friendship,
    required bool isSelf,
    required int? workoutsCount,    // NEW
    required int? racha,            // NEW
    required int? followersCount,   // NEW
    required int? followingCount,   // NEW
  }) = _PublicProfileView;
}
```

### C.5 publicProfileViewProvider pass-through

```dart
final publicProfileViewProvider =
    FutureProvider.family<PublicProfileView, String>((ref, targetUid) async {
  // ... existing logic ...
  return PublicProfileView(
    authorDisplayName: publicProfile?.displayName ?? 'Anónimo',
    authorAvatarUrl: publicProfile?.avatarUrl,
    authorGymId: publicProfile?.gymId,
    friendship: friendship,
    isSelf: isSelf,
    workoutsCount: publicProfile?.workoutsCount,
    racha: publicProfile?.racha,
    followersCount: publicProfile?.followersCount,
    followingCount: publicProfile?.followingCount,
  );
});
```

No new Firestore reads — counters arrive in the SAME `userPublicProfileProvider` fetch.

### C.6 PublicProfileStatsRow parameterization

```dart
class PublicProfileStatsRow extends StatelessWidget {
  const PublicProfileStatsRow({
    super.key,
    required this.workoutsCount,
    required this.racha,
    required this.followersCount,
    required this.followingCount,
  });

  final int? workoutsCount;
  final int? racha;
  final int? followersCount;
  final int? followingCount;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(child: _StatTile(label: 'WORKOUTS',  value: kFormat(workoutsCount ?? 0))),
        Expanded(child: _StatTile(label: 'RACHA',     value: '${racha ?? 0}', isAccent: true)),
        Expanded(child: _StatTile(label: 'SEGUIDORES',value: kFormat(followersCount ?? 0))),
        Expanded(child: _StatTile(label: 'SIGUIENDO', value: kFormat(followingCount ?? 0))),
      ],
    );
  }
}
```

Null → "0". `kFormat` applied to WORKOUTS / SEGUIDORES / SIGUIENDO (could grow large); RACHA stays raw (mockup shows small numbers like "23"). RACHA accent color preserved.

### C.7 Tests

- `session_repository_test.dart` additions (using `fake_cloud_firestore`):
  - SC-PR3-1: `finish()` writes session doc (existing) AND writes counters to `userPublicProfiles/{uid}` with workoutsCount, racha, followers, following
  - SC-PR3-2: when `userPublicProfileRepo` is null (test default), `finish()` still updates session doc and does NOT throw
  - SC-PR3-3: when `userPublicProfileRepo.set` throws, `finish()` STILL completes — session doc update succeeds, no exception propagated. Verified by injecting a failing fake repo that throws on `set()`.
  - SC-PR3-4: counter refresh uses the SAME computeStreak as Home/Profile (regression-check shared function)
- `friendship_repository_test.dart` additions:
  - SC-PR3-5: `accept(friendshipId, myUid)` refreshes ONLY myUid's followersCount/followingCount
  - SC-PR3-6: `delete(friendshipId, myUid)` refreshes ONLY myUid's counters
  - SC-PR3-7: when `userPublicProfileRepo.set` throws, both accept and delete still succeed
- `public_profile_stats_row_test.dart`:
  - Renders kFormat-applied values for large workouts/followers/following
  - Null fields render as "0"
  - RACHA tile uses accent color

### C.8 ADRs (PR#3)

| ADR | Decision | Rationale | Rejected |
|---|---|---|---|
| ADR-WRS-09 | Denormalized counters in `userPublicProfiles` (Q4, Q5 lock) | Public read = single doc fetch; matches existing displayName denorm pattern; rules already permit any auth user to read | Query-based counts — rejected: 2 extra Firestore queries per public profile view, scales poorly |
| ADR-WRS-10 | Cross-feature writes wrapped in `try/catch`, NEVER rethrow | Session finish UX must not fail because a secondary write failed (network blip, transient rule mismatch); counters are best-effort and self-heal on the next event | Rethrow + UI surface — rejected: would block users mid-workout-finish for a cosmetic counter; misaligned priority |
| ADR-WRS-11 | Direct repository-to-repository dependency (no service layer, no event bus) | Two known call sites; service layer = ceremony; event bus = infra over-build | Event bus / domain events — rejected: over-engineering for the current call-site count |
| ADR-WRS-12 | Self-only counter refresh on friendship accept/delete; other member self-heals on next event | Stays within existing rules (no rules change in PR#3); avoids cross-uid writes to userPublicProfiles which the current rule denies; eventual consistency window is bounded by next session finish or next friendship action of the other user | Loosen userPublicProfiles update rule to allow same-friendship members to write each other's followers/following — rejected: increases rule attack surface, breaks PR scope (rules changes consolidated in PR#4) |
| ADR-WRS-13 | `SessionRepository.finish()` takes an OPTIONAL `followerCountResolver` closure instead of importing FriendshipRepository | Keeps workout feature decoupled from feed feature; resolver is plumbed at provider-wire time; test default = null = skip follower fields | Direct FriendshipRepository import in SessionRepository — rejected: cyclic feature dependency risk (workout ↔ feed both depend on profile, but importing each other inverts the layering) |

---

## Section D — Check-in Design (PR#4)

### D.1 File map

| File | Op | Reason |
|---|---|---|
| `lib/features/check_in/domain/check_in.dart` | CREATE | Freezed model + `dateKey()` helper |
| `lib/features/check_in/data/check_in_repository.dart` | CREATE | `createTodayIfAbsent` + `getTodayForUser` |
| `lib/features/check_in/application/check_in_providers.dart` | CREATE | `checkInRepositoryProvider`, `todayCheckInProvider`, `checkInNotifier` |
| `lib/features/check_in/presentation/check_in_dialog.dart` | CREATE | Dialog widget matching `check-in.png` |
| `lib/features/check_in/presentation/check_in_strings.dart` | CREATE | UI copy constants (es-AR) |
| `lib/features/feed/feed_screen.dart` | MODIFY | Mount trigger; session-scoped flag |
| `firestore.rules` | MODIFY | New `/users/{uid}/checkIns/{date}` block |
| `scripts/rules_test/rules.test.js` | MODIFY | 3 new SCENARIOs |
| `test/features/check_in/domain/check_in_test.dart` | CREATE | dateKey + Freezed roundtrip |
| `test/features/check_in/data/check_in_repository_test.dart` | CREATE | Repo CRUD with fake_cloud_firestore |
| `test/features/check_in/application/check_in_providers_test.dart` | CREATE | Provider behavior + auth gating |
| `test/features/check_in/presentation/check_in_dialog_test.dart` | CREATE | Widget test: SI/NO buttons, gym display |
| `test/features/feed/feed_screen_check_in_test.dart` | CREATE | Trigger fires once per session, gated on todayCheckInProvider |

### D.2 CheckIn Freezed model

```dart
import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:freezed_annotation/freezed_annotation.dart';

import '../../profile/data/timestamp_converter.dart';

part 'check_in.freezed.dart';
part 'check_in.g.dart';

@freezed
class CheckIn with _$CheckIn {
  const factory CheckIn({
    required String uid,
    /// 'YYYY-MM-DD' in user local time. Also the Firestore doc id → natural dedup.
    required String date,
    @TimestampConverter() required DateTime checkedInAt,
    String? gymId,
    String? gymName,
  }) = _CheckIn;

  factory CheckIn.fromJson(Map<String, Object?> json) =>
      _$CheckInFromJson(json);

  /// Returns 'YYYY-MM-DD' for the given LOCAL date. Zero-pads month/day.
  static String dateKey(DateTime localDate) {
    final y = localDate.year.toString().padLeft(4, '0');
    final m = localDate.month.toString().padLeft(2, '0');
    final d = localDate.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
```

Reuses the existing `TimestampConverter` (already in `lib/features/profile/data/timestamp_converter.dart` — same pattern as Session).

### D.3 CheckInRepository API

```dart
class CheckInRepository {
  CheckInRepository({required FirebaseFirestore firestore})
      : _firestore = firestore;

  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, Object?>> _col(String uid) =>
      _firestore.collection('users').doc(uid).collection('checkIns');

  /// Reads the check-in for [localDate] (uses dateKey to derive doc id).
  Future<CheckIn?> getForDate({
    required String uid,
    required DateTime localDate,
  }) async {
    final id = CheckIn.dateKey(localDate);
    final snap = await _col(uid).doc(id).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return CheckIn.fromJson(data);
  }

  /// Creates today's check-in for [uid]. No-op (returns existing) if a doc
  /// for the same date already exists. Uses `set` with merge:false on the
  /// dated doc id — second call returns the previously-written CheckIn
  /// without overwriting.
  Future<CheckIn> createTodayIfAbsent({
    required String uid,
    required DateTime now,
    String? gymId,
    String? gymName,
  }) async {
    final local = now.toLocal();
    final id = CheckIn.dateKey(local);
    final ref = _col(uid).doc(id);
    final existing = await ref.get();
    if (existing.exists) {
      return CheckIn.fromJson(existing.data()!);
    }
    final checkIn = CheckIn(
      uid: uid,
      date: id,
      checkedInAt: now.toUtc(),
      gymId: gymId,
      gymName: gymName,
    );
    await ref.set(checkIn.toJson());
    return checkIn;
  }
}
```

Auth-gated at the provider layer (not in the repo).

### D.4 todayCheckInProvider

```dart
final checkInRepositoryProvider = Provider<CheckInRepository>(
  (ref) => CheckInRepository(firestore: ref.watch(firestoreProvider)),
);

/// Returns today's check-in for the current user, or null if not checked in
/// today. autoDispose: re-fetched on FeedScreen remount.
final todayCheckInProvider =
    FutureProvider.autoDispose<CheckIn?>((ref) async {
  final uid = ref.watch(currentUidProvider);
  if (uid == null) return null;
  return ref
      .watch(checkInRepositoryProvider)
      .getForDate(uid: uid, localDate: DateTime.now().toLocal());
});

/// AsyncNotifier wrapping the action of confirming a check-in. Exposes a
/// single `confirm()` method consumed by the dialog's SÍ button.
final checkInNotifierProvider =
    AsyncNotifierProvider<CheckInNotifier, CheckIn?>(CheckInNotifier.new);

class CheckInNotifier extends AsyncNotifier<CheckIn?> {
  @override
  Future<CheckIn?> build() async => null;

  Future<void> confirm({String? gymId, String? gymName}) async {
    final uid = ref.read(currentUidProvider);
    if (uid == null) return;
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() async {
      final result = await ref.read(checkInRepositoryProvider).createTodayIfAbsent(
            uid: uid,
            now: DateTime.now().toUtc(),
            gymId: gymId,
            gymName: gymName,
          );
      ref.invalidate(todayCheckInProvider);
      return result;
    });
  }
}
```

### D.5 CheckInDialog widget structure

**Implementation note (post-archive, per ADR-WRS-19)**: the dialog accepts
`gymId` and `gymName` as constructor props instead of reading
`userProfileProvider` inside the widget. The parent `FeedScreen` resolves
both via `userProfileProvider` + `gymNameFromId` before calling `showDialog`.
This keeps the dialog a pure presentation widget (no ambient provider
reads, no auth mocks needed in tests) and preserves Q7 (profile-based, NO
GPS — ADR-WRS-17): the lookup just moves up one level.

```
CheckInDialog extends ConsumerWidget
  const CheckInDialog({required this.gymId, required this.gymName, super.key})
  final String? gymId
  final String? gymName

  build(context, ref)
    final subtext = (gymId != null && gymName != null && gymName.isNotEmpty)
        ? CheckInStrings.gymSubtext(gymName)        // 'SMART FIT · ¡Detectamos que podés estar entrenando!'
        : CheckInStrings.neutralSubtext             // 'Sin gym configurado'
    return Dialog(
      backgroundColor: palette.bgCard,
      shape: RoundedRectangleBorder(borderRadius: 20),
      child: Padding(padding: EdgeInsets.all(20),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(TreinoIcon.mapPin, color: palette.accent, size: 48),
          SizedBox(height: 18),
          Text(CheckInStrings.header, style: barlowCondensed bold 18),
          SizedBox(height: 8),
          Text(subtext, style: bodyMuted),
          SizedBox(height: 20),
          Row(children: [
            Expanded(child: _NoButton(onPressed: () => Navigator.pop(context))),
            SizedBox(width: 12),
            Expanded(child: _SiButton(gymId: gymId, gymName: gymName, onPressed: () async {
              await ref.read(checkInNotifierProvider.notifier).confirm(
                gymId: gymId,
                gymName: gymName,
              );
              if (context.mounted) Navigator.pop(context);
            })),
          ]),
        ]),
      ),
    )
```

**Parent resolver** (FeedScreen, per D.6):

```
final profile = ref.read(userProfileProvider).valueOrNull;
final gymId = profile?.gymId;
final gymName = gymId != null ? gymNameFromId(gymId) : null;
showDialog(context: context, builder: (_) => CheckInDialog(
  gymId: gymId,
  gymName: gymName?.isNotEmpty == true ? gymName : null,
));
```

Q7 lock: `gymId` is read from the current user's profile via
`userProfileProvider` — **at the parent layer**, not inside the dialog
(ADR-WRS-19). NO GPS. If `profile.gymId` is null, the dialog still shows but
the copy degrades to a neutral prompt; check-in records `gymId: null,
gymName: null` (allowed by schema).

### D.6 FeedScreen mount trigger

The trigger MUST: (a) fire once per session per day, (b) NOT fire if the user has already checked in today, (c) NOT fire repeatedly on tab switches.

```dart
// Session-scoped (process-lifetime) provider — resets on app restart.
final _checkInDialogShownThisSessionProvider = StateProvider<bool>((_) => false);

class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  @override
  void initState() {
    super.initState();
    // Defer to after first frame so we have a valid context for showDialog.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeShowCheckIn());
  }

  Future<void> _maybeShowCheckIn() async {
    if (!mounted) return;
    if (ref.read(_checkInDialogShownThisSessionProvider)) return;
    final today = await ref.read(todayCheckInProvider.future);
    if (today != null) return; // already checked in today
    if (!mounted) return;
    ref.read(_checkInDialogShownThisSessionProvider.notifier).state = true;
    await showDialog<void>(
      context: context,
      builder: (_) => const CheckInDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    // ... existing build body ...
  }
}
```

Q6 lock: dialog dismissal (NO button) is ALSO recorded as "shown this session" (the StateProvider is set BEFORE awaiting the dialog). NO does NOT create a Firestore doc; it only prevents re-showing for the rest of the session. Next app launch + still no check-in → dialog reappears.

**Why convert to ConsumerStatefulWidget**: We need `initState` for the post-frame callback. The existing `ConsumerWidget` can't trigger one-shot mount logic without abuse of `ref.listen` in build (which fires on every rebuild). StatefulWidget makes the lifecycle explicit.

### D.7 Firestore rules block

Insert AFTER the `/users/{uid}/sessions/{sessionId}` block (sibling sub-collection):

```
match /users/{uid}/checkIns/{date} {
  // Owner-only R/W on check-ins — location data tied to user identity.
  // REQ-WRC-004 (wire-real-stats Section D — Check-in).
  allow read, write: if request.auth != null
                     && request.auth.uid == uid;
}
```

Path consistency with `sessions` sub-collection (also `/users/{uid}/x/{y}`) — both are owner-scoped private data. No special create/update split needed; write covers create+update+delete and the date doc id provides natural dedup.

### D.8 Rules tests — 3 new SCENARIOs

Append after SCENARIO-271 in `scripts/rules_test/rules.test.js`:

```js
// ---------------------------------------------------------------------------
// SCENARIO-272: owner can write their own check-in doc. REQ-WRC-004.
// ---------------------------------------------------------------------------
test('SCENARIO-272: owner can create their own check-in for today', async () => {
  const u1 = testEnv.authenticatedContext('u1');
  await assertSucceeds(
    u1.firestore()
      .collection('users').doc('u1')
      .collection('checkIns').doc('2026-05-15')
      .set({
        uid: 'u1',
        date: '2026-05-15',
        checkedInAt: new Date(),
        gymId: 'smart-fit-palermo',
        gymName: 'Smart Fit · Palermo',
      }),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-273: non-owner is blocked from reading another user's check-in.
// ---------------------------------------------------------------------------
test('SCENARIO-273: non-owner cannot read another user check-in', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await ctx.firestore()
      .collection('users').doc('u1')
      .collection('checkIns').doc('2026-05-15')
      .set({ uid: 'u1', date: '2026-05-15', checkedInAt: new Date() });
  });
  const u2 = testEnv.authenticatedContext('u2');
  await assertFails(
    u2.firestore()
      .collection('users').doc('u1')
      .collection('checkIns').doc('2026-05-15').get(),
  );
});

// ---------------------------------------------------------------------------
// SCENARIO-274: non-owner is blocked from writing to another user's check-in.
// ---------------------------------------------------------------------------
test('SCENARIO-274: non-owner cannot write another user check-in', async () => {
  const u2 = testEnv.authenticatedContext('u2');
  await assertFails(
    u2.firestore()
      .collection('users').doc('u1')
      .collection('checkIns').doc('2026-05-15')
      .set({ uid: 'u1', date: '2026-05-15', checkedInAt: new Date() }),
  );
});
```

### D.9 Tests

- `check_in_test.dart` (domain):
  - `dateKey(DateTime(2026,5,15))` → "2026-05-15"
  - `dateKey(DateTime(2026,1,3))` → "2026-01-03" (zero-padding)
  - `dateKey(DateTime(99,5,15))` → "0099-05-15" (year padding)
  - Freezed roundtrip via `fromJson`/`toJson`
- `check_in_repository_test.dart`:
  - createTodayIfAbsent creates doc with correct id derived from local date
  - createTodayIfAbsent called twice same day → second returns existing, does NOT overwrite checkedInAt
  - getForDate returns null when no doc
  - getForDate returns CheckIn when doc exists
- `check_in_providers_test.dart`:
  - todayCheckInProvider returns null when unauthenticated
  - todayCheckInProvider returns null when authed but no check-in today
  - checkInNotifier.confirm() creates doc + invalidates todayCheckInProvider
- `check_in_dialog_test.dart`:
  - Renders gym name when profile.gymId is non-null
  - Renders neutral copy when gymId is null
  - NO button closes dialog without writing
  - SÍ button calls notifier.confirm and closes dialog
- `feed_screen_check_in_test.dart`:
  - Dialog appears on first FeedScreen mount when todayCheckInProvider is null
  - Dialog does NOT appear when todayCheckInProvider returns a CheckIn
  - Dialog does NOT reappear after dismissal during same session
  - Session-scoped flag resets via container reset (simulates app restart)

### D.10 ADRs (PR#4)

| ADR | Decision | Rationale | Rejected |
|---|---|---|---|
| ADR-WRS-14 | Collection path `/users/{uid}/checkIns/{date}` nested under user | Consistent with `/users/{uid}/sessions/{sessionId}`; rule template = copy of sessions; private health-adjacent data stays scoped to owner doc | Top-level `/checkIns/{id}` — rejected: requires composite-uid doc ids and more permissive rule writing |
| ADR-WRS-15 | Doc id = `YYYY-MM-DD` local date for natural dedup | One doc per day per user; no need for query+filter on date; idempotent writes; createTodayIfAbsent is a single read+conditional set | UUID + date field + uniqueness query — rejected: more expensive, race conditions on concurrent writes |
| ADR-WRS-16 | Session-scoped flag (`StateProvider<bool>`) for trigger guard, in addition to `todayCheckInProvider` | Prevents dialog re-show on tab switch within the same app session; flag resets at process restart so the dialog reappears the next day if user hasn't acted | Persisting dismissal to Firestore — rejected: dismissal is not data, just UX; persisting creates spurious "I said no" doc + Firestore cost |
| ADR-WRS-17 | NO GPS, NO mood/energy sliders (Q7, Q8 lock) | Roadmap "básico" scope; GPS adds permission flow + dependency (geolocator); mood/energy is a separate Etapa | Add geolocator + mood sliders — rejected: scope creep; explicit out of scope in proposal |
| ADR-WRS-18 | FeedScreen converted to ConsumerStatefulWidget (not abusing ref.listen in build) | Mount-once trigger requires StatefulWidget lifecycle; addPostFrameCallback gives a safe context for showDialog | Use ref.listen in build of ConsumerWidget — rejected: fires on every rebuild; needs manual dedup; harder to reason about |
| ADR-WRS-19 | `CheckInDialog` receives `gymId`/`gymName` as constructor props (resolved by parent `FeedScreen._maybeShowCheckIn`) instead of reading `userProfileProvider` inside the widget — supersedes D.5 sketch | Container-presentational pattern declared in CLAUDE.md user prefs; dialog tests stay free of auth/provider mocking; zero coupling to the `profile` feature; Q7 lock (profile-based, NO GPS — ADR-WRS-17) preserved (lookup just moves to the parent). Deviation discovered + approved during PR#4 apply; promoted to ADR here per archive. | Read `userProfileProvider` inline in the dialog (the original D.5 sketch) — rejected: couples the dialog to ambient providers, complicates tests with overrides, and gives no meaningful reactivity (the dialog lives ~3 s; profile.gymId does not change mid-session) |

---

## Section E — Cross-cutting

### E.1 Rules Audit

Every Firestore query/write touched by this change:

| # | PR | Operation | Caller context | Required rule | Current rule | Verdict |
|---|---|---|---|---|---|---|
| 1 | PR#1 | READ `users/{uid}/sessions` (listByUid) | weeklyInsightsProvider, authed as uid | owner-only read | `allow read, write: if request.auth.uid == uid` (existing sessions block) | PASS |
| 2 | PR#1 | READ `users/{uid}/sessions/{sid}/setLogs` (listSetLogs) | weeklyInsightsProvider | owner-only | nested setLogs block (existing) | PASS |
| 3 | PR#2 | READ `users/{uid}/sessions` (listByUid for stats) | userSessionStatsProvider, authed as uid | owner-only | same as #1 | PASS |
| 4 | PR#3 | UPDATE `users/{uid}/sessions/{sid}` (finish, existing) | SessionRepository.finish | owner-only write | existing sessions block | PASS |
| 5 | PR#3 | WRITE `userPublicProfiles/{uid}` (SessionRepository.finish cross-feature) | SessionRepository.finish, authed as uid, writing to OWN public profile | owner-only update; uid in body == doc id | `allow update: if request.auth.uid == uid && request.resource.data.uid == resource.data.uid` (existing) | PASS — caller IS the owner |
| 6 | PR#3 | READ `friendships` where members array-contains uid (acceptedFriendsOf) | SessionRepository.finish → followerCountResolver | members can read | `allow read: if request.auth.uid in resource.data.members` | PASS |
| 7 | PR#3 | UPDATE `friendships/{id}` (accept, existing) | FriendshipRepository.accept | non-requester member can accept | existing friendships update rule | PASS |
| 8 | PR#3 | DELETE `friendships/{id}` (delete, existing) | FriendshipRepository.delete | either member can delete | existing friendships delete rule | PASS |
| 9 | PR#3 | WRITE `userPublicProfiles/{myUid}` (FriendshipRepository self-refresh) | FriendshipRepository.accept/delete, authed as myUid, writing to OWN public profile | owner-only update | same as #5 | PASS |
| 10 | PR#3 | READ `userPublicProfiles/{targetUid}` (PublicProfileView consumer) | publicProfileViewProvider, any authed | any authed read | existing rule | PASS |
| 11 | PR#4 | READ `users/{uid}/checkIns/{date}` (getForDate) | todayCheckInProvider, authed as uid | owner-only read | NONE — collection not yet ruled | GAP-A1 — closed by new block in PR#4 |
| 12 | PR#4 | WRITE `users/{uid}/checkIns/{date}` (createTodayIfAbsent) | CheckInRepository.createTodayIfAbsent, authed as uid | owner-only write | NONE | GAP-A1 — closed by same new block |

**Total GAPs: 1** (combined into a single new rule block in PR#4 covering both read and write).

### E.2 Field Privacy Classification

#### E.2.1 PR#3 — UserPublicProfile additions

| Field | Type | Classification | Goes to `userPublicProfiles`? | Reason |
|---|---|---|---|---|
| workoutsCount | int? | public-soft | YES | Derived count from private sessions; the count itself is non-identifying and matches the public profile UX goal |
| racha | int? | public-soft | YES | Derived count; non-identifying; visible on public profile per mockup |
| followersCount | int? | public-soft | YES | Derived count of friendship edges; both sides visible in social product UX |
| followingCount | int? | public-soft | YES | Same as followersCount |

NO source private fields (Session contents, friendship ids/members) are exposed in `userPublicProfiles`. Only the aggregate counts.

#### E.2.2 PR#4 — CheckIn fields

| Field | Type | Classification | Exposure |
|---|---|---|---|
| uid | String | private | Owner only |
| date | String | private | Owner only |
| checkedInAt | Timestamp | private | Owner only |
| gymId | String? | private (location data) | Owner only |
| gymName | String? | private (location data) | Owner only |

**Confirmed**: NO check-in field ever propagates to `userPublicProfiles`. Check-in is private telemetry only.

### E.3 PR chain mechanics

```
main
  └── feat/wire-real-stats-home              (PR#1) → squash-merge to main
       └── feat/wire-real-stats-own-profile  (PR#2) → rebases on main after PR#1 merges
            └── feat/wire-real-stats-public-profile (PR#3) → rebases on main after PR#2
                 └── feat/wire-real-stats-checkin    (PR#4) → rebases on main after PR#3
```

- Each PR targets `main` directly (no feature branch). Stacked-on-each-other locally; rebased forward when the predecessor merges.
- Dependency map:
  - PR#2 depends on PR#1's `_computeStreak` (PR#2 will lift it into `streak_calculator.dart` and re-export). If PR#1 is still open, PR#2 dev branches off PR#1's tip.
  - PR#3 depends on PR#2's `kFormat` helper (used in `PublicProfileStatsRow`) and on the existence of `streak_calculator.dart` (used in `SessionRepository.finish`).
  - PR#4 is fully independent of PR#1–3 in behavior, but ships AFTER them so the chain stays sequential.
- Rebase discipline: when PR#N merges, rebase PR#N+1 immediately. Resolve conflicts at rebase time, not at merge time. Keep `git rerere` enabled.

### E.4 TDD order per PR

| PR | Test-first order |
|---|---|
| PR#1 | (1) Write streak unit tests → (2) implement `_computeStreak` → (3) write monthSessionsCount tests → (4) implement → (5) write provider integration test (DTO has new fields) → (6) wire provider → (7) write widget test for ConsumerWidget routing → (8) implement EstaSemanaCard |
| PR#2 | (1) Write `kFormat` tests → (2) implement helper → (3) lift `_computeStreak` into shared file + adjust PR#1 tests if needed → (4) write `userSessionStatsProvider` tests with fake repo → (5) implement provider → (6) write ProfileScreen widget test → (7) implement screen |
| PR#3 | (1) Write SessionRepository.finish tests (success + failure swallow) → (2) modify finish() → (3) write FriendshipRepository tests (self-refresh on accept/delete + failure swallow) → (4) modify accept/delete → (5) write PublicProfileStatsRow parameterized tests → (6) modify widget → (7) wire providers + DTOs |
| PR#4 | (1) Write `dateKey` tests → (2) implement model → (3) write repository tests with fake_cloud_firestore → (4) implement repo → (5) write provider tests → (6) implement providers → (7) write dialog widget test → (8) implement dialog → (9) write FeedScreen trigger test → (10) modify FeedScreen → (11) write rules tests → (12) modify firestore.rules → (13) run rules test suite |

Strict TDD: every step writes the test BEFORE the implementation. Mandatory red → green → refactor.

### E.5 Style consistency notes

- **Palette**: All new widgets use `AppPalette.of(context)`. NEVER `Color(0xFF…)` or `Colors.X` literals. Mint Magenta tokens: accent (mint green), highlight (magenta), bg, bgCard, border, textPrimary, textMuted.
- **Icons**: `TreinoIcon.mapPin` (NEW addition to TreinoIcon if not present; otherwise use existing pin icon). NEVER `PhosphorIcons.X` directly in feature code.
- **Typography**: `GoogleFonts.barlowCondensed` for labels/headings, `GoogleFonts.barlow` for values/body. Letter spacing 1.0–1.4 for UPPERCASE labels.
- **Spacing**: 8 / 12 / 14 / 18 / 20 only. No 10, 16, 24 etc. Check each `SizedBox`/`EdgeInsets` literal.
- **Const constructors**: Use `const` wherever the tree allows. ConsumerWidgets that read providers cannot be `const` constructors themselves but their static child widgets can.
- **Freezed**: Used for new `CheckIn`, additions to `UserPublicProfile`, additions to `PublicProfileView`. NOT introduced to `WeeklyInsights` (kept hand-written — ADR-WRS-04).
- **Naming**: `userSessionStatsProvider`, `todayCheckInProvider`, `checkInNotifierProvider`, `checkInRepositoryProvider`, `_computeStreak`, `kFormat`, `CheckIn.dateKey`. Match existing snake_case file names, camelCase identifiers, PascalCase types.
- **UI copy**: Spanish (Rioplatense, voseo) for user-facing strings — matches existing screens. Identifiers and comments in English.
- **Logs**: `developer.log(... name: '<ClassName>.<method>')` pattern, NEVER `print`.

---

## ADR Index (18 total)

| ID | Title | PR |
|---|---|---|
| ADR-WRS-01 | Extend WeeklyInsights DTO over new provider | PR#1 |
| ADR-WRS-02 | Streak today inclusion (Q2 lock) | PR#1 |
| ADR-WRS-03 | Calendar month boundary (Q3 lock) | PR#1 |
| ADR-WRS-04 | Keep hand-written immutable for WeeklyInsights | PR#1 |
| ADR-WRS-05 | Stats row only, preserve sign-out scaffold (Q1 lock) | PR#2 |
| ADR-WRS-06 | kFormat in core/utils | PR#2 |
| ADR-WRS-07 | New UserSessionStats DTO (not a record) | PR#2 |
| ADR-WRS-08 | Lift _computeStreak in PR#2, not PR#1 | PR#2 |
| ADR-WRS-09 | Denormalized counters in userPublicProfiles (Q4, Q5 lock) | PR#3 |
| ADR-WRS-10 | try/catch + no rethrow on cross-feature writes | PR#3 |
| ADR-WRS-11 | Direct repo-to-repo dependency (no service layer) | PR#3 |
| ADR-WRS-12 | Self-only counter refresh; other member self-heals | PR#3 |
| ADR-WRS-13 | followerCountResolver closure injection into SessionRepository | PR#3 |
| ADR-WRS-14 | /users/{uid}/checkIns/{date} nested path | PR#4 |
| ADR-WRS-15 | Date doc id = natural dedup | PR#4 |
| ADR-WRS-16 | Session-scoped StateProvider for trigger guard | PR#4 |
| ADR-WRS-17 | No GPS / no mood-energy (Q7, Q8 lock) | PR#4 |
| ADR-WRS-18 | ConsumerStatefulWidget for FeedScreen lifecycle | PR#4 |
| ADR-WRS-19 | CheckInDialog props-down (supersedes D.5 inline provider read) | PR#4 (apply); promoted in archive |

---

## Open Risks → tasks/apply must address

1. **delete() signature change** (ADR-WRS-12): `FriendshipRepository.delete(String friendshipId, String myUid)` is BREAKING. PR#3 task list MUST grep all callers and update each.
2. **TreinoIcon.mapPin** may not exist yet. PR#4 task list MUST verify; add if missing.
3. **`developer.log` import**: ensure `dart:developer` is imported in the two repos that grow logging (SessionRepository, FriendshipRepository) and that the linter does not flag it.
4. **Rebase discipline**: 4 stacked PRs need active maintenance. If PR#1 review takes >2 days, PR#2 may drift; coordinator must remind devs to rebase forward.
5. **fake_cloud_firestore caveat**: rule semantics are NOT enforced by the fake. The PR#3 cross-feature write tests verify only behavior (`finish` does not throw on `set` failure). Rule-level coverage for the new checkIns block comes from PR#4's rules.test.js SCENARIOs.

---

## Ready for sdd-tasks
Yes. All 4 PR slices have concrete file maps, signatures, test scenarios, and ADRs. The only unresolved-at-design item (delete signature change) is explicit in §Open Risks and will be a discrete task in PR#3's task list.
