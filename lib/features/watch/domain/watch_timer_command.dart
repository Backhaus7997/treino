/// La orden de cronómetro que el teléfono le manda al reloj.
///
/// ── Por qué por MENSAJE y no por contexto de aplicación ───────────────────
///
/// El `applicationContext` de salida del teléfono es UNO SOLO y se pisa entero,
/// y ahí vive el payload de credencial ([WatchCredentialPayload]) — que es cómo
/// el reloj consigue autenticarse contra Firestore. Mandar el cronómetro por
/// ese canal borraría la credencial de un reloj recién emparejado que todavía
/// no la canjeó, y lo dejaría sin poder hablar con Firestore. Es la misma
/// restricción que ya documentó [WatchNudgeService], medida antes que esto.
///
/// `sendMessage` es transitorio: no toca el contexto persistido. El precio es
/// que exige que el reloj esté alcanzable AHORA. Con la app del reloj cerrada
/// la orden se pierde, y está bien: el caso real es entrenar con el reloj en la
/// muñeca. Falla en silencio, sin molestar al atleta.
///
/// ── Quién manda en la cuenta ──────────────────────────────────────────────
///
/// **El lado que arranca el cronómetro es el dueño de la serie.** El otro la
/// ESPEJA y no la carga.
///
/// No es un detalle de implementación, es lo que evita el bug: si el reloj
/// adoptara la orden como cronómetro propio, al llegar a cero cargaría la serie
/// por su cuenta — y el teléfono también, porque él la arrancó. Dos documentos
/// para la misma serie, que es exactamente el problema que ya describe
/// `WatchNudgeService.reasonSetLogged`.
///
/// Simétrico del otro lado: un cronómetro arrancado en el reloj viaja al
/// teléfono dentro del payload de esfuerzo y ahí también se muestra sin cargar
/// nada.
///
/// Viaja el INSTANTE DE FIN y no los segundos que faltan: así los dos lados
/// derivan la cuenta del mismo instante contra su propio reloj de pared, sin
/// tráfico por segundo, y una orden que llega tarde sigue mostrando el número
/// correcto. La aritmética está bajo contrato en `conformance/duration_timer.json`.
///
/// No es freezed a propósito, igual que [WatchEffort]: el reloj lee este mismo
/// shape en Swift (`PhoneTimerMirror.swift`), así que es un contrato entre
/// lenguajes y conviene tenerlo escrito a mano y a la vista.
library;

class WatchTimerCommand {
  const WatchTimerCommand._({
    required this.action,
    this.exerciseId,
    this.setNumber,
    this.totalSeconds,
    this.endsAt,
  });

  /// Arrancó una serie por tiempo en el teléfono.
  ///
  /// Los parámetros son NO nulos acá aunque los campos sean opcionales: una
  /// orden de arranque sin ejercicio o sin instante de fin no es una orden, y
  /// el tipo lo dice antes de que llegue al reloj.
  const WatchTimerCommand.start({
    required String exerciseId,
    required int setNumber,
    required int totalSeconds,
    required DateTime endsAt,
  }) : this._(
          action: actionStart,
          exerciseId: exerciseId,
          setNumber: setNumber,
          totalSeconds: totalSeconds,
          endsAt: endsAt,
        );

  /// Se cortó la serie sin cargarla. El reloj tiene que dejar de mostrarla.
  const WatchTimerCommand.cancel() : this._(action: actionCancel);

  /// Discrimina este mensaje de cualquier otro que viaje por el mismo canal.
  ///
  /// No es opcional: el canal lo comparte con el aviso de "relee"
  /// ([WatchNudgeService.kind]), y sin esto el reloj trataría una orden de
  /// cronómetro como un pedido de recarga.
  static const String kind = 'watchTimer';

  static const String actionStart = 'start';
  static const String actionCancel = 'cancel';

  final String action;
  final String? exerciseId;
  final int? setNumber;
  final int? totalSeconds;
  final DateTime? endsAt;

  /// El diccionario que viaja por WatchConnectivity.
  ///
  /// ⚠️ **Es un contrato con el lado Swift.** Las mismas claves las lee
  /// `PhoneTimerMirror.parse` en `ios/TreinoWatch Watch App/PhoneTimerMirror.swift`.
  /// Cambiar una acá sin cambiarla allá deja al reloj sin cronómetro y sin
  /// ningún error visible.
  ///
  /// `endsAtMs` son milisegundos desde epoch y rondan 1,8e12: NO entran en 32
  /// bits, y en watchOS `Int` es de 32 bits. El lado Swift tiene que leerlos
  /// como `Int64` — ver el comentario en `PhoneTimerMirror.swift`.
  Map<String, dynamic> toMessage() => {
        'kind': kind,
        'action': action,
        if (exerciseId != null) 'exerciseId': exerciseId,
        if (setNumber != null) 'setNumber': setNumber,
        if (totalSeconds != null) 'totalSeconds': totalSeconds,
        if (endsAt != null) 'endsAtMs': endsAt!.millisecondsSinceEpoch,
      };
}
