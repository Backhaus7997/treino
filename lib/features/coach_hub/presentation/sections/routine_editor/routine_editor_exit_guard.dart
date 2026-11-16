import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

/// El puente entre el `onExit` de las rutas del editor y la pantalla.
///
/// Quien sabe si hay trabajo sin guardar es el `State` del editor; quien ve
/// salir a la pantalla del árbol de rutas —el link del sidebar, Atrás del
/// navegador, cualquier `go`— es la ruta. Un `PopScope` no alcanza: sólo se
/// consulta con `Navigator.maybePop`, y un `go` reemplaza la pila sin pasar por
/// ahí. `GoRoute.onExit` sí corre en todos esos casos, pero no tiene acceso al
/// `State`. Esto es la mitad que los junta.
///
/// Vive en el `ProviderScope` y no en una variable global para que cada test —y
/// cada sesión del Hub— tenga el suyo.
class RoutineEditorExitGuard {
  Object? _dueno;
  Future<bool> Function()? _puedeSalir;

  /// El editor que está abierto se anota, con la pregunta que hay que hacerle.
  ///
  /// Un solo dueño a la vez: el editor es una pantalla de pantalla completa y
  /// no hay dos abiertos. Si alguna vez los hay, el último en montarse manda.
  void registrar(Object dueno, Future<bool> Function() puedeSalir) {
    _dueno = dueno;
    _puedeSalir = puedeSalir;
  }

  /// Se desanota, pero sólo si sigue siendo el dueño: un editor que se
  /// dispone DESPUÉS de que otro se montó no tiene que borrar al nuevo.
  void soltar(Object dueno) {
    if (!identical(_dueno, dueno)) return;
    _dueno = null;
    _puedeSalir = null;
  }

  /// `true` si la ruta puede salir. Sin editor registrado no hay nada que
  /// perder, así que sale.
  Future<bool> puedeSalir() async => await _puedeSalir?.call() ?? true;
}

final routineEditorExitGuardProvider = Provider<RoutineEditorExitGuard>(
  (ref) => RoutineEditorExitGuard(),
);

/// El `onExit` de las cuatro rutas del editor (ver `routes.dart`).
///
/// `context` es el del `Navigator` raíz, que está por debajo del `ProviderScope`
/// de la app, así que el guard se lee de ahí.
Future<bool> routineEditorOnExit(BuildContext context, GoRouterState state) =>
    ProviderScope.containerOf(context, listen: false)
        .read(routineEditorExitGuardProvider)
        .puedeSalir();
