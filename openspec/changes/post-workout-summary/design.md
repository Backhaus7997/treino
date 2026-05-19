# Design: Post-Workout Summary (Fase 4 · Etapa 3)

**Change**: `post-workout-summary` · **Branch**: `feat/post-workout-summary`
**SCENARIOs**: 334..354 (21) · **REQs**: REQ-PWS-001..014

## Technical Approach

Top-level GoRoute (NO ShellRoute) hosts `PostWorkoutSummaryScreen`. On mount, one autoDispose family provider loads `Session` + `List<SetLog>` in PARALLEL via `Future.wait` and exposes them as a single record — driving one loading state. `PostWorkoutNotifier` (`AsyncNotifier<void>`) handles share: builds `Post` (privacy=friends, denormalized author, routineTag), calls `PostRepository.create`, surfaces errors via rethrow → screen renders SnackBar based on `state.hasError`. LISTO never creates a Post. Strings live in a new `WorkoutStrings` abstract class mirroring `AuthStrings`. Repo gets one new method `getById(uid, sessionId)` returning `Session?`.

## Architecture Decisions

| # | Decision | Choice | Rejected | Rationale |
|---|---|---|---|---|
| 1 | Session + SetLogs loading | Single combined `FutureProvider.autoDispose.family<({Session, List<SetLog>}), ({String uid, String sessionId})>` using `Future.wait([getById, listSetLogs])` | (a) Two separate providers + `ref.watch` both | One loading state, parallel reads, mirrors existing `activeSessionForUidProvider` record pattern. |
| 2 | Provider family key shape | Dart record `({String uid, String sessionId})` | Tuple class / String concat / positional record | Explicit names at call site, value-equality semantics, no boilerplate, matches gentle-ai modern Dart idiom. |
| 3 | Share notifier shape | `AsyncNotifier<void>` (family-less) + `AsyncNotifierProvider.autoDispose` | `AsyncNotifier<bool>` like `CreatePostNotifier` | `void` matches "fire and forget" semantics — UI listens to `state.isLoading` and `state.hasError`; nav lives in widget callback. |
| 4 | Error propagation from notifier | `rethrow` after setting `state = AsyncError` | Return `bool` + read state | Standard Riverpod AsyncNotifier convention; screen uses `ref.listen(notifier, (prev, next) => ...)` to fire SnackBar reactively. |
| 5 | Author denormalization fallback | `profile?.displayName ?? ''` (empty string) | `'Anónimo'` (used by CreatePostNotifier) | Spec SCENARIO-338 mandates empty string fallback when profile not yet loaded — different from CreatePost UX intentionally (resumen runs right after player, profile typically cached). |
| 6 | Strings location | New `lib/features/workout/presentation/workout_strings.dart` mirroring `AuthStrings` (abstract final class, `static const` fields) | Inline in widget / shared `AppStrings` | Established convention in repo (`AuthStrings`); workout has no central strings yet — this seeds it for future workout screens. |
| 7 | Header copy gating | Conditional ternary on `session.wasFullyCompleted` → `summaryHeaderCompleted` vs `summaryHeaderAbandoned` | Always same header | REQ-PWS-005 / SCENARIO-343, 344. Field already exists in `Session` (default false, set by `finish`). |
| 8 | PRs section UX (no real data) | Section title `'PRS DE LA SESIÓN'` + single muted line `'Próximamente'` | Hide section entirely | Spec REQ-PWS-007 demands the section be visible as placeholder; "Próximamente" matches existing app idiom for not-yet-shipped features. |
| 9 | Emoji row interactivity | 5 `Text(emoji)` widgets in a `Row` — NO `GestureDetector` | Tappable visual-only buttons | REQ-PWS-008 says NO interaction; cheapest impl. Persistence is explicitly out-of-scope. |
| 10 | Loading state | Centered `CircularProgressIndicator(color: palette.accent)` — full-screen | Skeleton matching layout | Skeleton would mock content user has not seen; the load is fast (two Firestore doc reads) and a spinner is honest about latency. |
| 11 | Error / Not-found UI | Centered card-ish column: title (`headlineSmall`) + filled CTA | Banner at top + content blank | Both states fully block the screen — there is no partial content to show — so a single centered block is the clearest signal. |
| 12 | Retry behavior | `ref.invalidate(combinedProvider)` then `await ref.read(combinedProvider.future)` | Local `RetryNotifier` | Riverpod-native, no extra state surface. |
| 13 | Navigation after share success | Screen listens to notifier; on transition `isLoading → AsyncData` calls `context.go('/workout')` + SnackBar | Navigate from inside notifier via `BuildContext` ref | Notifiers must not own `BuildContext`; navigation belongs in widget layer. |
| 14 | Router placement | Top-level route at existing position (router.dart:153-158) — outside ShellRoute | Move under `/workout` ShellRoute | Player route is already top-level (same line range); summary inherits the same immersive treatment (no bottom bar). REQ-PWS-001 + SCENARIO-354. |

## Data Flow

    /workout/session-summary/:sessionId
              │
              ▼
    PostWorkoutSummaryScreen(sessionId)
              │
              ├──(watch)── sessionSummaryProvider((uid, sessionId))
              │                    │
              │                    ├── repo.getById(uid, sessionId) ───┐
              │                    └── repo.listSetLogs(uid, sId) ────┤  Future.wait
              │                                                       │
              │                    returns ({Session?, List<SetLog>}) ┘
              │
              ├──(render)── header + stat grid + PRs stub + mood row + CTAs
              │
              ├──(LISTO tap) ──► context.go('/workout')
              │
              └──(COMPARTIR tap) ──► postWorkoutNotifier.shareWorkout(session)
                                            │
                                            ├── userProfileProvider.valueOrNull
                                            ├── build Post (privacy=friends, routineTag, autoText)
                                            ├── postRepository.create(post)
                                            │
                                  ┌─────────┴─────────┐
                                  success             error
                                    │                   │
                                    ▼                   ▼
                          ref.invalidate(feeds)   state=AsyncError
                          SnackBar success        SnackBar error
                          context.go('/workout')  STAY on screen

## File Changes

| File | Action | Description |
|---|---|---|
| `lib/features/workout/data/session_repository.dart` | Modify | Add `getById({required String uid, required String sessionId}) → Future<Session?>` using existing `_sessionFromDoc` helper. |
| `lib/features/workout/application/session_providers.dart` | Modify | Add `sessionSummaryProvider` (FutureProvider.autoDispose.family, record key). |
| `lib/features/workout/application/post_workout_notifier.dart` | Create | `PostWorkoutNotifier extends AsyncNotifier<void>` + `postWorkoutNotifierProvider` (autoDispose). |
| `lib/features/workout/presentation/workout_strings.dart` | Create | `abstract final class WorkoutStrings` with all `summary*` + `postAutoCompleteText` consts. |
| `lib/features/workout/presentation/post_workout_summary_screen.dart` | Create | `ConsumerWidget` rendering Scaffold + AppBackground + scroll content + 4 states (loading/error/not-found/loaded). |
| `lib/app/router.dart` | Modify | Replace stub at lines 153-158 with `PostWorkoutSummaryScreen(sessionId: ...)`. |
| `test/features/workout/data/session_repository_get_by_id_test.dart` | Create | 3 tests (happy, null, path) — SCENARIO-334..336. |
| `test/features/workout/application/post_workout_notifier_test.dart` | Create | 5 tests — SCENARIO-337..341. |
| `test/features/workout/presentation/post_workout_summary_screen_test.dart` | Create | 13 widget tests — SCENARIO-342..353 + extras. |
| `test/app/router_post_workout_summary_test.dart` | Create | 1 test — SCENARIO-354. |

## Interfaces / Contracts

```dart
// session_repository.dart (addition)
Future<Session?> getById({
  required String uid,
  required String sessionId,
}) async {
  final snap = await _sessions(uid).doc(sessionId).get();
  return _sessionFromDoc(snap);
}

// session_providers.dart (addition)
final sessionSummaryProvider = FutureProvider.autoDispose
    .family<({Session? session, List<SetLog> setLogs}),
            ({String uid, String sessionId})>((ref, key) async {
  final repo = ref.read(sessionRepositoryProvider);
  final results = await Future.wait([
    repo.getById(uid: key.uid, sessionId: key.sessionId),
    repo.listSetLogs(uid: key.uid, sessionId: key.sessionId),
  ]);
  return (
    session: results[0] as Session?,
    setLogs: results[1] as List<SetLog>,
  );
});

// post_workout_notifier.dart
class PostWorkoutNotifier extends AsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> shareWorkout(Session session) async {
    state = const AsyncLoading();
    try {
      final authUser = await ref.read(authStateChangesProvider.future);
      final profile = ref.read(userProfileProvider).valueOrNull;
      final post = Post(
        id: '',
        authorUid: authUser!.uid,
        authorDisplayName: profile?.displayName ?? '',
        authorAvatarUrl: profile?.avatarUrl,
        authorGymId: profile?.gymId,
        text: WorkoutStrings.postAutoCompleteText,
        routineTag: RoutineTag(
          routineId: session.routineId,
          routineName: session.routineName,
        ),
        privacy: PostPrivacy.friends,
        createdAt: DateTime.now().toUtc(),
      );
      await ref.read(postRepositoryProvider).create(post);
      ref.invalidate(myFriendsFeedProvider);
      ref.invalidate(feedPublicProvider);
      state = const AsyncData(null);
    } catch (e, st) {
      state = AsyncError(e, st);
      rethrow;
    }
  }
}
```

## Testing Strategy

| Layer | What to Test | Approach |
|---|---|---|
| Repo (3) | `getById` happy / null / path correctness | `fake_cloud_firestore` — seed doc, call, assert. |
| Notifier (5) | Post construction, denormalization, fallback, success path, rethrow | `ProviderContainer` overrides for `postRepositoryProvider`, `userProfileProvider`, `authStateChangesProvider`. |
| Widget (13) | Loading, error, not-found, header conditional (2), stat grid values, sets count, PRs stub, mood row (5 emojis), LISTO nav, COMPARTIR triggers, success SnackBar + nav, error SnackBar + no-nav, retry invalidate | `MaterialApp` wrapped in `ProviderScope`; provider overrides; `pumpAndSettle` between states. |
| Router (1) | `/workout/session-summary/:sessionId` resolves to `PostWorkoutSummaryScreen` | `buildRouter` with overrides; `find.byType(PostWorkoutSummaryScreen)`; assert no `TreinoBottomBar`. |

Total: ~22 tests covering all 21 spec SCENARIOs.

## Migration / Rollout

No migration required. No schema changes, no `firestore.rules` changes, no `pubspec.yaml` changes. Single commit on `feat/post-workout-summary`; revert restores the stub.

## Open Questions

None — all decisions resolved per proposal/spec. PR size forecast ~280-340 LOC vs 400 budget: LOW risk; single PR planned.

## Review Workload Forecast

- **400-line budget risk**: Low
- **Chained PRs recommended**: No
- **Decision needed before apply**: No
