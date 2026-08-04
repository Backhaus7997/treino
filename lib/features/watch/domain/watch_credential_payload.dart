/// Lo que el teléfono le entrega al reloj para que consiga credencial propia.
///
/// Change `watch-standalone-client`, fase F1.
///
/// El reloj NO usa el SDK de Firebase (Locked Decision #9): Firestore ni
/// figura entre los productos soportados en watchOS. Habla HTTP directo contra
/// `identitytoolkit` y `securetoken`, así que necesita en el payload todo lo
/// que el SDK le habría dado gratis — de ahí `apiKey` y `projectId`.
///
/// El `customToken` dura una hora. Eso es a propósito y hace segura la
/// entrega: viaja por `updateApplicationContext`, que PERSISTE del lado del
/// reloj hasta que se pisa. Un token viejo que quede ahí no sirve para nada
/// pasada la hora, y el reloj ya lo canjeó por credenciales propias de larga
/// duración mucho antes.
///
/// No es freezed a propósito: el reloj tiene que parsear este mismo shape en
/// Swift, así que el JSON es un contrato entre lenguajes y conviene tenerlo
/// escrito a mano y a la vista, sin generación de por medio.
class WatchCredentialPayload {
  const WatchCredentialPayload({
    required this.customToken,
    required this.uid,
    required this.apiKey,
    required this.projectId,
  });

  /// Discrimina este payload de cualquier otro que viaje por el mismo canal.
  static const String kind = 'watchCredential';

  final String customToken;
  final String uid;
  final String apiKey;
  final String projectId;

  Map<String, dynamic> toJson() => {
        'kind': kind,
        'customToken': customToken,
        'uid': uid,
        'apiKey': apiKey,
        'projectId': projectId,
      };

  /// Parsea un payload entrante.
  ///
  /// Tira [FormatException] ante cualquier campo faltante o vacío en vez de
  /// construir un payload a medias: un `customToken` vacío que viaja hasta el
  /// reloj falla allá, lejos de la causa y sin nadie mirando.
  factory WatchCredentialPayload.fromJson(Map<String, dynamic> json) {
    String required(String key) {
      final value = json[key];
      if (value is! String || value.isEmpty) {
        throw FormatException(
          'WatchCredentialPayload: falta el campo "$key" o está vacío.',
          json.toString(),
        );
      }
      return value;
    }

    return WatchCredentialPayload(
      customToken: required('customToken'),
      uid: required('uid'),
      apiKey: required('apiKey'),
      projectId: required('projectId'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchCredentialPayload &&
          other.customToken == customToken &&
          other.uid == uid &&
          other.apiKey == apiKey &&
          other.projectId == projectId;

  @override
  int get hashCode => Object.hash(customToken, uid, apiKey, projectId);
}
