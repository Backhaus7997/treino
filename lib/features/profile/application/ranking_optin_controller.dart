import '../../gym_rankings/domain/main_lift_family_map.dart';
import '../../workout/data/session_repository.dart';
import '../../workout/domain/set_log.dart';
import '../data/user_public_profile_repository.dart';

/// Abstract surface for the opt-in toggle lifecycle — lets
/// `ProfileScreen`'s toggle widget (and its tests) depend on an interface
/// instead of the concrete Firestore-backed [RankingOptInController], via
/// `rankingOptInControllerProvider`.
abstract class RankingOptInControllerBase {
  Future<void> enableRankingOptIn(String uid);
  Future<void> disableRankingOptIn(String uid);
}

/// Orchestrates the `rankingOptIn` toggle lifecycle (spec `gym-rankings` —
/// Opt-In Toggle Lifecycle, design `sdd/rankings/design`).
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
///   `SessionRepository.finish()`.
/// - [disableRankingOptIn]: clears the 4 ranking-metric fields and sets
///   `rankingOptIn: false` via `UserPublicProfileRepository.clearRankingMetrics`.
class RankingOptInController implements RankingOptInControllerBase {
  RankingOptInController({
    required SessionRepository sessionRepository,
    required UserPublicProfileRepository publicProfileRepository,
  })  : _sessionRepository = sessionRepository,
        _publicProfileRepository = publicProfileRepository;

  final SessionRepository _sessionRepository;
  final UserPublicProfileRepository _publicProfileRepository;

  /// Enables ranking opt-in for [uid], backfilling ranking metrics from the
  /// athlete's own bounded recent-session/SetLog window (SAME window
  /// `finish()` uses — see [SessionRepository.listRecentCompletedByUid]) in
  /// one client-side pass. A failure here surfaces to the caller (does NOT
  /// swallow errors) — unlike `finish()`'s best-effort counters, an explicit
  /// user action deserves an explicit error rather than a silent no-op.
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
    await _publicProfileRepository.setRankingOptIn(uid, true);
  }

  /// Disables ranking opt-in for [uid], clearing all 4 ranking-metric fields
  /// so the athlete disappears from every leaderboard and their metrics are
  /// no longer publicly exposed.
  @override
  Future<void> disableRankingOptIn(String uid) async {
    await _publicProfileRepository.clearRankingMetrics(uid);
  }
}
