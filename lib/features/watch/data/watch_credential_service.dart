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
      debugPrint('[watch-cred] $callableName falló — ${e.code}: ${e.message}');
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
}
