import 'package:firebase_auth/firebase_auth.dart';

/// Costura fina sobre `FirebaseAuth` para el canje del custom token.
///
/// Existe por el mismo motivo que `WatchBridge`: `FirebaseAuth.instance` toca
/// el binding de plataforma, que en un test unitario no responde. Con esta
/// costura la máquina de emparejamiento se prueba entera con mocktail, sin
/// emulador y sin reloj.
///
/// Es deliberadamente tonta: no decide nada. Toda la política —cuándo canjear,
/// cuándo no, qué hacer si falla— vive en `wear_pairing_providers.dart`, que es
/// puro y testeable. Acá sólo se traduce el SDK.
class WearCredentialExchanger {
  WearCredentialExchanger({FirebaseAuth? auth})
      : _auth = auth ?? FirebaseAuth.instance;

  final FirebaseAuth _auth;

  /// El uid de la sesión actual, o null si no hay ninguna.
  ///
  /// Se lee de forma SÍNCRONA a propósito: es lo que permite decidir el estado
  /// inicial del emparejamiento sin esperar un stream. Firebase persiste la
  /// sesión entre arranques, así que en el arranque típico —el segundo en
  /// adelante— esto ya viene poblado y el reloj no tiene que canjear nada.
  String? get currentUid => _auth.currentUser?.uid;

  /// El uid a lo largo del tiempo. `null` cuando se cierra sesión.
  ///
  /// Es la ÚNICA fuente de verdad de que hay credencial viva. La máquina no
  /// declara `ready` por el retorno del canje sino por esto: un solo escritor
  /// para ese estado es lo que lo vuelve idempotente.
  Stream<String?> get uidChanges =>
      _auth.authStateChanges().map((user) => user?.uid);

  /// Canjea el token minteado por el teléfono por una sesión propia.
  ///
  /// Tira si el token está vencido, malformado, o si el proyecto lo rechaza.
  /// No se atrapa acá: quien llama necesita distinguir el fallo para mostrarlo.
  Future<void> exchange(String customToken) async {
    await _auth.signInWithCustomToken(customToken);
  }
}
