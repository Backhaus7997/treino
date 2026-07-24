import 'package:cloud_firestore/cloud_firestore.dart'
    show
        CollectionReference,
        DocumentSnapshot,
        FieldPath,
        FieldValue,
        FirebaseException,
        FirebaseFirestore,
        Query,
        SetOptions,
        Timestamp;

import '../../gyms/domain/gym.dart' show kNoGymId;
import '../domain/racha_freshness.dart';
import '../domain/user_public_profile.dart';

/// Repository for the `userPublicProfiles` collection.
///
/// Exposes only the three public operations:
///   - [get] — fetch a single profile by uid.
///   - [set] — write / merge a profile doc.
///   - [searchByDisplayName] — prefix-range query on `displayNameLowercase`.
///
/// Note: `fake_cloud_firestore` does NOT enforce Firestore security rules.
/// Permission coverage is provided by the T35-style manual emulator test
/// (SCENARIO-268..270). See design Section A.6.
class UserPublicProfileRepository {
  UserPublicProfileRepository({
    required FirebaseFirestore firestore,
    DateTime Function()? now,
  })  : _firestore = firestore,
        _now = now ?? DateTime.now;

  final FirebaseFirestore _firestore;

  /// Injectable clock for [leaderboard]'s racha decay (#552). Constructor
  /// injection (not a method param) so mocktail `when()`/`verify()` stubs on
  /// this repository's methods keep compiling unchanged.
  final DateTime Function() _now;

  CollectionReference<Map<String, Object?>> get _col =>
      _firestore.collection('userPublicProfiles');

  /// Returns the profile for [uid], or `null` if no document exists.
  Future<UserPublicProfile?> get(String uid) async {
    final snap = await _col.doc(uid).get();
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return UserPublicProfile.fromJson(data);
  }

  /// Live stream of the public profile at `userPublicProfiles/{uid}`, or null
  /// when the doc does not exist. Mirrors [get] but streamed.
  Stream<UserPublicProfile?> watch(String uid) {
    return _col.doc(uid).snapshots().map((snap) {
      final data = snap.data();
      if (!snap.exists || data == null) return null;
      return UserPublicProfile.fromJson(data);
    });
  }

  /// Batch lookup of public profiles by uid, returned as a `uid -> profile`
  /// map. Missing docs are simply absent from the map. Empty input
  /// short-circuits without I/O.
  ///
  /// `whereIn` is capped at 30 values per query in Firestore, so the distinct
  /// uids are chunked defensively. Used to resolve many review authors in a
  /// handful of reads instead of one live listener per tile (avoids the
  /// per-tile N+1 listen pattern in the RESEÑAS section).
  Future<Map<String, UserPublicProfile>> getByIds(List<String> uids) async {
    if (uids.isEmpty) return const {};
    final distinct = uids.toSet().toList();
    const chunkSize = 30;
    final out = <String, UserPublicProfile>{};
    for (var i = 0; i < distinct.length; i += chunkSize) {
      final chunk = distinct.sublist(
        i,
        i + chunkSize > distinct.length ? distinct.length : i + chunkSize,
      );
      final snap = await _col.where(FieldPath.documentId, whereIn: chunk).get();
      for (final doc in snap.docs) {
        final data = doc.data();
        out[doc.id] = UserPublicProfile.fromJson(data);
      }
    }
    return out;
  }

  /// Writes [profile] to `userPublicProfiles/{profile.uid}` with merge
  /// semantics so partial updates do not overwrite existing fields.
  Future<void> set(UserPublicProfile profile) async {
    await _col.doc(profile.uid).set(profile.toJson(), SetOptions(merge: true));
  }

  /// Performs a partial merge write on `userPublicProfiles/{uid}` using only
  /// the provided [fields]. Existing fields NOT in [fields] are preserved.
  ///
  /// Used by cross-feature write paths (SessionRepository.finish,
  /// FriendshipRepository.accept/delete) to update counters without
  /// clobbering identity fields (displayName, avatarUrl, gymId) set by
  /// UserRepository. See ADR-WRS-12.
  ///
  /// #552 — Callers MUST NOT pass `rachaUpdatedAt`: whenever the write
  /// includes `racha`, this method derives the freshness stamp itself
  /// (server timestamp), mirroring how `UserRepository` always derives
  /// `displayNameLowercase`/`n`. Keeping value and stamp in the SAME write
  /// is what makes [effectiveRacha]'s read-time decay trustworthy — a racha
  /// written without a stamp (or vice versa) would decay wrongly.
  Future<void> updateCounters(String uid, Map<String, Object?> fields) async {
    if (fields.containsKey('racha')) {
      final stamped = <String, Object?>{
        ...fields,
        'rachaUpdatedAt': FieldValue.serverTimestamp(),
      };
      try {
        await _col.doc(uid).set(stamped, SetOptions(merge: true));
        return;
      } on FirebaseException catch (e) {
        // Transitional (#552): until the updated firestore.rules (which add
        // `rachaUpdatedAt` to the userPublicProfiles field allowlist) are
        // deployed, the stamped write is denied. Fall back to the legacy
        // shape so `racha`/`workoutsCount` keep flowing — the board then
        // shows the pre-#552 passthrough behavior instead of silently
        // freezing every counter. Remove once the rules deploy is live.
        // Not covered by fake_cloud_firestore (it does not enforce rules);
        // covered by the T35-style manual emulator pass, like the rest of
        // this file's permission behavior.
        if (e.code != 'permission-denied') rethrow;
      }
    }
    await _col.doc(uid).set(fields, SetOptions(merge: true));
  }

  /// Flips the athlete's `rankingOptIn` flag via the same partial-merge path
  /// as [updateCounters]. Does NOT touch the 4 ranking-metric fields — the
  /// caller (`RankingOptInController`) is responsible for backfilling them
  /// on enable and clearing them on disable via [clearRankingMetrics]. See
  /// design `sdd/rankings/design` — Opt-In Toggle Lifecycle.
  Future<void> setRankingOptIn(String uid, bool value) async {
    await _col.doc(uid).set({'rankingOptIn': value}, SetOptions(merge: true));
  }

  /// Flips the user's `isProfilePublic` flag via a partial merge so identity
  /// fields (displayName/avatarUrl/gymId) and unrelated counters stay
  /// untouched. Existing `accepted` friendships are preserved (Option X):
  /// the flag only changes the behavior of NEW follow requests.
  Future<void> setProfilePublic(String uid, bool value) async {
    await _col
        .doc(uid)
        .set({'isProfilePublic': value}, SetOptions(merge: true));
  }

  /// Resets all 4 ranking-metric fields to their pre-opt-in defaults and
  /// flips `rankingOptIn` to `false`, via a partial merge so identity fields
  /// (displayName/avatarUrl/gymId) and unrelated counters are untouched.
  /// `best<Lift>Kg` fields are cleared to `null` (their default when not
  /// opted in / no matching lift) rather than `0`, matching the model's
  /// existing "null = no PR to report" semantics.
  Future<void> clearRankingMetrics(String uid) async {
    await _col.doc(uid).set(
      {
        'rankingOptIn': false,
        'lifetimeVolumeKg': 0,
        'bestSquatKg': null,
        'bestBenchKg': null,
        'bestDeadliftKg': null,
      },
      SetOptions(merge: true),
    );
  }

  /// Returns up to [limit] opted-in profiles for [gymId], ordered descending
  /// by [metricField] — the query behind every per-gym leaderboard
  /// (`gym-rankings` spec: Streak/Volume/Main-Lift Leaderboards).
  ///
  /// Returns an empty list without issuing a Firestore call when [gymId] is
  /// blank or equals [kNoGymId] — an athlete with no gym has no leaderboard
  /// to show (spec: Gym Scoping and No-Gym Exclusion). Athletes with
  /// `gymId == null`/`kNoGymId` never match `where('gymId', isEqualTo: ...)`
  /// against a real gym id either, so the composite index naturally excludes
  /// them from every OTHER gym's leaderboard too.
  ///
  /// A gym with zero opted-in athletes simply yields an empty snapshot — not
  /// an error (spec: Empty States). So does a gym where every opted-in athlete
  /// is missing the metric — see [_presenceRequiredMetrics].
  Future<List<UserPublicProfile>> leaderboard({
    required String gymId,
    required String metricField,
    int limit = 20,
  }) async {
    if (gymId.isEmpty || gymId == kNoGymId) return const [];

    Query<Map<String, Object?>> query = _col
        .where('gymId', isEqualTo: gymId)
        .where('rankingOptIn', isEqualTo: true);

    if (_presenceRequiredMetrics.contains(metricField)) {
      // Compiles to a `!= null` filter, which reuses the SAME composite index
      // the `orderBy` below already requires (gymId ASC, rankingOptIn ASC,
      // metricField DESC) — no `firestore.indexes.json` change needed.
      query = query.where(metricField, isNull: false);
    }

    final snap =
        await query.orderBy(metricField, descending: true).limit(limit).get();

    if (metricField == 'racha') return _decayedStreakBoard(snap.docs);

    return snap.docs.map((d) => UserPublicProfile.fromJson(d.data())).toList();
  }

  /// #552 — read-time decay for the streak board. The stored `racha` is a
  /// snapshot from the athlete's last finish and never decays on its own, so
  /// an inactive athlete would sit on the board with a dead streak forever
  /// while their own PERFIL (live `computeStreak`) says 0. Each row's racha
  /// is replaced with [effectiveRacha] (0 unless its `rachaUpdatedAt` stamp
  /// is from today/yesterday in ART), then rows are re-sorted because decay
  /// can reorder them.
  ///
  /// Metric-specific handling inside the generic query method follows the
  /// [_presenceRequiredMetrics] precedent above. Known bounded limitation:
  /// the top-[limit] cut happens server-side on the RAW values, so with more
  /// than `limit` opted-in athletes a stale-but-high racha can crowd a
  /// fresh-but-low one out of the page; within the page, order and values
  /// are correct. Docs never stamped (pre-#552) pass through undecayed until
  /// `scripts/backfill_racha_freshness.js` stamps them.
  List<UserPublicProfile> _decayedStreakBoard(
    List<DocumentSnapshot<Map<String, Object?>>> docs,
  ) {
    final now = _now();
    final decayed = docs.map((d) {
      final data = d.data() ?? const <String, Object?>{};
      final profile = UserPublicProfile.fromJson(data);
      final stamp = data['rachaUpdatedAt'];
      return profile.copyWith(
        racha: effectiveRacha(
          racha: profile.racha,
          rachaUpdatedAt: stamp is Timestamp ? stamp.toDate() : null,
          now: now,
        ),
      );
    }).toList();
    // Re-sort with the same tie-break Firestore itself applies (documentId
    // ASC — here uid == doc id), so the order is deterministic regardless of
    // List.sort's stability.
    decayed.sort((a, b) {
      final byRacha = (b.racha ?? 0).compareTo(a.racha ?? 0);
      return byRacha != 0 ? byRacha : a.uid.compareTo(b.uid);
    });
    return decayed;
  }

  /// QA-GYM-506 — the metric fields whose `null` means "el atleta no tiene ese
  /// dato", NOT "cero". Exactly the three [clearRankingMetrics] resets to an
  /// explicit `null`, which is also what the opt-in backfill leaves behind for
  /// a lift the athlete never performed.
  ///
  /// `orderBy` alone does NOT exclude them: Firestore only skips documents
  /// where the field is ABSENT, so an explicit `null` still matched the query
  /// and (under `descending: true`) landed at the tail of the board, where the
  /// client rendered it as a fabricated "0 kg" PR.
  ///
  /// `racha` and `lifetimeVolumeKg` are deliberately NOT in this set: no
  /// streak IS a 0-day streak and no volume IS 0 kg lifted, so their 0 floor
  /// is honest and those athletes stay on their boards.
  static const _presenceRequiredMetrics = {
    'bestSquatKg',
    'bestBenchKg',
    'bestDeadliftKg',
  };

  /// Flips the trainer's `sharedTemplatesWithAthletes` flag. When `true`,
  /// the Firestore rule on `routines` lets any authenticated user read this
  /// trainer's `trainer-template` docs — the athlete client filters them by
  /// linked-trainer-uid for the visible list. When `false`, only the
  /// trainer themselves can read their templates (existing behaviour).
  Future<void> setSharedTemplatesWithAthletes(String uid, bool value) async {
    await _col.doc(uid).set(
      {'sharedTemplatesWithAthletes': value},
      SetOptions(merge: true),
    );
  }

  /// Returns `true` when some OTHER user already owns the handle [displayName]
  /// (case-insensitive, exact match on `displayNameLowercase`). Used by the
  /// ProfileSetup step-1 availability check to prevent two athletes claiming
  /// the same public `@handle`.
  ///
  /// [excludeUid] lets the current user keep their own handle (re-running the
  /// onboarding / editing without seeing their own profile reported as taken).
  /// Returns `false` for a blank handle (the format validator already rejects
  /// it) without issuing a Firestore call.
  Future<bool> isDisplayNameTaken(
    String displayName, {
    String? excludeUid,
  }) async {
    final normalized = displayName.trim().toLowerCase();
    if (normalized.isEmpty) return false;

    final snap = await _col
        .where('displayNameLowercase', isEqualTo: normalized)
        .limit(2)
        .get();

    return snap.docs.any((d) => d.id != excludeUid);
  }

  /// Returns up to [limit] profiles whose `displayNameLowercase` starts with
  /// the trimmed lowercase [query]. Returns an empty list when [query] is
  /// blank after trimming. No Firestore call is issued in that case.
  ///
  /// The prefix-range technique uses the Unicode replacement character `￿`
  /// as an upper bound so that `startAt(q) + endBefore(q + '￿')` covers
  /// every string that begins with [q].
  Future<List<UserPublicProfile>> searchByDisplayName(
    String query, {
    int limit = 20,
  }) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return const [];

    final end = '$trimmed￿';

    final snap = await _col
        .where('displayNameLowercase', isGreaterThanOrEqualTo: trimmed)
        .where('displayNameLowercase', isLessThan: end)
        .limit(limit)
        .get();

    return snap.docs.map((d) => UserPublicProfile.fromJson(d.data())).toList();
  }
}
