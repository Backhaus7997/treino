import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore, Timestamp;

import '../../../core/utils/streak_calculator.dart';
import '../../profile/data/user_public_profile_repository.dart';
import '../domain/session.dart';
import '../domain/session_status.dart';
import '../domain/set_log.dart';

class SessionRepository {
  SessionRepository({
    required FirebaseFirestore firestore,
    UserPublicProfileRepository? publicProfileRepository,
  })  : _firestore = firestore,
        _publicProfileRepository = publicProfileRepository;

  final FirebaseFirestore _firestore;
  final UserPublicProfileRepository? _publicProfileRepository;

  /// Upper bound on how many recent sessions [finish] reads back when
  /// recomputing the public `workoutsCount` / `racha` counters. Caps the read
  /// cost+latency at a constant instead of growing linearly with the user's
  /// lifetime session count on every workout completion. A streak can never
  /// exceed this many distinct days, and the counters self-heal each finish,
  /// so the window stays exact for any realistic athlete while bounding the
  /// read.
  ///
  /// `sdd/rankings-integrity` AD-2: the server-side `recomputeMetrics`
  /// (`functions/src/ranking-aggregate.ts`) independently reads the SAME
  /// bounded window size (ported as its own `RECOMPUTE_WINDOW` TS const) when
  /// computing `lifetimeVolumeKg`/`best<Lift>Kg` — this Dart constant is no
  /// longer read by any Dart caller for that purpose (the client stopped
  /// computing those fields), but the two window sizes MUST stay in lockstep
  /// or the server's recompute would disagree with what the app historically
  /// showed for `workoutsCount`/`racha` scoping.
  static const int counterRecomputeWindow = 365;

  // ─── Private collection getters ─────────────────────────────────────────

  CollectionReference<Map<String, Object?>> _sessions(String uid) =>
      _firestore.collection('users').doc(uid).collection('sessions');

  CollectionReference<Map<String, Object?>> _setLogs(
          String uid, String sessionId) =>
      _sessions(uid).doc(sessionId).collection('setLogs');

  // ─── create ─────────────────────────────────────────────────────────────

  Future<Session> create({
    required String uid,
    required String routineId,
    required String routineName,
    required DateTime startedAt,
    int dayNumber = 1,
    int weekNumber = 0,
  }) async {
    final ref = _sessions(uid).doc();
    final session = Session(
      id: ref.id,
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: startedAt,
      finishedAt: null,
      totalVolumeKg: 0.0,
      durationMin: 0,
      status: SessionStatus.active,
      dayNumber: dayNumber,
      weekNumber: weekNumber,
    );
    await ref.set(session.toJson());
    return session;
  }

  // ─── finish ─────────────────────────────────────────────────────────────

  Future<void> finish({
    required String uid,
    required String sessionId,
    required DateTime finishedAt,
    required double totalVolumeKg,
    required int durationMin,
    bool wasFullyCompleted = false,
  }) async {
    // finishedAt MUST be Timestamp.fromDate, not a raw DateTime — real Firestore
    // serializes a raw DateTime as an ISO string, but the @TimestampConverter
    // on Session.finishedAt expects a Firestore Timestamp on read. Without
    // this conversion, listByUid()/getActive() would fail to deserialize
    // sessions finished against production Firestore.
    await _sessions(uid).doc(sessionId).update({
      'status': SessionStatusX(SessionStatus.finished).toJson(),
      'finishedAt': Timestamp.fromDate(finishedAt.toUtc()),
      'totalVolumeKg': totalVolumeKg,
      'durationMin': durationMin,
      'wasFullyCompleted': wasFullyCompleted,
    });

    // Cross-feature: update public stats counters (best-effort, REQ-WRX-003).
    // Executes after the primary session update. Reads a BOUNDED window of the
    // user's most recent sessions via [listRecentCompletedByUid] (newest-first,
    // capped at [counterRecomputeWindow]) and recomputes in Dart — instead of
    // an unbounded full-collection read on every finish — then filters in Dart
    // to avoid fake_cloud_firestore's indexed-query stale-read issue.
    //
    // `sdd/rankings-integrity` AD-2/AD-9: this method no longer computes or
    // writes `lifetimeVolumeKg`/`best<Lift>Kg` — that ranking-metric
    // denormalization now lives server-side in `recomputeMetrics`
    // (`functions/src/ranking-aggregate.ts`), triggered by
    // `rankingAggregateOnSession` on this very `sessions/{id}` write. Only
    // `workoutsCount`/`racha` remain client-written here.
    final pubRepo = _publicProfileRepository;
    if (pubRepo == null) return;

    try {
      final completedList = await listRecentCompletedByUid(uid);
      final racha = computeStreak(completedList);
      final counters = <String, Object?>{
        'workoutsCount': completedList.length,
        'racha': racha,
      };

      await pubRepo.updateCounters(uid, counters);
    } catch (e, st) {
      developer.log(
        'SessionRepository.finish: failed to update public profile counters '
        'for $uid',
        error: e,
        stackTrace: st,
      );
      // DO NOT rethrow — public stats are best-effort
    }
  }

  // ─── getById ────────────────────────────────────────────────────────────

  Future<Session?> getById({
    required String uid,
    required String sessionId,
  }) async {
    final snap = await _sessions(uid).doc(sessionId).get();
    return _sessionFromDoc(snap);
  }

  // ─── listByUid ──────────────────────────────────────────────────────────

  Future<List<Session>> listByUid(String uid) async {
    final snap =
        await _sessions(uid).orderBy('startedAt', descending: true).get();
    return snap.docs.map(_sessionFromDoc).whereType<Session>().toList();
  }

  // ─── listRecentCompletedByUid ───────────────────────────────────────────

  /// Returns the athlete's most recently STARTED completed sessions, bounded
  /// to the SAME [counterRecomputeWindow] used by [finish]'s public-counter
  /// recompute (`racha`/`workoutsCount`/`lifetimeVolumeKg`/`best<Lift>Kg`).
  ///
  /// "Completed" mirrors [finish]'s own filter: `status == finished &&
  /// wasFullyCompleted == true` — abandoned sessions (finished but not fully
  /// completed) are excluded, matching the display filter used elsewhere
  /// (historial_section.dart, planProgressProvider).
  ///
  /// This is the SAME window+filter [finish] uses internally. Any other
  /// caller that recomputes a metric [finish] ALSO recomputes (e.g.
  /// [RankingOptInController.enableRankingOptIn] backfilling
  /// `lifetimeVolumeKg`/`best<Lift>Kg`) MUST call this instead of
  /// [listByUid], or the two computations will disagree the moment the
  /// athlete's history exceeds [counterRecomputeWindow] sessions.
  Future<List<Session>> listRecentCompletedByUid(String uid) async {
    final recentSnap = await _firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .orderBy('startedAt', descending: true)
        .limit(counterRecomputeWindow)
        .get();
    final allSessions =
        recentSnap.docs.map(_sessionFromDoc).whereType<Session>().toList();
    return allSessions
        .where((s) => s.status == SessionStatus.finished && s.wasFullyCompleted)
        .toList();
  }

  // ─── listFinishedToday ────────────────────────────────────────────────────

  /// Returns the athlete's FINISHED sessions whose `finishedAt` falls on the
  /// current UTC calendar day, ordered by `finishedAt` descending.
  ///
  /// Bounded server-side query (status + finishedAt range + limit) so the
  /// trainer dashboard's "Entrenaron hoy" list does NOT pull each athlete's
  /// full session history. [now] is injectable for deterministic tests.
  Future<List<Session>> listFinishedToday(String uid, {DateTime? now}) async {
    final today = (now ?? DateTime.now()).toUtc();
    final startOfDay = DateTime.utc(today.year, today.month, today.day);
    final startOfNextDay = startOfDay.add(const Duration(days: 1));
    // Apply the lower bound on the server (status + finishedAt >= startOfDay)
    // so the read stays bounded to recent sessions, then enforce the upper
    // bound (finishedAt < startOfNextDay) in Dart. Mirrors the workaround in
    // [finish]: fake_cloud_firestore drops the `isLessThan` upper bound when it
    // is combined with `isGreaterThanOrEqualTo` in a single `.where()`, which
    // would otherwise leak a future-dated session (finishedAt == startOfNextDay)
    // into "today".
    final snap = await _sessions(uid)
        .where('status', isEqualTo: 'finished')
        .where(
          'finishedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(startOfDay),
        )
        .orderBy('finishedAt', descending: true)
        .get();
    return snap.docs.map(_sessionFromDoc).whereType<Session>().where((s) {
      final finishedAt = s.finishedAt;
      return finishedAt != null && finishedAt.toUtc().isBefore(startOfNextDay);
    }).toList();
  }

  // ─── listFinishedInWindow ────────────────────────────────────────────────

  /// Returns the athlete's FINISHED sessions whose `finishedAt` falls within
  /// the given UTC [from, to) window, ordered by `finishedAt` descending.
  ///
  /// Bounded server-side query: `status == finished && finishedAt >= from`.
  /// Upper bound (`finishedAt < to`) is enforced in Dart — mirrors the pattern
  /// from [listFinishedToday] to avoid fake_cloud_firestore's two-range query
  /// stale-read issue. Returns `[]` immediately when [uid] is empty.
  Future<List<Session>> listFinishedInWindow(
    String uid, {
    required DateTime from,
    required DateTime to,
  }) async {
    if (uid.isEmpty) return const [];
    final snap = await _sessions(uid)
        .where('status', isEqualTo: 'finished')
        .where(
          'finishedAt',
          isGreaterThanOrEqualTo: Timestamp.fromDate(from.toUtc()),
        )
        .orderBy('finishedAt', descending: true)
        .get();
    return snap.docs.map(_sessionFromDoc).whereType<Session>().where((s) {
      final f = s.finishedAt;
      return f != null && f.toUtc().isBefore(to.toUtc());
    }).toList();
  }

  // ─── getActive ──────────────────────────────────────────────────────────

  Future<Session?> getActive(String uid) async {
    final snap = await _sessions(uid)
        .where('status', isEqualTo: 'active')
        .orderBy('startedAt', descending: true)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return _sessionFromDoc(snap.docs.first);
  }

  // ─── addSetLog ──────────────────────────────────────────────────────────

  Future<SetLog> addSetLog({
    required String uid,
    required String sessionId,
    required SetLog setLog,
  }) async {
    final ref = _setLogs(uid, sessionId).doc();
    final withId = setLog.copyWith(id: ref.id);
    await ref.set(withId.toJson());
    return withId;
  }

  // ─── updateSetLog ───────────────────────────────────────────────────────

  /// Overwrites an existing SetLog doc with new values. Used by the inline
  /// edit flow when the user changes reps/weight of a set that was already
  /// logged. The doc id MUST be the existing one (no new doc is created).
  Future<void> updateSetLog({
    required String uid,
    required String sessionId,
    required SetLog setLog,
  }) async {
    await _setLogs(uid, sessionId).doc(setLog.id).set(setLog.toJson());
  }

  // ─── deleteSetLog ───────────────────────────────────────────────────────

  /// Permanently deletes a `setLog` doc (live-set-editing AD-2). Real hard
  /// delete — NO soft-delete flag, no tombstone. Confirmed safe by AD-8: the
  /// ranking recompute trigger fires on `sessions/{id}` writes only (never on
  /// `setLogs` subcollection writes) and re-queries `setLogs` fresh at finish
  /// time, so a deleted doc is simply absent from the next recompute.
  Future<void> deleteSetLog({
    required String uid,
    required String sessionId,
    required String setLogId,
  }) async {
    await _setLogs(uid, sessionId).doc(setLogId).delete();
  }

  // ─── listSetLogs ────────────────────────────────────────────────────────

  Future<List<SetLog>> listSetLogs({
    required String uid,
    required String sessionId,
  }) async {
    final snap = await _setLogs(uid, sessionId)
        .orderBy('setNumber', descending: false)
        .get();
    return snap.docs.map(_setLogFromDoc).whereType<SetLog>().toList();
  }

  // ─── Private helpers ────────────────────────────────────────────────────

  Session? _sessionFromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    try {
      // Inject the doc id so a doc that didn't persist `id` in its body still
      // decodes (mirrors AppointmentRepository). Wrapped in try/catch so a
      // single malformed session doc can't break the whole list — critical for
      // the trainer dashboard, which reads other users' sessions.
      return Session.fromJson({...data, 'id': snap.id});
    } catch (e, st) {
      developer.log(
        'SessionRepository: skipped unparseable session ${snap.id}',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }

  SetLog? _setLogFromDoc(DocumentSnapshot<Map<String, Object?>> snap) {
    final data = snap.data();
    if (!snap.exists || data == null) return null;
    return SetLog.fromJson(data);
  }
}
