import 'watch_bridge.dart';

/// Le avisa al reloj que algo cambió en el teléfono y conviene que relea.
///
/// ── Por qué existe ────────────────────────────────────────────────────────
/// El reloj habla Firestore por REST y **no tiene listeners**: Firestore no
/// figura entre los productos soportados en watchOS (Locked Decision #9). Por
/// eso un cambio hecho en el teléfono —marcar otra rutina como activa— no le
/// llega solo: recién lo ve al cambiar de página o al volver a primer plano.
///
/// El dueño lo notó probando: activar desde el reloj se ve al instante (el
/// reloj escribe y relee), pero activar desde el celular tardaba. Este aviso
/// cierra esa asimetría.
///
/// ── Por qué `sendMessage` y NO `updateApplicationContext` ─────────────────
/// El contexto de aplicación es UNO SOLO y se pisa entero. Ahí vive el payload
/// de credencial ([WatchCredentialPayload]), que es cómo el reloj consigue
/// autenticarse la primera vez. Mandar un aviso por ese canal borraría la
/// credencial de un reloj recién emparejado que todavía no la canjeó.
///
/// `sendMessage` es transitorio: no toca el contexto persistido.
///
/// ── Por qué es best-effort ────────────────────────────────────────────────
/// `sendMessage` exige que el reloj esté alcanzable AHORA. Si no lo está, el
/// aviso se pierde — y está bien: es una MEJORA de latencia, no el mecanismo
/// de corrección. El reloj igual relee al cambiar de página o al volver a
/// primer plano, así que el peor caso es exactamente el comportamiento que
/// había antes de esto.
class WatchNudgeService {
  const WatchNudgeService({required WatchBridge bridge}) : _bridge = bridge;

  final WatchBridge _bridge;

  /// Discrimina este mensaje de cualquier otro que viaje por el mismo canal.
  static const String kind = 'watchRefresh';

  /// El atleta cambió cuál es su rutina activa.
  static const String reasonActiveRoutine = 'activeRoutine';

  /// Arrancó un entreno en el teléfono. El reloj tiene que ponerse en modo
  /// entreno solo — es lo que lo vuelve un complemento y no una segunda app.
  static const String reasonWorkoutStarted = 'workoutStarted';

  /// Se cerró un entreno en el teléfono. El reloj tiene que salir del modo
  /// entreno en vez de quedarse sobre una sesión que ya no existe.
  static const String reasonWorkoutFinished = 'workoutFinished';

  /// Se marcó (o se borró) una serie en el teléfono.
  ///
  /// Cierra la ventana en la que el reloj todavía no sabe que esa serie existe:
  /// mientras no lo sepa, marcarla en la muñeca escribe un SEGUNDO documento de
  /// la misma serie y el atleta la ve dos veces. Los dos clientes generan ids
  /// distintos —el teléfono autogenerado, el reloj determinístico—, así que el
  /// que llega tarde no puede deduplicar por id.
  static const String reasonSetLogged = 'setLogged';

  /// CAMBIÓ EL ATLETA. Hay una credencial nueva esperando en el contexto.
  ///
  /// No le pide al reloj que relea Firestore —eso lo haría con la credencial
  /// VIGENTE, que si este aviso le gana la carrera al contexto es todavía la
  /// del atleta anterior— sino que vaya a MIRAR el contexto pendiente.
  ///
  /// Es un atajo, no el mecanismo: `updateApplicationContext` lo entrega el
  /// sistema cuando quiere, y con la app del reloj cerrada, recién en el
  /// próximo lanzamiento. Eso es lo que hacía que cambiar de cuenta tardara y
  /// obligara a cerrar y reabrir la app. Con el reloj a la vista, esto lo
  /// vuelve inmediato; sin él, todo sigue funcionando como antes.
  static const String reasonAccountChanged = 'accountChanged';

  /// Manda el aviso. Nunca tira: devuelve si se pudo entregar.
  Future<bool> nudge({String reason = reasonActiveRoutine}) async {
    try {
      if (!await _bridge.isSupported) return false;
      if (!await _bridge.isPaired) return false;
      // Sin alcanzabilidad no se intenta: `sendMessage` fallaría igual, y el
      // reloj se va a poner al día solo cuando el atleta lo mire.
      if (!await _bridge.isReachable) return false;
      await _bridge.sendMessage({'kind': kind, 'reason': reason});
      return true;
    } catch (_) {
      // Un aviso que no llega no puede romper nada en el teléfono.
      return false;
    }
  }
}
