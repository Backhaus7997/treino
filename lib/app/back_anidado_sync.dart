import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';

/// Corrige lo que la app le dice a Android sobre si "puede volver", cuando hay
/// un `ShellRoute` con una ruta empujada adentro y un chat (o cualquier ruta
/// top-level) que se apila y se saca encima (#1468).
///
/// ## El síntoma
///
/// Inicio → campana → Notificaciones → tocar un chat → atrás del SISTEMA →
/// Notificaciones → atrás del SISTEMA otra vez: **la app se cierra** en vez de
/// volver a Inicio. Con la flecha del AppBar anda, y sin pasar por el chat
/// también. Sólo pasa en Android con el back predictivo (targetSdk 36).
///
/// ## La causa
///
/// Con el back predictivo, Android no le manda el back a Flutter: lo resuelve
/// él, y por eso Flutter tiene que avisarle de antemano si "puede manejarlo"
/// (`SystemNavigator.setFrameworkHandlesBack`). Ese aviso sale de las
/// `NavigationNotification` que despacha **cada** `Navigator` cuando cambia
/// SU historial, y `WidgetsApp` se queda con la **última** que llegó.
///
/// La app tiene dos navigators: el raíz y el del `ShellRoute`. La secuencia:
///
///  1. Campana: cambia el del shell (`[Inicio, Notificaciones]`) → "puede
///     volver" = `true`.
///  2. Se empuja el chat en el raíz → `true`.
///  3. Se saca el chat: cambia el raíz, que vuelve a tener una sola página →
///     despacha `false`. El del shell **no cambió** y no despacha nada, así que
///     nadie corrige el valor: queda `false` aunque `[Inicio, Notificaciones]`
///     siga ahí para volver.
///  4. Atrás del sistema: Android ve `false`, no se lo manda a Flutter y cierra
///     la actividad.
///
/// ## El arreglo
///
/// Escuchar esas notificaciones y, cuando dicen `false` pero el router sí tiene
/// algo para sacar en CUALQUIERA de sus navigators (`GoRouter.canPop` recorre el
/// shell), reemplazarlas por `true`. La corrección se re-despacha desde ACÁ
/// arriba para que la reciba el handler por defecto de `WidgetsApp`, que ya
/// sabe ignorar el aviso si la app no está lista; no se reimplementa.
///
/// Sólo corrige en un sentido (`false` → `true`). Un `true` nunca se baja: si un
/// `PopScope(canPop: false)` o una ruta apilada piden manejar el back, siguen
/// pudiendo.
class BackAnidadoSync extends StatelessWidget {
  const BackAnidadoSync({super.key, required this.router, required this.child});

  final GoRouter router;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return NotificationListener<NavigationNotification>(
      onNotification: (notification) {
        // Nada que corregir: ya dice que sí, o de verdad no hay nada que sacar.
        if (notification.canHandlePop || !router.canPop()) return false;
        // `context` es el de ESTE widget: despachar desde acá sube por los
        // ancestros y NO vuelve a pasar por el listener de arriba (que es hijo).
        const NavigationNotification(canHandlePop: true).dispatch(context);
        return true;
      },
      child: child,
    );
  }
}
