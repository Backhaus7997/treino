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
/// Android/Wear OS NO está soportado en v1. El paquete cubre ambos lados, pero
/// exige que reloj y teléfono compartan clave de firma, y la firma de release
/// de Android sigue en debug keys. En Android sin companion instalado
/// `isPaired` devuelve false y todo esto queda inerte, que es el comportamiento
/// deseado.
class WatchBridge {
  WatchBridge({WatchConnectivity? connectivity})
      : _connectivity = connectivity ?? WatchConnectivity();

  final WatchConnectivity _connectivity;

  /// Si la plataforma soporta relojes. False en Android sin Wear OS, y en
  /// cualquier plataforma que no sea móvil.
  Future<bool> get isSupported => _connectivity.isSupported;

  /// Si hay un reloj emparejado con este teléfono.
  ///
  /// Ojo en Android: el paquete documenta que ahí NO se puede saber si hay un
  /// reloj emparejado — chequea si están instaladas las apps de Wear OS o
  /// Galaxy Wearable. Semántica distinta, otra razón para no soportarlo en v1.
  Future<bool> get isPaired => _connectivity.isPaired;

  /// Si la contraparte está alcanzable AHORA.
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
  Stream<Map<String, dynamic>> get contextStream => _connectivity.contextStream;
}
