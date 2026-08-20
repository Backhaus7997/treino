import '../domain/watch_timer_command.dart';
import 'watch_bridge.dart';

/// Le manda al reloj el cronómetro que arrancó en el teléfono.
///
/// El camino inverso ya existía y va por otro lado: un cronómetro arrancado en
/// el reloj viaja al teléfono DENTRO del payload de esfuerzo
/// (`EffortBroadcastRules.swift`), porque el reloj también tiene un solo
/// contexto de salida y el pulso ya lo ocupaba.
///
/// Acá el canal es `sendMessage` por la razón simétrica: el contexto de salida
/// del teléfono lo ocupa la credencial del reloj. El porqué completo está en
/// [WatchTimerCommand].
///
/// ── Por qué es best-effort ────────────────────────────────────────────────
///
/// `sendMessage` exige que el reloj esté alcanzable AHORA. Con la app del reloj
/// cerrada la orden se pierde, y no se reintenta: el cronómetro es una vista en
/// vivo de algo que está pasando en este momento: entregarlo tarde no sirve de
/// nada, y molestar al atleta con un error tampoco. El teléfono sigue contando
/// igual — él es el dueño de la serie.
class WatchTimerService {
  const WatchTimerService({required WatchBridge bridge}) : _bridge = bridge;

  final WatchBridge _bridge;

  /// Arrancó una serie por tiempo en el teléfono.
  ///
  /// [endsAt] es el INSTANTE de fin, no lo que falta: los dos lados derivan la
  /// misma cuenta de ahí contra su propio reloj de pared.
  Future<bool> start({
    required String exerciseId,
    required int setNumber,
    required int totalSeconds,
    required DateTime endsAt,
  }) =>
      _send(
        WatchTimerCommand.start(
          exerciseId: exerciseId,
          setNumber: setNumber,
          totalSeconds: totalSeconds,
          endsAt: endsAt,
        ),
      );

  /// Se cortó la serie sin cargarla.
  ///
  /// Al TERMINAR no hace falta avisar: el reloj llega a cero solo, porque
  /// cuenta contra el mismo instante de fin. Cancelar sí, porque adelanta un
  /// final que el instante de fin no anticipa.
  Future<bool> cancel() => _send(const WatchTimerCommand.cancel());

  Future<bool> _send(WatchTimerCommand command) async {
    try {
      if (!await _bridge.isSupported) return false;
      if (!await _bridge.isPaired) return false;
      // Sin alcanzabilidad no se intenta: `sendMessage` fallaría igual.
      if (!await _bridge.isReachable) return false;
      await _bridge.sendMessage(command.toMessage());
      return true;
    } catch (_) {
      // Un cronómetro que no llega al reloj no puede romper nada en el
      // teléfono, que es donde el atleta está mirando la serie.
      return false;
    }
  }
}
