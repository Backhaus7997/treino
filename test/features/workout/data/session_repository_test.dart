import 'package:cloud_firestore/cloud_firestore.dart'
    show QueryDocumentSnapshot, Timestamp;
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:treino/features/profile/data/user_public_profile_repository.dart';
import 'package:treino/features/profile/domain/user_public_profile.dart';
import 'package:treino/features/workout/data/session_repository.dart';
import 'package:treino/features/workout/domain/set_log.dart';
import 'package:treino/features/workout/domain/session_status.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late SessionRepository repo;
  late UserPublicProfileRepository publicProfileRepo;

  const uid = 'user-test-001';
  const routineId = 'routine-ppl';
  const routineName = 'Push Pull Legs';

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = SessionRepository(firestore: firestore);
    publicProfileRepo = UserPublicProfileRepository(firestore: firestore);
  });

  // ─── Helpers ──────────────────────────────────────────────────────────────

  DateTime testNow() => DateTime.utc(2026, 5, 18, 10, 0, 0);

  SetLog buildSetLog({required int setNumber, required DateTime completedAt}) {
    return SetLog(
      id: '', // repo replaces this with Firestore auto-id
      exerciseId: 'bench-press',
      exerciseName: 'Bench Press',
      setNumber: setNumber,
      reps: 10,
      weightKg: 80.0,
      rpe: null,
      completedAt: completedAt,
    );
  }

  Future<String> createActiveSession() async {
    final session = await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: testNow(),
    );
    return session.id;
  }

  // ─── create() ─────────────────────────────────────────────────────────────

  test('SCENARIO-240: create writes doc with status active and zero totals',
      () async {
    await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: testNow(),
    );

    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .get();

    expect(snap.docs, hasLength(1));
    final data = snap.docs.first.data();
    expect(data['status'], equals('active'));
    expect(data['totalVolumeKg'], equals(0.0));
    expect(data['durationMin'], equals(0));
    expect(data['finishedAt'], isNull);
  });

  test('SCENARIO-241: create returns Session with Firestore-generated id',
      () async {
    final session = await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: testNow(),
    );

    expect(session.id, isNotEmpty);

    // Verify the id matches the Firestore doc
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(session.id)
        .get();

    expect(snap.exists, isTrue);
    expect(snap.data()?['id'], equals(session.id));
  });

  // ─── finish() ─────────────────────────────────────────────────────────────

  test('SCENARIO-242: finish transitions status and persists totals', () async {
    final sessionId = await createActiveSession();
    final finishedAt = DateTime.utc(2026, 5, 18, 10, 45, 0);

    await repo.finish(
      uid: uid,
      sessionId: sessionId,
      finishedAt: finishedAt,
      totalVolumeKg: 95.5,
      durationMin: 45,
    );

    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .get();

    final data = snap.data()!;
    expect(data['status'], equals('finished'));
    // SCENARIO-242b: finishedAt MUST be a Firestore Timestamp, NOT a raw
    // DateTime. Otherwise real Firestore stores an ISO string and the
    // @TimestampConverter fails to deserialize on subsequent reads in Etapa 2.
    expect(
      data['finishedAt'],
      isA<Timestamp>(),
      reason: 'finish() must write Timestamp.fromDate, not raw DateTime',
    );
    expect(
      (data['finishedAt'] as Timestamp).toDate().toUtc(),
      equals(finishedAt),
    );
    expect(data['totalVolumeKg'], equals(95.5));
    expect(data['durationMin'], equals(45));
  });

  // ─── listByUid() ──────────────────────────────────────────────────────────

  test('SCENARIO-243: listByUid returns sessions newest-first', () async {
    final t1 = DateTime.utc(2026, 5, 17, 9, 0, 0); // older
    final t2 = DateTime.utc(2026, 5, 18, 9, 0, 0); // newer

    await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: t1,
    );
    await repo.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: t2,
    );

    final results = await repo.listByUid(uid);

    expect(results, hasLength(2));
    expect(results.first.startedAt, equals(t2)); // newest first
    expect(results.last.startedAt, equals(t1));
  });

  test('SCENARIO-244: listByUid returns empty list when user has no sessions',
      () async {
    final results = await repo.listByUid('uid-no-sessions');

    expect(results, isEmpty);
  });

  test('QA-WKT-008: listByUid bounds the read to [limit], newest-first',
      () async {
    for (var d = 1; d <= 3; d++) {
      await repo.create(
        uid: uid,
        routineId: routineId,
        routineName: routineName,
        startedAt: DateTime.utc(2026, 5, 10 + d, 9),
      );
    }

    // Bounded read returns only the N most recent (day 13, then day 12).
    final limited = await repo.listByUid(uid, limit: 2);
    expect(limited, hasLength(2));
    expect(limited.first.startedAt, DateTime.utc(2026, 5, 13, 9));
    expect(limited.last.startedAt, DateTime.utc(2026, 5, 12, 9));

    // Omitting the limit still returns the full history (the "show everything"
    // caller), so the bound is opt-in per call site.
    final all = await repo.listByUid(uid);
    expect(all, hasLength(3));
  });

  // ─── getActive() ──────────────────────────────────────────────────────────

  test('SCENARIO-245: getActive returns the active session when one exists',
      () async {
    await createActiveSession();

    final result = await repo.getActive(uid);

    expect(result, isNotNull);
    expect(result!.status, equals(SessionStatus.active));
    expect(result.uid, equals(uid));
  });

  test('SCENARIO-246: getActive returns null when no active session', () async {
    final sessionId = await createActiveSession();
    await repo.finish(
      uid: uid,
      sessionId: sessionId,
      finishedAt: DateTime.utc(2026, 5, 18, 10, 45, 0),
      totalVolumeKg: 0,
      durationMin: 0,
    );

    final result = await repo.getActive(uid);

    expect(result, isNull);
  });

  // ─── addSetLog() ──────────────────────────────────────────────────────────

  test('SCENARIO-247: addSetLog writes to nested sub-path', () async {
    final sessionId = await createActiveSession();
    final completedAt = DateTime.utc(2026, 5, 18, 10, 5, 0);

    await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(setNumber: 1, completedAt: completedAt),
    );

    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('setLogs')
        .get();

    expect(snap.docs, hasLength(1));
    final data = snap.docs.first.data();
    expect(data['exerciseId'], equals('bench-press'));
    expect(data['setNumber'], equals(1));
  });

  test('SCENARIO-248: addSetLog returns SetLog with auto-id', () async {
    final sessionId = await createActiveSession();
    final completedAt = DateTime.utc(2026, 5, 18, 10, 5, 0);

    final result = await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(setNumber: 1, completedAt: completedAt),
    );

    expect(result.id, isNotEmpty);

    // Verify the returned id matches the Firestore sub-doc id
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('setLogs')
        .doc(result.id)
        .get();

    expect(snap.exists, isTrue);
  });

  // ─── addSetLog(): dedupe contra lo que escribió el RELOJ ──────────────────
  //
  // El reloj escribe las series con id determinístico (`{exerciseId}__{n}`) y el
  // teléfono con uno autogenerado. Los dos espacios de ids son disjuntos, así que
  // el que escribía segundo no tenía contra qué deduplicar y creaba un documento
  // nuevo: DOS documentos para una sola serie, y volumen inflado en historial,
  // insights, progresión y rankings. Medido contra el emulador el 2026-08-11:
  // 5 de 7 sesiones con duplicados, la peor con 17 documentos para 10 series.
  //
  // Escribe el documento tal como lo deja el reloj vía la REST API.
  Future<void> seedWatchSetLog({
    required String sessionId,
    required String exerciseId,
    required int setNumber,
    required int fieldSetNumber,
  }) async {
    final docId = '${exerciseId}__$setNumber';
    await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('setLogs')
        .doc(docId)
        .set({
      'id': docId,
      'exerciseId': exerciseId,
      'exerciseName': 'Bench Press',
      // Se pasa aparte del id a propósito: la renumeración del teléfono deja
      // documentos cuyo campo `setNumber` ya no coincide con su ruta.
      'setNumber': fieldSetNumber,
      'reps': 10,
      'weightKg': 80.0,
      'completedAt': Timestamp.fromDate(DateTime.utc(2026, 5, 18, 10, 4, 0)),
    });
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> setLogDocs(
    String sessionId,
  ) async {
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('setLogs')
        .get();
    return snap.docs;
  }

  test(
      'addSetLog escribe SOBRE el documento del reloj en vez de crear un '
      'segundo documento de la misma serie', () async {
    final sessionId = await createActiveSession();
    await seedWatchSetLog(
      sessionId: sessionId,
      exerciseId: 'bench-press',
      setNumber: 1,
      fieldSetNumber: 1,
    );

    final persisted = await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(
        setNumber: 1,
        completedAt: DateTime.utc(2026, 5, 18, 10, 5, 0),
      ),
    );

    final docs = await setLogDocs(sessionId);
    expect(
      docs,
      hasLength(1),
      reason: 'Una serie lógica = un documento. Con dos, el volumen del '
          'historial se cuenta doble y rankings —que es competitivo entre gente '
          'del mismo gimnasio— lee un número inflado.',
    );
    expect(docs.first.id, equals('bench-press__1'));
    expect(
      persisted.id,
      equals('bench-press__1'),
      reason:
          'El id que se devuelve tiene que ser el del documento que existe: '
          'un updateSet/removeSet posterior apunta por id.',
    );
  });

  test(
      'addSetLog NO pisa un documento que la renumeración dejó en la ruta '
      'determinística con otra serie', () async {
    final sessionId = await createActiveSession();
    // Estado real después de que el teléfono borre una serie: `removeSet`
    // renumera las sobrevivientes con `updateSetLog`, que CONSERVA el id del
    // documento y baja el campo `setNumber`. Así, `bench-press__3` termina
    // conteniendo la serie 2.
    await seedWatchSetLog(
      sessionId: sessionId,
      exerciseId: 'bench-press',
      setNumber: 3,
      fieldSetNumber: 2,
    );

    final persisted = await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(
        setNumber: 3,
        completedAt: DateTime.utc(2026, 5, 18, 10, 5, 0),
      ),
    );

    expect(
      persisted.id,
      isNot(equals('bench-press__3')),
      reason: 'Confiar en la RUTA en vez de en los CAMPOS pisaría la serie 2, '
          'que el atleta cargó. Perder un dato es peor que el duplicado que '
          'este arreglo vino a cerrar.',
    );

    final docs = await setLogDocs(sessionId);
    expect(docs, hasLength(2));
    final renumbered = docs.firstWhere((d) => d.id == 'bench-press__3').data();
    expect(
      renumbered['setNumber'],
      equals(2),
      reason: 'La serie 2 sigue intacta en la ruta que quedó desalineada.',
    );
  });

  test(
      'addSetLog sigue creando su propio documento cuando el reloj no tocó '
      'esa serie', () async {
    final sessionId = await createActiveSession();
    await seedWatchSetLog(
      sessionId: sessionId,
      exerciseId: 'bench-press',
      setNumber: 1,
      fieldSetNumber: 1,
    );

    final persisted = await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(
        setNumber: 2,
        completedAt: DateTime.utc(2026, 5, 18, 10, 6, 0),
      ),
    );

    // El teléfono NO pasa a usar ids determinísticos para sus propias series:
    // eso obligaría a mover documentos al renumerar (HANDOFF §4.3). Solo ADOPTA
    // el del reloj cuando el reloj llegó primero.
    expect(persisted.id, isNot(equals('bench-press__2')));
    expect(await setLogDocs(sessionId), hasLength(2));
  });

  // ─── deleteSetLog() (live-set-editing PR2, AD-2) ─────────────────────────

  test(
      '[AD-2][REQ:workout#Confirmed removal deletes the underlying document] '
      'deleteSetLog hard-deletes the doc — no soft-delete flag, no lingering '
      'doc', () async {
    final sessionId = await createActiveSession();
    final completedAt = DateTime.utc(2026, 5, 18, 10, 5, 0);

    final persisted = await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(setNumber: 1, completedAt: completedAt),
    );

    await repo.deleteSetLog(
      uid: uid,
      sessionId: sessionId,
      setLogId: persisted.id,
    );

    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .collection('setLogs')
        .doc(persisted.id)
        .get();

    expect(snap.exists, isFalse,
        reason: 'deleteSetLog must be a hard delete — no lingering doc with '
            'a deleted:true marker or any other soft-delete flag');

    final remaining = await repo.listSetLogs(uid: uid, sessionId: sessionId);
    expect(remaining, isEmpty);
  });

  // ─── listSetLogs() ────────────────────────────────────────────────────────

  test('SCENARIO-249: listSetLogs returns logs ordered setNumber ASC',
      () async {
    final sessionId = await createActiveSession();

    // Add in reverse order on purpose
    await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(setNumber: 3, completedAt: testNow()),
    );
    await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(setNumber: 1, completedAt: testNow()),
    );
    await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(setNumber: 2, completedAt: testNow()),
    );

    final results = await repo.listSetLogs(uid: uid, sessionId: sessionId);

    expect(results, hasLength(3));
    expect(results[0].setNumber, equals(1));
    expect(results[1].setNumber, equals(2));
    expect(results[2].setNumber, equals(3));
  });

  test('SCENARIO-250: listSetLogs returns empty list when session has no logs',
      () async {
    final sessionId = await createActiveSession();

    final results = await repo.listSetLogs(uid: uid, sessionId: sessionId);

    expect(results, isEmpty);
  });

  test('SCENARIO-251: SetLogs are accessible after session is finished',
      () async {
    final sessionId = await createActiveSession();
    await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(setNumber: 1, completedAt: testNow()),
    );
    await repo.addSetLog(
      uid: uid,
      sessionId: sessionId,
      setLog: buildSetLog(setNumber: 2, completedAt: testNow()),
    );

    // Finish the session
    await repo.finish(
      uid: uid,
      sessionId: sessionId,
      finishedAt: DateTime.utc(2026, 5, 18, 10, 50, 0),
      totalVolumeKg: 1600.0,
      durationMin: 50,
    );

    // SetLogs must still be readable
    final results = await repo.listSetLogs(uid: uid, sessionId: sessionId);

    expect(results, hasLength(2));
    expect(results[0].setNumber, equals(1));
    expect(results[1].setNumber, equals(2));
  });

  // ─── finish() cross-feature write ─────────────────────────────────────────

  // SCENARIO-321 success: finish() updates userPublicProfiles with counters.
  // Uses repoWithProfile for BOTH create() and finish() to ensure
  // fake_cloud_firestore's sub-collection index is consistent.
  test(
      'SCENARIO-321: finish() updates userPublicProfiles/{uid} with workoutsCount and racha',
      () async {
    final repoWithProfile = SessionRepository(
      firestore: firestore,
      publicProfileRepository: publicProfileRepo,
    );

    // Use the same repo instance for create AND finish so fake_cloud_firestore
    // uses the same internal collection reference throughout.
    // Session date: 2026-05-15 = today (matches testNow() for streak calc)
    final session = await repoWithProfile.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: DateTime.utc(2026, 5, 15, 8, 0, 0),
    );

    await repoWithProfile.finish(
      uid: uid,
      sessionId: session.id,
      finishedAt: DateTime.utc(2026, 5, 15, 10, 45, 0),
      totalVolumeKg: 100.0,
      durationMin: 45,
      wasFullyCompleted: true,
    );

    final profileSnap =
        await firestore.collection('userPublicProfiles').doc(uid).get();
    expect(profileSnap.exists, isTrue);
    final data = profileSnap.data()!;
    // 1 fully completed session
    expect(data['workoutsCount'], equals(1));
    // racha is computed by computeStreak using DateTime.now(), bucketed by the
    // Argentina calendar day (#411). Its value depends on the real "today" in
    // ART relative to the fixed 2026-05-15 session, so we only assert it is a
    // non-negative integer (TZ-independent). startedAt is UTC-flagged, as real
    // data always is.
    expect(data['racha'], isA<int>());
  });

  // SCENARIO-321 failure: when public profile write fails, finish() still
  // completes and the primary session update is not affected
  test(
      'SCENARIO-321 failure: when public profile write throws, finish() resolves and session is finished',
      () async {
    final throwingRepo = _ThrowingPublicProfileRepository();
    final repoWithThrowingProfile = SessionRepository(
      firestore: firestore,
      publicProfileRepository: throwingRepo,
    );

    final sessionId = await createActiveSession();

    // Must not throw
    await expectLater(
      repoWithThrowingProfile.finish(
        uid: uid,
        sessionId: sessionId,
        finishedAt: DateTime.utc(2026, 5, 18, 10, 45, 0),
        totalVolumeKg: 75.0,
        durationMin: 40,
      ),
      completes,
    );

    // Primary op succeeded
    final snap = await firestore
        .collection('users')
        .doc(uid)
        .collection('sessions')
        .doc(sessionId)
        .get();
    expect(snap.data()?['status'], equals('finished'));
  });

  // ─── finish() ranking-metric denormalization — REMOVED
  // (sdd/rankings-integrity Phase 1, SCENARIO-RANK-3) ────────────────────────
  //
  // finish() no longer computes or writes lifetimeVolumeKg/best<Lift>Kg
  // itself (design AD-2/AD-9, spec `gym-rankings`: Session Finish — No
  // Longer the Client Authority for Metrics). That computation now lives
  // server-side in recomputeMetrics (functions/src/ranking-aggregate.ts),
  // triggered by rankingAggregateOnSession on every users/{uid}/sessions
  // write. SCENARIO-RANK-3a/3b/3c/3e/3f (which asserted the OLD client-side
  // compute-and-merge behavior) are replaced by SCENARIO-RANK-3g below;
  // SCENARIO-RANK-3d (opt-in OFF -> no ranking fields written) already
  // matched the new contract and is kept, restated for the new reason.

  test(
      'SCENARIO-RANK-3d (restated): opt-in OFF — none of the 4 ranking '
      'fields are written or changed', () async {
    await publicProfileRepo.set(
      const UserPublicProfile(uid: uid, rankingOptIn: false),
    );
    final repoWithProfile = SessionRepository(
      firestore: firestore,
      publicProfileRepository: publicProfileRepo,
    );

    final session = await repoWithProfile.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: DateTime.utc(2026, 5, 15, 8, 0, 0),
    );
    await repoWithProfile.addSetLog(
      uid: uid,
      sessionId: session.id,
      setLog: SetLog(
        id: '',
        exerciseId: 'squat-barra',
        exerciseName: 'Sentadilla (Barra)',
        setNumber: 1,
        reps: 5,
        weightKg: 120,
        completedAt: DateTime.utc(2026, 5, 15, 8, 10, 0),
      ),
    );
    await repoWithProfile.finish(
      uid: uid,
      sessionId: session.id,
      finishedAt: DateTime.utc(2026, 5, 15, 10, 45, 0),
      totalVolumeKg: 600.0,
      durationMin: 45,
      wasFullyCompleted: true,
    );

    final profile = await publicProfileRepo.get(uid);
    expect(profile!.lifetimeVolumeKg, equals(0));
    expect(profile.bestSquatKg, isNull);
    expect(profile.bestBenchKg, isNull);
    expect(profile.bestDeadliftKg, isNull);
  });

  test(
      'SCENARIO-RANK-3g (sdd/rankings-integrity Phase 1): finish() does NOT '
      'write lifetimeVolumeKg/best<Lift>Kg even when opted in with a real '
      'squat PR — that computation is server-side now (recomputeMetrics), '
      'not client-side', () async {
    await publicProfileRepo.set(
      const UserPublicProfile(uid: uid, rankingOptIn: true, bestSquatKg: 100),
    );
    final repoWithProfile = SessionRepository(
      firestore: firestore,
      publicProfileRepository: publicProfileRepo,
    );

    final session = await repoWithProfile.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: DateTime.utc(2026, 5, 15, 8, 0, 0),
    );
    await repoWithProfile.addSetLog(
      uid: uid,
      sessionId: session.id,
      setLog: SetLog(
        id: '',
        exerciseId: 'squat-barra',
        exerciseName: 'Sentadilla (Barra)',
        setNumber: 1,
        reps: 5,
        weightKg: 120,
        completedAt: DateTime.utc(2026, 5, 15, 8, 10, 0),
      ),
    );
    await repoWithProfile.finish(
      uid: uid,
      sessionId: session.id,
      finishedAt: DateTime.utc(2026, 5, 15, 10, 45, 0),
      totalVolumeKg: 600.0,
      durationMin: 45,
      wasFullyCompleted: true,
    );

    final profile = await publicProfileRepo.get(uid);
    // The stored value is untouched by finish() — no client-side compute
    // happens anymore. (The server-side trigger, not exercised by this
    // fake_cloud_firestore-backed test, would be the one to recompute it.)
    expect(profile!.bestSquatKg, equals(100));
    expect(profile.lifetimeVolumeKg, equals(0));
  });

  test(
      'SCENARIO-RANK-3h (sdd/rankings-integrity Phase 1): finish() still '
      'writes workoutsCount/racha exactly as before, independent of the '
      'ranking-metric server-side recompute', () async {
    await publicProfileRepo.set(
      const UserPublicProfile(uid: uid, rankingOptIn: true),
    );
    final repoWithProfile = SessionRepository(
      firestore: firestore,
      publicProfileRepository: publicProfileRepo,
    );

    final session = await repoWithProfile.create(
      uid: uid,
      routineId: routineId,
      routineName: routineName,
      startedAt: DateTime.utc(2026, 5, 15, 8, 0, 0),
    );
    await repoWithProfile.finish(
      uid: uid,
      sessionId: session.id,
      finishedAt: DateTime.utc(2026, 5, 15, 10, 45, 0),
      totalVolumeKg: 600.0,
      durationMin: 45,
      wasFullyCompleted: true,
    );

    final profile = await publicProfileRepo.get(uid);
    expect(profile!.workoutsCount, equals(1));
    expect(profile.racha, isA<int>());
  });
}

// ─── Test helpers ─────────────────────────────────────────────────────────────

class _ThrowingPublicProfileRepository extends UserPublicProfileRepository {
  _ThrowingPublicProfileRepository()
      : super(firestore: FakeFirebaseFirestore());

  @override
  Future<void> updateCounters(String uid, Map<String, Object?> fields) {
    throw Exception('Simulated public profile write failure');
  }
}
