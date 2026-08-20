import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/session_providers.dart';
import '../../workout/data/session_repository.dart';
import '../data/wear_workout_service.dart';
import '../domain/wear_timer_sync.dart';
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
/// El instante de arranque se guarda junto con la duración: quien lo lea
/// descuenta lo transcurrido, así los dos muestran el mismo número en vez de
/// quedar corridos por la latencia. Ver [wearRemainingSeconds].
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

  /// Arranca acá y lo anota en la sesión.
  ///
  /// El temporizador local arranca SIEMPRE, aunque la escritura falle: sin red
  /// el atleta igual tiene que poder hacer su plancha. Y la escritura no se
  /// espera — es la lección del ciclo: nunca hacer que la UI dependa del ack
  /// del servidor.
  Future<void> arrancar(int seconds) async {
    if (seconds <= 0) return cancelar();
    debugPrint('[wear-timer] ARRANCA local ($seconds s)');
    await _service.startExerciseTimer(seconds);
    if (!_puedeSincronizar) return;
    unawaited(
      _repo
          .startExerciseTimer(
            uid: _uid!,
            sessionId: _sessionId!,
            seconds: seconds,
            startedAtMs: DateTime.now().millisecondsSinceEpoch,
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

/// Refleja en el reloj el temporizador anotado en la sesión.
///
/// Se lee de forma EAGER en `main_wear.dart`. Emite el valor inicial al
/// suscribirse, así entrar al reloj DESPUÉS de haber arrancado el ejercicio en
/// el teléfono encuentra el temporizador en curso — el caso que un mensaje no
/// puede cubrir.
final wearTimerInboxProvider = Provider<void>((ref) {
  final sesion = ref.watch(wearSessionProvider);
  if (sesion is! WearSessionRunning) return;
  final uid = ref.watch(currentUidProvider);
  if (uid == null || uid.isEmpty) return;

  final service = ref.watch(wearWorkoutServiceProvider);

  final sub = ref
      .watch(sessionRepositoryProvider)
      .watchExerciseTimer(uid: uid, sessionId: sesion.session.sessionId)
      .listen(
    (remoto) async {
      debugPrint('[wear-timer] la sesión dice: $remoto');
      if (remoto == null) {
        // Se canceló del otro lado, o nunca hubo. Cancelar de más es inocuo:
        // el nativo borra un deadline que ya no está y listo.
        await service.cancelExerciseTimer();
        return;
      }

      // Si acá YA hay un temporizador corriendo, no se toca. Punto.
      //
      // Antes se comparaba el remanente y se reiniciaba ante cualquier
      // diferencia mayor a dos segundos, y eso era un bug: cada reinicio pisa
      // el deadline nativo, o sea que CAMBIA `endsAtElapsedMs`. Y como ocultar
      // se recuerda por deadline, el temporizador oculto dejaba de coincidir y
      // la pantalla reaparecía sola con el tiempo movido. El dueño lo vio como
      // "si oculto y vuelvo a entrar, se reinicia".
      //
      // Un temporizador que ya corre no necesita corrección: los dos aparatos
      // salieron del MISMO `startedAtMs`, así que van iguales por
      // construcción. Lo único que tiene que llegar de afuera es el arranque
      // —cuando acá no hay nada— y la cancelación, que se maneja arriba.
      final actual = await service.exerciseTimerState();
      debugPrint('[wear-timer] local=$actual');
      if (actual != null && !actual.finished) return;

      final restante = wearRemainingSeconds(
        seconds: remoto.seconds,
        startedAtEpochMs: remoto.startedAtMs,
        nowEpochMs: DateTime.now().millisecondsSinceEpoch,
      );
      if (restante <= 0) return;

      debugPrint('[wear-timer] sincronizado desde la sesión ($restante s)');
      await service.startExerciseTimer(restante);
    },
    onError: (Object e) => debugPrint('[wear-timer] el canal se quejó — $e'),
  );
  ref.onDispose(sub.cancel);
});
