import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart' show debugPrint;

import '../domain/watch_credential_payload.dart';
import 'watch_bridge.dart';

/// Resultado de intentar entregarle credencial al reloj.
///
/// Es un enum y no un bool porque "no pasó nada" tiene causas muy distintas —
/// no hay reloj, no hay plataforma, falló el minteo, falló el envío — y
/// tratarlas igual esconde justo la que hay que diagnosticar.
enum WatchCredentialOutcome {
  /// Entregada. El reloj la va a canjear por credenciales propias.
  delivered,

  /// La plataforma no soporta relojes. No es un error.
  notSupported,

  /// No hay reloj emparejado. No es un error: la mayoría de los usuarios no
  /// tiene reloj y no hay que mintearles credenciales.
  noWatchPaired,

  /// La Cloud Function no devolvió un token usable.
  mintFailed,

  /// Se minteó pero no se pudo entregar al reloj.
  deliveryFailed,
}

/// Le consigue al reloj una credencial PROPIA y se la entrega.
///
/// Change `watch-standalone-client`, fase F1.
///
/// POR QUE NO SE COMPARTE LA CREDENCIAL DEL TELEFONO
/// -------------------------------------------------
/// El plan original decía que el teléfono le pasara su refresh token. No se
/// puede: `User.refreshToken` de firebase_auth es vacío en nativo — la
/// documentación del platform interface lo dice textual ("empty string for
/// native platforms"). Así que el reloj obtiene la suya vía
/// `mintWatchCredential`, lo que además sale mejor: es revocable por separado y
/// el teléfono nunca expone la propia.
///
/// FLUJO
/// -----
///   1. ¿Hay reloj? Si no, cortar acá — no se mintea credencial al pedo. Ver
///      [_hayReloj]: la pregunta no se responde igual en las dos plataformas.
///   2. Llamar a `mintWatchCredential` (mintea SOLO para el uid autenticado).
///   3. Mandar el payload por `updateApplicationContext`, que persiste y se
///      entrega cuando el reloj se reconecte.
class WatchCredentialService {
  WatchCredentialService({
    required FirebaseFunctions functions,
    required WatchBridge bridge,
    required String apiKey,
    required String projectId,
    String? authEmulatorHost,
    String? firestoreEmulatorHost,
  })  : _functions = functions,
        _bridge = bridge,
        _apiKey = apiKey,
        _projectId = projectId,
        _authEmulatorHost = authEmulatorHost,
        _firestoreEmulatorHost = firestoreEmulatorHost;

  final FirebaseFunctions _functions;
  final WatchBridge _bridge;
  final String _apiKey;
  final String _projectId;

  /// Solo se puebla corriendo contra el emulador. Ver [WatchCredentialPayload].
  final String? _authEmulatorHost;

  /// Idem, pero para Firestore: vive en OTRO puerto que Auth.
  final String? _firestoreEmulatorHost;

  /// Nombre del callable. Debe coincidir con el export de
  /// `functions/src/index.ts`.
  static const String callableName = 'mintWatchCredential';

  Future<WatchCredentialOutcome> deliverCredential(
      {required String uid}) async {
    if (!await _bridge.isSupported) {
      return _rastro(WatchCredentialOutcome.notSupported);
    }
    if (!await _hayReloj()) {
      return _rastro(WatchCredentialOutcome.noWatchPaired);
    }

    final String customToken;
    try {
      final callable = _functions.httpsCallable(callableName);
      // Se llama SIN argumentos a propósito. La CF mintea únicamente para
      // `request.auth.uid` y no acepta uid por parámetro; mandarle uno
      // sugeriría que se puede elegir a quién mintearle, que es exactamente el
      // agujero que esa función evita.
      final result = await callable.call<Map<String, dynamic>>(
        const <String, dynamic>{},
      );
      final token = result.data['customToken'];
      if (token is! String || token.isEmpty) {
        debugPrint('[watch-cred] $callableName devolvió un customToken '
            'inusable (${token.runtimeType}).');
        return _rastro(WatchCredentialOutcome.mintFailed);
      }
      customToken = token;
    } on FirebaseFunctionsException catch (e) {
      // El sospechoso número uno acá es App Check: la CF lo exige
      // (`enforceAppCheck: true`) y un APK sideloadeado con debug keys no puede
      // atestar con Play Integrity. Ese caso llega como `unauthenticated` y sin
      // el código a la vista es indistinguible de "no hay sesión".
      //
      // Tragarse este error SIN DEJAR RASTRO costó caro: la función devolvía
      // 401 "Decoding App Check token failed", acá se comía entero, y el único
      // síntoma visible era el reloj clavado en "vinculando" para siempre. La
      // causa y el síntoma no se parecían en nada.
      //
      // Matiz medido el 2026-08-25: para saber QUIÉN falla ya no hace falta
      // instrumentar nada — `firebase-functions` v2 loguea la verificación de
      // cada callable en `jsonPayload.verifications.app`, y cruzándola con el
      // user-agent sale que el roto es Android (1 VALID / 8 INVALID) y no iOS
      // (8 VALID / 2 INVALID). Ver docs/security.md §4.8.2. Lo que este log
      // sigue aportando, y el server no puede, es el POR QUÉ del lado del
      // dispositivo: por eso van también los `details`.
      debugPrint(
        '[watch-cred] $callableName falló — code=${e.code} '
        'message=${e.message} details=${e.details}',
      );
      return _rastro(WatchCredentialOutcome.mintFailed);
    } catch (e) {
      // Quedarse sin credencial de reloj no debe tumbar nada del teléfono.
      debugPrint('[watch-cred] $callableName falló — $e');
      return _rastro(WatchCredentialOutcome.mintFailed);
    }

    final payload = WatchCredentialPayload(
      customToken: customToken,
      uid: uid,
      apiKey: _apiKey,
      projectId: _projectId,
      authEmulatorHost: _authEmulatorHost,
      firestoreEmulatorHost: _firestoreEmulatorHost,
    );

    try {
      await _bridge.updateApplicationContext(payload.toJson());
    } catch (e) {
      debugPrint('[watch-cred] no se pudo publicar la credencial — $e');
      return _rastro(WatchCredentialOutcome.deliveryFailed);
    }

    return _rastro(
      WatchCredentialOutcome.delivered,
      detalle: 'uid=$uid, customToken de ${customToken.length} caracteres',
    );
  }

  /// Si vale la pena mintearle credencial a este teléfono.
  ///
  /// Parece una pregunta sola y son DOS, porque `isPaired` no significa lo
  /// mismo de los dos lados:
  ///
  /// - **iOS**: `WCSession.isPaired` es literal — hay un Apple Watch
  ///   emparejado. Alcanza y sobra, y por eso es lo primero que se consulta.
  /// - **Android**: `isPaired` lista las apps COMPANION instaladas en el
  ///   teléfono (verificado en `WatchConnectivityPlugin.kt`). Responde "¿este
  ///   teléfono podría tener un reloj?", no "¿lo tiene?". La única prueba
  ///   POSITIVA que expone el plugin es `connectedNodes`, o sea [isReachable].
  ///
  /// Por eso el OR, y en este orden. No es un cinturón con tiradores: es que
  /// ninguna de las dos señales, sola, responde bien en las dos plataformas.
  ///
  /// El OR es estrictamente MÁS permisivo que preguntar sólo por `isPaired`,
  /// así que no puede bloquear nada que hoy funcione — sólo destapar el caso
  /// contrario, que es el caro: un reloj conectado de verdad, con el chequeo de
  /// apps instaladas dando false, y `deliverCredential` cortando en
  /// `noWatchPaired` sin un solo error a la vista. La muñeca queda esperando
  /// una credencial que nadie llegó a pedir.
  ///
  /// Lo que NO se hace acá es exigir alcanzabilidad: `updateApplicationContext`
  /// persiste y se entrega al reconectar, así que un reloj apagado o fuera de
  /// rango igual recibe lo que se publique ahora. Cortar por no estar alcanzable
  /// perdería justo eso.
  ///
  /// Costo cuando efectivamente no hay reloj: una llamada más por MethodChannel,
  /// local y barata. El viaje a la Cloud Function sigue sin ocurrir — este
  /// chequeo va ANTES.
  Future<bool> _hayReloj() async {
    if (await _bridge.isPaired) return true;
    return _bridge.isReachable;
  }

  /// Deja rastro del resultado y lo devuelve tal cual.
  ///
  /// Existe porque hasta acá la cadena entera fallaba **en silencio**: dos
  /// `catch` mudos y un outcome que sólo veía el provider. Con App Check de por
  /// medio el resultado observable de una configuración rota era exactamente
  /// cero, y la prueba de punta a punta se debuggeaba mirando una muñeca.
  ///
  /// Sin guard de `kDebugMode` a propósito: las corridas contra el reloj se
  /// hacen en PROFILE (HANDOFF §4.8), donde ese flag es false y un log guardado
  /// no existiría justo cuando hace falta.
  ///
  /// **Nunca** se loguea el token, sólo su longitud: alcanza para distinguir
  /// "vino vacío" de "vino bien" sin dejar una credencial viva en logcat.
  WatchCredentialOutcome _rastro(
    WatchCredentialOutcome outcome, {
    String? detalle,
  }) {
    debugPrint(
      '[watch-cred] ${outcome.name}${detalle == null ? '' : ' — $detalle'}',
    );
    return outcome;
  }

  /// El atleta cerró sesión: el reloj tiene que dejar de ser suyo.
  ///
  /// ── Por qué esto no existía y por qué importa ──────────────────────────
  ///
  /// El listener de auth era `if (user == null) return;` sin rama `else`, y
  /// `CredentialStore.delete()` del lado Swift tenía CERO llamadores — su
  /// docstring decía "se usa al cerrar sesión" y era código muerto.
  ///
  /// O sea que cerrar sesión en el teléfono no hacía absolutamente nada en el
  /// reloj: seguía con un refresh token válido y podía leer y escribir
  /// Firestore como el atleta anterior, indefinidamente y sin teléfono.
  /// Prestás el celular, la otra persona se loguea, y la muñeca sigue siendo
  /// del dueño anterior.
  ///
  /// Publicar este aviso PISA la credencial en el contexto, que es la parte
  /// que hace que funcione: no queda nada que un reloj pueda releer.
  ///
  /// Best-effort igual que el resto: no puede tirar en el camino de logout.
  Future<bool> clearCredential() async {
    try {
      if (!await _bridge.isSupported) return false;
      if (!await _bridge.isPaired) return false;
      await _bridge.updateApplicationContext(
        const WatchSignedOutPayload().toJson(),
      );
      return true;
    } catch (_) {
      return false;
    }
  }
}
