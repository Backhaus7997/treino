import 'dart:developer' as developer;

import '../../gyms/domain/gym.dart' show kNoGymId;
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
/// `sdd/rankings-v2/design` AD-4/AD-5;
/// `sdd/rankings-integrity/design` AD-2/AD-9).
///
/// - [enableRankingOptIn]: writes ONLY the eligibility intent — `gymId`/
///   `gymName` (denormalized from `users/{uid}.gymId` via
///   [UserRepository.update], AD-5, unchanged) followed by
///   `rankingOptIn: true` (LAST, so the athlete only becomes visible on a
///   leaderboard once gym identity is already on the public doc). As of
///   `sdd/rankings-integrity` (AD-2/AD-9), it no longer computes or writes
///   `lifetimeVolumeKg`/`best<Lift>Kg` itself — the server-side recompute
///   trigger (`rankingAggregateOnOptIn`, `functions/src/ranking-aggregate.ts`)
///   is the sole authority for those 4 fields, firing on the
///   `rankingOptIn` false→true transition this method just wrote and
///   populating metrics ~1-3s later (AD-5 eventual-consistency UX). `racha`
///   is NOT touched — it is denormalized by `SessionRepository.finish()`.
/// - [disableRankingOptIn]: clears the 4 ranking-metric fields and sets
///   `rankingOptIn: false` via `UserPublicProfileRepository.clearRankingMetrics`.
///   `gymId`/`gymName` are NOT touched by disable.
/// - [syncGymIfDesynced]: AD-4 self-heal, invoked once on the rankings
///   page's first build via `ref.read` (never `watch`). Best-effort —
///   failures are logged and swallowed, matching `finish()`'s counters
///   tolerance, so a transient failure never breaks the leaderboard render.
class RankingOptInController implements RankingOptInControllerBase {
  RankingOptInController({
    required UserPublicProfileRepository publicProfileRepository,
    required UserRepository userRepository,
  })  : _publicProfileRepository = publicProfileRepository,
        _userRepository = userRepository;

  final UserPublicProfileRepository _publicProfileRepository;
  final UserRepository _userRepository;

  /// Enables ranking opt-in for [uid]: writes the eligibility intent only.
  ///
  /// `sdd/rankings-integrity` AD-2/AD-9: this method no longer computes or
  /// writes `lifetimeVolumeKg`/`best<Lift>Kg` from the athlete's own
  /// session/SetLog history — that computation now lives server-side in
  /// `recomputeMetrics` (`functions/src/ranking-aggregate.ts`), triggered by
  /// the `rankingOptIn` false→true transition this method writes. Denormalizes
  /// `gymId`/`gymName` from the private source of truth onto the public doc,
  /// THROUGH [UserRepository.update] — the single canonical dual-write path
  /// (resolves `gymName` via `_resolveGymName`, which itself never throws on
  /// a null/kNoGymId/unknown id). Runs BEFORE `setRankingOptIn` so a query
  /// never observes a stale gym for a newly-visible athlete.
  /// `setRankingOptIn(uid, true)` runs LAST, so the athlete only becomes
  /// visible on a leaderboard once gym identity is already on the public doc
  /// (metrics populate ~1-3s later via the server trigger — AD-5).
  @override
  Future<void> enableRankingOptIn(String uid) async {
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
