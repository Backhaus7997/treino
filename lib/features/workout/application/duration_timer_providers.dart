import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/duration_timer_state.dart';
import 'session_providers.dart';

/// El cronómetro de la serie por tiempo anotado en la sesión activa.
///
/// Es lo que el OTRO aparato ve, y lo que este aparato ve del otro: un único
/// documento compartido en vez de un mensaje por dirección. El porqué está en
/// [SessionRepository.fieldTimerEndsAt].
///
/// ## Todo se resuelve dentro de un `try` y nada tira
///
/// Esto lo escucha cada fila por tiempo del player, que es la pantalla más
/// caliente de la app. Hacer que esa pantalla dependa de que Firebase esté
/// inicializado la rompe en cualquier contexto donde no lo esté — pasó, y
/// reventaba con `FirebaseException` apenas se montaba la fila en un test de
/// widget.
///
/// Una sincronización que no sale degrada el espejo. Una fila que tira no deja
/// entrenar.
final sessionDurationTimerProvider = StreamProvider<DurationTimerState?>((ref) {
  try {
    final uid = ref.watch(currentUidProvider);
    if (uid == null || uid.isEmpty) return const Stream.empty();
    final sesion = ref.watch(activeSessionProvider(uid)).valueOrNull;
    if (sesion == null) return const Stream.empty();

    return ref
        .watch(sessionRepositoryProvider)
        .watchExerciseTimer(uid: uid, sessionId: sesion.id);
  } catch (e) {
    debugPrint('[duration-timer] sin canal de sincronización — $e');
    return const Stream.empty();
  }
});

/// Anota y borra en la sesión el cronómetro que corre en ESTE aparato.
///
/// ## Nunca se espera la escritura
///
/// El cronómetro local ya arrancó cuando esto se llama. Atar la UI al ack del
/// servidor es el error que costó tres bugs en este ciclo: sin señal en el
/// gimnasio, el botón «Iniciar» se quedaba colgado y el atleta no podía hacer
/// su plancha. La escritura es el ESPEJO, no la serie.
class DurationTimerRecorder {
  const DurationTimerRecorder(this._ref);

  final Ref _ref;

  /// Adónde escribir, resuelto recién al momento de escribir. Ver el `try` de
  /// [sessionDurationTimerProvider]: mismo motivo, mismo costo de no tenerlo.
  ({String uid, String sessionId})? get _destino {
    final uid = _ref.read(currentUidProvider);
    if (uid == null || uid.isEmpty) return null;
    final sesion = _ref.read(activeSessionProvider(uid)).valueOrNull;
    if (sesion == null) return null;
    return (uid: uid, sessionId: sesion.id);
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

final durationTimerRecorderProvider =
    Provider<DurationTimerRecorder>(DurationTimerRecorder.new);
