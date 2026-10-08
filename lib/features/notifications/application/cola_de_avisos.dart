/// Un aviso de primer plano esperando a poder mostrarse.
///
/// Guarda lo mínimo que hace falta para entregarlo más tarde. NO guarda el
/// `RemoteMessage` entero a propósito: las guardas que deciden si mostrarlo
/// —«es tu propio mensaje» y «ya lo estás mirando»— ya corrieron cuando el
/// aviso llegó. Volver a evaluarlas al drenar las evaluaría contra la pantalla
/// de AHORA, que no es donde estaba el usuario cuando el aviso entró.
class Aviso {
  const Aviso({required this.title, required this.body, this.deepLink});

  final String title;
  final String body;
  final String? deepLink;
}

/// Los avisos que llegaron antes de que el permiso del sistema se resolviera.
///
/// ## Por qué existe
///
/// `PermissionGate` no pide el permiso hasta tener el perfil cargado y el
/// onboarding resuelto, así que en una instalación nueva hay una ventana
/// garantizada —no un caso de borde— en la que ya llegan pushes y todavía no
/// hay permiso.
///
/// Los dos sistemas fallan distinto adentro de esa ventana, y el peor es el
/// silencioso:
///
/// - **iOS**: `show()` tira (`Error 2003 — Source is not authorized`) y
///   devuelve `false`, así que al menos caía al cartel in-app.
/// - **Android**: sin `POST_NOTIFICATIONS` no tira nada. El sistema descarta la
///   notificación en silencio y `show()` devuelve `true`, así que el aviso
///   desaparecía ENTERO — sin cartel, sin log y sin forma de notarlo.
///
/// Encolar arregla las dos: el aviso espera a que el permiso resuelva y recién
/// ahí se intenta de verdad.
///
/// ## Lo que esta clase garantiza
///
/// **Nada se descarta en silencio.** [drenar] devuelve todo lo guardado, y el
/// llamador es el que decide cómo entregarlo. Lo único que se pierde es por
/// [maximo], y es explícito: los más VIEJOS.
class ColaDeAvisos {
  ColaDeAvisos({this.maximo = kMaxAvisosEnEspera})
      : assert(maximo > 0, 'una cola de cero no encola: descarta');

  /// Cuántos avisos se guardan como mucho.
  ///
  /// Tira los más viejos al desbordar. Quince notificaciones de golpe apenas el
  /// usuario acepta el permiso son su propia forma de ser ignoradas, y lo que
  /// se pierde es lo más viejo — que es también lo menos urgente.
  static const kMaxAvisosEnEspera = 5;

  /// Cuánto se espera a que el permiso resuelva antes de degradar al cartel.
  ///
  /// El prompt puede no llegar NUNCA en esta sesión: el gate espera perfil
  /// completo y onboarding terminado, y un usuario que se queda en el tour
  /// dejaría la cola colgada para siempre. Al vencer, los avisos salen igual
  /// por el cartel in-app — que es exactamente lo que pasaba antes de que la
  /// cola existiera, así que el PEOR caso de este mecanismo empata con el
  /// único caso del anterior.
  static const kEsperaMaxima = Duration(seconds: 10);

  final int maximo;
  final List<Aviso> _pendientes = [];

  bool get vacia => _pendientes.isEmpty;
  int get largo => _pendientes.length;

  /// Guarda [aviso]. Si la cola está llena, saca el más viejo.
  void encolar(Aviso aviso) {
    _pendientes.add(aviso);
    while (_pendientes.length > maximo) {
      _pendientes.removeAt(0);
    }
  }

  /// Devuelve todo lo guardado y deja la cola vacía.
  ///
  /// Vaciar ANTES de que el llamador entregue no es un detalle: entregar tiene
  /// awaits, y un aviso nuevo que llegue en el medio tiene que encolarse limpio
  /// en vez de aparecer a mitad de la iteración de otro.
  List<Aviso> drenar() {
    final salida = List<Aviso>.of(_pendientes);
    _pendientes.clear();
    return salida;
  }
}
