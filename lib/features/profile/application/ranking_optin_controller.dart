import '../../gym_rankings/domain/main_lift_family_map.dart';
import '../../workout/data/session_repository.dart';
import '../../workout/domain/session_status.dart';
import '../../workout/domain/set_log.dart';
import '../data/user_public_profile_repository.dart';

/// Orchestrates the `rankingOptIn` toggle lifecycle (spec `gym-rankings` —
/// Opt-In Toggle Lifecycle, design `sdd/rankings/design`).
///
/// - [enableRankingOptIn]: one-time, client-side backfill of
///   `lifetimeVolumeKg` (Σ `totalVolumeKg` over the athlete's own FULL
///   completed-session history) and `bestSquatKg`/`bestBenchKg`/`bestDeadliftKg`
///   (max weight per [MainLift] family over the athlete's own FULL SetLog
///   history), then sets `rankingOptIn: true`. Deliberately reads the
///   athlete's ENTIRE history (unlike `SessionRepository.finish()`'s bounded
///   365-session recompute window) since this only runs once, on enable.
///   `racha` is NOT touched — it is already denormalized by
///   `SessionRepository.finish()`.
/// - [disableRankingOptIn]: clears the 4 ranking-metric fields and sets
///   `rankingOptIn: false` via `UserPublicProfileRepository.clearRankingMetrics`.
class RankingOptInController {
  RankingOptInController({
    required SessionRepository sessionRepository,
    required UserPublicProfileRepository publicProfileRepository,
  })  : _sessionRepository = sessionRepository,
        _publicProfileRepository = publicProfileRepository;

  final SessionRepository _sessionRepository;
  final UserPublicProfileRepository _publicProfileRepository;

  /// Enables ranking opt-in for [uid], backfilling ranking metrics from the
  /// athlete's own FULL session/SetLog history in one client-side pass. A
  /// failure here surfaces to the caller (does NOT swallow errors) — unlike
  /// `finish()`'s best-effort counters, an explicit user action deserves an
  /// explicit error rather than a silent no-op.
  Future<void> enableRankingOptIn(String uid) async {
    final allSessions = await _sessionRepository.listByUid(uid);
    final completedList = allSessions
        .where((s) => s.status == SessionStatus.finished && s.wasFullyCompleted)
        .toList();

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
  Future<void> disableRankingOptIn(String uid) async {
    await _publicProfileRepository.clearRankingMetrics(uid);
  }
}
