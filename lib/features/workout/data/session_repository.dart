import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show CollectionReference, DocumentSnapshot, FirebaseFirestore, Timestamp;

import '../../../core/utils/argentina_time.dart';
import '../../../core/utils/streak_calculator.dart';
import '../../profile/data/user_public_profile_repository.dart';
import '../domain/session.dart';
import '../domain/session_status.dart';
import '../domain/set_log.dart';
import '../domain/set_log_identity.dart';

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

  /// Sessions for [uid], newest-first. Pass [limit] to bound the read.
  ///
  /// QA-WKT-008: the history read used to be unbounded, and because
  /// `sessionsByUidProvider` is autoDispose it re-ran that full collection scan
  /// on every re-mount of the Workout tab (plus the derived aggregate
  /// providers). For a user with years of history that is a linear, growing
  /// Firestore cost per visit. Callers now pass a limit; only a genuine
  /// "show my entire history" caller should omit it.
  Future<List<Session>> listByUid(String uid, {int? limit}) async {
    var query = _sessions(uid).orderBy('startedAt', descending: true);
    if (limit != null) query = query.limit(limit);
    final snap = await query.get();
    return snap.docs.map(_sessionFromDoc).whereType<Session>().toList();
  }

  // ─── watchRevision ──────────────────────────────────────────────────────

  /// Emite un número distinto cada vez que cambia ALGO en las sesiones de
  /// [uid]: se crea una, se termina, se le carga una serie.
  ///
  /// Existe porque el historial se lee con `listByUid` de una sola vez, y desde
  /// que el RELOJ también escribe sesiones el teléfono no tiene forma de
  /// enterarse: terminabas el entreno en la muñeca y la app seguía mostrando lo
  /// de antes hasta que la cerrabas.
  ///
  /// Devuelve una REVISIÓN y no las sesiones a propósito. Convertir
  /// `sessionsByUidProvider` en stream cambiaría su tipo, y de él cuelgan el
  /// historial, Home, cuatro pantallas de Insights, el panel del PF y 30
  /// archivos de test. Una señal barata que dispara el refetch da lo mismo
  /// —datos frescos sin reiniciar— sin tocar nada de eso.
  ///
  /// El primer valor llega apenas se suscribe (Firestore entrega el snapshot
  /// inicial), así que quien lo escuche no queda colgado esperando un cambio.
  Stream<int> watchRevision(String uid, {int? limit}) {
    if (uid.isEmpty) return Stream.value(0);
    var query = _sessions(uid).orderBy('startedAt', descending: true);
    if (limit != null) query = query.limit(limit);
    // El contador vive por suscripción: cada listener arranca en 0 y sube con
    // cada snapshot. No importa el valor, importa que CAMBIE.
    var revision = 0;
    return query.snapshots().map((_) => revision++);
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
    // "Today" is the Argentina calendar day (UTC-3, no DST), NOT the UTC day:
    // a session finished at 23:00 ART belongs to today even though in UTC it is
    // already tomorrow. Bounds are ART-midnight (= 03:00 UTC) as UTC instants.
    final artNow = toArgentina((now ?? DateTime.now()).toUtc());
    final startOfDay = DateTime.utc(artNow.year, artNow.month, artNow.day)
        .add(argentinaUtcOffset);
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

  /// Persiste una serie. **Idempotente por identidad lógica contra lo que
  /// escribió el RELOJ**, no solo contra el estado local del teléfono.
  ///
  /// Antes de crear su documento, mira la ruta determinística con la que el reloj
  /// escribe esa misma serie (`{exerciseId}__{setNumber}`) y, si ya está, escribe
  /// SOBRE ESE documento en vez de crear uno nuevo.
  ///
  /// Por qué la comprobación va acá y no alcanzaba con el guard de
  /// `SessionNotifier.logSet`: ese guard pregunta por el estado LOCAL, y el
  /// estado local es tan fresco como el último snapshot que llegó. Medido contra
  /// el emulador el 2026-08-11, sobre una sesión de `seed-athlete-001`: el reloj
  /// escribió la serie 1 a las 17:06:13 y el teléfono creó su propio documento de
  /// la MISMA serie 37 segundos después, y cerró la sesión con
  /// `totalVolumeKg = 1650` — sus 3 series propias, sin haber ingerido ninguno de
  /// los 4 documentos del reloj en 55 segundos. Con 37 segundos de ventaja no hay
  /// carrera que perder: lo que falla es depender de la frescura de una caché.
  /// De 77 sesiones inspeccionadas, 13 tenían duplicados —24 documentos de más y
  /// 11.450 kg fantasma acumulados—; la peor, 17 documentos para 10 series
  /// reales. El volumen inflado lo leen historial, insights, progresión y
  /// RANKINGS, que es competitivo entre gente del mismo gimnasio.
  ///
  /// Cuesta UNA lectura por serie cargada (~30 por entreno).
  ///
  /// ⚠️ ALCANCE EXACTO, para no prometer más de lo que hace: esto NO vuelve la
  /// escritura atómica. La secuencia `get` → (el reloj escribe) → `set` sigue
  /// siendo posible; lo que cambia es el TAMAÑO de la ventana, de "lo que tarde
  /// en refrescarse la caché" —37 segundos medidos— a un round-trip de `get`.
  /// Cerrarla del todo pediría una transacción, que reintenta si el documento
  /// leído cambió antes del commit; no se agregó porque `fake_cloud_firestore`
  /// resuelve `runTransaction` con un `_DummyTransaction` sin atomicidad ni
  /// reintento, así que la garantía quedaría afirmada y no medida.
  ///
  /// En la práctica hay DOS defensas y la de la caché gana casi siempre: medido
  /// en los simuladores emparejados el 2026-08-12, al escribir la serie con la
  /// app en segundo plano y marcarla al volver, el listener llegó primero y el
  /// guard de `logSet` cortó antes de esta lectura. Este camino es la red para
  /// cuando ese listener NO llegó a tiempo — que es exactamente lo que pasó en la
  /// sesión de 37 segundos de arriba.
  ///
  /// El teléfono NO pasa a usar ids determinísticos para sus propias series: al
  /// borrar una serie renumera las siguientes, y eso obligaría a mover documentos
  /// (HANDOFF §4.3). Solo ADOPTA el id del reloj cuando el reloj llegó primero.
  Future<SetLog> addSetLog({
    required String uid,
    required String sessionId,
    required SetLog setLog,
  }) async {
    final watchDocId = setLogDeterministicDocId(
      exerciseId: setLog.exerciseId,
      setNumber: setLog.setNumber,
    );
    final watchRef = _setLogs(uid, sessionId).doc(watchDocId);
    final watchSnap = await watchRef.get();
    final watchData = watchSnap.data();

    // La identidad se decide por los CAMPOS, nunca por el path. Un documento
    // puede quedar en una ruta que ya no lo describe: `removeSet` renumera las
    // sobrevivientes con `updateSetLog`, que conserva el id y baja el campo
    // `setNumber`, así que `sentadilla__3` puede contener la serie 2. Escribir
    // ahí confiando en la ruta perdería una serie que el atleta cargó — peor que
    // el duplicado que estamos arreglando.
    //
    // No es hipotético: reproducido en los simuladores emparejados el
    // 2026-08-12. El reloj escribió `peso-muerto__1/2/3`, se borró la serie 2
    // desde el teléfono —la renumeración dejó `peso-muerto__3` conteniendo la
    // serie 2— y al cargar una serie 3 nueva el teléfono creó su propio
    // documento. Confiando en la ruta, esa serie 2 se habría destruido.
    final holdsThisSet = watchSnap.exists &&
        watchData != null &&
        setLogDocHoldsSet(
          docExerciseId: watchData['exerciseId'],
          docSetNumber: watchData['setNumber'],
          exerciseId: setLog.exerciseId,
          setNumber: setLog.setNumber,
        );

    if (holdsThisSet) {
      // Se pisa con los valores del teléfono a propósito: es la superficie
      // interactiva —la única con edición de reps/peso— así que el documento
      // queda coincidiendo con lo que el atleta está viendo. El id que se
      // devuelve es el del reloj, para que un `updateSet`/`removeSet` posterior
      // apunte al documento que existe y no a uno inventado.
      final adopted = setLog.copyWith(id: watchDocId);
      await watchRef.set(adopted.toJson());
      return adopted;
    }

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

  // ─── watchSetLogs ───────────────────────────────────────────────────────

  /// Stream vivo de las series de una sesión, ordenadas por `setNumber`.
  ///
  /// Existe porque el RELOJ escribe series en la misma sesión que el teléfono
  /// tiene abierta, y `listSetLogs` es una lectura única: el atleta marcaba en
  /// la muñeca y la pantalla del celular seguía mostrando la serie sin tildar.
  ///
  /// Ordenado igual que [listSetLogs] para que el estado no dé un salto de
  /// orden cuando el stream reemplaza a la carga inicial.
  Stream<List<SetLog>> watchSetLogs({
    required String uid,
    required String sessionId,
  }) {
    if (uid.isEmpty || sessionId.isEmpty) {
      return Stream.value(const <SetLog>[]);
    }
    return _setLogs(uid, sessionId)
        .orderBy('setNumber', descending: false)
        .snapshots()
        .map((s) => s.docs.map(_setLogFromDoc).whereType<SetLog>().toList());
  }

  // ─── watchSessionFinished ───────────────────────────────────────────────

  /// Emite `true` cuando la sesión pasa a terminada, o deja de existir.
  ///
  /// El reloj puede cerrar el entreno mientras el teléfono lo tiene abierto.
  /// Sin esto la app se quedaba con el player vivo sobre una sesión cerrada, y
  /// lo que se marcara ahí se escribía sobre un entreno que ya estaba en el
  /// historial.
  Stream<bool> watchSessionFinished({
    required String uid,
    required String sessionId,
  }) {
    if (uid.isEmpty || sessionId.isEmpty) return Stream.value(false);
    return _sessions(uid).doc(sessionId).snapshots().map((snap) {
      if (!snap.exists) return true;
      final data = snap.data();
      // `finishedAt` viaja SIEMPRE como clave (json_serializable la incluye
      // con null), así que preguntar por la presencia de la clave no alcanza:
      // hay que mirar el valor. Es la misma trampa que rompió el lado del
      // reloj — ver `FS.isEmpty` en FirestoreREST.swift.
      return data != null && data['finishedAt'] != null;
    });
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
    try {
      // El id sale del PATH, no del cuerpo (HANDOFF §4.2, la trampa que dejaba
      // las rutinas reales con id vacío). Los dos clientes hoy lo escriben
      // adentro y coincide, pero el path es el que manda: si alguna vez no
      // coincidieran, un `updateSetLog`/`deleteSetLog` por el id del cuerpo
      // apuntaría a un documento que no existe.
      //
      // Y va envuelto por la MISMA razón que `_sessionFromDoc`: una sola serie
      // malformada no puede tumbar la lista entera. Sin esto, `SetLog.fromJson`
      // tiraba y se llevaba puesto todo `listSetLogs` — o sea el entreno no
      // abría, ni para retomar ni para ver el historial. Una serie que no se
      // puede leer es una serie perdida; todas las demás no tienen por qué
      // irse con ella.
      return SetLog.fromJson({...data, 'id': snap.id});
    } catch (e, st) {
      developer.log(
        'SessionRepository: skipped unparseable setLog ${snap.id}',
        error: e,
        stackTrace: st,
      );
      return null;
    }
  }
}
