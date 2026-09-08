import 'package:flutter/widgets.dart';

/// Frontera de semántica alrededor de un `Navigator` anidado.
///
/// **Qué arregla.** Todo `ModalRoute` siembra un `ModalBarrier` en el Overlay
/// de su `Navigator`, y `ModalBarrier` es un `BlockSemantics` — así una ruta
/// opaca tapa la semántica de las rutas de abajo. El mecanismo es la bandera
/// `dropsSemanticsOfPreviousSiblings`, y esa bandera **sube por cada
/// `RenderObject` que no sea semantic boundary**: en
/// `RenderObject._getSemanticsForParent`, cuando un hijo la trae se hace
/// `fragments.clear()` y, mientras `!config.isSemanticBoundary`, se sigue
/// propagando hacia arriba.
///
/// En un shell con navegación al costado eso no se queda adentro del
/// `Navigator`: sube hasta el `Row` del layout y borra a TODOS los hermanos
/// anteriores. En el Coach Hub se llevaba puestos el sidebar entero y la top
/// bar — para un lector de pantalla el menú lateral no existía, ni colapsado
/// ni expandido. No era un bug del sidebar: pasa igual con un `SizedBox` con
/// un `Text` adentro al lado de un `Navigator` pelado.
///
/// **Por qué el arreglo va acá y no en el sidebar.** El borrado ocurre en el
/// padre común, arriba del sidebar: para cuando se ejecuta, el fragmento del
/// sidebar ya está en la lista que se limpia. Envolver al sidebar en su
/// propia frontera NO lo salva (medido). La única defensa es cortar la
/// propagación antes de que salga de la rama del `Navigator`, y para eso
/// hace falta un semantic boundary de verdad: `container: true`.
///
/// `explicitChildNodes` para que la sección no se aplaste en un solo nodo con
/// todo su texto concatenado.
class NavigatorSemanticsBoundary extends StatelessWidget {
  const NavigatorSemanticsBoundary({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Semantics(
        container: true,
        explicitChildNodes: true,
        child: child,
      );
}
