import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../watch/application/watch_credential_providers.dart'
    show watchTimerServiceProvider;
import '../../watch/data/watch_timer_service.dart';

/// La cuenta por tiempo que corre en ESTE teléfono.
///
/// Lleva la identidad de la serie —la misma que usa el resto del sistema— para
/// que la fila que la dibuja pueda estar montada o no sin que eso cambie nada.
@immutable
class PhoneDurationTimer {
  const PhoneDurationTimer({
    required this.exerciseId,
    required this.setNumber,
    required this.totalSeconds,
    required this.endsAt,
  });

  final String exerciseId;
  final int setNumber;
  final int totalSeconds;

  /// Instante de fin. Se guarda el FIN y no lo que falta: la cuenta se deriva
  /// de acá contra el reloj de pared, así que no depende de cuántos ticks
  /// corrieron. Contrato compartido con el reloj en
  /// `conformance/duration_timer.json`.
  final DateTime endsAt;

  bool esDe({required String exerciseId, required int setNumber}) =>
      this.exerciseId == exerciseId && this.setNumber == setNumber;
}

/// Dónde vive el cronómetro del teléfono.
///
/// ── Por qué NO vive adentro de la fila ──────────────────────────────────
///
/// Vivía en el `State` de `DurationSetRow`. Los ejercicios del player cuelgan
/// de un `ListView` sin keep-alive, así que al scrollear la fila sale del
/// viewport, su `State` se destruye y **la cuenta moría con él**: el tiempo se
/// perdía, nadie marcaba la serie, y el atleta volvía a una fila que decía
/// "Iniciar" como si nunca hubiera pasado nada.
///
/// Del otro lado era peor: el reloj seguía espejando una cuenta que ya no
/// existía, llegaba a cero, VIBRABA "terminaste" por una serie que nadie cargó,
/// y encima bloqueaba arrancarla de nuevo desde la muñeca.
///
/// Acá la cuenta sobrevive al scroll, y el widget pasa a ser lo único que
/// debería haber sido: una vista.
///
/// ── Quién marca la serie ────────────────────────────────────────────────
///
/// Este notifier NO la marca. Solo tiene el estado y avisa al reloj cuando la
/// cuenta arranca o se corta. El que marca es la PANTALLA
/// (`SessionPlayerScreen`), que está montada todo el tiempo que el player está
/// abierto y es la que tiene el slot para armar el `SetLog`. Que la autoridad
/// de completado sea una sola —y esté siempre viva— es justamente lo que este
/// cambio viene a garantizar.
class PhoneDurationTimerNotifier extends ValueNotifier<PhoneDurationTimer?> {
  PhoneDurationTimerNotifier({required WatchTimerService reloj})
      : _reloj = reloj,
        super(null);

  final WatchTimerService _reloj;

  /// Arranca la cuenta de una serie.
  ///
  /// Si ya hay una corriendo no hace nada: dos cuentas a la vez sobre el mismo
  /// entreno no son un estado que el atleta pueda querer, y permitirlo abre la
  /// puerta a que se marquen dos series solas.
  Future<void> start({
    required String exerciseId,
    required int setNumber,
    required int totalSeconds,
    required DateTime endsAt,
  }) async {
    if (value != null) return;
    value = PhoneDurationTimer(
      exerciseId: exerciseId,
      setNumber: setNumber,
      totalSeconds: totalSeconds,
      endsAt: endsAt,
    );
    // Al reloj le viaja el INSTANTE de fin, así que la muñeca cuenta sola: no
    // hay tráfico por segundo y las dos pantallas no se pueden desfasar.
    await _reloj.start(
      exerciseId: exerciseId,
      setNumber: setNumber,
      totalSeconds: totalSeconds,
      endsAt: endsAt,
    );
  }

  /// Corta la cuenta SIN marcar la serie, y se lo avisa al reloj.
  ///
  /// Cancelar SÍ se avisa: adelanta un final que el instante de fin no
  /// anticipa. Sin eso el reloj seguiría contando algo que ya no existe.
  Future<void> cancel() async {
    if (value == null) return;
    value = null;
    await _reloj.cancel();
  }

  /// Corta la cuenta sin avisarle al reloj.
  ///
  /// Dos usos, y en los dos el aviso sobra:
  /// - La cuenta LLEGÓ A CERO: el reloj llega solo, porque cuenta contra el
  ///   mismo instante de fin.
  /// - El RELOJ pidió cancelar: ya sacó el espejo de su pantalla antes de
  ///   mandar el pedido.
  void clear() {
    value = null;
  }
}

/// Vive mientras viva la app, no mientras viva una fila.
///
/// Ese es el punto entero: si muriera con la pantalla —o peor, con la fila— la
/// cuenta volvería a depender de que el atleta no scrollee.
final phoneDurationTimerProvider = Provider<PhoneDurationTimerNotifier>((ref) {
  final notifier = PhoneDurationTimerNotifier(
    reloj: ref.watch(watchTimerServiceProvider),
  );
  ref.onDispose(notifier.dispose);
  return notifier;
});
