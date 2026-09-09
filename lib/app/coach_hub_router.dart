import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/utils/deep_link_destination.dart';
import '../features/auth/application/auth_providers.dart';
import '../features/coach_hub/presentation/coach_hub_login_screen.dart';
import '../features/coach_hub/presentation/coach_hub_not_allowed_screen.dart';
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
import '../features/profile/application/user_providers.dart';
import '../features/profile/domain/user_role.dart';

/// Rutas públicas del Coach Hub (no requieren auth).
const _coachHubPublicRoutes = {'/login'};

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
      final dest = initialDestination?.value;
      initialDestination?.value = null;
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
  ...perfilPublicoRoutes,
  ...planesRoutes,
  ...facturacionPlanesRoutes,
  ...reportesRoutes,
  ...chatRoutes,
  ...ajustesRoutes,
  ...legacyRoutes, // /upload-plan, /upload-plan/preview
  ...routineEditorRoutes, // /routine-editor/:athleteId
];

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
      ShellRoute(
        pageBuilder: (ctx, state, child) => NoTransitionPage(
          child: CoachHubScaffold(
            contentMaxWidth: contentMaxWidthForRoute(state.uri.path),
            child: child,
          ),
        ),
        routes: _signedInRoutes,
      ),
    ],
  );
}
