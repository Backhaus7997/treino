import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/app_clock.dart';
import '../../workout/application/session_providers.dart';
import '../../workout/data/session_repository.dart';
import '../../workout/domain/duration_timer_owner.dart';
import '../../workout/domain/duration_timer_state.dart';
import '../data/wear_workout_service.dart';
import 'wear_rest_providers.dart';
import 'wear_session_providers.dart';

/// Arranca y cancela el ejercicio por tiempo, en los DOS aparatos.
///
/// ## Por qué por Firestore y no por la Data Layer
///
/// Dos razones, y la segunda es la que manda.
///
/// 1. La Data Layer exige que el reloj esté emparejado con ESE teléfono, con la
///    app companion instalada. Medido en hardware: con un teléfono que no la
///    tiene, el envío muere en «no hay nodos conectados» y no cruza nada.
/// 2. **Un mensaje se pierde si el otro no está escuchando.** El caso real es
///    justamente ése: el atleta arranca el ejercicio en el teléfono y mira el
///    reloj un rato después. Para eso no alcanza un aviso, hace falta ESTADO —
///    y el estado va en la sesión, que es lo que los dos aparatos ya leen.
///
/// Lo que se anota es un [DurationTimerState] completo: con IDENTIDAD, para que
/// el teléfono sepa en qué fila dibujar el espejo, y con DUEÑO, para que sólo
/// uno de los dos cargue la serie al llegar a cero.
class WearTimerSync {
  const WearTimerSync({
    required WearWorkoutService service,
    required SessionRepository repo,
    required String? uid,
    required String? sessionId,
  })  : _service = service,
        _repo = repo,
        _uid = uid,
        _sessionId = sessionId;

  final WearWorkoutService _service;
  final SessionRepository _repo;
  final String? _uid;
  final String? _sessionId;

  bool get _puedeSincronizar =>
      (_uid?.isNotEmpty ?? false) && (_sessionId?.isNotEmpty ?? false);

  /// Arranca acá y lo anota en la sesión, con este reloj como DUEÑO.
  ///
  /// El temporizador local arranca SIEMPRE, aunque la escritura falle: sin red
  /// el atleta igual tiene que poder hacer su plancha. Y la escritura no se
  /// espera — es la lección del ciclo: nunca hacer que la UI dependa del ack
  /// del servidor.
  Future<void> arrancar({
    required String exerciseId,
    required int setNumber,
    required int seconds,
  }) async {
    if (seconds <= 0) return cancelar();
    debugPrint('[wear-timer] ARRANCA local ($seconds s)');
    await _service.startExerciseTimer(seconds);
    if (!_puedeSincronizar) return;
    unawaited(
      _repo
          .startExerciseTimer(
            uid: _uid!,
            sessionId: _sessionId!,
            timer: DurationTimerState.startedAt(
              exerciseId: exerciseId,
              setNumber: setNumber,
              totalSeconds: seconds,
              start: AppClock.now().toUtc(),
              owner: DurationTimerOwner.reloj,
            ),
          )
          .catchError(
            (Object e) => debugPrint('[wear-timer] no se pudo anotar — $e'),
          ),
    );
  }

  Future<void> cancelar() async {
    await _service.cancelExerciseTimer();
    if (!_puedeSincronizar) return;
    unawaited(
      _repo.clearExerciseTimer(uid: _uid!, sessionId: _sessionId!).catchError(
            (Object e) => debugPrint('[wear-timer] no se pudo borrar — $e'),
          ),
    );
  }
}

final wearTimerSyncProvider = Provider<WearTimerSync>((ref) {
  final sesion = ref.watch(wearSessionProvider);
  return WearTimerSync(
    service: ref.watch(wearWorkoutServiceProvider),
    repo: ref.watch(sessionRepositoryProvider),
    uid: ref.watch(currentUidProvider),
    sessionId: sesion is WearSessionRunning ? sesion.session.sessionId : null,
  );
});

/// Lo que la sesión dice del ejercicio por tiempo, visto desde el reloj.
///
/// Emite el valor inicial al suscribirse, así entrar al reloj DESPUÉS de haber
/// arrancado el ejercicio en el teléfono encuentra el temporizador en curso —
/// el caso que un mensaje no puede cubrir.
final wearSessionTimerProvider = StreamProvider<DurationTimerState?>((ref) {
  final sesion = ref.watch(wearSessionProvider);
  if (sesion is! WearSessionRunning) return const Stream.empty();
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid.isEmpty) return const Stream.empty();

  return ref.watch(sessionRepositoryProvider).watchExerciseTimer(
        uid: uid,
        sessionId: sesion.session.sessionId,
      );
});

/// El deadline nativo de un temporizador que NO es de este reloj.
///
/// ## Por qué se guarda el DEADLINE y no un bool
///
/// Es lo mismo que hace [wearTimerOcultadoProvider], y por el mismo motivo: un
/// bool habría que acordarse de apagarlo, y el olvido acá cuesta caro en las dos
/// direcciones —o el reloj deja de cargar series propias para siempre, o carga
/// una ajena—. Guardando CUÁL deadline es ajeno, un temporizador nuevo no
/// coincide y el estado se resetea solo.
///
/// Y por eso tampoco se limpia al cancelar. Limpiarlo abriría una carrera real:
/// el teléfono borra el documento al llegar a cero, y si eso llegara antes de
/// que el reloj note su propio vencimiento, el reloj se creería dueño y
/// cargaría la serie por segunda vez — que es exactamente el bug que esta regla
/// existe para evitar. Un valor viejo es inofensivo: apunta a un deadline que
/// ya no existe.
final wearTimerAjenoProvider = StateProvider<int?>((ref) => null);

/// Refleja en el reloj el temporizador anotado en la sesión.
///
/// Se lee de forma EAGER en `main_wear.dart`: sin eso, nadie escucha lo que el
/// teléfono anota y la sincronización es código muerto.
///
/// **Espeja siempre, sea de quien sea.** El dueño no decide qué se MUESTRA —el
/// atleta quiere ver la cuenta y sentir la vibración en la muñeca aunque la haya
/// arrancado en el teléfono—, decide quién CARGA la serie. Eso último se resuelve
/// con [wearTimerAjenoProvider].
final wearTimerInboxProvider = Provider<void>((ref) {
  final service = ref.watch(wearWorkoutServiceProvider);

  ref.listen<AsyncValue<DurationTimerState?>>(
    wearSessionTimerProvider,
    (_, next) => next.whenData(
      (remoto) => unawaited(_espejar(ref, service, remoto)),
    ),
    // Sin esto, un temporizador ya en curso al momento de suscribirse no se
    // espejaría hasta el siguiente cambio del documento — que puede no llegar
    // nunca, porque el instante de fin no cambia mientras corre.
    fireImmediately: true,
  );
});

Future<void> _espejar(
  Ref ref,
  WearWorkoutService service,
  DurationTimerState? remoto,
) async {
  debugPrint('[wear-timer] la sesión dice: $remoto');
  if (remoto == null) {
    // Se canceló del otro lado, o nunca hubo. Cancelar de más es inocuo: el
    // nativo borra un deadline que ya no está y listo.
    await service.cancelExerciseTimer();
    return;
  }

  // Si acá YA hay un temporizador corriendo, no se toca. Punto.
  //
  // Antes se comparaba el remanente y se reiniciaba ante cualquier diferencia
  // mayor a dos segundos, y eso era un bug: cada reinicio pisa el deadline
  // nativo, o sea que CAMBIA `endsAtElapsedMs`. Y como ocultar se recuerda por
  // deadline, el temporizador oculto dejaba de coincidir y la pantalla
  // reaparecía sola con el tiempo movido. El dueño lo vio como "si oculto y
  // vuelvo a entrar, se reinicia".
  //
  // Un temporizador que ya corre no necesita corrección: los dos aparatos
  // cuentan contra el MISMO instante de fin, así que van iguales por
  // construcción. Lo único que tiene que llegar de afuera es el arranque
  // —cuando acá no hay nada— y la cancelación, que se maneja arriba.
  final actual = await service.exerciseTimerState();
  debugPrint('[wear-timer] local=$actual');
  if (actual != null && !actual.finished) return;

  // `AppClock` y no `DateTime.now()`: lo que se le pasa al nativo son los
  // segundos que FALTAN, o sea una resta contra el reloj de pared. Con la hora
  // global no inyectada, cuánto da esa resta depende de lo que la máquina haya
  // tardado en llegar hasta acá — y `wear_timer_inbox_test.dart` lo pagaba,
  // esperando 40 y recibiendo 39 cuando el runner venía cargado. Congelado el
  // seam, la resta da siempre lo mismo.
  final restante = remoto.remainingAt(AppClock.now().toUtc());
  if (restante <= 0) return;

  debugPrint('[wear-timer] sincronizado desde la sesión ($restante s)');
  await service.startExerciseTimer(restante);

  // Y se anota que este deadline es AJENO, si lo es. Se lee de vuelta el estado
  // nativo porque el deadline lo pone el nativo —cuenta en `elapsedRealtime`,
  // no en reloj de pared— y es la única forma de saber cuál quedó.
  if (remoto.owner == DurationTimerOwner.reloj) return;
  final espejado = await service.exerciseTimerState();
  if (espejado == null) return;
  ref.read(wearTimerAjenoProvider.notifier).state = espejado.endsAtElapsedMs;
}
