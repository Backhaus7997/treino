import 'dart:developer' as developer;

import '../../gym_rankings/domain/main_lift_family_map.dart';
import '../../gyms/domain/gym.dart' show kNoGymId;
import '../../workout/data/session_repository.dart';
import '../../workout/domain/set_log.dart';
import '../data/user_public_profile_repository.dart';
import '../data/user_repository.dart';

/// Abstract surface for the opt-in toggle lifecycle — lets
/// `ProfileScreen`'s toggle widget (and its tests) depend on an interface
/// instead of the concrete Firestore-backed [RankingOptInController], via
/// `rankingOptInControllerProvider`.
abstract class RankingOptInControllerBase {
  Future<void> enableRankingOptIn(String uid);
  Future<void> disableRankingOptIn(String uid);

  /// AD-4 idempotent client-side self-heal: re-syncs `gymId`/`gymName` onto
  /// `userPublicProfiles/{uid}` for an already-opted-in athlete whose public
  /// `gymId` drifted from (or never got) the private `users/{uid}.gymId`.
  /// Best-effort — never throws to the caller.
  Future<void> syncGymIfDesynced(String uid);
}

/// Orchestrates the `rankingOptIn` toggle lifecycle (spec `gym-rankings` —
/// Opt-In Toggle Lifecycle, design `sdd/rankings/design`;
/// `sdd/rankings-v2/design` AD-4/AD-5).
///
/// - [enableRankingOptIn]: one-time, client-side backfill of
///   `lifetimeVolumeKg` (Σ `totalVolumeKg`) and
///   `bestSquatKg`/`bestBenchKg`/`bestDeadliftKg` (max weight per [MainLift]
///   family), computed over the athlete's own recent-completed-session
///   window via [SessionRepository.listRecentCompletedByUid] — the SAME
///   bounded window (`counterRecomputeWindow`, most recent 365 sessions by
///   `startedAt`) that `SessionRepository.finish()` recomputes over on every
///   session finish. Using the SAME window is REQUIRED: if the backfill used
///   the athlete's full history while `finish()` recomputes over a narrower
///   bounded window, the very next session finish after opt-in would
///   silently shrink `lifetimeVolumeKg`/`best<Lift>Kg` back down to the
///   windowed value, making the metrics visibly drop right after enabling.
///   `racha` is NOT touched — it is already denormalized by
///   `SessionRepository.finish()`. AFTER the metric backfill, `gymId` (and
///   the resolved `gymName`) are denormalized from `users/{uid}.gymId` onto
///   the public doc via [UserRepository.update] (AD-5) — the single
///   canonical dual-write + `_resolveGymName` tolerance path, reused
///   verbatim rather than duplicated. `setRankingOptIn(uid, true)` runs
///   LAST, so the athlete only becomes visible on a leaderboard once BOTH
///   metrics AND gym are already on the public doc.
/// - [disableRankingOptIn]: clears the 4 ranking-metric fields and sets
///   `rankingOptIn: false` via `UserPublicProfileRepository.clearRankingMetrics`.
///   `gymId`/`gymName` are NOT touched by disable.
/// - [syncGymIfDesynced]: AD-4 self-heal, invoked once on the rankings
///   page's first build via `ref.read` (never `watch`). Best-effort —
///   failures are logged and swallowed, matching `finish()`'s counters
///   tolerance, so a transient failure never breaks the leaderboard render.
class RankingOptInController implements RankingOptInControllerBase {
  RankingOptInController({
    required SessionRepository sessionRepository,
    required UserPublicProfileRepository publicProfileRepository,
    required UserRepository userRepository,
  })  : _sessionRepository = sessionRepository,
        _publicProfileRepository = publicProfileRepository,
        _userRepository = userRepository;

  final SessionRepository _sessionRepository;
  final UserPublicProfileRepository _publicProfileRepository;
  final UserRepository _userRepository;

  /// Enables ranking opt-in for [uid], backfilling ranking metrics from the
  /// athlete's own bounded recent-session/SetLog window (SAME window
  /// `finish()` uses — see [SessionRepository.listRecentCompletedByUid]) in
  /// one client-side pass, then denormalizing `gymId`/`gymName` (AD-5). A
  /// failure here surfaces to the caller (does NOT swallow errors) — unlike
  /// `finish()`'s best-effort counters, an explicit user action deserves an
  /// explicit error rather than a silent no-op. The one exception is
  /// `gymName` resolution itself, which [UserRepository._resolveGymName]
  /// already swallows internally (never throws) — a stale/unknown gym never
  /// aborts opt-in.
  @override
  Future<void> enableRankingOptIn(String uid) async {
    final completedList =
        await _sessionRepository.listRecentCompletedByUid(uid);

    final lifetimeVolumeKg = completedList.fold<double>(
      0.0,
      (sum, s) => sum + s.totalVolumeKg,
    );

    final allLogs = <SetLog>[];
    for (final session in completedList) {
      final logs = await _sessionRepository.listSetLogs(
        uid: uid,
        sessionId: session.id,
      );
      allLogs.addAll(logs);
    }

    final bestSquatKg = familyMaxWeight(MainLift.squat, allLogs) ?? 0;
    final bestBenchKg = familyMaxWeight(MainLift.bench, allLogs) ?? 0;
    final bestDeadliftKg = familyMaxWeight(MainLift.deadlift, allLogs) ?? 0;

    await _publicProfileRepository.updateCounters(uid, {
      'lifetimeVolumeKg': lifetimeVolumeKg,
      'bestSquatKg': bestSquatKg,
      'bestBenchKg': bestBenchKg,
      'bestDeadliftKg': bestDeadliftKg,
    });

    // AD-5: denormalize gymId/gymName from the private source of truth onto
    // the public doc, THROUGH UserRepository.update — the single canonical
    // dual-write path (resolves gymName via _resolveGymName, which itself
    // never throws on a null/kNoGymId/unknown id). Runs BEFORE
    // setRankingOptIn so a query never observes a stale gym for a
    // newly-visible athlete.
    final profile = await _userRepository.get(uid);
    await _userRepository.update(uid, {'gymId': profile?.gymId});

    await _publicProfileRepository.setRankingOptIn(uid, true);
  }

  /// Disables ranking opt-in for [uid], clearing all 4 ranking-metric fields
  /// so the athlete disappears from every leaderboard and their metrics are
  /// no longer publicly exposed. `gymId`/`gymName` are left unchanged — they
  /// are identity fields, not ranking metrics (AD-5).
  @override
  Future<void> disableRankingOptIn(String uid) async {
    await _publicProfileRepository.clearRankingMetrics(uid);
  }

  /// AD-4: one-time idempotent client-side self-heal for already-opted-in
  /// athletes whose public `gymId` is missing or stale relative to the
  /// private `users/{uid}.gymId` (the reported empty-leaderboard bug for
  /// existing users, whom [enableRankingOptIn]'s fix does not retroactively
  /// reach). No-ops when: the athlete is not opted in, the private profile
  /// is unavailable, or the public/private `gymId` already match — a
  /// matching pair issues ZERO writes. Best-effort: any failure is logged
  /// and swallowed so the caller (the rankings page mount) is never blocked
  /// or shown an error for a silent repair attempt.
  @override
  Future<void> syncGymIfDesynced(String uid) async {
    try {
      final publicProfile = await _publicProfileRepository.get(uid);
      if (publicProfile == null || publicProfile.rankingOptIn != true) {
        return;
      }

      final privateProfile = await _userRepository.get(uid);
      final privateGymId = privateProfile?.gymId;
      final publicGymId = publicProfile.gymId;

      final isPublicGymBlank =
          publicGymId == null || publicGymId.isEmpty || publicGymId == kNoGymId;
      final isDesynced = isPublicGymBlank || publicGymId != privateGymId;
      if (!isDesynced) return;

      await _userRepository.update(uid, {'gymId': privateGymId});
    } catch (e, st) {
      developer.log(
        'RankingOptInController: syncGymIfDesynced failed for uid=$uid',
        error: e,
        stackTrace: st,
      );
    }
  }
}
