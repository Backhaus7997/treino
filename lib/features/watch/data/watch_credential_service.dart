import 'package:cloud_functions/cloud_functions.dart';

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
  })  : _functions = functions,
        _bridge = bridge,
        _apiKey = apiKey,
        _projectId = projectId,
        _authEmulatorHost = authEmulatorHost;

  final FirebaseFunctions _functions;
  final WatchBridge _bridge;
  final String _apiKey;
  final String _projectId;

  /// Solo se puebla corriendo contra el emulador. Ver [WatchCredentialPayload].
  final String? _authEmulatorHost;

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
    } catch (_) {
      // Incluye FirebaseFunctionsException (no autenticado, App Check, red).
      // Quedarse sin credencial de reloj no debe tumbar nada del teléfono.
      return WatchCredentialOutcome.mintFailed;
    }

    final payload = WatchCredentialPayload(
      customToken: customToken,
      uid: uid,
      apiKey: _apiKey,
      projectId: _projectId,
      authEmulatorHost: _authEmulatorHost,
    );

    try {
      await _bridge.updateApplicationContext(payload.toJson());
    } catch (_) {
      return WatchCredentialOutcome.deliveryFailed;
    }

    return WatchCredentialOutcome.delivered;
  }
}
