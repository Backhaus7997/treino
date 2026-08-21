import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/duration_timer_state.dart';
import 'session_providers.dart';

/// La sesión que el player tiene ABIERTA, provista por su propio subárbol.
///
/// ── Por qué no se deduce ──────────────────────────────────────────────────
///
/// El primer intento resolvía la sesión con [activeSessionProvider], y estaba
/// mal por dos motivos, uno medido:
///
/// 1. **Se perdía la escritura, en silencio.** Ese provider envuelve a
///    `getActive`, que es una lectura que va al SERVIDOR primero y no tiene
///    timeout. Hasta que resuelve, leerlo da `null` y el cronómetro no se
///    anotaba — con la cuenta del teléfono andando igual, así que no había
///    ningún síntoma: el reloj simplemente nunca se enteraba. Medido con
///    `getActive` demorado: `timerEndsAtMs` quedaba nulo.
/// 2. **Era una SEGUNDA forma de nombrar la misma sesión.** El player ya sabe
///    cuál es —la que le devolvió su notifier— y `getActive` la vuelve a
///    buscar con otra consulta, que además CIERRA sesiones colgadas de paso.
///    Colgar el cronómetro de una lectura con efectos laterales, en la
///    pantalla más caliente de la app, es pedirlo.
///
/// El player la sabe. Que la diga.
///
/// ── Cómo se provee ────────────────────────────────────────────────────────
///
/// `SessionPlayerScreen` envuelve su subárbol —el de la rama `data`, donde la
/// sesión ya está resuelta— con un `ProviderScope` que sobreescribe esto:
///
/// ```dart
/// data: (state) => ProviderScope(
///   overrides: [playerSessionIdProvider.overrideWithValue(state.session.id)],
///   child: ...,
/// )
/// ```
///
/// El default es `null` a propósito, y es lo que hace que esto sea seguro fuera
/// de ese scope: sin sesión no se anota nada y no se rompe nada. Un test de
/// widget que monte una fila suelta cae ahí y no tiene que saber que el scope
/// existe.
final playerSessionIdProvider = Provider<String?>((ref) => null);

/// El cronómetro de la serie por tiempo anotado en la sesión abierta.
///
/// Es lo que el OTRO aparato ve, y lo que este aparato ve del otro: un único
/// documento compartido en vez de un mensaje por dirección. El porqué está en
/// [SessionRepository.fieldTimerEndsAt].
///
/// ## Todo se resuelve dentro de un `try` y nada tira
///
/// Esto lo escucha cada fila por tiempo del player. Hacer que esa pantalla
/// dependa de que Firebase esté inicializado la rompe en cualquier contexto
/// donde no lo esté — pasó, y reventaba con `FirebaseException` apenas se
/// montaba la fila en un test de widget.
///
/// Una sincronización que no sale degrada el espejo. Una fila que tira no deja
/// entrenar.
final sessionDurationTimerProvider = StreamProvider<DurationTimerState?>(
  (ref) {
    try {
      final sessionId = ref.watch(playerSessionIdProvider);
      if (sessionId == null || sessionId.isEmpty) return const Stream.empty();
      final uid = ref.watch(currentUidProvider);
      if (uid == null || uid.isEmpty) return const Stream.empty();

      return ref
          .watch(sessionRepositoryProvider)
          .watchExerciseTimer(uid: uid, sessionId: sessionId);
    } catch (e) {
      debugPrint('[duration-timer] sin canal de sincronización — $e');
      return const Stream.empty();
    }
  },
  // Obligatorio, no decorativo: Riverpod exige declarar de qué provider
  // SCOPEADO depende uno, y si falta lo tira en runtime al montar la fila
  // adentro del player. Es lo que hace que este provider se recree por scope
  // y lea el id de la sesion que ese subarbol tiene, no el del root.
  dependencies: [playerSessionIdProvider],
);

/// Anota y borra en la sesión el cronómetro que corre en ESTE aparato.
///
/// ## Nunca se espera la escritura
///
/// El cronómetro local ya arrancó cuando esto se llama. Atar la UI al ack del
/// servidor es el error que costó tres bugs en este ciclo: sin señal en el
/// gimnasio, el botón «Iniciar» se quedaba colgado y el atleta no podía hacer
/// su plancha. La escritura es el ESPEJO, no la serie.
///
/// ## Y el destino se lee, no se busca
///
/// Los dos datos que hacen falta —quién y cuál sesión— salen de providers
/// SÍNCRONOS: el uid ya está resuelto porque el atleta está adentro de la app,
/// y la sesión la provee el scope del player. Ninguno depende de una lectura
/// de red, que es lo que antes hacía que la anotación se perdiera sin ruido.
class DurationTimerRecorder {
  const DurationTimerRecorder(this._ref);

  final Ref _ref;

  ({String uid, String sessionId})? get _destino {
    final uid = _ref.read(currentUidProvider);
    if (uid == null || uid.isEmpty) return null;
    final sessionId = _ref.read(playerSessionIdProvider);
    if (sessionId == null || sessionId.isEmpty) return null;
    return (uid: uid, sessionId: sessionId);
  }

  void anotar(DurationTimerState timer) {
    try {
      final d = _destino;
      if (d == null) return;
      unawaited(
        _ref
            .read(sessionRepositoryProvider)
            .startExerciseTimer(
              uid: d.uid,
              sessionId: d.sessionId,
              timer: timer,
            )
            .catchError(
              (Object e) => debugPrint('[duration-timer] no se anotó — $e'),
            ),
      );
    } catch (e) {
      debugPrint('[duration-timer] no se pudo resolver la sesión — $e');
    }
  }

  void borrar() {
    try {
      final d = _destino;
      if (d == null) return;
      unawaited(
        _ref
            .read(sessionRepositoryProvider)
            .clearExerciseTimer(uid: d.uid, sessionId: d.sessionId)
            .catchError(
              (Object e) => debugPrint('[duration-timer] no se borró — $e'),
            ),
      );
    } catch (e) {
      debugPrint('[duration-timer] no se pudo resolver la sesión — $e');
    }
  }
}

final durationTimerRecorderProvider = Provider<DurationTimerRecorder>(
  DurationTimerRecorder.new,
  // Mismo motivo que arriba: sin esto, escribir desde adentro del scope tira.
  dependencies: [playerSessionIdProvider],
);
