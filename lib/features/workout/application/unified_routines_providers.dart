import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../profile/application/user_providers.dart';
import '../domain/routine.dart';
import 'assigned_routine_providers.dart';
import 'user_routines_providers.dart';

/// One entry of the unified RUTINAS list. [fromCoach] marks trainer-assigned
/// routines so the UI can pin them on top and render the "DE TU COACH" chip.
typedef UnifiedRoutineEntry = ({Routine routine, bool fromCoach});

/// Unified routines list for the athlete: trainer-assigned plans PINNED on
/// top (newest first — [RoutineRepository.listAssignedTo] order), followed by
/// the athlete's self-created routines (newest first).
///
/// Replaces the separate "Mi plan" + "Mis rutinas" sections of the workout
/// tab (workout-area redesign slice 1, 2026-07-27). Consumed by
/// `RutinasSection` and the `/profile/routines` read-only mirror.
///
/// ── Lazy adoption of the active routine ──────────────────────────────────
/// The product rule is "if you have routines, one is always active"
/// (`UserProfile.activeRoutineId`). Trainers cannot write `users/{athleteUid}`
/// (Firestore rules), so coach-assigned routines are activated from the
/// athlete's side: when the profile is loaded, has NO active routine, and the
/// unified list is non-empty, this provider adopts the HEAD of the list (the
/// pinned coach plan when there is one). This also migrates pre-existing
/// users without any backfill.
///
/// Safety properties:
///   * Idempotent-converging — writes only while `activeRoutineId` is
///     null/empty, and the write itself makes the condition false once the
///     profile stream echoes it back. Until that echo lands, a source-list
///     re-emission can trigger a redundant extra write; every write targets
///     the CURRENT list head, so concurrent writes converge to a valid head
///     (same-client writes resolve in order) and can never loop.
///   * Strict-null trigger — a STALE id (pointing to an archived/unassigned
///     routine) does NOT re-adopt. Transient half-loaded lists must never
///     steal an explicit user choice; stale pointers are already handled
///     downstream (chip simply not shown, home falls back to legacy chain).
///   * Best-effort — a failed write (offline, rules) never breaks the list.
final unifiedRoutinesProvider =
    FutureProvider.autoDispose.family<List<UnifiedRoutineEntry>, String>(
  (ref, uid) async {
    if (uid.isEmpty) return const [];

    // Read everything that drives adoption BEFORE any await — using `ref`
    // after an async gap is unsafe when the provider is recomputed mid-flight.
    // `select` keeps rebuilds scoped: profile emissions that don't change
    // these two values (racha updates, settings…) don't recompose the list.
    final profileLoaded = ref.watch(
      userProfileProvider.select((a) => a.hasValue && a.valueOrNull != null),
    );
    final activeRoutineId = ref.watch(
      userProfileProvider.select((a) => a.valueOrNull?.activeRoutineId),
    );

    final assignedFuture = ref.watch(assignedRoutinesProvider(uid).future);
    final ownFuture = ref.watch(userCreatedRoutinesProvider(uid).future);
    final assigned = await assignedFuture;
    final own = await ownFuture;

    final entries = List<UnifiedRoutineEntry>.unmodifiable([
      for (final r in assigned) (routine: r, fromCoach: true),
      for (final r in own) (routine: r, fromCoach: false),
    ]);

    final hasActive = activeRoutineId != null && activeRoutineId.isNotEmpty;
    if (profileLoaded && !hasActive && entries.isNotEmpty) {
      try {
        // `ref.read` stays INSIDE the try: it throws both when Firestore is
        // unavailable (unconfigured test harness) and when this execution
        // was superseded mid-await — in every case adoption is simply
        // skipped and retried on a later recomposition.
        await ref.read(userRepositoryProvider).update(uid, {
          'activeRoutineId': entries.first.routine.id,
        });
      } catch (_) {
        // Best-effort: adoption must never turn a loadable list into an
        // error state. A later recomposition retries while the id is null.
      }
    }

    return entries;
  },
);
