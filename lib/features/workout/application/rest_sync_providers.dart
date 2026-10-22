import 'dart:async';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../watch/application/watch_credential_providers.dart'
    show watchNudgeServiceProvider;
import '../../watch/data/watch_nudge_service.dart';
import '../data/session_repository.dart';
import '../domain/rest_state.dart';
import 'duration_timer_providers.dart' show playerSessionIdProvider;
import 'session_providers.dart';

/// El descanso anotado en la sesión que el player tiene abierta (#1616).
///
/// Es lo que el teléfono ve de los relojes: si el atleta marca la serie en la
/// muñeca, el descanso llega por acá. El porqué del diseño está en
/// `rest_rules.dart`; el formato, en `SessionRepository.fieldRestEndsAt`.
///
/// Scopeado por [playerSessionIdProvider], igual que el cronómetro y por el
/// mismo motivo (#817): la sesión la dice el player, no se deduce.
///
/// ## Nada tira
///
/// Mismo criterio que `sessionDurationTimerProvider`: sin Firebase —un test de
/// widget, un arranque raro— esto devuelve un stream vacío y el descanso del
/// teléfono sigue andando solo, como antes de #1616. Un espejo que no sale
/// degrada; uno que tira no deja entrenar.
final sessionRestProvider = StreamProvider<RestState?>(
  (ref) {
    try {
      final sessionId = ref.watch(playerSessionIdProvider);
      if (sessionId == null || sessionId.isEmpty) return const Stream.empty();
      final uid = ref.watch(currentUidProvider);
      if (uid == null || uid.isEmpty) return const Stream.empty();

      return ref
          .watch(sessionRepositoryProvider)
          .watchRest(uid: uid, sessionId: sessionId);
    } catch (e) {
      debugPrint('[descanso] sin canal de sincronización — $e');
      return const Stream.empty();
    }
  },
  dependencies: [playerSessionIdProvider],
);

/// Anota y borra en la sesión el descanso que cambió en ESTE teléfono.
///
/// ## Nunca se espera la escritura
///
/// El descanso local ya cambió cuando esto se llama. Sin red el atleta tiene
/// que poder descansar igual: la escritura es el ESPEJO, no el descanso.
///
/// ## Y al reloj de Apple se le avisa con la confirmación
///
/// El reloj de Apple no tiene listeners: se entera releyendo. Avisarle antes de
/// que el servidor tenga el descanso le haría leer el valor viejo, y no habría
/// un segundo aviso. Por eso el aviso cuelga del ack — offline queda pendiente
/// y sale cuando vuelve la red, que es cuando tiene sentido. Mismo criterio que
/// `SessionNotifier._onWriteSettled` con las series.
class RestRecorder {
  const RestRecorder(this._ref);

  final Ref _ref;

  ({String uid, String sessionId})? get _destino {
    final uid = _ref.read(currentUidProvider);
    if (uid == null || uid.isEmpty) return null;
    final sessionId = _ref.read(playerSessionIdProvider);
    if (sessionId == null || sessionId.isEmpty) return null;
    return (uid: uid, sessionId: sessionId);
  }

  void anotar(RestState rest) => _escribir(
        'anotar',
        (repo, d) =>
            repo.writeRest(uid: d.uid, sessionId: d.sessionId, rest: rest),
      );

  void borrar() => _escribir(
        'borrar',
        (repo, d) => repo.clearRest(uid: d.uid, sessionId: d.sessionId),
      );

  void _escribir(
    String que,
    Future<void> Function(
      SessionRepository repo,
      ({String uid, String sessionId}) destino,
    ) escritura,
  ) {
    try {
      final d = _destino;
      if (d == null) return;
      final repo = _ref.read(sessionRepositoryProvider);
      unawaited(
        escritura(repo, d).then<void>(
          (_) => _avisarAlReloj(),
          onError: (Object e) =>
              debugPrint('[descanso] no se pudo $que en la sesión — $e'),
        ),
      );
    } catch (e) {
      debugPrint('[descanso] no se pudo resolver la sesión — $e');
    }
  }

  void _avisarAlReloj() {
    try {
      unawaited(
        _ref
            .read(watchNudgeServiceProvider)
            .nudge(reason: WatchNudgeService.reasonRestChanged),
      );
    } catch (_) {
      // El scope pudo desmontarse mientras volvía el ack. Un aviso perdido no
      // rompe nada: el reloj relee al levantar la muñeca.
    }
  }
}

final restRecorderProvider = Provider<RestRecorder>(
  RestRecorder.new,
  dependencies: [playerSessionIdProvider],
);
