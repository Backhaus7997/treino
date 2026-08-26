import 'package:watch_connectivity/watch_connectivity.dart';

/// Envoltorio delgado sobre `WatchConnectivity`.
///
/// Existe por dos motivos:
///   1. **Testeabilidad.** `WatchConnectivity` habla por MethodChannel, que en
///      tests no responde. Una costura propia se mockea con mocktail sin tocar
///      el binding de plataforma.
///   2. **Contención.** El resto de la app no depende del paquete directamente,
///      así que cambiarlo (o reemplazarlo por un MethodChannel propio) toca un
///      solo archivo.
///
/// Nombres verificados contra `watch_connectivity 0.2.8` instalado, no
/// asumidos: `isPaired`/`isReachable` son `Future<bool>` — **no** streams, como
/// suponía el diseño original del ciclo `watch-connectivity`.
///
/// Este puente lo usan LOS DOS lados: el teléfono para publicar la credencial
/// y el reloj para recibirla. En Wear la Data Layer exige que ambos APKs
/// compartan `applicationId` **y clave de firma**; `android/key.properties` no
/// está versionado, así que el release cae a debug keys y mezclar un teléfono
/// bajado de Play con un reloj sideloadeado deja el canal mudo, sin error.
///
/// ⚠️ `isPaired` NO significa lo mismo en las dos plataformas. Ver su doc.
class WatchBridge {
  WatchBridge({WatchConnectivity? connectivity})
      : _connectivity = connectivity ?? WatchConnectivity();

  final WatchConnectivity _connectivity;

  /// Si la plataforma soporta relojes. False en Android sin Wear OS, y en
  /// cualquier plataforma que no sea móvil.
  Future<bool> get isSupported => _connectivity.isSupported;

  /// En iOS: si hay un Apple Watch emparejado. En **Android: otra pregunta**.
  ///
  /// Verificado en `WatchConnectivityPlugin.kt`: en Android esto lista las apps
  /// COMPANION instaladas en el teléfono (Wear OS, la nueva `wear.companion`,
  /// Galaxy Wearable) y devuelve si hay alguna. No consulta un solo nodo. O
  /// sea que responde "¿este teléfono podría tener un reloj?", no "¿lo tiene?".
  ///
  /// Por eso quien decide si vale la pena mintear NO se apoya sólo en esto —
  /// ver `WatchCredentialService`.
  Future<bool> get isPaired => _connectivity.isPaired;

  /// Si la contraparte está alcanzable AHORA.
  ///
  /// En Android sí sale de la red de verdad: `nodeClient.connectedNodes`. Es la
  /// única prueba POSITIVA de que hay un reloj del otro lado, pero es
  /// transitoria — un reloj apagado o fuera de rango da false.
  Future<bool> get isReachable => _connectivity.isReachable;

  /// Estado "actual" hacia el reloj. Se pisa, persiste, y no requiere que el
  /// reloj esté alcanzable en este momento: se entrega cuando se reconecta.
  Future<void> updateApplicationContext(Map<String, dynamic> context) =>
      _connectivity.updateApplicationContext(context);

  /// Mensaje puntual. Requiere alcanzabilidad inmediata.
  Future<void> sendMessage(Map<String, dynamic> message) =>
      _connectivity.sendMessage(message);

  /// Mensajes entrantes desde el reloj.
  Stream<Map<String, dynamic>> get messageStream => _connectivity.messageStream;

  /// Contextos entrantes desde el reloj.
  ///
  /// Es el canal por el que llega el esfuerzo en vivo — pulsaciones y calorías
  /// mientras el atleta entrena (change `watch-workout-session`, F4).
  ///
  /// El contexto de ida y el de vuelta son independientes: cada lado tiene el
  /// suyo, así que el reloj publicando esfuerzo no pisa la credencial que el
  /// teléfono publica hacia él.
  ///
  /// ⚠️ Sólo trae lo que llega MIENTRAS hay alguien escuchando. Para lo que ya
  /// estaba escrito antes de abrir la app, ver [receivedApplicationContexts].
  Stream<Map<String, dynamic>> get contextStream => _connectivity.contextStream;

  /// Los contextos que la contraparte YA dejó escritos, se hayan recibido antes
  /// de abrir esta app o no.
  ///
  /// Hace falta en LAS DOS direcciones, y las dos ramas llegaron a esto por
  /// separado:
  ///
  /// - **Teléfono → reloj**: la credencial se publica como DataItem cuando el
  ///   atleta inicia sesión, o sea mucho antes de que nadie abra la app del
  ///   reloj. Sin sembrar con esto, el arranque en frío espera para siempre una
  ///   credencial que ya estaba escrita.
  /// - **Reloj → teléfono**: un estado publicado por el reloj antes de que el
  ///   teléfono empezara a escuchar se perdería, y la pantalla quedaría vacía
  ///   sin ningún error.
  ///
  /// La causa común es la misma: [contextStream] sólo emite lo NUEVO — reenvía
  /// eventos recibidos con el plugin ya enganchado— y no reproduce el pasado.
  ///
  /// En Wear devuelve un mapa por cada nodo que haya publicado contexto; en
  /// watchOS, a lo sumo uno.
  Future<List<Map<String, dynamic>>> get receivedApplicationContexts =>
      _connectivity.receivedApplicationContexts;
}
