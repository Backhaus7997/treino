import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Pregunta antes de abandonar una pantalla con cambios sin guardar cuando se
/// sale por la BARRA DE PESTAÑAS.
///
/// `PopScope` alcanza para la flecha atrás y el swipe de iOS, pero no para la
/// barra: el shell es un `ShellRoute` común (no stateful), y tocar otra
/// pestaña hace `context.go(...)`, que destruye la subruta abierta —y lo que
/// tenía tipeado— sin pasar por ningún `PopScope`. Pasó en el editor del perfil
/// del PF: apagabas un switch, cambiabas de pestaña y el cambio se perdía en
/// silencio.
///
/// Una pantalla con formulario se anota con [registrar] mientras está montada
/// y se borra con [liberar] al desmontarse; el `onTap` de la barra llama a
/// [puedeSalir] antes de navegar. Hay una sola pantalla a la vez arriba del
/// shell, así que alcanza con un único lugar.
///
/// Es un objeto mutable detrás de un `Provider` y no estado de Riverpod a
/// propósito: la pantalla se libera en `dispose`, donde `ref` ya no se puede
/// usar, así que guarda la referencia a este objeto al montarse.
class GuardiaDeSalida {
  Future<bool> Function()? _confirmar;

  /// [confirmar] devuelve `true` si se puede salir (no había cambios, o el
  /// usuario eligió descartarlos).
  void registrar(Future<bool> Function() confirmar) => _confirmar = confirmar;

  /// Sólo libera si sigue anotada ESA pantalla: si otra se registró después,
  /// no se la borra.
  void liberar(Future<bool> Function() confirmar) {
    if (identical(_confirmar, confirmar)) _confirmar = null;
  }

  Future<bool> puedeSalir() async {
    final confirmar = _confirmar;
    return confirmar == null ? true : await confirmar();
  }
}

final guardiaDeSalidaProvider = Provider<GuardiaDeSalida>(
  (ref) => GuardiaDeSalida(),
);
