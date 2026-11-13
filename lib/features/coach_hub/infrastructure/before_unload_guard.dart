import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'before_unload_guard_stub.dart'
    if (dart.library.js_interop) 'before_unload_guard_web.dart' as impl;

/// Le pide al navegador que pregunte antes de recargar o cerrar la pestaña.
///
/// Es el único aviso que cubre ESA salida: F5, cerrar la pestaña o pegar otra
/// URL no pasan por el `Router` de la app, así que ni un `PopScope` ni un
/// `GoRoute.onExit` se enteran. El navegador pinta su propio diálogo (el texto
/// no se puede cambiar) y sólo lo muestra si la página lo pidió ANTES.
///
/// Quien lo use lo prende mientras haya trabajo sin guardar y lo apaga apenas
/// deja de haberlo. Mismo patrón que `browser_download.dart`: la implementación
/// web vive en `before_unload_guard_web.dart` y fuera de web (la VM de los
/// tests, el teléfono) es un no-op, que es lo correcto porque el problema es
/// del navegador.
///
/// Es una clase y no funciones sueltas para que un test la reemplace por un
/// registro de llamadas: el listener real no se puede probar en la VM.
class BeforeUnloadGuard {
  const BeforeUnloadGuard();

  /// Prende el aviso. Llamarlo dos veces no registra dos listeners.
  void arm() => impl.armBeforeUnload();

  /// Lo apaga. Es seguro sobre uno que nunca se prendió.
  void disarm() => impl.disarmBeforeUnload();
}

/// El guard de la pestaña. Al disponerse el scope lo apaga, para que un listener
/// colgado no siga preguntando después de que se fue quien lo pidió.
final beforeUnloadGuardProvider = Provider<BeforeUnloadGuard>((ref) {
  const guard = BeforeUnloadGuard();
  ref.onDispose(guard.disarm);
  return guard;
});
