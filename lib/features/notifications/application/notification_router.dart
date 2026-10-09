import 'dart:async' show unawaited;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/widgets.dart' show BuildContext;
import 'package:go_router/go_router.dart';

/// Navigates to [deepLink] using the current [context]'s GoRouter.
///
/// Fallback rules (ADR-PN-009):
/// - null or empty → `context.go('/coach')`.
/// - no leading `/` → log warning + `context.go('/coach')`.
/// - valid path → `context.go(deepLink)`.
/// - link de CHAT (`/coach/chat/...`) → arma el stack
///   Feed → Mensajes → chat. Ver [abrirChatConStack].
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

  if (Uri.tryParse(deepLink)?.path.startsWith(kPrefijoDeepLinkDeChat) ??
      false) {
    abrirChatConStack(GoRouter.of(context), deepLink);
    return;
  }

  context.go(deepLink);
}

/// Feed: la base del stack que arma [abrirChatConStack].
const kUbicacionFeed = '/feed';

/// La bandeja de MENSAJES: lo que queda debajo de un chat abierto desde una
/// notificación.
const kUbicacionBandejaDeMensajes = '/feed/messages';

/// Abre el chat de [deepLink] dejando DEBAJO la bandeja y el feed:
/// `go('/feed')` → `push('/feed/messages')` → `push(deepLink)`.
///
/// ## Por qué no alcanza con `go(deepLink)`
///
/// El chat es una ruta top-level: un `go` lo deja SOLO en el navigator raíz.
/// La flecha se las arreglaba con un fallback (`canPop() ? pop() : go(...)`),
/// pero el swipe de volver de iOS sólo existe si hay una ruta debajo — y para
/// que la bandeja tampoco cerrara la app con el back de Android, se le había
/// puesto un `PopScope(canPop: false)`, que APAGA el gesto. Resultado: la
/// flecha andaba y el swipe no hacía nada. Con el stack de verdad, flecha,
/// swipe y back de Android hacen lo mismo porque es un `pop` nativo.
///
/// ## Por qué tres llamadas seguidas funcionan
///
/// `push` apila sobre `routerDelegate.currentConfiguration`. Si el `go` previo
/// no se hubiera aplicado todavía, el push se apilaría sobre el stack VIEJO.
/// Acá se aplica en el acto: los redirects del router son síncronos (el parser
/// devuelve un `SynchronousFuture`) y no hay `onExit`, así que el `Router` deja
/// la configuración nueva antes de que vuelva la llamada.
///
/// No se ASUME: después de cada paso se verifica que el router haya llegado. Si
/// no llegó —un redirect de auth que manda a `/welcome`, o el día que alguien
/// meta un redirect async— se cae al `go(deepLink)` de siempre, que deja que
/// el redirect decida igual que antes de este cambio. Peor caso: el chat sin
/// nada debajo, con la flecha de fallback de `ChatScreen`.
///
/// ## Arranque en frío (app cerrada, se abre por el push)
///
/// `app.dart` llama a esto en un post-frame, con `/splash` montado y la sesión
/// todavía cargando. `authRedirect` devuelve `null` mientras carga, así que el
/// stack se arma igual; el `go('/feed')` desmonta el splash y su `go('/home')`
/// diferido no corre (chequea `mounted`). No hay doble navegación. Cuando la
/// sesión resuelve, el `refreshListenable` re-evalúa el redirect sobre la base
/// (`/feed`) y el stack queda; si no hay sesión, manda a `/welcome` como antes.
///
/// La supresión de avisos en primer plano no cambia: lee `state.uri`, que
/// refleja la ruta del tope aunque haya llegado por `push`
/// (ver [locationActualDe]).
void abrirChatConStack(GoRouter router, String deepLink) {
  router.go(kUbicacionFeed);
  if (!_llegoA(router, kUbicacionFeed)) {
    router.go(deepLink);
    return;
  }
  unawaited(router.push<void>(kUbicacionBandejaDeMensajes));
  if (!_llegoA(router, kUbicacionBandejaDeMensajes)) {
    router.go(deepLink);
    return;
  }
  unawaited(router.push<void>(deepLink));
}

bool _llegoA(GoRouter router, String path) =>
    Uri.tryParse(locationActualDe(router) ?? '')?.path == path;

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
///
/// Vivía en `/feed/notifications` hasta que la campana se movió a la pantalla
/// principal. Se compara sólo el PATH (ver [shouldSuppressForegroundNotification]),
/// así que el `?tab=` que traen los deep links no rompe la comparación.
const kCentroDeNotificaciones = '/home/notifications';

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
