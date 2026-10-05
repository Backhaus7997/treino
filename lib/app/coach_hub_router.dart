import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/utils/deep_link_destination.dart';
import '../features/auth/application/auth_providers.dart';
import '../features/auth/application/email_gate_providers.dart';
import '../features/auth/domain/mail_verificado.dart';
import '../features/auth/presentation/verify_mail_screen.dart';
import '../features/coach_hub/domain/hub_onboarding_stage.dart';
import '../features/coach_hub/presentation/coach_hub_login_screen.dart';
import '../features/coach_hub/presentation/onboarding/completar_perfil_screen.dart';
import '../features/coach_hub/presentation/coach_hub_not_allowed_screen.dart';
import 'package:treino/features/coach_hub/presentation/sections/moderacion/routes.dart';
import '../features/coach_hub/presentation/sections/actividad/routes.dart';
import '../features/coach_hub/presentation/sections/agenda/routes.dart';
import '../features/coach_hub/presentation/sections/ajustes/routes.dart';
import '../features/coach_hub/presentation/sections/alumnos/routes.dart';
import '../features/coach_hub/presentation/sections/biblioteca/routes.dart';
import '../features/coach_hub/presentation/sections/chat/routes.dart';
import '../features/coach_hub/presentation/sections/cuestionario/routes.dart';
import '../features/coach_hub/presentation/sections/dashboard/routes.dart';
import '../features/coach_hub/presentation/sections/facturacion_planes/routes.dart';
import '../features/coach_hub/presentation/sections/habitos/routes.dart';
import '../features/coach_hub/presentation/sections/invitaciones/routes.dart';
import '../features/coach_hub/presentation/sections/legacy/routes.dart';
import '../features/coach_hub/presentation/sections/nutricion/routes.dart';
import '../features/coach_hub/presentation/sections/pagos/routes.dart';
import '../features/coach_hub/presentation/sections/perfil_publico/routes.dart';
import '../features/coach_hub/presentation/sections/planes/routes.dart';
import '../features/coach_hub/presentation/sections/planner/routes.dart';
import '../features/coach_hub/presentation/sections/recetas/routes.dart';
import '../features/coach_hub/presentation/sections/reportes/routes.dart';
import '../features/coach_hub/presentation/sections/routine_editor/routes.dart';
import '../features/coach_hub/presentation/sections/rutinas/routes.dart';
import '../features/coach_hub/presentation/sections/suplementos/routes.dart';
import '../features/coach_hub/presentation/sections/templates/routes.dart';
import '../features/coach_hub/presentation/shell/coach_hub_scaffold.dart';
import '../features/coach_hub/presentation/shell/content_max_width.dart';
import '../features/coach_hub/presentation/shell/mobile_facturacion_shell.dart';
import '../features/profile/application/user_providers.dart';
import '../features/profile/domain/user_role.dart';
import 'theme/app_palette.dart';

/// Rutas públicas del Coach Hub (no requieren auth).
const _coachHubPublicRoutes = {'/login'};

/// Gate del mail confirmado con código (`VerifyMailScreen`).
///
/// El MISMO path que en la app móvil (`_verifyMailRoute` de `router.dart`):
/// es la misma pantalla y el mismo gate, y tener un solo nombre evita que los
/// dos routers se desincronicen. Acá es una ruta top-level FUERA del
/// `ShellRoute`: quien todavía no confirmó el mail no ve el sidebar.
const _verifyMailRoute = '/verificar-mail';

/// Ruta del onboarding del PF promovido (ver `hubOnboardingStage`).
const kCoachHubOnboardingRoute = '/completar-perfil';

/// Lógica de redirect pura del Coach Hub — testeable como función standalone.
///
/// Diferencias clave vs `authRedirect` mobile:
/// 1. NO hay `/welcome`, `/register`, `/forgot-password`, `/splash` — el hub
///    es solo para PFs ya registrados desde mobile (signup vive en mobile).
/// 2. **Role gating**: usuarios con `role != trainer` se redirigen a
///    `/not-allowed`. Athletes que entran por accidente ven una info page.
/// 3. NO hay flow de profile-setup — si el PF llegó al hub es porque ya
///    tiene profile completo desde mobile.
///
/// [initialDestination] es el destino fino que trajo un mail —
/// `/abrir/profe?to=...` en Vercel redirige a `app.gettreino.com/?to=...`
/// (el query string se reenvía solo; ver `buildCoachHubRouter`, que lo lee
/// UNA vez de `Uri.base` al construir el router).
///
/// Viaja en una CAJA MUTABLE ([DeepLinkDestinationBox]) y no como un valor
/// plano, y eso no es un detalle: esta función lo APAGA (`box.value = null`)
/// apenas el gate de abajo lo consulta — no solo cuando produce un path
/// no-nulo. Sin esa distinción quedaba un bug real, encontrado en revisión:
/// "Cerrar sesión" (`sections/ajustes/ajustes_screen.dart`, antes en el top
/// bar, que dejó de tener menú propio cuando los tres accesos a cuenta se
/// unificaron en uno) es `FirebaseAuth.signOut()` puro, SIN
/// reload de página, así que `isPublic` (`location == '/login'`) SÍ vuelve
/// a ser cierto dentro de la MISMA pestaña en cuanto alguien cierra sesión.
/// Con un valor plano, el PF (u otro PF, en una compu compartida) que se
/// loguea DESPUÉS reciclaba el destino de la sesión anterior en vez de caer
/// en `/dashboard`. Apagando la caja en el primer consult — logueado o no,
/// con destino o sin él — un logout+login posterior encuentra la caja vacía.
String? coachHubRedirect(
  T Function<T>(ProviderListenable<T> provider) read,
  String location, {
  DeepLinkDestinationBox? initialDestination,
}) {
  final auth = read(authNotifierProvider);

  // Mientras carga auth no redirigimos — evita flicker.
  //
  // Ojo: este `return null` deja al router en `/dashboard`, y en un teléfono
  // eso dibujaba el `MobileBanner`. `coachHubSessionResolvingProvider` espeja
  // esta espera (y la del perfil, abajo) para que el scaffold ponga una vista
  // de carga en su lugar: si cambiás cuándo se espera acá, cambialo allá.
  if (auth.isLoading || !auth.hasValue) return null;

  final user = auth.valueOrNull;
  final loggedIn = user != null;
  final isPublic = _coachHubPublicRoutes.any(location.startsWith);
  final isNotAllowed = location.startsWith('/not-allowed');

  // Anonymous → /login (override de cualquier path protegido)
  if (!loggedIn && !isPublic) return '/login';

  // Authenticated en /login → resolver según role
  // (el switch entre dashboard / not-allowed pasa por el role check abajo)
  if (loggedIn && isPublic) {
    // Caemos al role check below — no return null acá porque queremos
    // resolver el role gate antes de mandar al dashboard.
  }

  // Authenticated → role gating
  if (loggedIn) {
    final profileAsync = read(userProfileProvider);
    // Misma espera que `coachHubSessionResolvingProvider` (ver arriba).
    if (profileAsync.isLoading) return null;
    final profile = profileAsync.valueOrNull;

    // Sin profile (caso edge: user borrado de Firestore manualmente, o
    // signup raro): tratar como no-allowed defensive.
    if (profile == null) {
      return isNotAllowed ? null : '/not-allowed';
    }

    if (profile.role != UserRole.trainer) {
      // Athletes (o cualquier role distinto a trainer) → /not-allowed
      return isNotAllowed ? null : '/not-allowed';
    }

    // Gate del mail confirmado con código. Misma regla que la app móvil
    // (`authRedirect`): el interruptor `app_config/email_gate`
    // (`emailGateEnabledProvider`, falla ABIERTO: cargando, en error o sin
    // documento es «apagado») y `correoVerificadoParaElRol`, POR ROL y contra
    // el mail de Auth de hoy. Un alumno verificado que el equipo promueve a
    // entrenador entra por el Hub —es donde se loguea un PF— y vuelve a ver la
    // pantalla, porque el mail que le llega es el del entrenador.
    //
    // Va DESPUÉS del role gate de arriba —un alumno nunca ve esta pantalla en
    // el Hub: va a `/not-allowed`— y ANTES del mapeo de `/home/notifications` y
    // del bloque de aterrizajes de abajo. Ese orden no es cosmético:
    // `initialDestination` (el `?to=` que trajo el mail) se CONSUME en el
    // bloque de aterrizajes. Si el gate corriera después, el PF que llega desde
    // un mail con `?to=facturacion` y todavía no confirmó gastaría el destino
    // camino a `/facturacion/planes`, el gate lo rebotaría a `/verificar-mail`
    // y, al confirmar, caería en el dashboard con el destino perdido. Con el
    // gate antes, mientras confirma la caja NO se toca.
    //
    // Por eso la SALIDA va a `kCoachHubInitialLocation` y no a cualquier ruta:
    // es una ruta de aterrizaje, así que en la pasada siguiente (go_router
    // re-evalúa el redirect sobre lo que devolvimos) el bloque de abajo consume
    // la caja y lo manda a `/facturacion/planes`.
    //
    // ENTRADA y SALIDA contra la MISMA condición, y quedarse mientras no se
    // pueda salir (misma regla que el gate de la app móvil). A diferencia de
    // allá, tampoco se exceptúa `/login`: un PF sin confirmar que se acaba de
    // loguear tiene que ir al gate ANTES del bloque de aterrizajes, no después.
    final gateAsync = read(emailGateEnabledProvider);
    final mailSinConfirmar = !correoVerificadoParaElRol(profile, user.email);
    final gateOn = gateAsync.valueOrNull ?? false;
    final enElGateDelMail = location.startsWith(_verifyMailRoute);
    if (gateOn && mailSinConfirmar && !enElGateDelMail) {
      return _verifyMailRoute;
    }
    if (enElGateDelMail) {
      return gateOn && mailSinConfirmar ? null : kCoachHubInitialLocation;
    }

    // Gate del onboarding del PF promovido (#1331): una cuenta web promovida a
    // trainer llega SIN `bornAt`, sin nombre público o sin perfil profesional, y
    // `hubOnboardingStage` dice qué le falta. Una sola ruta, `/completar-perfil`,
    // y la pantalla dibuja el paso que corresponde al perfil vivo: por eso un
    // cambio de etapa DENTRO del gate no navega.
    //
    // Va DESPUÉS del role gate y del mail, y ANTES de `/home/notifications` y de
    // los aterrizajes, por la misma razón que el gate del mail: el `?to=` vive en
    // la caja que el bloque de aterrizajes consume. Este gate NO la toca; la
    // SALIDA va a `kCoachHubInitialLocation` (un aterrizaje) y la pasada
    // siguiente usa el destino.
    //
    // ENTRADA y SALIDA contra el MISMO predicado. La salida exige además que la
    // última escritura esté confirmada por el servidor: el stream emite el dato
    // optimista antes del ack, y si el servidor rechaza, el PF volvería al paso
    // sin la pantalla que mostraba el error. `pendiente` es cargando o `true`; un
    // error del stream falla ABIERTO (`valueOrNull` es null) para no encerrarlo.
    // Se lee SOLO acá: un PF completo que edita su perfil no depende de él.
    //
    // La comparación es de path EXACTO (`location` es la ruta matcheada, sin
    // query): un `startsWith` capturaría cualquier subruta futura.
    final etapa = hubOnboardingStage(profile);
    final enElOnboarding = location == kCoachHubOnboardingRoute;
    if (enElOnboarding) {
      final pendingAsync = read(userProfileHasPendingWritesProvider);
      final pendiente =
          pendingAsync.isLoading || (pendingAsync.valueOrNull ?? false);
      return etapa == HubOnboardingStage.done && !pendiente
          ? kCoachHubInitialLocation
          : null;
    }
    if (etapa != HubOnboardingStage.done) return kCoachHubOnboardingRoute;

    // El push de vinculación manda UN SOLO `deepLink` a las dos superficies, y
    // las rutas no coinciden: en la app móvil las solicitudes pendientes viven
    // en `/home/notifications?tab=solicitudes` y acá la sección es
    // `/invitaciones` (el path quedó con el nombre viejo por estabilidad —
    // ADR-F4-01 —, la copia de usuario es «Solicitudes»).
    //
    // Sin este mapeo, el PF que toca la notificación con el Hub abierto cae en
    // la pantalla de error de go_router, porque en ESTE router no hay ninguna
    // ruta bajo `/home`. Va acá y no en la lista de aterrizajes de abajo
    // porque no es un aterrizaje: es una traducción de path, y tiene que valer
    // también para el PF que ya está navegando adentro del Hub.
    //
    // Se compara sólo el path: el `?tab=` del deep link lo descarta go_router
    // antes de llegar acá, y el Hub no tiene sub-pestañas que honrarlo.
    if (location == '/home/notifications') return '/invitaciones';

    // Trainer autenticado → si está en una de las rutas de ATERRIZAJE,
    // mandalo al dashboard o al destino fino que trajo el link.
    //
    // ── Por qué `kCoachHubInitialLocation` está en esta lista ──
    //
    // Porque es dónde aterriza de verdad un PF que YA tiene sesión, y sin él
    // los destinos finos NUNCA funcionaron para ese caso.
    //
    // El Coach Hub usa HASH routing: no hay una sola llamada a
    // `usePathUrlStrategy` en el repo, así que Flutter cae al
    // `HashUrlStrategy` por default. Una URL como `app.gettreino.com/?to=X`
    // —que es a donde Vercel manda `/abrir/profe`, y por donde entran TODOS
    // los mails al PF y el `back_url` de Mercado Pago— llega con el FRAGMENTO
    // vacío. Y con el fragmento vacío go_router no arranca en `/` sino en su
    // [initialLocation]. Así que el `location == '/'` de acá abajo, que se
    // escribió para cubrir ese caso, no da true nunca.
    //
    // El bug sobrevivió porque **sólo falla para el que ya está logueado**:
    // sin sesión la landing es `/login`, que sí es `isPublic`, y después del
    // login el destino se aplica bien. Probarlo deslogueado da verde. Y el
    // test que lo cubría llamaba con `location: '/'`, fijando la misma
    // suposición equivocada.
    //
    // `location == '/'` se conserva igual: si un PF llega efectivamente ahí,
    // devolver `null` le muestra la pantalla de error de go_router, porque no
    // hay ninguna GoRoute para `/`.
    //
    // Y la lista sigue siendo de ATERRIZAJES, no "cualquier ruta": un `to`
    // viejo no puede sacar a un PF de una ruta protegida en la que ya está.
    // Eso importa porque `refreshListenable` revalida el redirect con cada
    // cambio de auth/profile, y sin ese límite una revalidación podría
    // secuestrarlo de vuelta al destino del mail sin que haya tocado nada.
    if (isPublic ||
        isNotAllowed ||
        location == '/' ||
        location == kCoachHubInitialLocation) {
      // Se apaga ACÁ, apenas el gate lo consulta — no recién cuando resulta
      // en un path no-nulo. Un logout+login posterior en la MISMA pestaña
      // también pasa por este mismo branch (vía `isPublic`), y tiene que
      // encontrar la caja vacía, no reciclar el destino de la sesión previa.
      //
      // Única excepción: el interruptor todavía no llegó Y el mail está sin
      // confirmar. El perfil y el interruptor son dos listeners de Firestore
      // distintos y nada garantiza que el interruptor llegue primero: si el
      // perfil llega antes, el PF que cae desde un mail con `?to=` gastaría el
      // destino ACÁ, un instante antes de que el interruptor llegue en `true` y
      // lo mande al gate, y la caja ya estaría vacía. No es una espera: el PF
      // sigue su camino (a `/dashboard`, como siempre) y el destino queda
      // guardado; cuando el interruptor llega, o lo manda al gate o este mismo
      // bloque lo consume. Al PF con el mail ya confirmado no lo toca: para él
      // da igual lo que diga el interruptor.
      final destinoEnEspera = gateAsync.isLoading && mailSinConfirmar;
      final dest = destinoEnEspera ? null : initialDestination?.value;
      if (!destinoEnEspera) initialDestination?.value = null;
      final destino = _coachHubPathFor(dest);
      if (destino != null) return destino;

      // Sin destino fino: al dashboard — salvo que ya estemos ahí, porque
      // devolver la misma ruta es un redirect a sí mismo. Antes no hacía
      // falta distinguirlo: `/dashboard` no estaba en la lista de aterrizajes.
      return location == kCoachHubInitialLocation
          ? null
          : kCoachHubInitialLocation;
    }
  }

  return null;
}

/// Dónde arranca el Coach Hub, y por lo tanto dónde ATERRIZA todo el que
/// entra desde afuera con sesión abierta.
///
/// Es una constante y no dos literales sueltos porque `coachHubRedirect`
/// necesita reconocer esta ruta como aterrizaje: bajo hash routing, una URL
/// externa llega con el fragmento vacío y go_router arranca acá, no en `/`.
/// Si el `initialLocation` del router y el chequeo del redirect se
/// desincronizaran, los destinos finos volverían a caer en silencio — que es
/// exactamente el bug que esto cierra.
const String kCoachHubInitialLocation = '/dashboard';

/// Caja mutable para pasar un [DeepLinkDestination] por REFERENCIA a
/// [coachHubRedirect]. Ver el docstring de esa función para el bug que
/// resuelve: sin esto, "un solo uso" era una promesa que el código de al
/// lado no cumplía.
class DeepLinkDestinationBox {
  DeepLinkDestinationBox(this.value);
  DeepLinkDestination? value;
}

/// A dónde manda la RAÍZ del Coach Hub cuando trae un destino fino — o
/// `null` si no trae ninguno, para que el caller caiga a `/dashboard`.
///
/// El mapeo NO es el mismo que `mobileTrainerEntryPath` (`router.dart`): un
/// mismo `to` cae en paths distintos de cada lado (`/coach/athlete/:id` vs
/// `/alumnos/:id`), así que cada router tiene el suyo a propósito. Compartir
/// esto sería forzar una coincidencia que no existe.
String? _coachHubPathFor(DeepLinkDestination? dest) => switch (dest?.to) {
      DeepLinkTo.facturacion => '/facturacion/planes',
      DeepLinkTo.agenda => '/agenda',
      DeepLinkTo.solicitudes => '/invitaciones',
      DeepLinkTo.alumno => '/alumnos/${dest!.athleteId}',
      // Misma razón que en `mobileTrainerEntryPath`: el Coach Hub es
      // trainer-only por construcción (`coachHubRedirect` manda a cualquier
      // otro rol a `/not-allowed`), así que acá NUNCA hay un alumno esperando
      // vincularse. `null` cae al dashboard, que es lo correcto.
      DeepLinkTo.invitacion => null,
      null => null,
    };

/// Rutas signed-in del Coach Hub, agregadas desde cada `sections/<x>/routes.dart`
/// (ADR-CHW-002, ADR-CHW-008). El **orden no afecta** el matching de go_router
/// (cada path es único); se listan en orden de sidebar por legibilidad.
///
/// Todas viven dentro del `ShellRoute` → renderizan con sidebar + top bar.
/// `legacy` (`/upload-plan`) está acá a propósito: el PF ve el shell mientras
/// sube un plan, aunque no tenga item de sidebar.
final List<RouteBase> _signedInRoutes = [
  ...dashboardRoutes,
  ...actividadRoutes,
  ...agendaRoutes,
  ...alumnosRoutes,
  ...invitacionesRoutes,
  ...cuestionarioRoutes,
  ...rutinasRoutes,
  ...plannerRoutes,
  ...bibliotecaRoutes,
  ...templatesRoutes,
  ...nutricionRoutes,
  ...recetasRoutes,
  ...suplementosRoutes,
  ...habitosRoutes,
  ...pagosRoutes,
  ...moderacionRoutes,
  ...perfilPublicoRoutes,
  ...planesRoutes,
  ...facturacionPlanesRoutes,
  ...reportesRoutes,
  ...chatRoutes,
  ...ajustesRoutes,
  ...legacyRoutes, // /upload-plan, /upload-plan/preview
  ...routineEditorRoutes, // /routine-editor/:athleteId
];

/// [VerifyMailScreen] con el ancho de una pantalla de escritorio.
///
/// La pantalla se hizo para el teléfono: el campo del código y el botón ocupan
/// todo el ancho disponible (medido: 1360 px en una ventana de 1400). Acá se la
/// acota igual que `CoachHubLoginScreen` y `CoachHubNotAllowedScreen`, las
/// otras dos pantallas sin shell del Hub. El fondo se pinta afuera porque el
/// `Scaffold` de la pantalla solo cubre la caja.
class _VerifyMailEnElHub extends StatelessWidget {
  const _VerifyMailEnElHub();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppPalette.of(context).bg,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: const VerifyMailScreen(),
        ),
      ),
    );
  }
}

/// Build del GoRouter del Coach Hub (ADR-CHW-001, ADR-CHW-008).
///
/// `/login` y `/not-allowed` son rutas top-level (NO renderizan el shell): el
/// usuario anónimo o no autorizado nunca ve el sidebar. Todo lo demás cuelga del
/// `ShellRoute`, que envuelve cada página de sección en [CoachHubScaffold].
GoRouter buildCoachHubRouter({
  required Listenable refreshListenable,
  required T Function<T>(ProviderListenable<T>) read,
  // Inyectable para tests: sin esto, tendrían que confiar en cómo se
  // comporta `Uri.base` afuera de un navegador de verdad. En la VM de
  // `flutter test` resuelve al directorio de trabajo como `file://` sin
  // query — inofensivo — pero no hace falta apoyarse en esa casualidad.
  Uri? initialUri,
}) {
  // Se lee UNA sola vez, acá — no en `coachHubRedirect` — porque esta
  // función corre una vez por vida de la app (`initState`, no en cada
  // rebuild). Va en una CAJA (no un valor plano) porque `coachHubRedirect`
  // la apaga sola apenas la consulta — ver su docstring: sin eso, un
  // logout+login posterior en la MISMA pestaña reciclaba este mismo valor.
  final destination = DeepLinkDestinationBox(
    DeepLinkDestination.fromQuery((initialUri ?? Uri.base).queryParameters),
  );

  return GoRouter(
    initialLocation: kCoachHubInitialLocation,
    refreshListenable: refreshListenable,
    redirect: (ctx, state) => coachHubRedirect(
      read,
      state.matchedLocation,
      initialDestination: destination,
    ),
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const CoachHubLoginScreen(),
      ),
      GoRoute(
        path: '/not-allowed',
        builder: (_, __) => const CoachHubNotAllowedScreen(),
      ),
      // Gate del mail con código. Top-level, fuera del shell, como `/login` y
      // `/not-allowed`: sin sidebar hasta que confirme.
      GoRoute(
        path: _verifyMailRoute,
        builder: (_, __) => const _VerifyMailEnElHub(),
      ),
      // Onboarding del PF promovido. Top-level, fuera del shell: sin sidebar
      // hasta que complete el perfil. El ancho acotado lo pone la pantalla.
      GoRoute(
        path: kCoachHubOnboardingRoute,
        builder: (_, __) => const CompletarPerfilScreen(),
      ),
      ShellRoute(
        pageBuilder: (ctx, state, child) => NoTransitionPage(
          child: CoachHubScaffold(
            contentMaxWidth: contentMaxWidthForRoute(state.uri.path),
            mobileFacturacionAllowed: isMobileFacturacionRoute(state.uri.path),
            child: child,
          ),
        ),
        routes: _signedInRoutes,
      ),
    ],
  );
}
