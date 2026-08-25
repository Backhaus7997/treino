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
///   1. ¿Hay reloj? Si no, cortar acá — no se mintea credencial al pedo.
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
      return WatchCredentialOutcome.notSupported;
    }
    if (!await _bridge.isPaired) {
      return WatchCredentialOutcome.noWatchPaired;
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
        return WatchCredentialOutcome.mintFailed;
      }
      customToken = token;
    } catch (e) {
      // Quedarse sin credencial de reloj no debe tumbar nada del teléfono: por
      // eso se traga. Pero tragarlo SIN DEJAR RASTRO costó caro.
      //
      // Este catch es el que hizo irreconocible el problema de App Attest: la
      // función devolvía 401 "Decoding App Check token failed", acá se comía el
      // error entero, y el único síntoma visible era el reloj clavado en
      // "vinculando" para siempre. La causa y el síntoma no se parecían en
      // nada, y encontrarla costó llegar hasta los logs de la Cloud Function.
      //
      // Ahora el motivo queda escrito. Es lo que pide la condición de salida de
      // la deuda de App Check (`functions/src/mint-watch-credential.ts`):
      // saber POR QUÉ App Attest no emite token.
      //
      // Matiz medido el 2026-08-25: para saber QUIÉN falla ya no hace falta
      // instrumentar nada — `firebase-functions` v2 loguea la verificación de
      // cada callable en `jsonPayload.verifications.app`, y cruzándola con el
      // user-agent sale que el roto es Android (1 VALID / 8 INVALID) y no iOS
      // (8 VALID / 2 INVALID). Ver docs/security.md §4.8.2. Lo que este log
      // sigue aportando, y el server no puede, es el POR QUÉ del lado del
      // dispositivo.
      if (e is FirebaseFunctionsException) {
        debugPrint(
          '[watch] mintWatchCredential falló: code=${e.code} '
          'message=${e.message} details=${e.details}',
        );
      } else {
        debugPrint('[watch] mintWatchCredential falló: $e');
      }
      return WatchCredentialOutcome.mintFailed;
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
    } catch (_) {
      return WatchCredentialOutcome.deliveryFailed;
    }

    return WatchCredentialOutcome.delivered;
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
