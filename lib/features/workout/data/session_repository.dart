import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore, Timestamp;

import '../../../core/utils/streak_calculator.dart';
import '../../gym_rankings/domain/main_lift_family_map.dart';
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
  /// exceed this many distinct days, and the counters self-heal each finish, so
  /// the window stays exact for any realistic athlete while bounding the read.
  static const int _counterRecomputeWindow = 365;

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
    // user's most recent sessions (newest-first, capped at
    // [_counterRecomputeWindow]) and recomputes in Dart — instead of an
    // unbounded full-collection read on every finish — then filters in Dart to
    // avoid fake_cloud_firestore's indexed-query stale-read issue.
    final pubRepo = _publicProfileRepository;
    if (pubRepo == null) return;

    try {
      final recentSnap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('sessions')
          .orderBy('startedAt', descending: true)
          .limit(_counterRecomputeWindow)
          .get();
      final allSessions =
          recentSnap.docs.map(_sessionFromDoc).whereType<Session>().toList();
      // Only sessions actually completed count toward the public workout count
      // and streak. Abandoned sessions are also written with status=finished
      // (wasFullyCompleted=false), so we must exclude them here to match the
      // display filter (historial_section.dart, planProgressProvider).
      final completedList = allSessions
          .where(
              (s) => s.status == SessionStatus.finished && s.wasFullyCompleted)
          .toList();
      final racha = computeStreak(completedList);
      final counters = <String, Object?>{
        'workoutsCount': completedList.length,
        'racha': racha,
      };

      // Ranking-metric denormalization (REQ: Session-Finish Denormalization,
      // spec `user-public-profiles-layer`). Gated entirely on the athlete's
      // own rankingOptIn — reads their profile first so a non-opted-in
      // athlete never gets ranking fields written to their doc.
      final profile = await pubRepo.get(uid);
      if (profile != null && profile.rankingOptIn) {
        // RECOMPUTE (not FieldValue.increment) over the SAME completedList
        // window already fetched above for racha/workoutsCount — this makes
        // the write idempotent on a best-effort retry (increment would
        // double-count volume) at zero extra reads.
        final lifetimeVolumeKg = completedList.fold<double>(
          0.0,
          (sum, s) => sum + s.totalVolumeKg,
        );

        // Read setLogs per session in the SAME window (bounded — no
        // additional full-collection scan) to compute each main-lift
        // family's max weight, then max-merge against the stored value so
        // the write is naturally idempotent (max is idempotent) and
        // self-heals if the family map ever changes.
        final logsBySession = <String, List<SetLog>>{};
        for (final s in completedList) {
          logsBySession[s.id] = await listSetLogs(uid: uid, sessionId: s.id);
        }
        final allWindowLogs = logsBySession.values.expand((l) => l).toList();

        double? mergeBest(num? stored, double? windowMax) {
          if (windowMax == null) return stored?.toDouble();
          if (stored == null) return windowMax;
          return stored > windowMax ? stored.toDouble() : windowMax;
        }

        counters['lifetimeVolumeKg'] = lifetimeVolumeKg;
        counters['bestSquatKg'] = mergeBest(
          profile.bestSquatKg,
          familyMaxWeight(MainLift.squat, allWindowLogs),
        );
        counters['bestBenchKg'] = mergeBest(
          profile.bestBenchKg,
          familyMaxWeight(MainLift.bench, allWindowLogs),
        );
        counters['bestDeadliftKg'] = mergeBest(
          profile.bestDeadliftKg,
          familyMaxWeight(MainLift.deadlift, allWindowLogs),
        );
      }

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
