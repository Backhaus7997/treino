import 'dart:async';

import 'package:flutter_branch_sdk/flutter_branch_sdk.dart';

/// De dónde sale una invitación que llegó ANTES de que la app existiera en el
/// teléfono.
///
/// ─── El caso que esto resuelve, y por qué necesita un tercero ──────────────
///
/// El alumno abre el link sin tener TREINO instalada. El sistema operativo no
/// tiene a quién dársela: lo manda a la tienda. Cuando termina de instalar y
/// abre la app, el link ya no existe en ninguna parte — la app arranca en frío,
/// sin ninguna pista de por qué se la instaló.
///
/// Eso NO lo resuelve `PendingInviteStore`: ese guarda a disco lo que la app ya
/// recibió, y acá la app todavía no existía. Tampoco lo resuelven los universal
/// links: sólo funcionan si hay app que los reciba.
///
/// La única forma es que alguien recuerde el click del lado del servidor y lo
/// empareje con la primera apertura. Eso es un servicio de deferred deep
/// linking. Firebase Dynamic Links lo hacía y está discontinuado; acá se usa
/// Branch.
///
/// ─── Por qué hay una interfaz y no una llamada directa ────────────────────
///
/// Un proveedor de deferred links es un tercero con cuenta, clave y dominio
/// propios, y es un TRATAMIENTO DE DATOS que hay que declarar. Encapsularlo
/// permite tres cosas concretas: que la app corra sin proveedor configurado
/// (que es como corre hoy, y como corre en tests), que cambiarlo no toque el
/// flujo de invitación, y que el flujo se pueda testear sin SDK nativo.
abstract class DeferredInviteSource {
  /// El PF de la invitación que provocó ESTA instalación, o `null`.
  ///
  /// Sólo tiene sentido en la primera apertura después de instalar. De ahí en
  /// adelante los links entran por el camino normal.
  Future<String?> trainerIdDeLaInstalacion();
}

/// Sin proveedor. Es el default y no es un placeholder roto: sin Branch
/// configurado el resto del flujo de invitación funciona igual —los casos B a
/// E no dependen de esto— y lo único que se pierde es que la invitación
/// sobreviva a la instalación.
class SinDeferredInvites implements DeferredInviteSource {
  const SinDeferredInvites();

  @override
  Future<String?> trainerIdDeLaInstalacion() async => null;
}

/// Branch.
///
/// `getFirstReferringParams()` devuelve los parámetros del link que causó la
/// INSTALACIÓN — no el último abierto. Esa distinción es la que hace al caso:
/// entre el click y la primera apertura pasó una visita a la tienda.
///
/// ⚠️ **Requiere configuración que no vive en este repo**: cuenta de Branch,
/// `branch_key` en `Info.plist` y en el `AndroidManifest`, y el dominio del
/// link dado de alta en el panel de Branch. Sin eso, [init] falla y esta clase
/// se comporta igual que [SinDeferredInvites] — a propósito: que falte una
/// clave de un tercero no puede impedir que la app arranque.
class BranchDeferredInviteSource implements DeferredInviteSource {
  BranchDeferredInviteSource({this.claveDelParametro = 'pf'});

  /// El parámetro donde viaja el PF. Es el MISMO que usa el link propio
  /// (`?pf=`), para que las dos vías de entrada se lean igual.
  final String claveDelParametro;

  bool _iniciado = false;

  /// Arranca el SDK. Devuelve `false` si no se pudo —típicamente porque no hay
  /// clave configurada— y en ese caso [trainerIdDeLaInstalacion] devuelve
  /// `null` sin volver a intentar.
  Future<bool> init() async {
    try {
      await FlutterBranchSdk.init();
      _iniciado = true;
    } catch (_) {
      // Silencioso a propósito. Un proveedor de deep links caído o sin
      // configurar degrada una función; no puede tumbar el arranque.
      _iniciado = false;
    }
    return _iniciado;
  }

  @override
  Future<String?> trainerIdDeLaInstalacion() async {
    if (!_iniciado) return null;
    try {
      final params = await FlutterBranchSdk.getFirstReferringParams();
      return trainerIdDeParamsDeBranch(params, clave: claveDelParametro);
    } catch (_) {
      return null;
    }
  }
}

/// Saca el PF de los parámetros que devuelve Branch.
///
/// Vive afuera de la clase para poder testearse: el resto del adaptador no se
/// puede ejercitar sin SDK nativo, pero ESTO es lo que hay que revisar. Los
/// params son `Map<dynamic, dynamic>` y llegan de la red — entrada NO
/// confiable, igual que el `?to=` de un deep link. Se exige un String no
/// vacío; cualquier otra cosa es `null`.
String? trainerIdDeParamsDeBranch(
  Map<dynamic, dynamic> params, {
  String clave = 'pf',
}) {
  final crudo = params[clave];
  if (crudo is! String || crudo.trim().isEmpty) return null;
  return crudo;
}
