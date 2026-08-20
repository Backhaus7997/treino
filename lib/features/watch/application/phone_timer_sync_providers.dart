import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../workout/application/session_providers.dart';
import '../domain/wear_timer_sync.dart';

/// Lo que el otro aparato dice sobre el ejercicio por tiempo.
sealed class WatchTimerCommand {
  const WatchTimerCommand();
}

/// Está corriendo allá, con [seconds] restantes.
class WatchTimerStart extends WatchTimerCommand {
  const WatchTimerStart(this.seconds);
  final int seconds;
}

/// No hay ninguno corriendo.
class WatchTimerCancel extends WatchTimerCommand {
  const WatchTimerCancel();
}

/// Anota en la sesión lo que pasa con el temporizador de este lado.
///
/// Va por Firestore y no por la Data Layer por dos motivos, y el segundo manda:
/// la Data Layer exige emparejamiento con ESE teléfono —medido: sin app
/// companion el envío muere en «no hay nodos conectados»—, y sobre todo un
/// mensaje se pierde si el otro no está escuchando. El caso real es arrancar en
/// el teléfono y mirar el reloj un rato después, y para eso hace falta ESTADO.
///
/// ## Todo se resuelve PEREZOSAMENTE y nada tira
///
/// El repositorio y la sesión se leen recién al momento de escribir, dentro de
/// un `try`. No es defensa de más: esto cuelga del botón «Iniciar» de la
/// pantalla más caliente de la app, y hacer que ese botón dependa de que
/// Firebase esté inicializado lo rompe en cualquier contexto donde no lo esté —
/// pasó en los tests de widget del player, que reventaron con
/// `FirebaseException` apenas se tocaba el botón.
///
/// Un aviso que no sale degrada la sincronización. Un botón que tira, no
/// deja entrenar.
class PhoneTimerSync {
  const PhoneTimerSync(this._ref);

  final Ref _ref;

  /// La sesión activa del atleta, o null si todavía no hay o no se puede saber.
  ({String uid, String sessionId})? get _destino {
    final uid = _ref.read(currentUidProvider);
    if (uid == null || uid.isEmpty) return null;
    final sesion = _ref.read(activeSessionProvider(uid)).valueOrNull;
    if (sesion == null) return null;
    return (uid: uid, sessionId: sesion.id);
  }

  /// No se espera la escritura: el temporizador local ya arrancó, y hacer que
  /// la UI dependa del ack del servidor es el error que costó tres bugs en
  /// este ciclo.
  void arranco(int seconds) {
    if (seconds <= 0) return;
    try {
      final d = _destino;
      if (d == null) return;
      unawaited(
        _ref
            .read(sessionRepositoryProvider)
            .startExerciseTimer(
              uid: d.uid,
              sessionId: d.sessionId,
              seconds: seconds,
              startedAtMs: DateTime.now().millisecondsSinceEpoch,
            )
            .catchError(
              (Object e) => debugPrint('[phone-timer] no se pudo anotar — $e'),
            ),
      );
    } catch (e) {
      debugPrint('[phone-timer] no se pudo resolver la sesión — $e');
    }
  }

  void cancelo() {
    try {
      final d = _destino;
      if (d == null) return;
      unawaited(
        _ref
            .read(sessionRepositoryProvider)
            .clearExerciseTimer(uid: d.uid, sessionId: d.sessionId)
            .catchError(
              (Object e) => debugPrint('[phone-timer] no se pudo borrar — $e'),
            ),
      );
    } catch (e) {
      debugPrint('[phone-timer] no se pudo resolver la sesión — $e');
    }
  }
}

final phoneTimerSyncProvider = Provider<PhoneTimerSync>(PhoneTimerSync.new);

/// El temporizador anotado en la sesión, ya traducido a un pedido.
///
/// Devuelve un stream vacío —y no tira— cuando todavía no hay sesión o no se
/// puede llegar a Firestore, por el mismo motivo que arriba: esto lo escucha la
/// pantalla del player y no puede ser un punto de falla.
final phoneTimerCommandsProvider = StreamProvider<WatchTimerCommand>((ref) {
  try {
    final uid = ref.watch(currentUidProvider);
    if (uid == null || uid.isEmpty) return const Stream.empty();
    final sesion = ref.watch(activeSessionProvider(uid)).valueOrNull;
    if (sesion == null) return const Stream.empty();

    return ref
        .watch(sessionRepositoryProvider)
        .watchExerciseTimer(uid: uid, sessionId: sesion.id)
        .expand((remoto) {
      if (remoto == null) return const [WatchTimerCancel()];

      final restante = wearRemainingSeconds(
        seconds: remoto.seconds,
        startedAtEpochMs: remoto.startedAtMs,
        nowEpochMs: DateTime.now().millisecondsSinceEpoch,
      );
      // Llegó vencido: arrancar uno de cero sería peor que ignorarlo.
      if (restante <= 0) return const <WatchTimerCommand>[];
      return [WatchTimerStart(restante)];
    });
  } catch (e) {
    debugPrint('[phone-timer] sin canal de sincronización — $e');
    return const Stream.empty();
  }
});
