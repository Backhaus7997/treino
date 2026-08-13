import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

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
import '../features/coach_hub/presentation/sections/planes/routes.dart';
import '../features/coach_hub/presentation/sections/planner/routes.dart';
import '../features/coach_hub/presentation/sections/recetas/routes.dart';
import '../features/coach_hub/presentation/sections/reportes/routes.dart';
import '../features/coach_hub/presentation/sections/routine_editor/routes.dart';
import '../features/coach_hub/presentation/sections/rutinas/routes.dart';
import '../features/coach_hub/presentation/sections/suplementos/routes.dart';
import '../features/coach_hub/presentation/sections/templates/routes.dart';
import '../features/coach_hub/presentation/shell/coach_hub_scaffold.dart';
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
String? coachHubRedirect(
  T Function<T>(ProviderListenable<T> provider) read,
  String location,
) {
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

    // Trainer autenticado → si está en /login o /not-allowed, mandalo
    // al dashboard. Si ya está en alguna ruta protegida, dejalo.
    if (isPublic || isNotAllowed) return '/dashboard';
  }

  return null;
}

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
}) {
  return GoRouter(
    initialLocation: '/dashboard',
    refreshListenable: refreshListenable,
    redirect: (ctx, state) => coachHubRedirect(read, state.matchedLocation),
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
          child: CoachHubScaffold(child: child),
        ),
        routes: _signedInRoutes,
      ),
    ],
  );
}
