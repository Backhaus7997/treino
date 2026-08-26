import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/routine_providers.dart';
import '../../workout/application/session_providers.dart'
    show currentUidProvider, sessionRepositoryProvider, sessionsByUidProvider;
import '../../workout/data/session_repository.dart';
import '../../workout/domain/plan_advance.dart';
import '../../workout/application/session_duration.dart'
    show maxWorkoutDuration;
import '../../workout/domain/session.dart';
import '../../workout/domain/set_log.dart';
import '../../workout/domain/set_log_identity.dart';
import '../domain/wear_workout_plan.dart';
import '../domain/wear_workout_session.dart';
import '../presentation/wear/wear_view_models.dart';
import 'wear_rest_providers.dart';

/// En qué anda el entreno del reloj.
///
/// Espeja `session: WorkoutSession?` de watchOS, que es la forma que `WearRoot`
/// ya tiene: si hay entreno, gana sobre todo lo demás.
sealed class WearSessionState {
  const WearSessionState();
}

/// No hay entreno. El reloj muestra HOY.
class WearSessionIdle extends WearSessionState {
  const WearSessionIdle();
}

/// Abriendo: se está resolviendo si hay uno activo, o creando uno.
class WearSessionOpening extends WearSessionState {
  const WearSessionOpening();
}

/// Hay entreno en curso.
class WearSessionRunning extends WearSessionState {
  const WearSessionRunning(this.session);

  final WearWorkoutSession session;
}

/// No se pudo abrir. Es distinto de [WearSessionIdle]: acá hubo un intento.
class WearSessionFailed extends WearSessionState {
  const WearSessionFailed(this.motivo);

  final String motivo;
}

final wearSessionProvider =
    NotifierProvider<WearSessionNotifier, WearSessionState>(
  WearSessionNotifier.new,
);

/// Abre, adopta y mantiene el entreno del reloj.
///
/// ## La regla que no se negocia: ADOPTAR antes que CREAR
///
/// `start` llama SIEMPRE a `getActive` antes de crear. No es prolijidad: es que
/// `SessionRepository.create` no tiene ningún guard, así que crear a ciegas
/// mientras el teléfono ya tiene una sesión abierta deja DOS activas.
///
/// Y dos activas no es un empate benigno. `getActive` barre: cierra CUALQUIER
/// activa que no sea la más nueva por `startedAt` —tenga ocho horas o cinco
/// minutos— marcándola `wasFullyCompleted: false`. La que sobrevive es la del
/// reloj, porque es la más nueva. O sea: el entreno que el atleta está haciendo
/// EN EL TELÉFONO, con series cargadas, muere y lo expulsan del player.
///
/// ## El plan sale de la POSICIÓN DE LA SESIÓN
///
/// Nunca de «el día que tocaría hoy». Ver `wearWorkoutPlanFrom` — es el bug más
/// caro del lado Apple.
class WearSessionNotifier extends Notifier<WearSessionState> {
  StreamSubscription<List<SetLog>>? _series;

  /// Cambios en la colección de sesiones del atleta.
  ///
  /// Es lo que hace que el reloj ENTRE SOLO al entreno que se abrió en el
  /// teléfono. Antes la adopción corría una única vez, cuando llegaba el uid —
  /// o sea en la práctica al abrir la app—, así que arrancar desde el celular
  /// no se veía en la muñeca hasta reabrirla a mano.
  ///
  /// El companion de Apple tiene el mismo límite (`adoptRemoteSessionIfAny` se
  /// llama desde `restore()`), pero allá no hay alternativa: watchOS no tiene
  /// SDK de Firestore y habla REST. Wear sí lo tiene, así que acá se puede
  /// escuchar de verdad en vez de resincronizar al abrir.
  StreamSubscription<int>? _novedades;

  /// Que la sesión abierta se haya cerrado DESDE AFUERA.
  ///
  /// El caso que reportó el dueño: abandonaba desde el teléfono y el reloj
  /// seguía mostrando el entreno, con la única salida de reabrir la app.
  StreamSubscription<bool>? _cierreRemoto;

  var _muerto = false;

  /// Si hay una adopción EN VUELO.
  ///
  /// No es paranoia: `watchRevision` entrega el snapshot inicial apenas alguien
  /// se suscribe, así que al llegar el uid salían DOS adopciones casi
  /// simultáneas —la directa y la del primer evento del stream—. El guard de
  /// `state is! WearSessionIdle` no las separa, porque ninguna de las dos
  /// alcanzó todavía a mover el estado: entre el `getActive` y el `_abrir` hay
  /// dos `await`.
  ///
  /// El resultado era el entreno abierto dos veces y `startWorkout` llamado
  /// doble. Lo destaparon tres tests que ya existían, contando llamadas al
  /// servicio nativo.
  var _adoptando = false;

  /// Idem para el camino de salida. Entre el chequeo de estado y el `_set` de
  /// [_soltarLocal] hay un `await` —apagar el nativo—, y en esa ventana entran
  /// las dos vías: la local, que cierra el entreno, y la remota, que se entera
  /// de esa misma escritura. Sin un flag SÍNCRONO el servicio se apagaba dos
  /// veces.
  var _soltando = false;

  @override
  WearSessionState build() {
    ref.onDispose(() {
      _muerto = true;
      _series?.cancel();
      _novedades?.cancel();
      _cierreRemoto?.cancel();
    });

    // ⚠️ El uid llega ASÍNCRONO, y esto costó una corrida en el reloj.
    //
    // `currentUidProvider` sale de `authStateChangesProvider`, que es un stream:
    // cuando este notifier se construye, Firebase Auth todavía no restauró la
    // sesión y el uid es null. Leerlo UNA sola vez acá —que es lo que hacía—
    // daba null en todo arranque en frío, la adopción volvía en silencio, y el
    // reloj mostraba HOY teniendo un entreno abierto. Se recuperaba sólo si el
    // atleta tocaba Empezar, porque ese camino corre mucho después.
    //
    // Se ESCUCHA. `fireImmediately` cubre el arranque en caliente, donde el uid
    // ya está.
    ref.listen<String?>(
      currentUidProvider,
      (previo, nuevo) {
        if (nuevo == null || nuevo.isEmpty) return;
        if (previo == nuevo) return;
        // En microtask porque `fireImmediately` dispara este listener DENTRO
        // del build, y `_adoptarSiHay` mira `state` — que todavía no existe.
        // Riverpod tira "Tried to read the state of an uninitialized provider".
        unawaited(Future<void>.microtask(() {
          _escucharNovedades(nuevo);
          return _adoptarSiHay(nuevo);
        }));
      },
      fireImmediately: true,
    );

    // Adoptar es asíncrono, así que el estado inicial es Idle y la adopción lo
    // corrige. Arrancar en Opening haría parpadear un spinner en el caso
    // normal, que es no tener ningún entreno abierto.
    return const WearSessionIdle();
  }

  String? get _uid => ref.read(currentUidProvider);

  /// Si el atleta ya tiene un entreno abierto —lo empezó en el teléfono, o el
  /// reloj se reinició en medio— el reloj se suma a ÉSE.
  Future<void> _adoptarSiHay(String uid) async {
    // No pisar un entreno que ya se abrió por otro camino.
    if (state is! WearSessionIdle) return;
    // Ni duplicar el que se está abriendo AHORA. Ver [_adoptando].
    if (_adoptando) return;

    _adoptando = true;
    try {
      final abierta = await ref.read(sessionRepositoryProvider).getActive(uid);
      if (abierta == null) return;
      await _abrir(uid, abierta);
    } catch (e) {
      debugPrint('[wear-session] no se pudo adoptar el entreno abierto — $e');
      // Se queda en Idle a propósito: no poder adoptar no es no poder entrenar.
      // El atleta todavía puede tocar Empezar, y ese camino vuelve a intentar.
    } finally {
      _adoptando = false;
    }
  }

  /// Empieza el entreno de hoy, o se suma al que ya esté abierto.
  Future<void> start(WearTodaysWorkout hoy) async {
    if (state is WearSessionRunning || state is WearSessionOpening) return;

    final uid = _uid;
    if (uid == null || uid.isEmpty) {
      _set(const WearSessionFailed('sin sesión'));
      return;
    }

    _set(const WearSessionOpening());
    final repo = ref.read(sessionRepositoryProvider);

    try {
      // ADOPTAR PRIMERO. Ver el encabezado de la clase.
      final abierta = await _adoptable(repo, uid);
      if (abierta != null) {
        debugPrint('[wear-session] adoptando el entreno abierto '
            '${abierta.id} (día ${abierta.dayNumber})');
        await _abrir(uid, abierta);
        return;
      }

      final creada = await repo.create(
        uid: uid,
        routineId: hoy.routineId,
        routineName: hoy.routineName,
        startedAt: DateTime.now(),
        dayNumber: hoy.dayNumber,
        weekNumber: hoy.weekNumber,
        waitForServer: false,
      );
      debugPrint('[wear-session] entreno creado ${creada.id} '
          '(día ${creada.dayNumber}, semana ${creada.weekNumber})');
      await _abrir(uid, creada);
    } catch (e) {
      debugPrint('[wear-session] no se pudo empezar — $e');
      _set(const WearSessionFailed('no se pudo empezar el entreno'));
    }
  }

  /// Empieza una rutina que NO es la de hoy, desde las listas laterales.
  ///
  /// ## La posición sale de ESA rutina, no del día 1
  ///
  /// El día y la semana se calculan con las sesiones terminadas de esta misma
  /// rutina, así que una plantilla ya empezada **retoma donde iba**. Es la regla
  /// de `startNow` en `RoutineListView.swift`, y arrancar siempre del día 1
  /// haría que el atleta repita el primer día cada vez que entra por la lista.
  ///
  /// Adopta antes de crear, igual que [start]: la razón está en el encabezado de
  /// la clase y no cambia por venir de otra pantalla.
  ///
  /// Devuelve false si no se pudo abrir, para que el detalle muestre el error en
  /// vez de cerrarse como si hubiera funcionado.
  Future<bool> startRoutine(String routineId) async {
    if (state is WearSessionRunning || state is WearSessionOpening) {
      return false;
    }

    final uid = _uid;
    if (uid == null || uid.isEmpty) return false;

    _set(const WearSessionOpening());
    final repo = ref.read(sessionRepositoryProvider);

    try {
      final abierta = await _adoptable(repo, uid);
      if (abierta != null) {
        debugPrint('[wear-session] ya habia un entreno abierto '
            '${abierta.id}: se adopta en vez de empezar $routineId');
        await _abrir(uid, abierta);
        return state is WearSessionRunning;
      }

      final rutina = await ref.read(routineByIdProvider(routineId).future);
      if (rutina == null || rutina.days.isEmpty) {
        _set(const WearSessionFailed('no se encontró la rutina'));
        return false;
      }

      // La última sesión TERMINADA de esta rutina manda la posición. El
      // historial ya viene ordenado por startedAt descendente.
      final historial = await ref.read(sessionsByUidProvider(uid).future);
      Session? ultima;
      for (final s in historial) {
        if (s.routineId == routineId && s.countsAsWorkout) {
          ultima = s;
          break;
        }
      }

      final posicion = nextPlanPosition(
        lastFinished: ultima == null
            ? null
            : (dayNumber: ultima.dayNumber, weekNumber: ultima.weekNumber),
        numDays: rutina.days.length,
        numWeeks: rutina.numWeeks,
      );

      // Un día sin ejercicios presentes esta semana —una descarga, por ejemplo—
      // no se puede entrenar. Mejor decirlo que abrir una pantalla vacía; misma
      // guarda que `startNow` de watchOS.
      final plan = wearWorkoutPlanFrom(
        routine: rutina,
        dayNumber: posicion.dayNumber,
        weekNumber: posicion.weekNumber,
      );
      if (plan == null || plan.exercises.isEmpty) {
        _set(const WearSessionFailed('esta rutina no tiene ejercicios hoy'));
        return false;
      }

      final creada = await repo.create(
        uid: uid,
        routineId: routineId,
        routineName: rutina.name,
        startedAt: DateTime.now(),
        dayNumber: posicion.dayNumber,
        weekNumber: posicion.weekNumber,
        waitForServer: false,
      );
      debugPrint('[wear-session] entreno creado desde la lista ${creada.id} '
          '(día ${creada.dayNumber}, semana ${creada.weekNumber})');
      await _abrir(uid, creada);
      return state is WearSessionRunning;
    } catch (e) {
      debugPrint('[wear-session] no se pudo empezar $routineId — $e');
      _set(const WearSessionFailed('no se pudo empezar el entreno'));
      return false;
    }
  }

  /// Busca un entreno abierto, pero con TOPE.
  ///
  /// `getActive` es una lectura que va al servidor primero, así que sin red se
  /// cuelga y con ella se cuelga toda la pantalla.
  ///
  /// Si vence el tope se propaga el error en vez de devolver null, y eso es
  /// deliberado: devolver null diría «no hay ninguno» y el llamador crearía una
  /// segunda sesión. Dos activas hacen que el próximo barrido cierre la que NO
  /// es más nueva —la del teléfono, con el atleta adentro y series cargadas—.
  /// Fallar y que el atleta reintente es mucho más barato que eso.
  Future<Session?> _adoptable(SessionRepository repo, String uid) =>
      repo.getActive(uid).timeout(const Duration(seconds: 6));

  /// Resuelve el plan de [sesion] y engancha el historial en vivo.
  Future<void> _abrir(String uid, Session sesion) async {
    final rutina = await ref.read(routineByIdProvider(sesion.routineId).future);
    if (rutina == null) {
      _set(const WearSessionFailed('no se encontró la rutina'));
      return;
    }

    final plan = wearWorkoutPlanFrom(
      routine: rutina,
      dayNumber: sesion.dayNumber,
      weekNumber: sesion.weekNumber,
    );
    if (plan == null) {
      _set(const WearSessionFailed('la rutina no tiene ese día'));
      return;
    }

    _set(
      WearSessionRunning(
        WearWorkoutSession(
          sessionId: sesion.id,
          startedAt: sesion.startedAt,
          plan: plan,
          logged: const [],
        ),
      ),
    );

    _escucharSeries(uid, sesion.id);
    _escucharCierreRemoto(uid, sesion.id);
    await _prepararNativo();
  }

  /// Mira la colección de sesiones y adopta lo que aparezca.
  ///
  /// Se apoya en `watchRevision`, que ya existía como señal barata: no trae
  /// documentos, sólo avisa que algo cambió. Cuando avisa, y **sólo si el reloj
  /// está en Idle**, se vuelve a preguntar por la activa.
  ///
  /// Quién decide si corresponde adoptar es `_adoptarSiHay`, no este listener:
  /// ahí viven los dos guards —estado y adopción en vuelo— y ahí se chequean
  /// ANTES de cualquier consulta. Repetirlos acá era ruido, y se notó al mutar:
  /// sacar la copia no rompía ningún test porque no cambiaba nada.
  ///
  /// Las series NO viven en esta colección sino en una subcolección, así que
  /// marcar una serie no produce ruido acá.
  void _escucharNovedades(String uid) {
    _novedades?.cancel();
    _novedades = ref
        .read(sessionRepositoryProvider)
        .watchRevision(uid, limit: _sesionesQueSeMiran)
        .listen(
      (_) {
        if (_muerto) return;
        unawaited(_adoptarSiHay(uid));
      },
      onError: (Object e) =>
          debugPrint('[wear-session] el canal de novedades se quejó — $e'),
    );
  }

  /// Cuántas sesiones alcanza con vigilar para enterarse de una nueva.
  ///
  /// La activa es siempre de las más recientes, y `watchRevision` ordena por
  /// `startedAt` descendente. Acotarlo mantiene barato el listener en un reloj.
  static const int _sesionesQueSeMiran = 5;

  /// Suelta el entreno si lo cerraron desde el teléfono.
  ///
  /// `watchSessionFinished` ya existía —la usa el teléfono para el caso
  /// simétrico, cuando el reloj cierra un entreno que el celular tiene
  /// abierto— y emite tanto si la sesión se marcó terminada como si dejó de
  /// existir.
  void _escucharCierreRemoto(String uid, String sessionId) {
    _cierreRemoto?.cancel();
    _cierreRemoto = ref
        .read(sessionRepositoryProvider)
        .watchSessionFinished(uid: uid, sessionId: sessionId)
        .listen(
      (terminada) {
        if (_muerto || !terminada) return;
        debugPrint('[wear-session] el entreno se cerró desde afuera');
        unawaited(_soltarLocal());
      },
      onError: (Object e) =>
          debugPrint('[wear-session] el canal de cierre se quejó — $e'),
    );
  }

  /// Vuelve a HOY: corta los listeners, apaga el nativo y limpia el estado.
  ///
  /// Es IDEMPOTENTE a propósito. Cerrar desde el reloj escribe en Firestore, y
  /// esa misma escritura hace emitir a [_escucharCierreRemoto]: sin el guard,
  /// el camino local y el remoto apagarían el servicio dos veces.
  Future<void> _soltarLocal() async {
    if (state is WearSessionIdle) return;
    if (_soltando) return;
    _soltando = true;
    _series?.cancel();
    _series = null;
    _cierreRemoto?.cancel();
    _cierreRemoto = null;
    try {
      await _soltarNativo();
      _set(const WearSessionIdle());
    } finally {
      _soltando = false;
    }
  }

  /// Deja el lado nativo en el estado que corresponde a un entreno que EMPIEZA.
  ///
  /// Dos cosas, y las dos son bugs que se vieron en el reloj:
  ///
  /// 1. **Se limpia el descanso.** El deadline vive persistido en el nativo
  ///    (`RestStore`) para sobrevivir a que se destruya la Activity, así que un
  ///    descanso que quedó de un entreno abandonado seguía corriendo en el
  ///    siguiente — con CERO series marcadas, que es absurdo.
  /// 2. **Se arranca el foreground service acá y no antes.** Es lo que enciende
  ///    `ExerciseSessionController`, o sea pulso y calorías. Arrancaba con el
  ///    EMPAREJAMIENTO, así que las calorías se acumulaban desde que se abría la
  ///    app y el número no era del entreno. Además dejaba una notificación
  ///    permanente y Health Services corriendo para mirar la pantalla de HOY.
  Future<void> _prepararNativo() async {
    final service = ref.read(wearWorkoutServiceProvider);
    try {
      await service.cancelRest();
      await service.startWorkout();
    } catch (e) {
      // Sin servicio el entreno igual funciona; lo que se degrada es el
      // keep-alive. Tumbarlo por esto seria peor.
      debugPrint('[wear-session] no se pudo preparar el nativo — $e');
    }
  }

  /// Y lo deja como corresponde a un entreno que TERMINA.
  Future<void> _soltarNativo() async {
    final service = ref.read(wearWorkoutServiceProvider);
    try {
      await service.cancelRest();
      await service.stopWorkout();
    } catch (e) {
      debugPrint('[wear-session] no se pudo soltar el nativo — $e');
    }
  }

  /// El historial en vivo. **Es la única fuente de `logged`.**
  ///
  /// Acá se cobra la diferencia con watchOS: allá no hay listeners y por eso
  /// existe toda la máquina de avisos por WatchConnectivity. Wear tiene el SDK,
  /// así que una serie marcada en el teléfono llega sola —mediana medida de 206
  /// ms— y el cursor se recalcula con ella.
  ///
  /// Pisa la lista ENTERA en cada snapshot. Nunca hace merge: si el teléfono
  /// borró una serie, tiene que desaparecer, y eso con un merge es imposible.
  void _escucharSeries(String uid, String sessionId) {
    _series?.cancel();
    _series = ref
        .read(sessionRepositoryProvider)
        .watchSetLogs(uid: uid, sessionId: sessionId)
        .listen(
      (series) {
        final actual = state;
        if (actual is! WearSessionRunning) return;
        if (actual.session.sessionId != sessionId) return;

        final nuevas = [
          for (final s in series)
            WearLoggedSet(
              docId: s.id,
              exerciseId: s.exerciseId,
              setNumber: s.setNumber,
              reps: s.reps,
              weightKg: s.weightKg,
            ),
        ];

        // ⚠️ ACÁ se drena `pending`, y no en el `finally` de `logSet`.
        //
        // `set()` de Firestore NO completa hasta que el servidor confirma. Sin
        // red —y una muñeca pierde red todo el tiempo— la escritura queda en la
        // cola local y ese `await` no vuelve NUNCA: el `finally` no corre, la
        // identidad se queda en `pending` para siempre, y el cartel de «sin
        // subir» va creciendo con cada serie. Lo vio el dueño.
        //
        // La compensación de latencia de Firestore aplica la escritura al caché
        // al instante y el listener la refleja en milisegundos, sin esperar al
        // servidor. Así que la señal correcta de «ya no está en vuelo» es que la
        // serie APAREZCA en el historial, no que una promesa vuelva.
        //
        // Y es idempotente por construcción: se recalcula del historial entero
        // en cada snapshot, sin deltas.
        final visibles = {for (final l in nuevas) l.logicalId};

        _set(
          WearSessionRunning(
            actual.session.copyWith(
              logged: nuevas,
              pending: {
                for (final id in actual.session.pending)
                  if (!visibles.contains(id)) id,
              },
            ),
          ),
        );
      },
      onError: (Object e) {
        debugPrint('[wear-session] el historial dejó de llegar — $e');
        // NO se cambia de estado: el entreno sigue, con lo último que se supo.
        // Sacarlo de Running por un corte de red le borraria al atleta la
        // pantalla en medio de una serie.
      },
    );
  }

  /// Marca una serie del entreno.
  ///
  /// [exerciseId] lo pasa la FILA, no se resuelve del cursor. Entre que la fila
  /// se dibuja y el atleta la toca puede llegar un snapshot del teléfono que
  /// mueva el cursor, y la serie terminaría escrita en OTRO ejercicio.
  ///
  /// Es idempotente por identidad lógica: dos toques sobre la misma serie
  /// escriben una sola vez. El guard es POR SERIE y no global —a diferencia del
  /// `_isLoggingSet` del teléfono— porque en la muñeca marcar dos series
  /// seguidas rápido es normal, y un candado global se comería la segunda.
  Future<void> logSet({
    required String exerciseId,
    required int setNumber,
  }) async {
    final actual = state;
    if (actual is! WearSessionRunning) return;
    final sesion = actual.session;

    final identidad = '${exerciseId}__$setNumber';
    // Ya marcada, o con una escritura en vuelo. `identities` incluye `pending`.
    if (sesion.identities.contains(identidad)) return;

    final ejercicio = _ejercicioDe(sesion, exerciseId);
    if (ejercicio == null) return;
    if (setNumber < 1 || setNumber > ejercicio.sets.length) return;
    final spec = ejercicio.sets[setNumber - 1];

    final uid = _uid;
    if (uid == null || uid.isEmpty) return;

    // El círculo se llena en el toque: la escritura tiene un viaje de red por
    // delante y esperar a que vuelva se siente roto en la muñeca.
    _set(
      WearSessionRunning(
        sesion.copyWith(pending: {...sesion.pending, identidad}),
      ),
    );

    try {
      await ref.read(sessionRepositoryProvider).addSetLogFromWatch(
        uid: uid,
        sessionId: sesion.sessionId,
        setLog: SetLog(
          id: '',
          exerciseId: exerciseId,
          exerciseName: ejercicio.exerciseName,
          setNumber: setNumber,
          // Con un rango se registra el MÁXIMO: es el objetivo del plan.
          // Misma regla que watchOS; el atleta corrige desde el teléfono.
          reps: spec.reps ?? spec.repsMax ?? spec.repsMin ?? 0,
          weightKg: spec.weightKg ?? 0,
          completedAt: DateTime.now(),
        ),
        // El historial que el listener ya trajo. Sin esto, cada serie
        // releería la colección entera. Ver `addSetLogFromWatch`.
        knownRemote: [
          for (final l in sesion.logged)
            RemoteSetLogRef(
              docId: l.docId,
              exerciseId: l.exerciseId,
              setNumber: l.setNumber,
            ),
        ],
      );
    } catch (e) {
      debugPrint('[wear-session] no se pudo marcar $identidad — $e');
    } finally {
      // Red de seguridad, no el camino principal: si la escritura completó y el
      // listener ya la trajo, esto no hace nada. Lo que importa es el caso de
      // ERROR, donde la serie nunca va a aparecer en el historial y hay que
      // sacarla de `pending` para que el círculo se vacíe — que es honesto,
      // porque la serie NO quedó guardada.
      //
      // Ojo: sin red este `finally` NO CORRE, porque el `await` de arriba no
      // vuelve. Por eso el drenaje real vive en el listener.
      _sacarDePending(identidad);
    }
  }

  /// Cierra el entreno como COMPLETADO.
  ///
  /// Sólo se ofrece con todas las series de todos los ejercicios hechas
  /// (`isFullyCompleted`), que es pedido del dueño: tenerlo a la vista antes
  /// invita a cerrar el entreno de más.
  Future<void> finish() => _cerrar(completo: true);

  /// Abandona el entreno sin completarlo.
  ///
  /// Existe porque sin esto una lesión deja la sesión abierta para siempre y el
  /// atleta sin salida si no tiene el teléfono a mano — la deuda §8.3 del
  /// companion de Apple, que allá ya se cerró.
  Future<void> abandon() => _cerrar(completo: false);

  Future<void> _cerrar({required bool completo}) async {
    final actual = state;
    if (actual is! WearSessionRunning) return;
    final sesion = actual.session;

    final uid = _uid;
    if (uid == null || uid.isEmpty) return;

    final ahora = DateTime.now();
    try {
      await ref.read(sessionRepositoryProvider).finish(
            uid: uid,
            sessionId: sesion.sessionId,
            finishedAt: ahora,
            totalVolumeKg: sesion.totalVolumeKg,
            durationMin: _duracionMin(sesion.startedAt, ahora),
            wasFullyCompleted: completo,
          );
    } catch (e) {
      debugPrint('[wear-session] no se pudo cerrar el entreno — $e');
      // Se queda en Running: si la escritura falló, la sesión sigue abierta en
      // Firestore y sacar al atleta de la pantalla le mentiría.
      return;
    }

    await _soltarLocal();
  }

  /// Minutos del entreno, redondeados hacia arriba y con el mismo tope que usa
  /// el teléfono.
  ///
  /// No hay timer: un tick por segundo en un ARM de 32 bits es un rebuild por
  /// segundo durante todo el entreno. Como el número sólo hace falta al cerrar,
  /// se calcula ahí.
  int _duracionMin(DateTime desde, DateTime hasta) {
    final segundos = hasta
        .difference(desde)
        .inSeconds
        .clamp(0, maxWorkoutDuration.inSeconds);
    return (segundos + 59) ~/ 60;
  }

  WearPlannedExercise? _ejercicioDe(WearWorkoutSession s, String exerciseId) {
    for (final e in s.plan.exercises) {
      if (e.exerciseId == exerciseId) return e;
    }
    return null;
  }

  void _sacarDePending(String identidad) {
    final actual = state;
    if (actual is! WearSessionRunning) return;
    if (!actual.session.pending.contains(identidad)) return;
    _set(
      WearSessionRunning(
        actual.session.copyWith(
          pending: {...actual.session.pending}..remove(identidad),
        ),
      ),
    );
  }

  void _set(WearSessionState nuevo) {
    if (_muerto) return;
    state = nuevo;
  }
}
