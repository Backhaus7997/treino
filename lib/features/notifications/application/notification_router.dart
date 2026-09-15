import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:go_router/go_router.dart';

/// Navigates to [deepLink] using the current [context]'s GoRouter.
///
/// Fallback rules (ADR-PN-009):
/// - null or empty → `context.go('/coach')`.
/// - no leading `/` → log warning + `context.go('/coach')`.
/// - valid path → `context.go(deepLink)`.
///
/// Callers MUST check `context.mounted` before calling this function.
///
/// REQ-PN-HANDLER-001, REQ-PN-HANDLER-002, REQ-PN-HANDLER-003, ADR-PN-009.
void goDeepLink(BuildContext context, String? deepLink) {
  const fallback = '/coach';

  if (deepLink == null || deepLink.isEmpty) {
    context.go(fallback);
    return;
  }

  if (!deepLink.startsWith('/')) {
    debugPrint('[fcm] invalid deepLink (no leading slash): $deepLink');
    context.go(fallback);
    return;
  }

  context.go(deepLink);
}

/// Location concreta del router, o `null` si todavía no resolvió ninguna.
///
/// ## Por qué `state.uri` y no las otras dos opciones obvias
///
/// No sirve **`state.fullPath`**: es el PATRÓN de la ruta
/// (`/coach/chat/:chatId`) y hay que comparar contra un deep link CONCRETO.
///
/// No sirve **`routerDelegate.currentConfiguration.uri`**, aunque parezca la
/// correcta y sea la que usaba la primera versión de esto. Su propio dartdoc
/// dice que la URL "ignora cualquier RouteBase que sea resultado de una
/// llamada imperativa". Y el chat se abre SIEMPRE con `context.push(...)`, así
/// que estando adentro del chat devolvía la location de abajo (`/coach`,
/// `/home`) y [shouldSuppressForegroundNotification] no podía matchear NUNCA.
/// La supresión del chat no funcionó desde que se escribió; se detectó
/// probando con dos teléfonos el 2026-09-15.
///
/// `state.uri` sí: su dartdoc dice que es el estado de la ruta usada por
/// última vez "en `go` **o `push`**", y expone la uri completa.
///
/// Vive acá afuera y no adentro del State de la app para que se pueda testear
/// con un router de verdad — que es justo lo que faltaba cuando se coló el bug.
String? locationActualDe(GoRouter router) {
  // Con la lista de matches vacía, `state` tira `StateError: No element`.
  // Mismo motivo que documenta `RouteAnalytics._currentRoute`.
  if (router.routerDelegate.currentConfiguration.isEmpty) return null;
  return router.state.uri.toString();
}

/// El centro de notificaciones in-app. Estando acá, la lista ya se actualiza
/// sola: un aviso encima sería el mismo dato dos veces.
const kCentroDeNotificaciones = '/feed/notifications';

/// Prefijo de los deep links de chat que arma `notify-chat-message.ts`:
/// `/coach/chat/{chatId}?other={senderId}`.
///
/// El acople con la Cloud Function es real y es a propósito: el deepLink ES el
/// contrato entre las dos puntas. Si allá cambia la forma, esta constante
/// tiene que cambiar con ella — y el test que compara un link de chat contra
/// una location de chat se pone rojo si se desincronizan.
const kPrefijoDeepLinkDeChat = '/coach/chat/';

/// Si una notificación que llegó con la app ABIERTA no tiene que mostrarse
/// porque el usuario ya está mirando eso mismo.
///
/// Dos reglas, y nada más:
/// 1. Está en el centro de notificaciones → no se muestra ninguna.
/// 2. Está en el chat exacto al que apunta el deep link → no se muestra ésa.
///
/// **Falla ABIERTA**: si la location no se puede determinar, o el link no se
/// puede parsear, devuelve `false` y la notificación SE MUESTRA. Mismo criterio
/// que [isOwnChatMessage]: de los dos errores posibles —avisar de más o comerse
/// un mensaje en silencio— el segundo es el caro, porque el usuario nunca se
/// entera de lo que se perdió.
///
/// **No se generaliza a "mismo path ⇒ suprimir"**, aunque salga solo. El
/// deepLink de los cambios de vínculo es `/coach`, que además es una tab
/// entera: estar parado en la tab Coach no quiere decir que hayas visto que un
/// alumno te aceptó. La regla amplia suprimiría eso, y suprimir de más es
/// exactamente el modo de falla caro de arriba. Por eso la regla 2 exige que el
/// destino sea un chat concreto.
bool shouldSuppressForegroundNotification({
  required String? currentLocation,
  required String? deepLink,
}) {
  if (currentLocation == null || currentLocation.isEmpty) return false;
  final actual = Uri.tryParse(currentLocation);
  if (actual == null) return false;

  if (actual.path == kCentroDeNotificaciones) return true;

  if (deepLink == null || deepLink.isEmpty) return false;
  final destino = Uri.tryParse(deepLink);
  if (destino == null) return false;

  // Sólo el PATH: el chat abierto y el link traen el mismo `?other=`, pero
  // comparar la URI entera ataría la supresión a que no aparezca nunca un
  // query param nuevo de un lado y no del otro.
  if (!destino.path.startsWith(kPrefijoDeepLinkDeChat)) return false;
  return actual.path == destino.path;
}
