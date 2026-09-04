import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/utils/app_clock.dart';

/// Guarda la invitación recibida hasta que se pueda aplicar.
///
/// ─── Por qué hace falta ────────────────────────────────────────────────────
///
/// El alumno abre el link, la app se abre, y le pide iniciar sesión. Todo lo
/// que vive en memoria —providers, estado de pantalla— se rearma después de
/// autenticarse, así que una invitación sostenida ahí se pierde exactamente en
/// el momento en que recién se vuelve aplicable: hace falta un uid para crear
/// el vínculo, y el uid llega DESPUÉS del login.
///
/// Por eso va a disco y no a memoria. `shared_preferences` sobrevive al login,
/// al signup y a cerrar la app; no sobrevive a desinstalarla, que es justo el
/// caso que necesita un proveedor de deferred links y no esto.
///
/// ─── Por qué caduca ────────────────────────────────────────────────────────
///
/// Sin fecha, una invitación que nunca se llegó a aplicar —el alumno abrió el
/// link, no completó el registro, volvió tres meses después— reaparecería
/// entera, con un PF que a esa altura ya no tiene nada que ver. Una invitación
/// vieja no es un pedido pendiente: es basura que sobrevivió.
class PendingInviteStore {
  PendingInviteStore(this._prefs);

  final SharedPreferences _prefs;

  static const _kTrainerId = 'pending_invite_trainer_id';
  static const _kRecibidaEn = 'pending_invite_received_at';

  /// Cuánto vale una invitación sin aplicar.
  ///
  /// 30 días es holgado a propósito: cubre "la abrí, me distraje, la retomé
  /// el fin de semana que viene" sin dejar que una invitación sobreviva a un
  /// cambio de entrenador.
  static const Duration validez = Duration(days: 30);

  /// [ahora] existe para que un test pueda fijar el instante sin congelar el
  /// reloj global. En producción cae a [AppClock.now], que es lo que pide el
  /// ratchet de deriva de reloj del repo: un reloj crudo no se puede congelar,
  /// y una caducidad que no se puede testear es una promesa.
  ///
  /// (El scanner de ese ratchet es TEXTUAL y cuenta comentarios: nombrar la
  /// llamada prohibida acá, aunque fuera para explicar por qué no se usa, la
  /// sumaba al total igual.)
  Future<void> guardar(String trainerId, {DateTime? ahora}) async {
    if (trainerId.trim().isEmpty) return;
    await _prefs.setString(_kTrainerId, trainerId);
    await _prefs.setInt(
      _kRecibidaEn,
      (ahora ?? AppClock.now()).millisecondsSinceEpoch,
    );
  }

  /// La invitación pendiente, o `null` si no hay o si ya caducó.
  ///
  /// Una caducada se limpia acá mismo: dejarla ocupando lugar significa que la
  /// próxima invitación que llegue tenga que competir con ella.
  Future<String?> leer({DateTime? ahora}) async {
    final id = _prefs.getString(_kTrainerId);
    if (id == null || id.isEmpty) return null;

    final ms = _prefs.getInt(_kRecibidaEn);
    if (ms == null) {
      // Guardada por una versión anterior, sin fecha. Se descarta en vez de
      // asumirla fresca: no hay forma de saber de cuándo es.
      await limpiar();
      return null;
    }
    final recibida = DateTime.fromMillisecondsSinceEpoch(ms);
    if ((ahora ?? AppClock.now()).difference(recibida) > validez) {
      await limpiar();
      return null;
    }
    return id;
  }

  /// Se llama SIEMPRE que la invitación se resolvió, haya terminado en vínculo
  /// o no. Una invitación que el alumno ya vio y decidió cancelar no puede
  /// volver a aparecer en el próximo arranque.
  Future<void> limpiar() async {
    await _prefs.remove(_kTrainerId);
    await _prefs.remove(_kRecibidaEn);
  }
}
