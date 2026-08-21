import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart'
    show
        CollectionReference,
        DocumentSnapshot,
        FieldValue,
        FirebaseFirestore,
        SetOptions,
        Timestamp;

import '../../../core/utils/argentina_time.dart';
import '../../../core/utils/streak_calculator.dart';
import '../../profile/data/user_public_profile_repository.dart';
import '../domain/duration_timer.dart';
import '../domain/duration_timer_owner.dart';
import '../domain/duration_timer_state.dart';
import '../domain/session.dart';
import '../domain/session_status.dart';
import '../domain/set_log.dart';
import '../application/session_duration.dart';
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

  /// Cuántas sesiones `active` mira [getActive] para barrer las colgadas.
  ///
  /// No es 1 porque con `limit(1)` era imposible enterarse de que había otras;
  /// y no es ilimitado porque la lectura no puede crecer con la basura
  /// acumulada. 10 alcanza de sobra: el barrido corre en cada lectura, así que
  /// una cola larga se drena en pocas visitas en vez de en una sola cara.
  static const int _staleActiveSweep = 10;

  // ─── Private collection getters ─────────────────────────────────────────

  CollectionReference<Map<String, Object?>> _sessions(String uid) =>
      _firestore.collection('users').doc(uid).collection('sessions');

  CollectionReference<Map<String, Object?>> _setLogs(
          String uid, String sessionId) =>
      _sessions(uid).doc(sessionId).collection('setLogs');

  // ─── create ─────────────────────────────────────────────────────────────

  /// Crea la sesión.
  ///
  /// [waitForServer] en false devuelve apenas la escritura se aplica al caché
  /// LOCAL, sin esperar el ack del servidor. Es lo que necesita el reloj: el
  /// `Future` de `set()` no completa hasta que Firestore confirma, y sin red no
  /// completa NUNCA — el atleta tocaba «Empezar» y la app quedaba en «cargando»
  /// para siempre, con el entreno igual creado localmente.
  ///
  /// El id no depende del servidor: sale de `doc()`, que lo genera en el
  /// cliente. Así que la sesión que se devuelve es válida en los dos modos.
  ///
  /// El teléfono sigue esperando por defecto: ahí un fallo de escritura tiene
  /// que poder propagarse, y la pantalla puede mostrarlo.
  Future<Session> create({
    required String uid,
    required String routineId,
    required String routineName,
    required DateTime startedAt,
    int dayNumber = 1,
    int weekNumber = 0,
    bool waitForServer = true,
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
    final escritura = ref.set(session.toJson());
    if (waitForServer) {
      await escritura;
    } else {
      // La escritura ya se aplicó al caché al llamar a `set`. Lo que se saltea
      // es la confirmación del servidor, que Firestore reintenta solo.
      unawaited(
        escritura.catchError(
          (Object e) => developer.log(
            'create: la sesión no llegó al servidor todavía — $e',
            name: 'SessionRepository',
          ),
        ),
      );
    }
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

  /// La sesión activa del atleta. **Y cierra las que quedaron colgadas.**
  ///
  /// No existía ningún invariante de "una sola sesión activa por atleta": hay
  /// DOS caminos que crean sesiones `active` —`SessionNotifier._buildFresh` en
  /// el teléfono y `HistorySync.adoptOrCreateSession` en el reloj— y NINGUNO
  /// cerraba las que quedaban atrás. Como esta consulta siempre devolvió la más
  /// nueva, las viejas se volvían zombis invisibles que se acumulaban para
  /// siempre. Es la causa de fondo del "me marca el entreno como pendiente"
  /// (HANDOFF §8.1).
  ///
  /// Cerrarlas NO cambia nada de lo que ve el atleta: esta consulta ya
  /// devolvía solo la más nueva, así que las otras no se mostraban en ningún
  /// lado. Lo que sí cambia es que dejan de acumularse, y que el reloj —cuyo
  /// `findAnyActiveSession` mira las 10 más recientes sin terminar— deja de
  /// poder engancharse a una que para el atleta ya no existe.
  ///
  /// Va acá y no en `create` a propósito: `create` es el camino del TELÉFONO, y
  /// el reloj crea sus sesiones por REST sin pasar por Dart. Esta consulta es el
  /// único punto donde convergen los zombis de los dos clientes.
  ///
  /// Se cierran con `wasFullyCompleted: false`, así que no cuentan como entreno
  /// hecho: no mueven el avance del plan, ni la racha, ni los rankings.
  /// `totalVolumeKg` y `durationMin` se dejan como están —una sesión activa nace
  /// en 0 y nadie los toca hasta terminarla— porque inventarles un valor sería
  /// peor que dejar el 0 honesto.
  /// Además cierra la ÚLTIMA si ya venció.
  ///
  /// Barrer las repetidas dejaba viva una sesión de ayer, y el aviso de retomar
  /// seguía saliendo hoy — con un agravante: el modal muestra solo la hora, sin
  /// fecha, así que un entreno de hace cinco días se lee como "desde 19:42" y el
  /// atleta no tiene forma de saber que está viejo.
  ///
  /// El corte es [maxWorkoutDuration], la MISMA constante que ya usa
  /// `sanitizedActiveSessionElapsedSeconds` para acotar el cronómetro. No es un
  /// número nuevo: si el propio contador de tiempo considera que un entreno no
  /// puede durar más de eso, una sesión activa más vieja está muerta por
  /// definición.
  ///
  /// [now] se inyecta para que el test sea determinístico, igual que en
  /// [listFinishedToday].
  Future<Session?> getActive(String uid, {DateTime? now}) async {
    final snap = await _sessions(uid)
        .where('status', isEqualTo: 'active')
        .orderBy('startedAt', descending: true)
        // Se piden VARIAS y no una: con `limit(1)` era imposible enterarse de
        // que había colgadas. La cota existe igual para que la lectura no
        // crezca con la basura acumulada.
        .limit(_staleActiveSweep)
        .get();
    if (snap.docs.isEmpty) return null;

    final ahora = (now ?? DateTime.now()).toUtc();
    final masNueva = _sessionFromDoc(snap.docs.first);
    // Una sesión que no se puede ni leer no se puede ofrecer para retomar, pero
    // tampoco hay que dejarla colgada: entra en el barrido con las demás.
    final vencio = masNueva == null ||
        ahora.difference(masNueva.startedAt.toUtc()) > maxWorkoutDuration;

    // Si venció, se cierran TODAS; si no, todas menos la que el atleta está
    // haciendo.
    final aCerrar = vencio ? snap.docs : snap.docs.skip(1).toList();

    // Best-effort: si el barrido falla, se devuelve igual la sesión activa. El
    // atleta tiene que poder seguir entrenando aunque la limpieza no entre.
    if (aCerrar.isNotEmpty) {
      try {
        final cerradaEn = Timestamp.fromDate(ahora);
        for (final vieja in aCerrar) {
          await vieja.reference.update({
            'status': SessionStatusX(SessionStatus.finished).toJson(),
            'finishedAt': cerradaEn,
            'wasFullyCompleted': false,
          });
        }
      } catch (e, st) {
        developer.log(
          'SessionRepository: no se pudieron cerrar las sesiones colgadas '
          'de $uid',
          error: e,
          stackTrace: st,
        );
      }
    }

    return vencio ? null : masNueva;
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

  // ─── addSetLogFromWatch ─────────────────────────────────────────────────

  /// Escribe una serie marcada desde un RELOJ.
  ///
  /// Es un camino aparte de [addSetLog] a propósito, y la diferencia importa:
  /// [addSetLog] es el camino del TELÉFONO, que ADOPTA el documento del reloj si
  /// está y si no crea uno con id autogenerado. Un reloj escribiendo por ahí
  /// sería invisible para esa adopción — el teléfono no lo encontraría en la
  /// ruta determinística— y volverían los duplicados que costaron 24 documentos
  /// de más y 11.450 kg fantasma.
  ///
  /// **Lee el historial ANTES de escribir, y ese orden es parte del contrato.**
  /// Estaba al revés en el companion de Apple y por eso no había nada que
  /// adoptar (HANDOFF §4.3). El estado local no sirve para decidir esto: es tan
  /// fresco como el último snapshot que llegó, y la ventana medida entre los dos
  /// clientes fue de 37 segundos.
  ///
  /// Dónde escribir lo decide [resolveSetLogWriteTarget], que está bajo el
  /// contrato compartido de `conformance/set_log_write_target.json`.
  ///
  /// Devuelve la serie escrita, o **null** si ya estaba en el historial — en ese
  /// caso no se toca nada, porque reescribirla podría pisar una corrección que
  /// el atleta hizo en el teléfono.
  ///
  /// ## [knownRemote]: el historial que quien llama YA tiene
  ///
  /// Pasarlo evita releer la colección, y eso importa más de lo que parece. Sin
  /// él, marcar n series cuesta n(n-1)/2 lecturas de documento —para un entreno
  /// de 30 series, más de 400— porque cada escritura relee TODO el historial.
  ///
  /// El companion de Apple no hace eso: `WorkoutCoordinator.sync` lee el
  /// historial UNA vez y resuelve todas las series pendientes contra ese
  /// snapshot. El §4.3 del HANDOFF fija el ORDEN —leer antes de escribir— no la
  /// granularidad; leer por cada serie es endurecerlo a cuadrático sin que nadie
  /// lo pidiera.
  ///
  /// El reloj Wear tiene algo que watchOS no: un listener vivo sobre `setLogs`.
  /// Su vista está, como mucho, un push atrás —mediana medida de 206 ms— y
  /// además el teléfono tiene su propia defensa de adopción en [addSetLog]. Esa
  /// ventana es aceptable; cuatrocientas lecturas por entreno en una muñeca, no.
  ///
  /// Sin [knownRemote] se relee, para que un llamador sin listener siga siendo
  /// correcto.
  Future<SetLog?> addSetLogFromWatch({
    required String uid,
    required String sessionId,
    required SetLog setLog,
    List<RemoteSetLogRef>? knownRemote,
  }) async {
    final remote = knownRemote ?? await _leerHistorial(uid, sessionId);

    final target = resolveSetLogWriteTarget(
      exerciseId: setLog.exerciseId,
      setNumber: setLog.setNumber,
      remote: remote,
    );

    if (target is SetLogAlreadyThere) return null;

    final withId = setLog.copyWith(id: target.docId);
    await _setLogs(uid, sessionId).doc(target.docId).set(withId.toJson());
    return withId;
  }

  /// El historial de la sesión, reducido a lo que decide dónde escribir.
  Future<List<RemoteSetLogRef>> _leerHistorial(
    String uid,
    String sessionId,
  ) async {
    final snapshot = await _setLogs(uid, sessionId).get();
    final remote = <RemoteSetLogRef>[];
    for (final doc in snapshot.docs) {
      final data = doc.data();
      final exerciseId = data['exerciseId'];
      final setNumber = data['setNumber'];
      // Un documento corrupto o a medio escribir se saltea: no puede impedir
      // que el atleta marque una serie.
      if (exerciseId is! String || setNumber is! int) continue;
      remote.add(
        RemoteSetLogRef(
          docId: doc.id,
          exerciseId: exerciseId,
          setNumber: setNumber,
        ),
      );
    }
    return remote;
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

  // ─── Temporizador del ejercicio por tiempo ──────────────────────────────

  /// Campos del temporizador dentro del doc de sesión.
  ///
  /// Viven en la SESIÓN y no viajan como mensaje, y esa es la decisión de
  /// fondo. Un mensaje se pierde si el otro aparato no está escuchando en ese
  /// instante; el caso real es justamente el contrario — el atleta arranca el
  /// ejercicio en el teléfono y mira el reloj un rato después. Con estado
  /// persistido, el que llega tarde lo lee igual.
  ///
  /// Y va por Firestore y no por la Data Layer porque ésta exige que el reloj
  /// esté emparejado con ESE teléfono: medido en hardware, con un teléfono sin
  /// app companion el envío muere en «no hay nodos conectados» y no cruza nada.
  /// Firestore ya es el canal por el que los dos aparatos se mantienen al día.
  ///
  /// Lo que viaja es el shape de [DurationTimerState]: identidad, duración
  /// total, INSTANTE DE FIN y DUEÑO. El instante de fin y no los segundos que
  /// faltan, para que los dos lados deriven la cuenta con [DurationTimerRules]
  /// —la misma aritmética que el reloj de Apple, bajo contrato en
  /// `conformance/duration_timer.json`—. Y el dueño porque el documento es
  /// COMPARTIDO: a diferencia de un mensaje, acá el canal no dice quién arrancó,
  /// y sin eso los dos aparatos cargarían la misma serie al llegar a cero.
  static const String fieldTimerExerciseId = 'timerExerciseId';
  static const String fieldTimerSetNumber = 'timerSetNumber';
  static const String fieldTimerTotalSeconds = 'timerTotalSeconds';
  static const String fieldTimerEndsAt = 'timerEndsAtMs';
  static const String fieldTimerOwner = 'timerOwner';

  /// El dueño, escrito explícito y NO como `enum.name`.
  ///
  /// Renombrar el enum en Dart no puede cambiar en silencio lo que ya está
  /// escrito en una sesión viva: si el valor guardado deja de reconocerse, el
  /// espejo pasa a creerse dueño y carga la serie por segunda vez.
  static const String ownerPhone = 'phone';
  static const String ownerWatch = 'watch';

  /// Deja anotado el cronómetro que está corriendo.
  ///
  /// [DurationTimerState.endsAt] se guarda en epoch UTC de milisegundos. Es
  /// absoluto a propósito: ronda 1,8e12 y no entra en 32 bits, por lo mismo que
  /// documenta `conformance/duration_timer.json`.
  Future<void> startExerciseTimer({
    required String uid,
    required String sessionId,
    required DurationTimerState timer,
  }) async {
    if (uid.isEmpty || sessionId.isEmpty) return;
    if (timer.totalSeconds <= 0 || timer.exerciseId.isEmpty) return;
    final owner = _ownerToDoc(timer.owner);
    if (owner == null) return;
    await _sessions(uid).doc(sessionId).set(
      {
        fieldTimerExerciseId: timer.exerciseId,
        fieldTimerSetNumber: timer.setNumber,
        fieldTimerTotalSeconds: timer.totalSeconds,
        fieldTimerEndsAt: timer.endsAt.toUtc().millisecondsSinceEpoch,
        fieldTimerOwner: owner,
      },
      SetOptions(merge: true),
    );
  }

  /// Borra el temporizador. Se llama al cancelar y al completar la serie.
  Future<void> clearExerciseTimer({
    required String uid,
    required String sessionId,
  }) async {
    if (uid.isEmpty || sessionId.isEmpty) return;
    await _sessions(uid).doc(sessionId).set(
      {
        fieldTimerExerciseId: FieldValue.delete(),
        fieldTimerSetNumber: FieldValue.delete(),
        fieldTimerTotalSeconds: FieldValue.delete(),
        fieldTimerEndsAt: FieldValue.delete(),
        fieldTimerOwner: FieldValue.delete(),
      },
      SetOptions(merge: true),
    );
  }

  /// El temporizador anotado en la sesión, o null si no hay ninguno.
  ///
  /// Emite el valor inicial apenas se suscribe, así el aparato que entra TARDE
  /// —el caso que un mensaje no puede cubrir— encuentra el temporizador en
  /// curso.
  ///
  /// Un documento al que le falta cualquier campo se lee como "no hay
  /// temporizador". Es deliberado: media cuenta no se puede ubicar en una fila
  /// ni se le puede saber el dueño, y un espejo sin dueño se cree dueño.
  Stream<DurationTimerState?> watchExerciseTimer({
    required String uid,
    required String sessionId,
  }) {
    if (uid.isEmpty || sessionId.isEmpty) {
      return Stream.value(null);
    }
    return _sessions(uid)
        .doc(sessionId)
        .snapshots()
        .map((snap) => _timerFromDoc(snap.data()))
        .distinct();
  }

  static DurationTimerState? _timerFromDoc(Map<String, Object?>? data) {
    if (data == null) return null;
    final exerciseId = data[fieldTimerExerciseId];
    final setNumber = (data[fieldTimerSetNumber] as num?)?.toInt();
    final totalSeconds = (data[fieldTimerTotalSeconds] as num?)?.toInt();
    final endsAtMs = (data[fieldTimerEndsAt] as num?)?.toInt();
    final owner = _ownerFromDoc(data[fieldTimerOwner]);
    if (exerciseId is! String || exerciseId.isEmpty) return null;
    if (setNumber == null || setNumber <= 0) return null;
    if (totalSeconds == null || totalSeconds <= 0) return null;
    if (endsAtMs == null || owner == null) return null;
    return DurationTimerState(
      exerciseId: exerciseId,
      setNumber: setNumber,
      totalSeconds: totalSeconds,
      endsAt: DateTime.fromMillisecondsSinceEpoch(endsAtMs, isUtc: true),
      owner: owner,
    );
  }

  static String? _ownerToDoc(DurationTimerOwner owner) => switch (owner) {
        DurationTimerOwner.telefono => ownerPhone,
        DurationTimerOwner.reloj => ownerWatch,
        // Un cronómetro de nadie no es un cronómetro: no se escribe.
        DurationTimerOwner.nadie => null,
      };

  static DurationTimerOwner? _ownerFromDoc(Object? raw) => switch (raw) {
        ownerPhone => DurationTimerOwner.telefono,
        ownerWatch => DurationTimerOwner.reloj,
        _ => null,
      };

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
