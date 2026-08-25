/// Lo único que el reloj Wear necesita para conseguir sesión propia.
///
/// ## Por qué no se reusa `WatchCredentialPayload`
///
/// Ese payload es el contrato de cable con el companion de **watchOS**, que no
/// tiene SDK de Firebase y habla HTTP crudo: por eso carga `apiKey`,
/// `projectId` y los hosts de emulador. En Wear todo eso SOBRA —el SDK lo saca
/// de `google-services.json`— y los hosts encima son inservibles: vienen como
/// `http://localhost:9099`, y en un reloj físico `localhost` es el reloj.
///
/// Depender del payload entero acoplaría la máquina de emparejamiento a campos
/// que no usa, y peor: ataría la inicialización de Firebase a que llegue el
/// payload, cuando tiene que ser determinista y anterior.
///
/// Así que el contrato de cable **no se toca** —romperlo rompería watchOS sin
/// comprar nada— y el adaptador de la Data Layer traduce
/// `WatchCredentialPayload` → [WearCredential], descartando lo que sobra.
class WearCredential {
  const WearCredential({required this.customToken, required this.uid});

  /// Token minteado por el teléfono vía `mintWatchCredential`.
  ///
  /// Dura **una hora** (default del Admin SDK). Importa porque el DataItem que
  /// lo transporta persiste para siempre: un token que quedó ahí de ayer se
  /// canjea con error, no con éxito. Ver [uid].
  final String customToken;

  /// A quién pertenece el token.
  ///
  /// Es lo que permite no canjear al pepe. Si el reloj ya tiene sesión de este
  /// mismo atleta, el token que llegó no aporta nada y muy probablemente esté
  /// vencido: canjearlo mostraría `failed` en cada arranque pasada la hora.
  final String uid;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WearCredential &&
          other.customToken == customToken &&
          other.uid == uid;

  @override
  int get hashCode => Object.hash(customToken, uid);

  @override
  String toString() =>
      'WearCredential(uid: $uid, customToken: ${customToken.length} chars)';
}
